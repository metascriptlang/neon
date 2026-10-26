import { flush } from "../../src/core/runtime";
import { NeonNode } from "../../src/render/hostTypes";
import { element } from "../../src/macros/ui/element";
import { HostNode, MockNode, mockNode, mockHost, render } from "../../src/render/host";
import { RoutingHistory, createMemoryRoutingHistory } from "../../src/navigation/routingHistory";
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

function Shell(props: LayoutProps): NeonNode { return <main>{props.children}</main>; }
function Home(): NeonNode { return <h1>home</h1>; }
function Feed(): NeonNode { return <h1>feed</h1>; }
function Post(): NeonNode { return <h1>{"post " + (useParams().get("post") ?? "")}</h1>; }
function Inbox(): NeonNode { return <h1>inbox</h1>; }
function Thread(): NeonNode { return <h1>{"thread " + (useParams().get("id") ?? "")}</h1>; }

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
	]);
}

function open(history: RoutingHistory): Router {
	const r = createRouter(appRoutes(), history);
	if (!r.ok) { throw new Error("router " + r.error.toString()); }
	return r.value;
}

function mounted(router: Router): MockNode {
	const root: MockNode = mockNode("root");
	render(element(<RouterProvider router={router} />), mockHost(), root as unknown as HostNode);
	return root;
}

test "a link to a tab root whose stack is retained writes that root as a new entry" {
	const history = createMemoryRoutingHistory({ url: "/", state: "" });
	const router = open(history);
	const root = mounted(router);
	router.navigate("/feed/1"); flush();
	router.navigate("/inbox"); flush();
	router.navigate("/feed"); flush();
	assert history.read().url === "/feed", history.read().url;
	assert router.location().pathname === "/feed", router.location().pathname;
	assert visibleText(root) === "feed", visibleText(root);
	assert history.go(-1);
	flush();
	assert history.read().url === "/feed/1", history.read().url;
	assert visibleText(root) === "post 1", visibleText(root);
	assert history.go(-1);
	flush();
	assert history.read().url === "/", history.read().url;
	assert visibleText(root) === "home", visibleText(root);
	router.dispose();
}

test "reload at a tab root pushed over a retained stack restores the root" {
	const history = createMemoryRoutingHistory({ url: "/", state: "" });
	const router = open(history);
	mounted(router);
	router.navigate("/feed/1"); flush();
	router.navigate("/inbox"); flush();
	router.navigate("/feed"); flush();
	router.dispose();
	const again = open(history);
	const root = mounted(again);
	assert history.read().url === "/feed", history.read().url;
	assert again.location().pathname === "/feed", again.location().pathname;
	assert visibleText(root) === "feed", visibleText(root);
	again.dispose();
}
