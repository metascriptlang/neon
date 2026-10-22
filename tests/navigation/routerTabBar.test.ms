import { flush } from "../../src/core/runtime";
import { Signal } from "../../src/core/signal";
import { NeonNode } from "../../src/render/hostTypes";
import { element } from "../../src/macros/ui/element";
import { For } from "../../src/macros/ui/flow";
import { HostNode, MockNode, mockNode, mockHost, render } from "../../src/render/host";
import { RoutingHistory, createMemoryRoutingHistory } from "../../src/navigation/routingHistory";
import { ScreenOptions } from "../../src/navigation/core";
import { TabBar, TabTrigger, useTabs } from "../../src/navigation/tabBar";
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
import { attrOf, findLabel, press, visibleText } from "./navHarness";

const unread = new Signal<int32>(0);

function Feed(): NeonNode {
	return <h1>feed</h1>;
}

function Inbox(): NeonNode {
	return <h1>inbox</h1>;
}

function Thread(): NeonNode {
	return <h1>{"thread " + (useParams().get("id") ?? "")}</h1>;
}

function Profile(): NeonNode {
	return <h1>profile</h1>;
}

function inboxOptions(): ScreenOptions {
	const count = unread.get();
	return { title: "Inbox", tabBarBadge: count === 0 ? null : count.toString() };
}

function tabChildren(): Routes {
	return createRoutes([
		{ navigator: Tabs, children: [
			{ path: "/feed", component: Feed, options: { title: "Feed" } },
			{ path: "/inbox", navigator: Stack, options: inboxOptions, children: [
				{ path: "", component: Inbox },
				{ path: ":id", component: Thread },
			] },
			{ path: "/profile", component: Profile, options: { title: "Profile", tabBarLabel: "Me" } },
		] },
	]);
}

function opened(routes: Routes, history: RoutingHistory): Router {
	const router = createRouter(routes, history);
	if (!router.ok) { throw new Error("router: " + router.error.toString()); }
	return router.value;
}

function mounted(router: Router): MockNode {
	const root: MockNode = mockNode("root");
	render(element(<RouterProvider router={router} />), mockHost(), root as unknown as HostNode);
	flush();
	return root;
}

function failure(build: () => void): string {
	try { build(); } catch (error) { return error.message; }
	return "";
}

test "Tabs without a layout draw React Navigation's bottom tab bar, labelled from each route's options" {
	unread.set(0);
	const router = opened(tabChildren(), createMemoryRoutingHistory({ url: "/feed", state: "" }));
	const root = mounted(router);
	assert visibleText(root) === "feed|Feed|Inbox|Me", visibleText(root);
	const feed = findLabel(root, "Feed") as MockNode;
	assert attrOf(feed, "accessibilityRole") === "tab", attrOf(feed, "accessibilityRole");
	unread.set(3);
	flush();
	assert visibleText(root) === "feed|Feed|Inbox|3|Me", visibleText(root);
	router.dispose();
}

test "pressing another tab shows it as it was left, and pressing the shown tab pops its stack to the root" {
	unread.set(0);
	const cold = opened(tabChildren(), createMemoryRoutingHistory({ url: "/inbox/42", state: "" }));
	const deep = mounted(cold);
	press(deep, "Inbox");
	assert visibleText(deep).startsWith("thread 42|"), visibleText(deep);
	cold.dispose();
	const history = createMemoryRoutingHistory({ url: "/inbox", state: "" });
	const router = opened(tabChildren(), history);
	const root = mounted(router);
	assert router.navigate("/inbox/42");
	flush();
	assert visibleText(root).startsWith("thread 42|"), visibleText(root);
	press(root, "Feed");
	assert visibleText(root).startsWith("feed|"), visibleText(root);
	assert history.read().url === "/feed", history.read().url;
	press(root, "Inbox");
	assert visibleText(root).startsWith("thread 42|"), visibleText(root);
	assert history.read().url === "/inbox/42", history.read().url;
	assert history.go(-1);
	flush();
	assert visibleText(root).startsWith("inbox|"), visibleText(root);
	assert history.go(-1);
	flush();
	assert visibleText(root).startsWith("feed|"), visibleText(root);
	assert history.go(2);
	flush();
	assert visibleText(root).startsWith("thread 42|"), visibleText(root);
	press(root, "Inbox");
	assert visibleText(root).startsWith("inbox|"), visibleText(root);
	assert history.read().url === "/inbox", history.read().url;
	assert router.location().pathname === "/inbox", router.location().pathname;
	press(root, "Inbox");
	assert visibleText(root).startsWith("inbox|"), visibleText(root);
	router.dispose();
}

function Shell(props: LayoutProps): NeonNode {
	return <main>{props.children}<TabBar /></main>;
}

function Links(props: LayoutProps): NeonNode {
	const tabs = useTabs();
	return <main>
		{props.children}
		<nav>
			<For each={tabs}>{(tab: TabTrigger): NeonNode => {
				return <p>{tab.label() + " " + (tab.href() ?? "") + (tab.focused() ? " *" : "")}</p>;
			}}</For>
		</nav>
	</main>;
}

test "a layout places the default bar itself, or draws its own from useTabs with each tab's live address" {
	const shell = opened(createRoutes([
		{ layout: Shell, navigator: Tabs, children: [
			{ path: "/feed", component: Feed, options: { title: "Feed" } },
			{ path: "/profile", component: Profile },
		] },
	]), createMemoryRoutingHistory({ url: "/profile", state: "" }));
	const framed = mounted(shell);
	assert visibleText(framed) === "profile|Feed|profile", visibleText(framed);
	shell.dispose();
	const links = opened(createRoutes([
		{ layout: Links, navigator: Tabs, children: [
			{ path: "/feed", component: Feed, options: { title: "Feed" } },
			{ path: "/inbox", navigator: Stack, options: { title: "Inbox" }, children: [
				{ path: "", component: Inbox },
				{ path: ":id", component: Thread },
			] },
		] },
	]), createMemoryRoutingHistory({ url: "/feed", state: "" }));
	const drawn = mounted(links);
	assert visibleText(drawn) === "feed|Feed /feed *|Inbox /inbox", visibleText(drawn);
	assert links.navigate("/inbox/7");
	flush();
	assert links.navigate("/feed");
	flush();
	assert visibleText(drawn) === "feed|Feed /feed *|Inbox /inbox/7", visibleText(drawn);
	links.dispose();
}

test "tab options outside Tabs and useTabs outside a Tabs layout are refused where they are written" {
	const declared = failure((): void => {
		createRoutes([{ navigator: Stack, children: [{ path: "/feed", component: Feed, options: { title: "Feed" } }] }]);
	});
	assert declared === "routing: \"/feed\" names options, which only a route in Tabs reads", declared;
	const outside = opened(createRoutes([
		{ layout: Links, navigator: Stack, children: [{ path: "/feed", component: Feed }] },
	]), createMemoryRoutingHistory({ url: "/feed", state: "" }));
	const used = failure((): void => { mounted(outside); });
	assert used === "navigation: useTabs is called outside the layout of a Tabs route", used;
}
