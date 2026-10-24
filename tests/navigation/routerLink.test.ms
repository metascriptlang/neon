import { NeonNode } from "../../src/render/hostTypes";
import { element } from "../../src/macros/ui/element";
import { HostNode, mockNode, mockHost, render, mockToString } from "../../src/render/host";
import { createMemoryRoutingHistory } from "../../src/navigation/routingHistory";
import { A, RouterProvider, createRoutes, createRouter } from "../../src/navigation/router";

function Links(): NeonNode {
	return <nav>
		<A href="/">Plain</A>
		<A href="/off" preload={false}>Off</A>
	</nav>;
}

test "A renders a preload prop on its anchor for followPreloads to read" {
	const routes = createRoutes([{ path: "/", component: Links }, { path: "/off", component: Links }]);
	const made = createRouter(routes, createMemoryRoutingHistory({ url: "/", state: "" }));
	assert made.ok;
	if (made.ok) {
		const root = mockNode("root");
		render(element(<RouterProvider router={made.value} />), mockHost(), root as unknown as HostNode);
		assert mockToString(root) === "<root><nav><a href=\"/\" aria-current=\"page\">Plain</a><a href=\"/off\" preload=\"false\">Off</a></nav></root>", mockToString(root);
		made.value.dispose();
	}
}
