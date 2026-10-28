import { flush, resetErrorHalt } from "../../src/core/runtime";
import { createRoot } from "../../src/core/owner";
import { createRenderEffect } from "../../src/core/effect";
import { Cleanup, Dispose } from "../../src/core/types";
import { NeonNode } from "../../src/render/hostTypes";
import { element } from "../../src/macros/ui/element";
import { HostNode, MockNode, mockNode, mockHost, render, mockToString } from "../../src/render/host";
import { RoutingError } from "../../src/navigation/routing";
import {
	RoutingHistory,
	createMemoryRoutingHistory,
	createRequestRoutingHistory,
} from "../../src/navigation/routingHistory";
import { GuardDecision, ParamsCodec, PreloadArgs, RouteMatch, notFound, proceed, redirect, route } from "../../src/navigation/route";
import { PathMatch } from "../../src/navigation/routeMatcher";
import {
	A,
	LayoutProps,
	NavigateOptions,
	Router,
	RouterProvider,
	Routes,
	createRouter,
	createRoutes,
	useLocation,
	useMatch,
	useNavigate,
	useParams,
} from "../../src/navigation/router";

let layouts: int32 = 0;
let docs: int32 = 0;
let signedIn = true;
let go: ((to: string | int32, options?: NavigateOptions | null) => boolean) | null = null;

function Shell(props: LayoutProps): NeonNode {
	layouts += 1;
	return <main>{props.children}</main>;
}

function Home(): NeonNode {
	return <h1>home</h1>;
}

function Doc(): NeonNode {
	docs += 1;
	const slug = useParams().get("slug");
	return <h1>{"doc " + (slug ?? "")}</h1>;
}

function Missing(): NeonNode {
	return <h1>missing</h1>;
}

struct ThreadParams {
	id: string;
}

const threadCodec: ParamsCodec<ThreadParams> = {
	parse: (values: Map<string, string>): Result<ThreadParams, RoutingError> => {
		const id = values.get("id") ?? "";
		for (let i: int32 = 0; i < id.length; i += 1) {
			const code = id.charCodeAt(i);
			if (code < 48 || code > 57) { return Result.err(RoutingError.InvalidParams); }
		}
		return id.length === 0 ? Result.err(RoutingError.InvalidParams) : Result.ok({ id });
	},
	stringify: (params: ThreadParams): Map<string, string> => {
		const values = new Map<string, string>();
		values.set("id", params.id);
		return values;
	},
};

const thread = route<ThreadParams>("/threads/:id", { params: threadCodec });

function Thread(): NeonNode {
	return <h1>{"thread " + (useParams().get("id") ?? "")}</h1>;
}

function Probe(props: LayoutProps): NeonNode {
	go = useNavigate();
	const location = useLocation();
	const doc = useMatch("/docs/:slug");
	const slugOf = (): string => {
		const found = doc();
		return found === null ? "-" : (found as PathMatch).params.get("slug") ?? "";
	};
	return <div>
		<p>{location().pathname + "|" + slugOf() + "|" + (location().search.get("q") ?? "")}</p>
		{props.children}
	</div>;
}

function Links(props: LayoutProps): NeonNode {
	return <nav>
		<A href="/">Home</A>
		<A href="/docs/start">Start</A>
		<A href="/docs/routing#notes">Notes</A>
		{props.children}
	</nav>;
}

function siteRoutes(): Routes {
	return createRoutes([
		{ layout: Shell, children: [
			{ path: "/", component: Home },
			{ path: "/docs/:slug", component: Doc },
			{ path: "*", status: 404, component: Missing },
		] },
	]);
}

function memory(url: string): RoutingHistory {
	return createMemoryRoutingHistory({ url, state: "" });
}

function opened(routes: Routes, history: RoutingHistory): Router {
	const router = createRouter(routes, history);
	if (!router.ok) { throw new Error("router: " + router.error.toString()); }
	return router.value;
}

function mounted(router: Router): MockNode {
	const root: MockNode = mockNode("root");
	render(element(<RouterProvider router={router} />), mockHost(), root as unknown as HostNode);
	return root;
}

function failure(build: () => Routes): string {
	try { build(); } catch (error) { return error.message; }
	return "";
}

test "a layout keeps its instance while the page under it is replaced per path param" {
	layouts = 0;
	docs = 0;
	const history = memory("/docs/start?utm=1");
	const router = opened(siteRoutes(), history);
	const root = mounted(router);
	assert mockToString(root) === "<root><main><h1>doc start</h1></main></root>", mockToString(root);
	assert router.navigate("/docs/start?utm=2");
	flush();
	assert docs === 1, "a search change replaced the page";
	assert router.navigate("/docs/routing");
	flush();
	assert mockToString(root) === "<root><main><h1>doc routing</h1></main></root>", mockToString(root);
	assert docs === 2, "a path param change kept the page";
	assert router.navigate("/");
	flush();
	assert mockToString(root) === "<root><main><h1>home</h1></main></root>", mockToString(root);
	assert layouts === 1, "the layout was rebuilt";
	assert history.read().url === "/";
	assert history.go(-1);
	flush();
	assert mockToString(root) === "<root><main><h1>doc routing</h1></main></root>", mockToString(root);
	assert history.read().url === "/docs/routing";
	assert router.navigate("/nowhere/deep");
	flush();
	assert mockToString(root) === "<root><main><h1>missing</h1></main></root>", mockToString(root);
	assert history.read().url === "/nowhere/deep", history.read().url;
	assert router.location().pathname === "/nowhere/deep", router.location().pathname;
	assert router.response().status === 404;
	router.dispose();
}

test "a request answers with the route's status, a guard's redirect and its location" {
	const routes = createRoutes([
		{ path: "/", component: Home },
		{
			path: "/settings",
			component: Home,
			guard: (params: Map<string, string>, found: RouteMatch): GuardDecision => {
				return found.search.get("session") === null ? redirect("/signin", 302) : proceed();
			},
		},
		{ path: "/signin", component: Missing },
		{ path: "*", status: 404, component: Missing },
	]);
	const home = opened(routes, createRequestRoutingHistory("/")).response();
	assert home.status === 200 && home.location === null;
	const signedOut = opened(routes, createRequestRoutingHistory("/settings")).response();
	assert signedOut.status === 302;
	assert signedOut.location === "/signin";
	const signedIn = opened(routes, createRequestRoutingHistory("/settings?session=s")).response();
	assert signedIn.status === 200 && signedIn.location === null;
	const missing = opened(routes, createRequestRoutingHistory("/nowhere")).response();
	assert missing.status === 404 && missing.location === null;
	const cold = memory("/settings");
	opened(routes, cold);
	assert cold.read().url === "/signin", "a cold client load kept the guarded address";
	const visited = memory("/");
	const router = opened(routes, visited);
	assert router.navigate("/settings");
	flush();
	assert visited.read().url === "/signin";
	assert visited.go(-1);
	flush();
	assert visited.read().url === "/";
	assert !visited.go(-2);
	flush();
}

test "an address ending in a slash is redirected for good to the one without it" {
	const request = opened(siteRoutes(), createRequestRoutingHistory("/docs/start/?utm=1")).response();
	assert request.status === 308;
	assert request.location === "/docs/start?utm=1", request.location ?? "";
	const root = opened(siteRoutes(), createRequestRoutingHistory("/")).response();
	assert root.status === 200 && root.location === null;
	const cold = memory("/docs/start//#notes");
	opened(siteRoutes(), cold);
	assert cold.read().url === "/docs/start#notes", cold.read().url;
}

test "going back to an address whose guard now redirects rewrites that entry to where it went" {
	signedIn = true;
	const routes = createRoutes([
		{ path: "/", component: Home },
		{
			path: "/settings",
			component: Home,
			guard: (params: Map<string, string>, found: RouteMatch): GuardDecision => {
				return signedIn ? proceed() : redirect("/signin");
			},
		},
		{ path: "/signin", component: Missing },
	]);
	const history = memory("/");
	const router = opened(routes, history);
	assert router.navigate("/settings");
	flush();
	assert router.navigate("/");
	flush();
	signedIn = false;
	assert history.go(-1);
	flush();
	assert history.read().url === "/signin", history.read().url;
	assert router.location().pathname === "/signin";
	assert history.go(1);
	flush();
	assert history.read().url === "/";
	router.dispose();
}

test "going back to a page a guard turned into not found shows that page again" {
	const routes = createRoutes([
		{ layout: Shell, children: [
			{ path: "/", component: Home },
			{
				path: "/docs/:slug",
				component: Doc,
				guard: (params: Map<string, string>, found: RouteMatch): GuardDecision => {
					return params.get("slug") === "start" ? proceed() : notFound();
				},
			},
			{ path: "*", status: 404, component: Missing },
		] },
	]);
	const history = memory("/docs/missing");
	const router = opened(routes, history);
	const root = mounted(router);
	assert mockToString(root) === "<root><main><h1>missing</h1></main></root>", mockToString(root);
	assert router.navigate("/");
	flush();
	assert router.navigate("/docs/gone");
	flush();
	assert router.navigate("/");
	flush();
	assert history.go(-1);
	flush();
	assert history.read().url === "/docs/gone", history.read().url;
	assert mockToString(root) === "<root><main><h1>missing</h1></main></root>", mockToString(root);
	assert history.go(-2);
	flush();
	assert history.read().url === "/docs/missing", history.read().url;
	assert mockToString(root) === "<root><main><h1>missing</h1></main></root>", mockToString(root);
	router.dispose();
}

test "a redirect loop fails loudly, naming where it started" {
	const routes = createRoutes([
		{ path: "/a", component: Home, guard: (p: Map<string, string>, f: RouteMatch): GuardDecision => redirect("/b") },
		{ path: "/b", component: Home, guard: (p: Map<string, string>, f: RouteMatch): GuardDecision => redirect("/a") },
	]);
	let message = "";
	try { createRouter(routes, createRequestRoutingHistory("/a")); } catch (error) { message = error.message; }
	assert message === "routing: more than 20 redirects from \"/a\"", message;
}

test "an address no route takes is an error before anything mounts" {
	const routes = createRoutes([{ path: "/", component: Home }]);
	const router = createRouter(routes, createRequestRoutingHistory("/elsewhere"));
	assert !router.ok;
	if (!router.ok) { assert router.error === RoutingError.NoMatch; }
}

test "useNavigate, useLocation and useMatch read and drive the router" {
	const routes = createRoutes([
		{ layout: Probe, children: [
			{ path: "/", component: Home },
			{ path: "/docs/:slug", component: Doc },
		] },
	]);
	const history = memory("/?q=1");
	const router = opened(routes, history);
	const root = mounted(router);
	assert mockToString(root) === "<root><div><p>/|-|1</p><h1>home</h1></div></root>", mockToString(root);
	const navigate = go as (to: string | int32, options?: NavigateOptions | null) => boolean;
	assert navigate("/docs/start");
	flush();
	assert mockToString(root) === "<root><div><p>/docs/start|start|</p><h1>doc start</h1></div></root>", mockToString(root);
	assert navigate("/docs/routing", { replace: true });
	flush();
	assert history.read().url === "/docs/routing";
	assert history.go(-1);
	flush();
	assert history.read().url === "/?q=1";
	assert mockToString(root) === "<root><div><p>/|-|1</p><h1>home</h1></div></root>", mockToString(root);
}

test "A marks the link to the current page with aria-current" {
	const routes = createRoutes([
		{ layout: Links, children: [
			{ path: "/", component: Home },
			{ path: "/docs/:slug", component: Doc },
		] },
	]);
	const router = opened(routes, memory("/docs/start/"));
	const root = mounted(router);
	assert mockToString(root) === "<root><nav><a href=\"/\" class=\"active\">Home</a><a href=\"/docs/start\" aria-current=\"page\" class=\"active\">Start</a><a href=\"/docs/routing#notes\" class=\"inactive\">Notes</a><h1>doc start</h1></nav></root>", mockToString(root);
	assert router.navigate("/docs/routing");
	flush();
	assert mockToString(root) === "<root><nav><a href=\"/\" class=\"active\">Home</a><a href=\"/docs/start\" class=\"inactive\">Start</a><a href=\"/docs/routing#notes\" class=\"active\" aria-current=\"page\">Notes</a><h1>doc routing</h1></nav></root>", mockToString(root);
}

test "a route tree refuses a leaf without a component and a component beside children" {
	const bare = failure((): Routes => createRoutes([{ path: "/" }]));
	assert bare === "routing: \"/\" has neither children nor a component", bare;
	const both = failure((): Routes => createRoutes([
		{ path: "/docs", component: Home, children: [{ path: ":slug", component: Doc }] },
	]));
	assert both === "routing: \"/docs\" has children, so it takes a layout, not a component", both;
	const lone = failure((): Routes => createRoutes([{ path: "/", layout: Shell }]));
	assert lone === "routing: \"/\" has a layout but no children to lay out", lone;
}

test "a route tree takes a typed route, whose codec decides the addresses it matches" {
	const routes = createRoutes([
		{ layout: Shell, children: [
			{ route: thread, component: Thread },
			{ path: "*", status: 404, component: Missing },
		] },
	]);
	const router = opened(routes, memory("/threads/7"));
	const root = mounted(router);
	assert mockToString(root) === "<root><main><h1>thread 7</h1></main></root>", mockToString(root);
	assert router.navigate("/threads/seven");
	assert mockToString(root) === "<root><main><h1>missing</h1></main></root>", mockToString(root);
	assert router.response().status === 404;
	router.dispose();
	const both = failure((): Routes => createRoutes([{ path: "/threads", route: thread, component: Thread }]));
	assert both === "routing: \"/threads/:id\" takes its path, status, guard, paths and preload from its route", both;
}

struct ProjectParams {
	project: string;
}

const projectCodec: ParamsCodec<ProjectParams> = {
	parse: (values: Map<string, string>): Result<ProjectParams, RoutingError> => {
		const project = values.get("project") ?? "";
		return project.length === 0 ? Result.err(RoutingError.InvalidParams) : Result.ok({ project });
	},
	stringify: (params: ProjectParams): Map<string, string> => {
		const values = new Map<string, string>();
		values.set("project", params.project);
		return values;
	},
};

const project = route<ProjectParams>("/projects/:project", { params: projectCodec });

function ProjectFrame(props: LayoutProps): NeonNode {
	return <main><h2>{"project " + useParams({ from: project }).project}</h2>{props.children}</main>;
}

function ProjectItem(): NeonNode {
	return <p>{useParams({ from: project }).project + " item " + (useParams().get("item") ?? "")}</p>;
}

function TypedThread(): NeonNode {
	const params: ThreadParams = useParams({ from: thread });
	return <h1>{"thread " + params.id}</h1>;
}

function StrayThread(): NeonNode {
	return <h1>{useParams({ from: project }).project}</h1>;
}

test "useParams({ from }) reads a route's own params or an ancestor's through its codec, and refuses a route off the path" {
	const routes = createRoutes([
		{ route: thread, component: TypedThread },
		{ route: project, layout: ProjectFrame, children: [{ path: ":item", component: ProjectItem }] },
	]);
	const router = opened(routes, memory("/threads/7"));
	const root = mounted(router);
	assert mockToString(root) === "<root><h1>thread 7</h1></root>", mockToString(root);
	assert router.navigate("/projects/neon/42");
	assert mockToString(root) === "<root><main><h2>project neon</h2><p>neon item 42</p></main></root>", mockToString(root);
	router.dispose();
	const stray = opened(createRoutes([{ route: thread, component: StrayThread }]), memory("/threads/7"));
	let refused = "";
	try { mounted(stray); } catch (error) { refused = error.message; }
	resetErrorHalt();
	stray.dispose();
	assert refused === "routing: useParams({ from }) names /projects/:project, which is not on this component's route", refused;
}

function QueriedThread(): NeonNode {
	const location = useLocation();
	return <h1>{"thread " + useParams({ from: thread }).id + "|" + (location().search.get("q") ?? "-")}</h1>;
}

test "navigate({ to, params }) writes a typed route's address through its codec, and refuses a route outside the tree" {
	const history = memory("/threads/7");
	const router = opened(createRoutes([{ route: thread, component: QueriedThread }]), history);
	const root = mounted(router);
	assert router.navigate({ to: thread, params: { id: "8" } });
	flush();
	assert mockToString(root) === "<root><h1>thread 8|-</h1></root>", mockToString(root);
	const search = new Map<string, string>();
	search.set("q", "a b");
	assert router.navigate({ to: thread, params: { id: "9" }, search, replace: true });
	flush();
	assert history.read().url === "/threads/9?q=a%20b", history.read().url;
	assert mockToString(root) === "<root><h1>thread 9|a b</h1></root>", mockToString(root);
	assert history.go(-1);
	flush();
	assert mockToString(root) === "<root><h1>thread 7|-</h1></root>", mockToString(root);
	let refused = "";
	try { router.navigate({ to: project, params: { project: "neon" } }); } catch (error) { refused = error.message; }
	assert refused === "routing: navigate({ to }) cannot build an address for /projects/:project: NoMatch", refused;
	router.dispose();
}

test "static paths come from the route tree, with enumerated params" {
	const routes = createRoutes([
		{ layout: Shell, children: [
			{ path: "/", component: Home },
			{
				path: "/docs/:slug",
				component: Doc,
				paths: (): Map<string, string>[] => {
					const start = new Map<string, string>();
					start.set("slug", "start");
					return [start];
				},
			},
			{ path: "*", status: 404, component: Missing },
		] },
	]);
	const paths = routes.tree.staticPaths();
	assert paths.ok;
	if (paths.ok) { assert paths.value.join(",") === "/,/docs/start", paths.value.join(","); }
}

test "a search or hash change pushes an entry as Solid's navigate does, and keeps the page" {
	docs = 0;
	const routes = createRoutes([
		{ layout: Probe, children: [
			{ path: "/", component: Home },
			{ path: "/docs/:slug", component: Doc },
		] },
	]);
	const history = memory("/docs/start?q=1");
	const router = opened(routes, history);
	const root = mounted(router);
	const navigate = go as (to: string | int32, options?: NavigateOptions | null) => boolean;
	assert navigate("/docs/start?q=2");
	flush();
	assert navigate("/docs/start?q=2#top");
	flush();
	assert navigate("/docs/start?q=3", { replace: true });
	flush();
	assert history.read().url === "/docs/start?q=3", history.read().url;
	assert history.go(-1);
	flush();
	assert history.read().url === "/docs/start?q=2", history.read().url;
	assert history.go(-1);
	flush();
	assert history.read().url === "/docs/start?q=1", history.read().url;
	assert mockToString(root) === "<root><div><p>/docs/start|start|1</p><h1>doc start</h1></div></root>", mockToString(root);
	assert !router.canGoBack();
	assert docs === 1, "a search change remounted the page";
}

test "navigate takes a history delta as Solid's does, and canGoBack follows the entries this app wrote" {
	const routes = createRoutes([
		{ layout: Probe, children: [
			{ path: "/", component: Home },
			{ path: "/docs/:slug", component: Doc },
		] },
	]);
	const router = opened(routes, memory("/"));
	const root = mounted(router);
	const navigate = go as (to: string | int32, options?: NavigateOptions | null) => boolean;
	const seen: boolean[] = [];
	const stop = createRoot((dispose: Dispose): Dispose => {
		createRenderEffect<boolean>((prev: boolean | null): boolean => router.canGoBack(), (back: boolean, prev: boolean | null): Cleanup | null => { seen.push(back); return null; });
		return dispose;
	});
	assert navigate("/docs/start");
	flush();
	assert navigate(-1);
	flush();
	assert mockToString(root) === "<root><div><p>/|-|</p><h1>home</h1></div></root>", mockToString(root);
	assert navigate(1);
	flush();
	assert mockToString(root) === "<root><div><p>/docs/start|start|</p><h1>doc start</h1></div></root>", mockToString(root);
	assert seen.join(",") === "false,true,false,true", seen.join(",");
	stop();
}

const trace: string[] = [];

function note(entry: string): void {
	trace.push(entry);
}

function seen(): string {
	const text = trace.join(" | ");
	trace.length = 0;
	return text;
}

function PreloadedHome(): NeonNode {
	note("render home");
	return <h1>home</h1>;
}

function PreloadedDoc(): NeonNode {
	note("render doc");
	return <h1>{"doc " + (useParams().get("slug") ?? "")}</h1>;
}

function PreloadedThread(): NeonNode {
	note("render thread");
	return <h1>{"thread " + useParams({ from: watched }).id}</h1>;
}

const watched = route<ThreadParams>("/threads/:id", {
	params: threadCodec,
	preload: (args: PreloadArgs<ThreadParams>): void => {
		note("thread " + args.params.id + " " + args.intent + " " + args.location.pathname);
	},
});

function preloadRoutes(): Routes {
	return createRoutes([
		{ layout: Shell, children: [
			{
				path: "/",
				component: PreloadedHome,
				preload: (args: PreloadArgs<Map<string, string>>): void => { note("home " + args.intent); },
			},
			{
				path: "/docs/:slug",
				component: PreloadedDoc,
				preload: (args: PreloadArgs<Map<string, string>>): void => {
					note("doc " + (args.params.get("slug") ?? "") + " " + args.intent + " " + args.location.pathname + " q=" + (args.location.search.get("q") ?? "-"));
				},
			},
			{ route: watched, component: PreloadedThread },
		] },
	]);
}

test "a route's preload runs once before its component, as initial at open and navigate on a link, as Solid's createRouteContext does" {
	seen();
	const router = opened(preloadRoutes(), memory("/"));
	const root = mounted(router);
	assert seen() === "home initial | render home", "open";
	assert router.navigate("/docs/start?q=1");
	flush();
	assert mockToString(root) === "<root><main><h1>doc start</h1></main></root>", mockToString(root);
	assert seen() === "doc start navigate /docs/start q=1 | render doc", "navigate";
	assert router.navigate("/docs/start?q=2");
	flush();
	assert seen() === "", "a search change re-ran the preload";
	assert router.navigate("/docs/other");
	flush();
	assert seen() === "doc other navigate /docs/other q=- | render doc", "param change";
	router.dispose();
}

test "a typed route's preload takes its params through the codec, as useParams({ from }) does" {
	seen();
	const router = opened(preloadRoutes(), memory("/threads/7"));
	const root = mounted(router);
	assert seen() === "thread 7 initial /threads/7 | render thread", "open";
	assert router.navigate({ to: watched, params: { id: "8" } });
	flush();
	assert mockToString(root) === "<root><main><h1>thread 8</h1></main></root>", mockToString(root);
	assert seen() === "thread 8 navigate /threads/8 | render thread", "navigate";
	router.dispose();
}

test "a history move preloads the page it shows with the native intent" {
	seen();
	const history = memory("/");
	const router = opened(preloadRoutes(), history);
	mounted(router);
	seen();
	assert router.navigate("/docs/a");
	flush();
	seen();
	assert history.go(-1);
	flush();
	const back = seen();
	assert back === "home native | render home", back;
	assert history.go(1);
	flush();
	assert seen() === "doc a native /docs/a q=- | render doc", "forward";
	router.dispose();
}

test "a parent's preload runs before its child's, which runs as the parent renders its children" {
	seen();
	const routes = createRoutes([
		{ path: "/area", layout: Shell, preload: (args: PreloadArgs<Map<string, string>>): void => { note("area " + args.intent + " " + args.location.pathname); }, children: [
			{ path: "", component: PreloadedHome },
			{
				path: ":leaf",
				component: PreloadedDoc,
				preload: (args: PreloadArgs<Map<string, string>>): void => { note("leaf " + (args.params.get("leaf") ?? "") + " " + args.intent); },
			},
		] },
	]);
	const router = opened(routes, memory("/area/x"));
	mounted(router);
	assert seen() === "area initial /area/x | leaf x initial | render doc", "open";
	assert router.navigate("/area/y");
	flush();
	assert seen() === "leaf y navigate | render doc", "sibling";
	router.dispose();
}

test "preload(href) runs the preloads along an address with the preload intent and mounts nothing" {
	seen();
	const router = opened(preloadRoutes(), memory("/"));
	const root = mounted(router);
	seen();
	router.preload("/docs/next?q=9");
	router.preload("/threads/12");
	router.preload("/nowhere/at/all");
	assert seen() === "doc next preload /docs/next q=9 | thread 12 preload /threads/12", "preload";
	assert mockToString(root) === "<root><main><h1>home</h1></main></root>", mockToString(root);
	router.dispose();
}

test "a config naming a preload beside a typed route is refused" {
	const both = failure((): Routes => createRoutes([{ route: watched, preload: (args: PreloadArgs<Map<string, string>>): void => {}, component: Thread }]));
	assert both === "routing: \"/threads/:id\" takes its path, status, guard, paths and preload from its route", both;
}
