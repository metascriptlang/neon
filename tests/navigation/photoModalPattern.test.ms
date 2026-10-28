import { flush } from "../../src/core/runtime";
import { NeonNode } from "../../src/render/hostTypes";
import { element } from "../../src/macros/ui/element";
import { HostNode, MockNode, mockNode, mockHost, render } from "../../src/render/host";
import { RoutingHistory, createMemoryRoutingHistory } from "../../src/navigation/routingHistory";
import { Router, RouterProvider, Routes, Stack, createRouter, createRoutes, useParams } from "../../src/navigation/router";
import { visibleText } from "./navHarness";

let grids: int32 = 0;

function Grid(): NeonNode {
	grids += 1;
	return <h1>grid</h1>;
}

function Photo(): NeonNode {
	return <h1>{"photo " + (useParams().get("id") ?? "")}</h1>;
}

function photoRoutes(): Routes {
	return createRoutes([
		{ path: "/photos", navigator: Stack, initial: "", children: [
			{ path: "", component: Grid },
			{ path: ":id", component: Photo, presentation: "transparentModal" },
		] },
	]);
}

function opened(history: RoutingHistory): Router {
	const router = createRouter(photoRoutes(), history);
	if (!router.ok) { throw new Error("router: " + router.error.toString()); }
	return router.value;
}

function mounted(router: Router): MockNode {
	const root: MockNode = mockNode("root");
	render(element(<RouterProvider router={router} />), mockHost(), root as unknown as HostNode);
	flush();
	return root;
}

test "a photo opened from the grid shows over it with its own address, and back closes it" {
	grids = 0;
	const history = createMemoryRoutingHistory({ url: "/photos", state: "" });
	const router = opened(history);
	const root = mounted(router);
	assert visibleText(root) === "grid", visibleText(root);
	assert router.navigate("/photos/42");
	flush();
	assert visibleText(root) === "grid|photo 42", visibleText(root);
	assert history.read().url === "/photos/42", history.read().url;
	assert history.go(-1);
	flush();
	assert visibleText(root) === "grid", visibleText(root);
	assert history.go(1);
	flush();
	assert visibleText(root) === "grid|photo 42", visibleText(root);
	assert grids === 1, "the grid under the photo kept its instance";
}

test "a reload keeps the photo over the grid, and a cold address opens it over the grid too" {
	const history = createMemoryRoutingHistory({ url: "/photos", state: "" });
	assert opened(history).navigate("/photos/7");
	flush();
	const reloaded = mounted(opened(createMemoryRoutingHistory(history.read())));
	assert visibleText(reloaded) === "grid|photo 7", visibleText(reloaded);
	const cold = mounted(opened(createMemoryRoutingHistory({ url: "/photos/9", state: "" })));
	assert visibleText(cold) === "grid|photo 9", visibleText(cold);
}

test "opted in, a reload shows the photo page, while back and forward in the same page keep the modal" {
	const routes = (): Routes => createRoutes([
		{ path: "/photos", navigator: Stack, children: [
			{ path: "", component: Grid },
			{ path: ":id", component: Photo, presentation: "transparentModal", resolveOnReload: true },
		] },
	]);
	const history = createMemoryRoutingHistory({ url: "/photos", state: "" });
	const first = createRouter(routes(), history);
	assert first.ok;
	const router = first.value;
	const root = mounted(router);
	assert router.navigate("/photos/7");
	flush();
	assert history.go(-1);
	flush();
	assert history.go(1);
	flush();
	assert visibleText(root) === "grid|photo 7", visibleText(root);
	const again = createRouter(routes(), createMemoryRoutingHistory(history.read()));
	assert again.ok;
	const reloaded = mounted(again.value);
	assert visibleText(reloaded) === "photo 7", visibleText(reloaded);
}

test "a presentation outside a Stack is refused where it is declared" {
	let message = "";
	try {
		createRoutes([{ path: "/photo/:id", component: Photo, presentation: "transparentModal" }]);
	} catch (error) {
		message = error.message;
	}
	assert message === "routing: \"/photo/:id\" names a presentation, which only a route in a Stack takes", message;
}
