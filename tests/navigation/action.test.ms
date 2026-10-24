import { sleepAsync } from "std/core/promise";
import { el, text, dynText, NeonNode } from "../../src/render/node";
import { Host, HostNode, MockNode, mockNode, mockHost, render, mockToString } from "../../src/render/host";
import { element } from "../../src/macros/ui/element";
import { flush } from "../../src/core/runtime";
import { createRoot } from "../../src/core/owner";
import { Dispose } from "../../src/core/types";
import { Loading } from "../../src/macros/ui/flow";
import { createMemoryRoutingHistory } from "../../src/navigation/routingHistory";
import { Router, RouterProvider, createRoutes, createRouter } from "../../src/navigation/router";
import { redirect, reload } from "../../src/navigation/route";
import { query, createAsync, action, useAction, useSubmission, useSubmissions, Submission } from "../../src/navigation/index";
import { Gate, opened, release } from "../core/asyncClock";

class Mounted {
	router: Router;
	root: MockNode;

	constructor(router: Router, root: MockNode) {
		this.router = router;
		this.root = root;
	}

	shown(): string {
		return mockToString(this.root);
	}
}

let inside: (() => NeonNode) | null = null;
let toProbe = true;

function Probe(): NeonNode {
	return inside!();
}

function Elsewhere(): NeonNode {
	return el("p", [], [], text("elsewhere"));
}

function session(body: () => NeonNode): Mounted {
	inside = body;
	const routes = createRoutes([
		{ path: "/", component: Probe },
		{ path: "/next", component: Elsewhere },
	]);
	const made = createRouter(routes, createMemoryRoutingHistory({ url: "/", state: "" }));
	if (!made.ok) { throw new Error("router: " + made.error.toString()); }
	const root = mockNode("root");
	render(element(<RouterProvider router={made.value} />), mockHost(), root as unknown as HostNode);
	return new Mounted(made.value, root);
}

function plain(body: () => void): Mounted {
	return session((): NeonNode => {
		body();
		return el("p", [], [], text("probe"));
	});
}

function failureOf(run: () => void): string {
	try {
		createRoot((dispose: Dispose): number => { run(); return 0; });
	} catch (error) {
		return error.message;
	}
	return "";
}

const runs: string[] = [];

function ran(name: string): int32 {
	let n = 0;
	for (const r of runs) { if (r === name) { n += 1; } }
	return n;
}

async function save(gate: Gate, name: string, input: string): Promise<string> {
	runs.push(name);
	await opened(gate);
	return input + "!";
}

async function failingSave(gate: Gate, name: string, input: string): Promise<string> {
	runs.push(name);
	await opened(gate);
	if (ran(name) === 1) { throw new Error("denied " + input); }
	return input + "!";
}

function stateOf(sub: Submission<string, string> | null): string {
	if (sub === null) { return "none"; }
	if (sub.pending()) { return "pending:" + sub.input; }
	const error = sub.error();
	if (error !== null) { return "error:" + error.message; }
	return "result:" + (sub.result() ?? "");
}

test "an action call runs its function once and its submission goes from pending to result" {
	const gate = new Gate();
	const save1 = action((input: string): Promise<string> => save(gate, "once", input), "once");
	let call: ((input: string) => Promise<string | null>) | null = null;
	const mounted = session((): NeonNode => {
		call = useAction(save1);
		const sub = useSubmission(save1);
		return el("p", [], [], dynText((): string => stateOf(sub())));
	});
	assert mounted.shown().includes("<p>none</p>"), mounted.shown();
	const answer = call!("a");
	flush();
	assert mounted.shown().includes("<p>pending:a</p>"), mounted.shown();
	await release(gate);
	assert (await answer) === "a!";
	flush();
	assert mounted.shown().includes("<p>result:a!</p>"), mounted.shown();
	assert ran("once") === 1, ran("once").toString();
	mounted.router.dispose();
}

test "an error lands in the submission, rejects the call, and retry runs the function again" {
	const gate = new Gate();
	gate.open = true;
	const save2 = action((input: string): Promise<string> => failingSave(gate, "retry", input), "retry");
	let call: ((input: string) => Promise<string | null>) | null = null;
	let subs: (() => Submission<string, string>[]) | null = null;
	const mounted = plain((): void => {
		call = useAction(save2);
		subs = useSubmissions(save2);
	});
	let message = "";
	try { await call!("b"); } catch (error) { message = error.message; }
	flush();
	assert message === "denied b", message;
	const list = subs!();
	assert list.length === 1 && stateOf(list[0]) === "error:denied b", list.length.toString();
	assert (await list[0].retry()) === "b!";
	flush();
	assert stateOf(list[0]) === "result:b!", stateOf(list[0]);
	assert ran("retry") === 2, ran("retry").toString();
	mounted.router.dispose();
}

interface Note {
	text: string;
}

async function fetchNote(name: string): Promise<Note> {
	runs.push(name);
	return { text: "note#" + ran(name).toString() };
}

test "settling an action revalidates a query a reader holds, and a failing action does not" {
	const getNote = query((): Promise<Note> => fetchNote("note"), "note");
	const gate = new Gate();
	gate.open = true;
	const edit = action((input: string): Promise<string> => failingSave(gate, "edit", input), "edit");
	const waiting: NeonNode = el("b", [], [], text("loading"));
	let call: ((input: string) => Promise<string | null>) | null = null;
	const mounted = session((): NeonNode => {
		call = useAction(edit);
		const note = createAsync((): Promise<Note> => getNote());
		return Loading({ children: el("p", [], [], dynText((): string => note().text)), fallback: waiting });
	});
	await sleepAsync(8);
	assert mounted.shown().includes("<p>note#1</p>"), mounted.shown();
	let message = "";
	try { await call!("x"); } catch (error) { message = error.message; }
	flush();
	await sleepAsync(8);
	assert message === "denied x" && ran("note") === 1, "an error leaves the query: " + ran("note").toString();
	assert (await call!("y")) === "y!";
	flush();
	await sleepAsync(8);
	assert ran("note") === 2 && mounted.shown().includes("<p>note#2</p>"), "one rerun after the settle: " + mounted.shown();
	mounted.router.dispose();
}

test "useSubmissions lists the submissions of one action, narrowed by a filter, and clear drops one" {
	const gate = new Gate();
	gate.open = true;
	const first = action((input: string): Promise<string> => save(gate, "list", input), "list");
	const other = action((input: string): Promise<string> => save(gate, "list-other", input), "list-other");
	let callFirst: ((input: string) => Promise<string | null>) | null = null;
	let callOther: ((input: string) => Promise<string | null>) | null = null;
	let all: (() => Submission<string, string>[]) | null = null;
	let onlyB: (() => Submission<string, string>[]) | null = null;
	let latest: (() => Submission<string, string> | null) | null = null;
	const mounted = plain((): void => {
		callFirst = useAction(first);
		callOther = useAction(other);
		all = useSubmissions(first);
		onlyB = useSubmissions(first, (input: string): boolean => input === "b");
		latest = useSubmission(first);
	});
	assert all!().length === 0 && latest!() === null;
	await callFirst!("a");
	await callFirst!("b");
	await callOther!("c");
	flush();
	assert all!().length === 2 && onlyB!().length === 1, all!().length.toString();
	assert stateOf(latest!()) === "result:b!", stateOf(latest!());
	all!()[1].clear();
	flush();
	assert all!().length === 1 && stateOf(latest!()) === "result:a!", all!().length.toString();
	mounted.router.dispose();
}

async function nothing(input: string): Promise<string | null> {
	runs.push("nothing");
	// Parked on ~/metascript/.inbox/compiler/2026-10-08-async-return-null-literal-refused.md: `return null;` in place of this typed constant.
	const none: string | null = null;
	return none;
}

test "an action that answers null leaves no submission behind" {
	const quiet = action(nothing, "quiet");
	let call: ((input: string) => Promise<string | null>) | null = null;
	let subs: (() => Submission<string, string | null>[]) | null = null;
	const mounted = plain((): void => {
		call = useAction(quiet);
		subs = useSubmissions(quiet);
	});
	await call!("a");
	flush();
	assert subs!().length === 0;
	mounted.router.dispose();
}

test "useAction, useSubmissions and useSubmission fail loud outside a RouterProvider, naming the caller" {
	const act = action((input: string): Promise<string> => save(new Gate(), "outside", input), "outside");
	assert failureOf((): void => { useAction(act); }) === "routing: useAction is called outside a RouterProvider";
	assert failureOf((): void => { useSubmissions(act); }) === "routing: useSubmissions is called outside a RouterProvider";
	assert failureOf((): void => { useSubmission(act); }) === "routing: useSubmission is called outside a RouterProvider";
}

test "submissions belong to the router: another router does not see them" {
	const gate = new Gate();
	gate.open = true;
	const shared = action((input: string): Promise<string> => save(gate, "shared", input), "shared");
	let call: ((input: string) => Promise<string | null>) | null = null;
	let here: (() => Submission<string, string>[]) | null = null;
	const one = plain((): void => {
		call = useAction(shared);
		here = useSubmissions(shared);
	});
	await call!("a");
	flush();
	let there: (() => Submission<string, string>[]) | null = null;
	const two = plain((): void => { there = useSubmissions(shared); });
	assert here!().length === 1, "the router that ran it keeps it";
	assert there!().length === 0, "the other router starts empty";
	one.router.dispose();
	two.router.dispose();
}

test "onComplete sees the settled submission before the live one settles, and a retry from it replaces the answer" {
	const gate = new Gate();
	gate.open = true;
	const seen: string[] = [];
	let latest: (() => Submission<string, string> | null) | null = null;
	const noted = action(
		(input: string): Promise<string> => failingSave(gate, "complete", input),
		{
			name: "complete",
			onComplete: (done: Submission<string, string>): void => {
				seen.push(stateOf(done) + "|live:" + stateOf(latest!()));
				if (done.error() !== null) { done.retry(); }
			},
		},
	);
	let call: ((input: string) => Promise<string | null>) | null = null;
	const mounted = plain((): void => {
		call = useAction(noted);
		latest = useSubmission(noted);
	});
	assert (await call!("b")) === "b!", "the retry's answer replaces the failure";
	flush();
	assert ran("complete") === 2, ran("complete").toString();
	assert seen.length === 2, seen.length.toString();
	assert seen[0] === "error:denied b|live:pending:b", seen[0];
	assert seen[1] === "result:b!|live:pending:b", seen[1];
	assert stateOf(latest!()) === "result:b!", stateOf(latest!());
	mounted.router.dispose();
}

async function moveByThrow(name: string, input: string): Promise<string> {
	runs.push(name);
	if (input === "go") { throw redirect("/next"); }
	return input + "!";
}

test "an action that throws a redirect is handled as one that returns it, and its error is not a failure" {
	const move = action((input: string): Promise<string> => moveByThrow("moveThrown", input), "moveThrown");
	let call: ((input: string) => Promise<string | null>) | null = null;
	const mounted = plain((): void => { call = useAction(move); });
	const answer = await call!("go");
	flush();
	assert answer === null;
	assert mounted.router.location().pathname === "/next", mounted.router.location().pathname;
	assert mounted.router.submissions.peek().length === 0;
	mounted.router.dispose();
}

async function reloading(name: string, keys: string[] | null): Promise<string> {
	runs.push(name);
	throw keys === null ? reload() : reload({ revalidate: keys });
}

test "a thrown reload revalidates only the query keys it names, and none named revalidates all" {
	const keep = query((): Promise<Note> => fetchNote("keep"), "keep");
	const drop = query((): Promise<Note> => fetchNote("drop"), "drop");
	const some = action((input: string[]): Promise<string> => reloading("some", input), "some");
	const every = action((input: string): Promise<string> => reloading("every", null), "every");
	const waiting: NeonNode = el("b", [], [], text("loading"));
	let callSome: ((input: string[]) => Promise<string | null>) | null = null;
	let callEvery: ((input: string) => Promise<string | null>) | null = null;
	const mounted = session((): NeonNode => {
		callSome = useAction(some);
		callEvery = useAction(every);
		const a = createAsync((): Promise<Note> => keep());
		const b = createAsync((): Promise<Note> => drop());
		return Loading({ children: el("p", [], [], dynText((): string => a().text + "," + b().text)), fallback: waiting });
	});
	await sleepAsync(8);
	assert mounted.shown().includes("<p>note#1,note#1</p>"), mounted.shown();
	assert (await callSome!(["drop"])) === null;
	flush();
	await sleepAsync(8);
	assert ran("keep") === 1 && ran("drop") === 2, ran("keep").toString() + "," + ran("drop").toString();
	assert (await callEvery!("")) === null;
	flush();
	await sleepAsync(8);
	assert ran("keep") === 2 && ran("drop") === 3, ran("keep").toString() + "," + ran("drop").toString();
	mounted.router.dispose();
}
