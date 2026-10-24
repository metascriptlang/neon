import { sleepAsync } from "std/core/promise";
import { el, text, dynText, NeonNode } from "../../src/render/node";
import { HostNode, MockNode, mockNode, mockHost, render, mockToString } from "../../src/render/host";
import { element } from "../../src/macros/ui/element";
import { flush } from "../../src/core/runtime";
import { Loading } from "../../src/macros/ui/flow";
import { RoutingHistory, createMemoryRoutingHistory } from "../../src/navigation/routingHistory";
import { PreloadArgs, redirect, reload } from "../../src/navigation/route";
import { Router, RouterProvider, createRoutes, createRouter } from "../../src/navigation/router";
import { query, createAsync } from "../../src/navigation/index";

interface Note {
	text: string;
}

const runs: string[] = [];

function ran(name: string): int32 {
	let n = 0;
	for (const r of runs) { if (r === name) { n += 1; } }
	return n;
}

async function fetchNote(name: string): Promise<Note> {
	runs.push(name);
	return { text: name + "#" + ran(name).toString() };
}

async function signedOut(): Promise<Note> {
	runs.push("signedOut");
	throw redirect("/login");
}

async function stale(): Promise<Note> {
	runs.push("stale");
	throw reload();
}

const waiting: NeonNode = el("b", [], [], text("loading"));

const getSigned = query(signedOut, "signed");
const getStale = query(stale, "stale");
const getP = query((): Promise<Note> => fetchNote("p"), "p");
const getP2 = query((): Promise<Note> => fetchNote("p2"), "p2");
const getEarly = query(signedOut, "early");
const getQ = query((): Promise<Note> => fetchNote("q"), "q");

function Account(): NeonNode {
	const note = createAsync((): Promise<Note> => getSigned());
	return Loading({ children: el("p", [], [], dynText((): string => note().text)), fallback: waiting });
}

function Login(): NeonNode {
	return el("p", [], [], text("login"));
}

function Home(): NeonNode {
	return el("p", [], [], text("home"));
}

function PageP(): NeonNode {
	const note = createAsync((): Promise<Note> => getP());
	return Loading({ children: el("p", [], [], dynText((): string => note().text)), fallback: waiting });
}

function PageQ(): NeonNode {
	const note = createAsync((): Promise<Note> => getQ());
	return Loading({ children: el("p", [], [], dynText((): string => note().text)), fallback: waiting });
}

function warm(args: PreloadArgs<Map<string, string>>): void {
	getP();
}

function PageP2(): NeonNode {
	const note = createAsync((): Promise<Note> => getP2());
	return Loading({ children: el("p", [], [], dynText((): string => note().text)), fallback: waiting });
}

function warmP2(args: PreloadArgs<Map<string, string>>): void {
	getP2();
}

function warmEarly(args: PreloadArgs<Map<string, string>>): void {
	getEarly();
}

function warmQ(args: PreloadArgs<Map<string, string>>): void {
	getQ();
}

function opened(history: RoutingHistory): Router {
	const routes = createRoutes([
		{ path: "/", component: Home },
		{ path: "/account", component: Account },
		{ path: "/login", component: Login },
		{ path: "/p", component: PageP, preload: warm },
		{ path: "/q", component: PageQ, preload: warmQ },
		{ path: "/p2", component: PageP2, preload: warmP2 },
		{ path: "/early", component: Home, preload: warmEarly },
	]);
	const made = createRouter(routes, history);
	if (!made.ok) { throw new Error("router: " + made.error.toString()); }
	return made.value;
}

function mounted(router: Router): MockNode {
	const root = mockNode("root");
	render(element(<RouterProvider router={router} />), mockHost(), root as unknown as HostNode);
	return root;
}

test "a query that throws a redirect while a page reads it navigates the router in place and never answers the page" {
	const history = createMemoryRoutingHistory({ url: "/account", state: "" });
	const router = opened(history);
	const root = mounted(router);
	await sleepAsync(8);
	flush();
	assert router.location().pathname === "/login", router.location().pathname;
	assert mockToString(root).includes("<p>login</p>"), mockToString(root);
	assert history.read().url === "/login", history.read().url;
	assert !history.go(-1), "the redirect replaced the entry";
	assert ran("signedOut") === 1, ran("signedOut").toString();
	router.dispose();
}

test "a thrown redirect outside a router names the case, and a thrown reload stays the caller's error" {
	let message = "";
	try { await getSigned(); } catch (error) { message = error.message; }
	assert message === "query: the answer redirects to /login, and no RouterProvider is in scope to follow it", message;
	let kept = "";
	try { await getStale(); } catch (error) { kept = error.message; }
	assert kept === "", "a reload carries no address: " + kept;
	assert ran("stale") === 1;
}

test "a preload makes an entry that a navigation refetches after the preload timeout, and a native return reuses" {
	const history = createMemoryRoutingHistory({ url: "/", state: "" });
	const router = opened(history);
	const root = mounted(router);
	router.preload("/p");
	await sleepAsync(2);
	assert ran("p") === 1, "the preload fetched: " + ran("p").toString();
	assert router.navigate("/q");
	await sleepAsync(8);
	flush();
	assert mockToString(root).includes("<p>q#1</p>"), mockToString(root);
	assert router.navigate("/");
	flush();
	await sleepAsync(5100);
	assert history.go(-1);
	await sleepAsync(8);
	flush();
	assert mockToString(root).includes("<p>q#1</p>"), mockToString(root);
	assert ran("q") === 1, "native reuses an entry older than the preload timeout: " + ran("q").toString();
	assert router.navigate("/p");
	await sleepAsync(8);
	flush();
	assert ran("p") === 2, "a navigation refetches an unread preload after the timeout: " + ran("p").toString();
	router.dispose();
}

test "a preload run from outside any owner keeps the router's owner: its entry is preload-made and a redirect there is ignored" {
	const history = createMemoryRoutingHistory({ url: "/", state: "" });
	const router = opened(history);
	const root = mounted(router);
	const before = ran("signedOut");
	router.preload("/early");
	await sleepAsync(8);
	flush();
	assert ran("signedOut") === before + 1, "the preload query ran: " + ran("signedOut").toString();
	assert router.location().pathname === "/", "a redirect in a preload does not navigate: " + router.location().pathname;
	router.preload("/p2");
	await sleepAsync(2);
	assert router.navigate("/p2");
	await sleepAsync(2600);
	assert router.navigate("/");
	flush();
	assert router.navigate("/p2");
	await sleepAsync(8);
	flush();
	assert router.navigate("/");
	flush();
	await sleepAsync(3000);
	assert router.navigate("/p2");
	await sleepAsync(8);
	flush();
	assert ran("p2") === 1, "a read refreshed the preload-made entry, so it outlived the timeout from its creation: " + ran("p2").toString();
	assert mockToString(root).includes("<p>p2#1</p>"), mockToString(root);
	router.dispose();
}
