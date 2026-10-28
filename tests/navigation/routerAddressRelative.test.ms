import { flush } from "../../src/core/runtime";
import { NeonNode } from "../../src/render/hostTypes";
import { element } from "../../src/macros/ui/element";
import { HostNode, MockNode, mockNode, mockHost, render } from "../../src/render/host";
import { RoutingHistory, createMemoryRoutingHistory } from "../../src/navigation/routingHistory";
import { resolvePath } from "../../src/navigation/routeMatcher";
import { NavigateOptions, Router, RouterProvider, Routes, createRouter, createRoutes, useNavigate } from "../../src/navigation/router";

let go: ((to: string | int32, options?: NavigateOptions | null) => boolean) | null = null;

function Doc(): NeonNode {
	go = useNavigate();
	return <h1>doc</h1>;
}
function Home(): NeonNode { return <h1>home</h1>; }

function site(): Routes {
	return createRoutes([
		{ path: "/", component: Home },
		{ path: "/docs/start/edit", component: Doc },
		{ path: "/docs/start/edit/docs/a", component: Home },
		{ path: "/docs/start/docs/a", component: Home },
		{ path: "/docs/a", component: Home },
	]);
}

function opened(url: string): { router: Router; history: RoutingHistory } {
	const history = createMemoryRoutingHistory({ url, state: "" });
	const made = createRouter(site(), history);
	if (!made.ok) { throw new Error("router " + made.error.toString()); }
	const root: MockNode = mockNode("root");
	render(element(<RouterProvider router={made.value} />), mockHost(), root as unknown as HostNode);
	return { router: made.value, history };
}

test "resolvePath joins a relative target onto the route it is called from" {
	assert resolvePath("", "docs/a", "/docs/start/edit") === "/docs/start/edit/docs/a";
	assert resolvePath("", "#frag", "/docs/start/edit") === "/docs/start/edit#frag";
	assert resolvePath("", "/docs/a", "/docs/start/edit") === "/docs/a";
	assert resolvePath("", "docs/a", "") === "/docs/a";
	assert resolvePath("", "#frag", "") === "/#frag";
	assert resolvePath("", "", "/docs/x") === "/docs/x";
}

test "resolvePath refuses an absolute url as not routable" {
	assert resolvePath("", "https://example.com/x", "/a") === null;
	assert resolvePath("", "//example.com/x", "/a") === null;
}

test "navigate from the router keeps the current path for a query only target" {
	const at = opened("/docs/start/edit");
	assert at.router.navigate("?q=2");
	flush();
	assert at.history.read().url === "/docs/start/edit?q=2", at.history.read().url;
	at.router.dispose();
}

test "navigate from the router resolves a relative target from the root" {
	const at = opened("/docs/start/edit");
	assert at.router.navigate("docs/a");
	flush();
	assert at.history.read().url === "/docs/a", at.history.read().url;
	at.router.dispose();
}

test "navigate from a route resolves a relative target under that route" {
	const at = opened("/docs/start/edit");
	assert go !== null;
	assert (go as (to: string | int32, options?: NavigateOptions | null) => boolean)("docs/a");
	flush();
	assert at.history.read().url === "/docs/start/edit/docs/a", at.history.read().url;
	at.router.dispose();
}

test "navigate from a route keeps the route path for a hash only target" {
	const at = opened("/docs/start/edit");
	assert (go as (to: string | int32, options?: NavigateOptions | null) => boolean)("#frag");
	flush();
	assert at.history.read().url === "/docs/start/edit#frag", at.history.read().url;
	at.router.dispose();
}

test "navigate removes dot segments as the url parser does" {
	const at = opened("/docs/start/edit");
	assert (go as (to: string | int32, options?: NavigateOptions | null) => boolean)("../docs/a");
	flush();
	assert at.history.read().url === "/docs/start/docs/a", at.history.read().url;
	at.router.dispose();
}

test "navigate to an absolute address that no redirect produced throws naming the case" {
	const opening = opened("/docs/a");
	let message = "";
	try { opening.router.navigate("https://example.com/x"); } catch (error) { message = error.message; }
	assert message === "routing: \"https://example.com/x\" is not a routable path", message;
	message = "";
	try { opening.router.navigate("//example.com/x"); } catch (error) { message = error.message; }
	assert message === "routing: \"//example.com/x\" is not a routable path", message;
	assert opening.history.read().url === "/docs/a", opening.history.read().url;
	opening.router.dispose();
}
