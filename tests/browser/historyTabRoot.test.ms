import { sleepAsync } from "std/core/promise";
import { flush } from "../../src/core/runtime";
import { NeonNode } from "../../src/render/hostTypes";
import { element } from "../../src/macros/ui/element";
import { HostNode, MockNode, mockNode, mockHost, render } from "../../src/render/host";
import { createBrowserRoutingHistory } from "../../src/platform/browser/routingHistory";
import { RoutingHistory } from "../../src/navigation/routingHistory";
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
} from "../../src/navigation/index";
import { visibleText } from "../navigation/navHarness";

function Shell(props: LayoutProps): NeonNode { return <main>{props.children}</main>; }
function Home(): NeonNode { return <h1>home</h1>; }
function Feed(): NeonNode { return <h1>feed</h1>; }
function Post(): NeonNode { return <h1>{"post " + (useParams().get("post") ?? "")}</h1>; }
function Inbox(): NeonNode { return <h1>inbox</h1>; }

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
			] },
		] },
	]);
}

function start(history: RoutingHistory, root: MockNode): Router {
	const created = createRouter(appRoutes(), history);
	if (!created.ok) { throw new Error("router " + created.error.toString()); }
	render(element(<RouterProvider router={created.value} />), mockHost(), root as unknown as HostNode);
	return created.value;
}

test "a link to a tab root with a retained stack writes the root to the browser and back walks it" {
	const history = createBrowserRoutingHistory();
	const original = history.read();
	history.replace({ url: "/", state: "" });
	const root: MockNode = mockNode("root");
	const router = start(history, root);
	try {
		assert router.navigate("/feed/1");
		flush();
		assert router.navigate("/inbox");
		flush();
		assert router.navigate("/feed");
		flush();
		await sleepAsync(100);
		assert history.read().url === "/feed", history.read().url;
		assert history.go(-1);
		await sleepAsync(100);
		assert history.read().url === "/feed/1", history.read().url;
		assert visibleText(root) === "post 1", visibleText(root);
		assert history.go(1);
		await sleepAsync(100);
		assert history.read().url === "/feed", history.read().url;
		assert visibleText(root) === "feed", visibleText(root);
	} finally {
		router.dispose();
		history.replace(original);
	}
}

test "a reload at a tab root pushed over a retained stack keeps the root" {
	const history = createBrowserRoutingHistory();
	const original = history.read();
	history.replace({ url: "/", state: "" });
	const router = start(history, mockNode("root"));
	try {
		assert router.navigate("/feed/1");
		flush();
		assert router.navigate("/inbox");
		flush();
		assert router.navigate("/feed");
		flush();
		await sleepAsync(100);
		router.dispose();
		const root: MockNode = mockNode("root");
		const again = start(history, root);
		assert history.read().url === "/feed", history.read().url;
		assert again.location().pathname === "/feed", again.location().pathname;
		assert visibleText(root) === "feed", visibleText(root);
		again.dispose();
	} finally {
		history.replace(original);
	}
}
