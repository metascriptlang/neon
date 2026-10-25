import { el, text, NeonNode } from "../../src/render/node";
import { HostNode, mockNode, mockHost, render, mockToString } from "../../src/render/host";
import { element } from "../../src/macros/ui/element";
import { Gate, gated, release } from "../core/asyncClock";
import { Loading } from "../../src/macros/ui/flow";
import { createComponent } from "../../src/render/component";
import { lazyModule } from "../../src/render/lazy";
import { createMemoryRoutingHistory } from "../../src/navigation/routingHistory";
import { RouterProvider, createRoutes, createRouter } from "../../src/navigation/router";

function Docs(props: {}): NeonNode {
	return el("p", [], [], text("docs"));
}

const gate = new Gate();

async function loadDocs(): Promise<(props: {}) => NeonNode> {
	return gated(gate, Docs);
}

const Docs2 = lazyModule<{}>("tests/navigation/routeLazy/docs", loadDocs);

test "a route entry takes a lazy component directly, and mounts it at once once its module has loaded" {
	const warm = mockNode("warm");
	const stop = render(Loading({ children: createComponent(Docs2, {}), fallback: el("b", [], [], text("loading")) }), mockHost(), warm as unknown as HostNode);
	assert mockToString(warm).includes("loading"), mockToString(warm);
	await release(gate);
	assert mockToString(warm).includes("<p>docs</p>"), mockToString(warm);
	stop();
	const routes = createRoutes([{ path: "/", component: Docs2 }]);
	const made = createRouter(routes, createMemoryRoutingHistory({ url: "/", state: "" }));
	assert made.ok;
	if (made.ok) {
		const root = mockNode("root");
		render(element(<RouterProvider router={made.value} />), mockHost(), root as unknown as HostNode);
		assert mockToString(root).includes("<p>docs</p>"), mockToString(root);
		made.value.dispose();
	}
}
