import { NeonNode } from "../../src/render/hostTypes";
import { element } from "../../src/macros/ui/element";
import { HostNode, MockNode, mockNode, mockHost, render, mockToString } from "../../src/render/host";
import { RoutingError } from "../../src/navigation/routing";
import {
	RoutingHistory,
	createMemoryRoutingHistory,
	createRequestRoutingHistory,
} from "../../src/navigation/routingHistory";
import { GuardDecision, RouteMatch, proceed, redirect } from "../../src/navigation/route";
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
let go: ((href: string, options?: NavigateOptions | null) => boolean) | null = null;

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
	assert docs === 1, "a search change replaced the page";
	assert router.navigate("/docs/routing");
	assert mockToString(root) === "<root><main><h1>doc routing</h1></main></root>", mockToString(root);
	assert docs === 2, "a path param change kept the page";
	assert router.navigate("/");
	assert mockToString(root) === "<root><main><h1>home</h1></main></root>", mockToString(root);
	assert layouts === 1, "the layout was rebuilt";
	assert history.read().url === "/";
	assert history.go(-1);
	assert mockToString(root) === "<root><main><h1>doc routing</h1></main></root>", mockToString(root);
	assert history.read().url === "/docs/routing";
	assert router.navigate("/nowhere/deep");
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
	assert visited.read().url === "/signin";
	assert visited.go(-1);
	assert visited.read().url === "/";
	assert !visited.go(-2);
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
	assert router.navigate("/");
	signedIn = false;
	assert history.go(-1);
	assert history.read().url === "/signin", history.read().url;
	assert router.location().pathname === "/signin";
	assert history.go(1);
	assert history.read().url === "/";
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
	const navigate = go as (href: string, options?: NavigateOptions | null) => boolean;
	assert navigate("/docs/start");
	assert mockToString(root) === "<root><div><p>/docs/start|start|</p><h1>doc start</h1></div></root>", mockToString(root);
	assert navigate("/docs/routing", { replace: true });
	assert history.read().url === "/docs/routing";
	assert history.go(-1);
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
	assert mockToString(root) === "<root><nav><a href=\"/\">Home</a><a href=\"/docs/start\" aria-current=\"page\">Start</a><a href=\"/docs/routing#notes\">Notes</a><h1>doc start</h1></nav></root>", mockToString(root);
	assert router.navigate("/docs/routing");
	assert mockToString(root) === "<root><nav><a href=\"/\">Home</a><a href=\"/docs/start\">Start</a><a href=\"/docs/routing#notes\" aria-current=\"page\">Notes</a><h1>doc routing</h1></nav></root>", mockToString(root);
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
