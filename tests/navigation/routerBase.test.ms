import { flush } from "../../src/core/runtime";
import { NeonNode } from "../../src/render/hostTypes";
import { element } from "../../src/macros/ui/element";
import { HostNode, MockNode, mockNode, mockHost, mockToString, render } from "../../src/render/host";
import { RoutingHistory, createMemoryRoutingHistory, createRequestRoutingHistory } from "../../src/navigation/routingHistory";
import { RoutingError } from "../../src/navigation/routing";
import { GuardDecision, RouteMatch, path, redirect } from "../../src/navigation/route";
import { A, Router, RouterProvider, Routes, createRouter, createRoutes, useLocation } from "../../src/navigation/router";

function Where(): NeonNode {
	const location = useLocation();
	return <nav>
		<A href="/docs/a">A</A>
		<A href="/docs/b" end>B</A>
		<A href="https://example.com/x">X</A>
		<p>{location().pathname}</p>
	</nav>;
}

const doc = path("/docs/:slug");

function site(): Routes {
	return createRoutes([
		{ path: "/", component: Where },
		{ route: doc, component: Where },
		{ path: "/old", component: Where, guard: (p: Map<string, string>, f: RouteMatch): GuardDecision => redirect("/docs/a") },
	], "/app/");
}

function opened(history: RoutingHistory): Router {
	const made = createRouter(site(), history);
	if (!made.ok) { throw new Error("router " + made.error.toString()); }
	const root: MockNode = mockNode("root");
	render(element(<RouterProvider router={made.value} />), mockHost(), root as unknown as HostNode);
	lastRoot = root;
	return made.value;
}

let lastRoot: MockNode = mockNode("root");

test "a router with a base matches only addresses under it" {
	const inside = createRouter(site(), createMemoryRoutingHistory({ url: "/app/docs/a", state: "" }));
	assert inside.ok;
	if (inside.ok) { inside.value.dispose(); }
	const root = createRouter(site(), createMemoryRoutingHistory({ url: "/app", state: "" }));
	assert root.ok;
	if (root.ok) { root.value.dispose(); }
	const outside = createRouter(site(), createMemoryRoutingHistory({ url: "/docs/a", state: "" }));
	assert !outside.ok;
	if (!outside.ok) { assert outside.error === RoutingError.NoMatch; }
}

test "navigate adds the base to the history and to the location, and A links carry it" {
	const history = createMemoryRoutingHistory({ url: "/app/docs/a", state: "" });
	const router = opened(history);
	assert router.base === "/app";
	assert mockToString(lastRoot).indexOf("<a href=\"/app/docs/a\" aria-current=\"page\"") >= 0, mockToString(lastRoot);
	assert mockToString(lastRoot).indexOf("<a href=\"/app/docs/b\"") >= 0, mockToString(lastRoot);
	assert mockToString(lastRoot).indexOf("<a href=\"https://example.com/x\"") >= 0, mockToString(lastRoot);
	assert router.navigate("/docs/b");
	flush();
	assert history.read().url === "/app/docs/b", history.read().url;
	assert router.location().pathname === "/app/docs/b", router.location().pathname;
	assert mockToString(lastRoot).indexOf("<p>/app/docs/b</p>") >= 0, mockToString(lastRoot);
	router.dispose();
}

test "a typed navigate and a guard redirect add the base once" {
	const history = createMemoryRoutingHistory({ url: "/app", state: "" });
	const router = opened(history);
	const params = new Map<string, string>();
	params.set("slug", "z");
	assert router.navigate({ to: doc, params: params });
	flush();
	assert history.read().url === "/app/docs/z", history.read().url;
	assert router.navigate("/old");
	flush();
	assert history.read().url === "/app/docs/a", history.read().url;
	router.dispose();
}

test "a request under a base answers its redirect with the base in the location" {
	const made = createRouter(site(), createRequestRoutingHistory("/app/old"));
	assert made.ok;
	if (made.ok) {
		assert made.value.response().status === 307, made.value.response().status.toString();
		assert made.value.response().location === "/app/docs/a", made.value.response().location ?? "-";
		made.value.dispose();
	}
}
