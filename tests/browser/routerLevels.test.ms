import { sleepAsync } from "std/core/promise";
import { flush } from "../../src/core/runtime";
import { NeonNode } from "../../src/render/hostTypes";
import { element } from "../../src/macros/ui/element";
import { HostNode, MockNode, mockNode, mockHost, render, mockToString } from "../../src/render/host";
import { createBrowserRoutingHistory } from "../../src/platform/browser/routingHistory";
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

function Shell(props: LayoutProps): NeonNode {
	return <main>{props.children}</main>;
}

function Feed(): NeonNode {
	return <h1>feed</h1>;
}

function Post(): NeonNode {
	return <h1>{"post " + (useParams().get("post") ?? "")}</h1>;
}

function Inbox(): NeonNode {
	return <h1>inbox</h1>;
}

function Thread(): NeonNode {
	return <h1>{"thread " + (useParams().get("id") ?? "")}</h1>;
}

function appRoutes(): Routes {
	return createRoutes([
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

function shown(root: MockNode): string {
	const text = mockToString(root);
	return text.substring("<root>".length, text.length - "</root>".length);
}

test "back and forward walk each tab's stack in real browser history" {
	const history = createBrowserRoutingHistory();
	const original = history.read();
	history.replace({ url: "/feed", state: "" });
	const created = createRouter(appRoutes(), history);
	assert created.ok;
	if (!created.ok) { return; }
	const router: Router = created.value;
	const root: MockNode = mockNode("root");
	render(element(<RouterProvider router={router} />), mockHost(), root as unknown as HostNode);
	try {
		assert router.navigate("/feed/1");
		flush();
		assert history.read().url === "/feed/1", history.read().url;
		assert history.go(-1);
		await sleepAsync(100);
		assert history.read().url === "/feed", history.read().url;
		assert visibleText(root) === "feed", visibleText(root);
		assert history.go(1);
		await sleepAsync(100);
		assert visibleText(root) === "post 1", visibleText(root);

		assert router.navigate("/inbox/7");
		flush();
		await sleepAsync(100);
		assert history.read().url === "/inbox/7", history.read().url;
		assert router.navigate("/inbox/8");
		flush();
		assert history.read().url === "/inbox/8", history.read().url;
		assert history.go(-1);
		await sleepAsync(100);
		assert history.read().url === "/inbox/7", history.read().url;
		assert router.location().pathname === "/inbox/7", router.location().pathname;
		assert visibleText(root) === "thread 7", visibleText(root);
		assert shown(root).includes("<h1>inbox</h1>"), shown(root);

		assert router.navigate("/feed/1");
		flush();
		await sleepAsync(100);
		assert history.read().url === "/feed/1", history.read().url;
		assert visibleText(root) === "post 1", visibleText(root);

		assert router.navigate("/inbox/7");
		await sleepAsync(100);
		assert history.read().url === "/inbox/7", history.read().url;
		assert history.go(-1);
		await sleepAsync(100);
		assert visibleText(root) === "inbox", visibleText(root);
		assert history.go(-1);
		await sleepAsync(100);
		assert history.read().url === "/feed/1", history.read().url;
		assert visibleText(root) === "post 1", visibleText(root);
		assert history.go(-1);
		await sleepAsync(100);
		assert history.read().url === "/feed", history.read().url;
		assert visibleText(root) === "feed", visibleText(root);
	} finally {
		router.dispose();
		history.replace(original);
	}
}
