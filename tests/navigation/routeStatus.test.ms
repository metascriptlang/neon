import { sleepAsync } from "std/core/promise";
import { el, text, dynText, NeonNode } from "../../src/render/node";
import { HostNode, MockNode, mockNode, mockHost, render, mockToString } from "../../src/render/host";
import { element } from "../../src/macros/ui/element";
import { flush } from "../../src/core/runtime";
import { Loading } from "../../src/macros/ui/flow";
import { createMemoryRoutingHistory } from "../../src/navigation/routingHistory";
import { notFound } from "../../src/navigation/route";
import { Router, RouterProvider, createRoutes, createRouter } from "../../src/navigation/router";
import { query, createAsync } from "../../src/navigation/index";

interface Pkg {
	name: string;
}

async function fetchPkg(name: string): Promise<Pkg> {
	await sleepAsync(2);
	if (name === "gone") { throw notFound(); }
	return { name: name };
}

const getPkg = query(fetchPkg, "pkgStatus");

function PkgPage(): NeonNode {
	const pkg = createAsync((): Promise<Pkg> => getPkg("gone"));
	return Loading({ children: el("p", [], [], dynText((): string => "pkg " + pkg().name)), fallback: el("b", [], [], text("loading")) });
}

function Everything(): NeonNode {
	return el("p", [], [], text("not found page"));
}

function mounted(router: Router): MockNode {
	const root = mockNode("root");
	render(element(<RouterProvider router={router} />), mockHost(), root as unknown as HostNode);
	return root;
}

test "a page whose query answers not found renders the catch-all route at the same address" {
	const history = createMemoryRoutingHistory({ url: "/pkg/gone", state: "" });
	const routes = createRoutes([
		{ path: "/pkg/:name", component: PkgPage },
		{ path: "*", status: 404, component: Everything },
	]);
	const made = createRouter(routes, history);
	assert made.ok;
	if (made.ok) {
		const router = made.value;
		const root = mounted(router);
		await sleepAsync(10);
		flush();
		assert mockToString(root).includes("not found page"), mockToString(root);
		assert !mockToString(root).includes("pkg "), mockToString(root);
		assert history.read().url === "/pkg/gone", history.read().url;
		assert router.response().status === 404, router.response().status.toString();
		router.dispose();
	}
}

test "a query that answers not found where no other route matches names the case" {
	const history = createMemoryRoutingHistory({ url: "/pkg/gone", state: "" });
	const routes = createRoutes([{ path: "/pkg/:name", component: PkgPage }]);
	const made = createRouter(routes, history);
	assert made.ok;
	if (made.ok) {
		const router = made.value;
		let failed = "";
		try { router.missing(notFound()); } catch (error) { failed = error.message; }
		assert failed === "routing: /pkg/gone answered not found and no other route matches it", failed;
		router.dispose();
	}
}
