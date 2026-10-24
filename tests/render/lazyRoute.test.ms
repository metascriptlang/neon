import { sleepAsync } from "std/core/promise";
import { flush } from "../../src/core/runtime";
import { NeonNode } from "../../src/render/hostTypes";
import { el, text } from "../../src/render/node";
import { element } from "../../src/macros/ui/element";
import { HostNode, MockNode, mockNode, mockHost, render, mockToString } from "../../src/render/host";
import { lazy } from "../../src/render/component";
import { Loading } from "../../src/macros/ui/flow";
import { createMemoryRoutingHistory } from "../../src/navigation/routingHistory";
import { LayoutProps, RouterProvider, createRouter, createRoutes } from "../../src/navigation/router";

const loads = [0];
const LazyDocs = lazy<{}>(loadDocs);

function Docs(props: {}): NeonNode {
	return el("h1", [], [], text("docs page"));
}

async function loadDocs(): Promise<(props: {}) => NeonNode> {
	loads[0] = loads[0] + 1;
	await sleepAsync(5);
	return Docs;
}

function Shell(props: LayoutProps): NeonNode {
	return Loading({ children: props.children, fallback: el("b", [], [], text("loading")) });
}

test "a route whose component is lazy shows the Loading fallback of its layout and then the page" {
	const routes = createRoutes([
		{ layout: Shell, children: [{ path: "/docs", component: LazyDocs }] },
	]);
	const router = createRouter(routes, createMemoryRoutingHistory({ url: "/docs", state: "" }));
	assert router.ok;
	if (!router.ok) { return; }
	const root: MockNode = mockNode("root");
	const dispose = render(element(<RouterProvider router={router.value} />), mockHost(), root as unknown as HostNode);
	const shown = (): string => mockToString(root);
	assert shown().includes("<b>loading</b>") && !shown().includes("docs page"), "fallback first: " + shown();
	let polls: int32 = 0;
	while (shown().includes("loading") && polls < 500) { await sleepAsync(1); flush(); polls += 1; }
	assert shown().includes("<h1>docs page</h1>") && !shown().includes("loading"), "page after the load: " + shown();
	assert loads[0] === 1, "one load: " + loads[0].toString();
	dispose();
}
