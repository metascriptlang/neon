import { flush } from "../../src/core/runtime";
import { NeonNode } from "../../src/render/hostTypes";
import { element } from "../../src/macros/ui/element";
import { HostNode, MockNode, mockNode, mockHost, render } from "../../src/render/host";
import { RoutingHistory, createMemoryRoutingHistory } from "../../src/navigation/routingHistory";
import { Router, RouterProvider, Routes, Stack, createRouter, createRoutes, useParams } from "../../src/navigation/router";
import { visibleText } from "./navHarness";

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

function open(history: RoutingHistory): Router {
	const r = createRouter(appRoutes(), history);
	if (!r.ok) { throw new Error("router " + r.error.toString()); }
	return r.value;
}

function mounted(router: Router): MockNode {
	const root: MockNode = mockNode("root");
	render(element(<RouterProvider router={router} />), mockHost(), root as unknown as HostNode);
	flush();
	return root;
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

let shown: MockNode = mockNode("root");

function reloadedAtPost2(): RoutingHistory {
	const history = createMemoryRoutingHistory({ url: "/feed", state: "" });
	const router = open(history);
	mounted(router);
	router.navigate("/feed/1"); flush();
	router.navigate("/feed/2"); flush();
	router.dispose();
	shown = mounted(open(history));
	return history;
}

test "a back onto an entry written before a reload shows its address alone, not over the reloaded page" {
	const history = reloadedAtPost2();
	assert pages(shown) === "post 2", pages(shown);
	assert history.go(-1);
	flush();
	assert history.read().url === "/feed/1", history.read().url;
	assert visibleText(shown) === "post 1", visibleText(shown);
	assert pages(shown) === "post 1", pages(shown);
}

test "a forward onto the reloaded page restores the stack it was reloaded with" {
	const history = reloadedAtPost2();
	assert history.go(-1);
	flush();
	assert history.go(1);
	flush();
	assert history.read().url === "/feed/2", history.read().url;
	assert visibleText(shown) === "post 2", visibleText(shown);
	assert pages(shown) === "post 2", pages(shown);
}

test "a back onto an entry without state shows its address alone" {
	const history = createMemoryRoutingHistory({ url: "/feed/1", state: "" });
	history.push({ url: "/feed/2", state: "" });
	shown = mounted(open(history));
	assert pages(shown) === "post 2", pages(shown);
	assert history.go(-1);
	flush();
	assert history.read().url === "/feed/1", history.read().url;
	assert visibleText(shown) === "post 1", visibleText(shown);
	assert pages(shown) === "post 1", pages(shown);
}

test "a forward onto an entry without state resolves its address as a link does" {
	const history = createMemoryRoutingHistory({ url: "/feed/1", state: "" });
	history.push({ url: "/feed/2", state: "" });
	history.push({ url: "/feed/3", state: "" });
	shown = mounted(open(history));
	assert history.go(-2);
	flush();
	assert pages(shown) === "post 1", pages(shown);
	assert history.go(1);
	flush();
	assert history.read().url === "/feed/2", history.read().url;
	assert pages(shown) === "post 1|post 2", pages(shown);
}
