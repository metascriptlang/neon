import { sleepAsync } from "std/core/promise";
import { el, text, dynText, NeonNode } from "../../src/render/node";
import { Loading } from "../../src/macros/ui/flow";
import { renderToStream, StreamSink } from "../../src/render/ssr";
import { App, serve } from "../../src/render/serve";
import { createRequestRoutingHistory } from "../../src/navigation/routingHistory";
import { notFound, redirect } from "../../src/navigation/route";
import { RouterProvider, createRouter, createRoutes } from "../../src/navigation/router";
import { query, createAsync } from "../../src/navigation/index";

interface Pkg {
	name: string;
}

async function fetchPkg(name: string): Promise<Pkg> {
	await sleepAsync(3);
	if (name === "gone") { throw notFound(); }
	if (name === "private") { throw redirect("/login"); }
	return { name: name };
}

const getPkg = query(fetchPkg, "pkgStatusServer");

function pkgNamed(): NeonNode {
	return el("p", [], [], text("login"));
}

function Root(): NeonNode {
	const pkg = createAsync((): Promise<Pkg> => getPkg("gone"));
	return el("p", [], [], dynText((): string => "pkg " + pkg().name));
}

function Deferred(): NeonNode {
	const pkg = createAsync((): Promise<Pkg> => getPkg("gone"));
	return Loading({ children: el("p", [], [], dynText((): string => "pkg " + pkg().name)), fallback: el("b", [], [], text("loading")) });
}

function Private(): NeonNode {
	const pkg = createAsync((): Promise<Pkg> => getPkg("private"));
	return Loading({ children: el("p", [], [], dynText((): string => "pkg " + pkg().name)), fallback: el("b", [], [], text("loading")) });
}

function Everything(): NeonNode {
	return el("p", [], [], text("not found page"));
}

const routes = createRoutes([
	{ path: "/root", component: Root },
	{ path: "/deferred", component: Deferred },
	{ path: "/private", component: Private },
	{ path: "/login", component: pkgNamed },
	{ path: "*", status: 404, component: Everything },
]);

const app: App = { routes: routes, notFound: el("p", [], [], text("app not found")), client: "", document: null };

test "a served page whose query answers not found is a 404 holding the catch-all route" {
	const served = await serve(app, "/root");
	assert served.status === 404 && served.location === null, served.status.toString();
	assert served.body.includes("not found page") && !served.body.includes("pkg "), served.body;
}

test "a served page whose query answers not found under a Loading boundary is a 404 holding the catch-all route" {
	const served = await serve(app, "/deferred");
	assert served.status === 404, served.status.toString();
	assert served.body.includes("not found page") && !served.body.includes("pkg "), served.body;
}

test "a served page whose query throws a redirect answers it with its location" {
	const served = await serve(app, "/private");
	assert served.status === 307 && served.location === "/login", served.status.toString() + " " + (served.location ?? "-");
}

async function statusAtFirstWrite(url: string): Promise<int32> {
	const opened = createRouter(routes, createRequestRoutingHistory(url));
	if (!opened.ok) { throw new Error("router: " + opened.error.toString()); }
	const router = opened.value;
	let seen: int32 = 0;
	const sink: StreamSink = {
		write: (chunk: string): void => { if (seen === 0) { seen = router.response().status; } },
		end: (): void => {},
	};
	const stream = renderToStream(<RouterProvider router={router} />);
	stream.pipe(sink);
	try { await stream; } catch (failure) {}
	const settled = router.response().status;
	router.dispose();
	return seen * 1000 + settled;
}

test "the status is final at the first streamed byte for a read the shell waits on, and not for one under Loading" {
	const waited = await statusAtFirstWrite("/root");
	assert waited === 404404, "a read outside Loading blocks the shell until its answer: " + waited.toString();
	const deferred = await statusAtFirstWrite("/deferred");
	assert deferred === 200404, "a read under Loading is answered after the shell: " + deferred.toString();
}
