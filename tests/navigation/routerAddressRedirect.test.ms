import { flush } from "../../src/core/runtime";
import { NeonNode } from "../../src/render/hostTypes";
import { element } from "../../src/macros/ui/element";
import { HostNode, MockNode, mockNode, mockHost, render } from "../../src/render/host";
import { RoutingHistory, createMemoryRoutingHistory, createRequestRoutingHistory } from "../../src/navigation/routingHistory";
import { GuardDecision, RouteMatch, redirect } from "../../src/navigation/route";
import { Router, RouterProvider, Routes, createRouter, createRoutes } from "../../src/navigation/router";

function Home(): NeonNode { return <h1>home</h1>; }
function Page(): NeonNode { return <h1>page</h1>; }

function toward(target: string): (p: Map<string, string>, f: RouteMatch) => GuardDecision {
	return (p: Map<string, string>, f: RouteMatch): GuardDecision => redirect(target);
}

function site(): Routes {
	return createRoutes([
		{ path: "/", component: Home },
		{ path: "/page", component: Page },
		{ path: "/out", component: Home, guard: toward("https://example.com/x") },
		{ path: "/schemeless", component: Home, guard: toward("//example.com/x") },
		{ path: "/bad", component: Home, guard: toward("page") },
	]);
}

function opened(history: RoutingHistory): Router {
	const made = createRouter(site(), history);
	if (!made.ok) { throw new Error("router " + made.error.toString()); }
	const root: MockNode = mockNode("root");
	render(element(<RouterProvider router={made.value} />), mockHost(), root as unknown as HostNode);
	return made.value;
}

test "a request to a route that redirects outside the app answers with that location" {
	const made = createRouter(site(), createRequestRoutingHistory("/out"));
	assert made.ok;
	if (made.ok) {
		assert made.value.response().status === 307, made.value.response().status.toString();
		assert made.value.response().location === "https://example.com/x";
		made.value.dispose();
	}
	const bare = createRouter(site(), createRequestRoutingHistory("/schemeless"));
	assert bare.ok;
	if (bare.ok) {
		assert bare.value.response().location === "//example.com/x";
		bare.value.dispose();
	}
}

test "a navigation that redirects outside the app is handed to the host" {
	const history = createMemoryRoutingHistory({ url: "/", state: "" });
	const router = opened(history);
	let left = "";
	router.leaveWith((url: string): void => { left = url; });
	assert router.navigate("/out");
	flush();
	assert left === "https://example.com/x", left;
	assert history.read().url === "/", history.read().url;
	router.dispose();
}

test "a navigation that redirects outside the app without a host throws" {
	const router = opened(createMemoryRoutingHistory({ url: "/", state: "" }));
	let message = "";
	try { router.navigate("/out"); } catch (e) { message = e.message; }
	assert message.includes("https://example.com/x"), message;
	router.dispose();
}

test "a router opened on a route that redirects outside the app hands it to the host" {
	const history = createMemoryRoutingHistory({ url: "/out", state: "" });
	const router = opened(history);
	let left = "";
	router.leaveWith((url: string): void => { left = url; });
	assert left === "https://example.com/x", left;
	router.dispose();
}

test "a relative redirect target resolves from the root" {
	const made = createRouter(site(), createRequestRoutingHistory("/bad"));
	assert made.ok;
	if (made.ok) {
		assert made.value.response().status === 307;
		assert made.value.response().location === "/page", made.value.response().location ?? "-";
		made.value.dispose();
	}
}
