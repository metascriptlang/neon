import { flush } from "../../src/core/runtime";
import { NeonNode } from "../../src/render/hostTypes";
import { element } from "../../src/macros/ui/element";
import { HostNode, MockNode, mockNode, mockHost, render, mockToString } from "../../src/render/host";
import { RoutingSnapshot } from "../../src/navigation/routing";
import { BackBehavior } from "../../src/navigation/childPages";
import { createMemoryRoutingHistory } from "../../src/navigation/routingHistory";
import {
	LayoutProps,
	Router,
	RouterProvider,
	Routes,
	Stack,
	Tabs,
	createRouter,
	createRoutes,
	useParams,
} from "../../src/navigation/router";
import { visibleText } from "./navHarness";

let mounts = "";

function Shell(props: LayoutProps): NeonNode {
	return <main>{props.children}</main>;
}

function Home(): NeonNode {
	return <h1>home</h1>;
}

function Feed(): NeonNode {
	mounts += "feed;";
	return <h1>feed</h1>;
}

function Post(): NeonNode {
	mounts += "post;";
	return <h1>{"post " + (useParams().get("post") ?? "")}</h1>;
}

function Inbox(): NeonNode {
	return <h1>inbox</h1>;
}

function Thread(): NeonNode {
	mounts += "thread;";
	return <h1>{"thread " + (useParams().get("id") ?? "")}</h1>;
}

function Missing(): NeonNode {
	return <h1>missing</h1>;
}

function Profile(): NeonNode {
	return <h1>profile</h1>;
}

function visitRoutes(behavior: BackBehavior): Routes {
	return createRoutes([
		{ layout: Shell, navigator: Tabs, backBehavior: behavior, children: [
			{ path: "/feed", component: Feed },
			{ path: "/inbox", component: Inbox },
			{ path: "/profile", component: Profile },
		] },
	]);
}

function appRoutes(): Routes {
	return createRoutes([
		{ path: "/", component: Home },
		{ layout: Shell, navigator: Tabs, children: [
			{ path: "/feed", navigator: Stack, children: [
				{ path: "", component: Feed },
				{ path: ":post", component: Post },
			] },
			{ path: "/inbox", navigator: Stack, initial: "", children: [
				{ path: "", component: Inbox },
				{ path: ":id", component: Thread },
			] },
		] },
		{ path: "*", status: 404, component: Missing },
	]);
}

function opened(url: string): Router {
	const router = createRouter(appRoutes(), createMemoryRoutingHistory({ url, state: "" }));
	if (!router.ok) { throw new Error("router: " + router.error.toString()); }
	return router.value;
}

function mounted(router: Router): MockNode {
	const root: MockNode = mockNode("root");
	render(element(<RouterProvider router={router} />), mockHost(), root as unknown as HostNode);
	return root;
}

function shown(root: MockNode): string {
	const text = mockToString(root);
	return text.substring("<root>".length, text.length - "</root>".length);
}

function failure(build: () => Routes): string {
	try { build(); } catch (error) { return error.message; }
	return "";
}

test "a cold address opens its tab on the stack's initial route below the destination" {
	const history = createMemoryRoutingHistory({ url: "/inbox/42", state: "" });
	const created = createRouter(appRoutes(), history);
	assert created.ok;
	if (!created.ok) { return; }
	const router = created.value;
	const root = mounted(router);
	assert visibleText(root) === "thread 42", visibleText(root);
	assert shown(root).includes("<h1>inbox</h1>"), shown(root);
	assert history.read().url === "/inbox/42", history.read().url;
	assert router.location().pathname === "/inbox/42";
	assert router.navigate("/feed");
	flush();
	assert visibleText(root) === "feed", visibleText(root);
	router.dispose();
}

test "the initial route goes below a cold address only, not below an in-app one" {
	const router = opened("/");
	const root = mounted(router);
	assert visibleText(root) === "home", visibleText(root);
	assert router.navigate("/inbox/42");
	flush();
	assert visibleText(root) === "thread 42", visibleText(root);
	assert !shown(root).includes("<h1>inbox</h1>"), shown(root);
	router.dispose();
}

test "each tab keeps its stack and its mounted screens while the other tab is shown" {
	mounts = "";
	const history = createMemoryRoutingHistory({ url: "/feed", state: "" });
	const created = createRouter(appRoutes(), history);
	assert created.ok;
	if (!created.ok) { return; }
	const router = created.value;
	const root = mounted(router);
	assert visibleText(root) === "feed", visibleText(root);
	assert router.navigate("/feed/1");
	flush();
	assert visibleText(root) === "post 1", visibleText(root);
	assert history.go(-1);
	flush();
	assert visibleText(root) === "feed", visibleText(root);
	assert history.read().url === "/feed", history.read().url;
	assert history.go(1);
	flush();
	assert visibleText(root) === "post 1", visibleText(root);
	assert router.navigate("/inbox/7");
	flush();
	assert visibleText(root) === "thread 7", visibleText(root);
	assert history.read().url === "/inbox/7", history.read().url;
	assert router.navigate("/feed/1");
	flush();
	assert visibleText(root) === "post 1", visibleText(root);
	assert history.read().url === "/feed/1", history.read().url;
	assert router.navigate("/inbox/7");
	flush();
	assert visibleText(root) === "thread 7", visibleText(root);
	assert router.navigate("/inbox/8");
	flush();
	assert visibleText(root) === "thread 8", visibleText(root);
	assert shown(root).includes("<h1>thread 7</h1>"), shown(root);
	assert history.go(-1);
	flush();
	assert visibleText(root) === "thread 7", visibleText(root);
	assert history.read().url === "/inbox/7", history.read().url;
	assert mounts === "feed;post;post;thread;thread;", mounts;
	router.dispose();
}

test "browser back from another tab returns to the first tab where it was, then down its stack" {
	const history = createMemoryRoutingHistory({ url: "/", state: "" });
	const created = createRouter(appRoutes(), history);
	assert created.ok;
	if (!created.ok) { return; }
	const router = created.value;
	const root = mounted(router);
	assert router.navigate("/feed");
	flush();
	assert router.navigate("/feed/1");
	flush();
	assert router.navigate("/inbox");
	flush();
	assert visibleText(root) === "inbox", visibleText(root);
	assert history.index() === 3, history.index().toString();
	assert history.go(-1);
	flush();
	assert visibleText(root) === "post 1", visibleText(root);
	assert history.read().url === "/feed/1", history.read().url;
	assert history.go(-1);
	flush();
	assert visibleText(root) === "feed", visibleText(root);
	assert history.go(-1);
	flush();
	assert visibleText(root) === "home", visibleText(root);
	assert history.go(3);
	flush();
	assert visibleText(root) === "inbox", visibleText(root);
	assert router.navigate("/feed/1");
	flush();
	assert visibleText(root) === "post 1", visibleText(root);
	assert history.index() === 2, history.index().toString();
	assert history.go(-2);
	flush();
	assert visibleText(root) === "home", visibleText(root);
	router.dispose();
}

test "tabs with a history back behavior walk the visits back, as the browser restores them" {
	const history = createMemoryRoutingHistory({ url: "/feed", state: "" });
	const created = createRouter(visitRoutes("history"), history);
	assert created.ok;
	if (!created.ok) { return; }
	const router = created.value;
	const root = mounted(router);
	assert router.navigate("/inbox");
	flush();
	assert router.navigate("/profile");
	flush();
	assert router.navigate("/inbox");
	flush();
	assert history.index() === 2, history.index().toString();
	assert history.go(-1);
	flush();
	assert visibleText(root) === "profile", visibleText(root);
	assert history.go(-1);
	flush();
	assert visibleText(root) === "feed", visibleText(root);
	assert history.go(2);
	flush();
	assert visibleText(root) === "inbox", visibleText(root);
	assert history.go(-1);
	flush();
	assert router.navigate("/feed");
	flush();
	assert history.index() === 1, history.index().toString();
	assert history.go(-1);
	flush();
	assert visibleText(root) === "profile", visibleText(root);
	router.dispose();
}

test "tabs with no back behavior replace the entry on a switch" {
	const history = createMemoryRoutingHistory({ url: "/feed", state: "" });
	const created = createRouter(visitRoutes("none"), history);
	assert created.ok;
	if (!created.ok) { return; }
	const router = created.value;
	const root = mounted(router);
	assert router.navigate("/inbox");
	flush();
	assert router.navigate("/profile");
	flush();
	assert visibleText(root) === "profile", visibleText(root);
	assert history.index() === 0, history.index().toString();
	assert history.read().url === "/profile", history.read().url;
	router.dispose();
}

test "an entry whose router state does not parse opens from its address" {
	const history = createMemoryRoutingHistory({ url: "/feed", state: "" });
	const created = createRouter(appRoutes(), history);
	assert created.ok;
	if (!created.ok) { return; }
	const router = created.value;
	const root = mounted(router);
	const broken: RoutingSnapshot = { regions: [{ scope: "main", state: "not json" }] };
	history.push({ url: "/inbox/9", state: JSON.stringify(broken) });
	assert history.go(-1);
	flush();
	assert visibleText(root) === "feed", visibleText(root);
	assert history.go(1);
	flush();
	assert visibleText(root) === "thread 9", visibleText(root);
	assert router.location().pathname === "/inbox/9", router.location().pathname;
	router.dispose();
}

test "a route tree refuses a navigator without children, a misplaced initial route or back behavior" {
	const bare = failure((): Routes => createRoutes([{ path: "/feed", navigator: Stack }]));
	assert bare === "routing: \"/feed\" has a navigator but no children to navigate", bare;
	const tabs = failure((): Routes => createRoutes([
		{ path: "/app", navigator: Tabs, initial: "", children: [{ path: "", component: Home }] },
	]));
	assert tabs === "routing: \"/app\" names an initial route, which only a Stack takes", tabs;
	const params = failure((): Routes => createRoutes([
		{ path: "/inbox", navigator: Stack, initial: ":id", children: [{ path: ":id", component: Thread }] },
	]));
	assert params === "routing: the initial route \":id\" of \"/inbox\" takes params", params;
	const absent = failure((): Routes => createRoutes([
		{ path: "/inbox", navigator: Stack, initial: "all", children: [{ path: "", component: Inbox }] },
	]));
	assert absent === "routing: \"/inbox\" has no child \"all\" to start on", absent;
	const stacked = failure((): Routes => createRoutes([
		{ path: "/inbox", navigator: Stack, backBehavior: "history", children: [{ path: "", component: Inbox }] },
	]));
	assert stacked === "routing: \"/inbox\" names a backBehavior, which only Tabs take", stacked;
	const initial = failure((): Routes => createRoutes([
		{ path: "/app", navigator: Tabs, backBehavior: "initialRoute", children: [{ path: "", component: Home }] },
	]));
	assert initial === "routing: \"/app\" goes back to its initial route, which Tabs do not take", initial;
}
