import { NeonNode } from "../../src/render/hostTypes";
import { element } from "../../src/macros/ui/element";
import { HostNode, mockNode, mockHost, render, mockToString } from "../../src/render/host";
import { createMemoryRoutingHistory } from "../../src/navigation/routingHistory";
import { flush } from "../../src/core/runtime";
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
		assert mockToString(root) === "<root><nav><a href=\"/\" aria-current=\"page\" class=\"active\">Plain</a><a href=\"/off\" class=\"inactive\" preload=\"false\">Off</a></nav></root>", mockToString(root);
		made.value.dispose();
	}
}

function Styled(): NeonNode {
	return <nav>
		<A href="/docs" class="nav" end>Docs</A>
		<A href="/docs/a" activeClass="on" inactiveClass="off" target="_blank" rel="noopener">A</A>
		<A href="/docs/b" replace noScroll>B</A>
		<A href="/">Home</A>
	</nav>;
}

test "A marks a link active under its path, exact only with end, and names the page it points at" {
	const routes = createRoutes([{ path: "/docs/a", component: Styled }, { path: "/docs", component: Styled }, { path: "/docs/b", component: Styled }, { path: "/", component: Styled }]);
	const made = createRouter(routes, createMemoryRoutingHistory({ url: "/docs/a", state: "" }));
	assert made.ok;
	if (made.ok) {
		const root = mockNode("root");
		render(element(<RouterProvider router={made.value} />), mockHost(), root as unknown as HostNode);
		const shown = mockToString(root);
		assert shown.indexOf("<a href=\"/docs\" class=\"nav inactive\">Docs</a>") >= 0, shown;
		assert shown.indexOf("<a href=\"/docs/a\" aria-current=\"page\" class=\"on\" target=\"_blank\" rel=\"noopener\">A</a>") >= 0, shown;
		assert shown.indexOf("<a href=\"/docs/b\" class=\"inactive\" replace=\"true\" noScroll=\"true\">B</a>") >= 0, shown;
		assert shown.indexOf("<a href=\"/\" class=\"active\">Home</a>") >= 0, shown;
		made.value.dispose();
	}
}

test "A with a parent path is active without end and inactive with it" {
	const routes = createRoutes([{ path: "/docs/a", component: Styled }, { path: "/docs", component: Styled }, { path: "/docs/b", component: Styled }, { path: "/", component: Styled }]);
	const made = createRouter(routes, createMemoryRoutingHistory({ url: "/docs/a", state: "" }));
	assert made.ok;
	if (made.ok) {
		const root = mockNode("root");
		render(element(<RouterProvider router={made.value} />), mockHost(), root as unknown as HostNode);
		assert mockToString(root).indexOf("class=\"nav inactive\"") >= 0, mockToString(root);
		made.value.navigate("/docs");
		flush();
		assert mockToString(root).indexOf("<a href=\"/docs\" aria-current=\"page\" class=\"nav active\">Docs</a>") >= 0, mockToString(root);
		made.value.dispose();
	}
}
