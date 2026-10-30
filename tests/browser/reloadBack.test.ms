import { sleepAsync } from "std/core/promise";
import { flush } from "../../src/core/runtime";
import { NeonNode } from "../../src/render/hostTypes";
import { element } from "../../src/macros/ui/element";
import { HostNode, MockNode, mockNode, mockHost, render } from "../../src/render/host";
import { createBrowserRoutingHistory } from "../../src/platform/browser/routingHistory";
import { RoutingHistory } from "../../src/navigation/routingHistory";
import {
	Router,
	RouterProvider,
	Routes,
	Stack,
	createRouter,
	createRoutes,
	useParams,
} from "../../src/navigation/index";
import { visibleText } from "../navigation/navHarness";

function Feed(): NeonNode { return <h1>feed</h1>; }
function Post(): NeonNode { return <h1>{"post " + (useParams().get("post") ?? "")}</h1>; }

function appRoutes(): Routes {
	return createRoutes([
		{ path: "/feed", navigator: Stack, children: [
			{ path: "", component: Feed },
			{ path: ":post", component: Post, resolveOnReload: true },
		] },
	]);
}

function start(history: RoutingHistory, root: MockNode): Router {
	const created = createRouter(appRoutes(), history);
	if (!created.ok) { throw new Error("router " + created.error.toString()); }
	render(element(<RouterProvider router={created.value} />), mockHost(), root as unknown as HostNode);
	return created.value;
}

function pages(node: MockNode): string {
	if (node.tag === "") { return node.text; }
	let out = "";
	for (const child of node.children) {
		const part = pages(child);
		if (part === "") { continue; }
		out = out === "" ? part : out + "|" + part;
	}
	return out;
}

test "a back onto an entry written before a reload shows its address alone, not over the reloaded page" {
	const history = createBrowserRoutingHistory();
	const original = history.read();
	history.replace({ url: "/feed", state: "" });
	const router = start(history, mockNode("root"));
	try {
		assert router.navigate("/feed/1");
		flush();
		assert router.navigate("/feed/2");
		flush();
		await sleepAsync(100);
		router.dispose();
		const root: MockNode = mockNode("root");
		const again = start(history, root);
		assert pages(root) === "post 2", pages(root);
		assert history.go(-1);
		await sleepAsync(100);
		assert history.read().url === "/feed/1", history.read().url;
		assert visibleText(root) === "post 1", visibleText(root);
		assert pages(root) === "post 1", pages(root);
		again.dispose();
	} finally {
		history.replace(original);
	}
}
