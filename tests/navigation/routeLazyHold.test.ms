import { NeonNode } from "../../src/render/hostTypes";
import { el, text } from "../../src/render/node";
import { HostNode, MockNode, mockNode, mockHost, render, mockToString } from "../../src/render/host";
import { element } from "../../src/macros/ui/element";
import { Gate, gated, release } from "../core/asyncClock";
import { Loading } from "../../src/macros/ui/flow";
import { lazyModule } from "../../src/render/lazy";
import { createMemoryRoutingHistory } from "../../src/navigation/routingHistory";
import { LayoutProps, RouterProvider, Routes, createRoutes, createRouter } from "../../src/navigation/router";

function Start(props: {}): NeonNode {
	return el("p", [], [], text("start"));
}

function Ownership(props: {}): NeonNode {
	return el("p", [], [], text("ownership"));
}

const gate = new Gate();

async function loadOwnership(): Promise<(props: {}) => NeonNode> {
	return gated(gate, Ownership);
}

const LazyOwnership = lazyModule<{}>("tests/navigation/routeLazyHold/ownership", loadOwnership);

function Shell(props: LayoutProps): NeonNode {
	return <main><Loading fallback={el("b", [], [], text("loading"))}>{props.children}</Loading></main>;
}

function siteRoutes(): Routes {
	return createRoutes([
		{ layout: Shell, children: [
			{ path: "/", component: Start },
			{ path: "/ownership", component: LazyOwnership },
		] },
	]);
}

test "a click to a lazy route whose module has not loaded keeps the old page until the new one can render" {
	const made = createRouter(siteRoutes(), createMemoryRoutingHistory({ url: "/", state: "" }));
	assert made.ok;
	if (made.ok) {
		const router = made.value;
		const root: MockNode = mockNode("root");
		render(element(<RouterProvider router={router} />), mockHost(), root as unknown as HostNode);
		assert mockToString(root).includes("<p>start</p>"), mockToString(root);
		router.navigate("/ownership");
		assert mockToString(root).includes("<p>start</p>"), "the old page left before the new one could render: " + mockToString(root);
		assert !mockToString(root).includes("loading"), "the fallback flashed: " + mockToString(root);
		await release(gate);
		assert mockToString(root).includes("<p>ownership</p>"), mockToString(root);
		assert !mockToString(root).includes("<p>start</p>"), mockToString(root);
		router.dispose();
	}
}

const bareGate = new Gate();

async function loadBare(): Promise<(props: {}) => NeonNode> {
	return gated(bareGate, Ownership);
}

const LazyBare = lazyModule<{}>("tests/navigation/routeLazyHold/bare", loadBare);

function BareShell(props: LayoutProps): NeonNode {
	return <main>{props.children}</main>;
}

test "a click to a lazy route under a layout with no Loading keeps the old page until the new one can render" {
	const routes = createRoutes([{ layout: BareShell, children: [{ path: "/", component: Start }, { path: "/ownership", component: LazyBare }] }]);
	const made = createRouter(routes, createMemoryRoutingHistory({ url: "/", state: "" }));
	assert made.ok;
	if (made.ok) {
		const router = made.value;
		const root: MockNode = mockNode("root");
		render(element(<RouterProvider router={router} />), mockHost(), root as unknown as HostNode);
		router.navigate("/ownership");
		assert mockToString(root) === "<root><main><p>start</p></main></root>", "the old page left before the new one could render: " + mockToString(root);
		await release(bareGate);
		assert mockToString(root) === "<root><main><p>ownership</p></main></root>", mockToString(root);
		router.navigate("/");
		assert mockToString(root) === "<root><main><p>start</p></main></root>", "a loaded page swaps at once: " + mockToString(root);
		router.dispose();
	}
}
