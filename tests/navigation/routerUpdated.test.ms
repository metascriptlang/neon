import { flush } from "../../src/core/runtime";
import { NeonNode } from "../../src/render/hostTypes";
import { element } from "../../src/macros/ui/element";
import { HostNode, MockNode, mockNode, mockHost, mockToString, render } from "../../src/render/host";
import { createMemoryRoutingHistory } from "../../src/navigation/routingHistory";
import {
	BeforeLeaveEvent,
	Router,
	RouterProvider,
	Routes,
	createRouter,
	createRoutes,
	useRouter,
} from "../../src/navigation/router";

function Home(): NeonNode {
	const router = useRouter("Home");
	return <p>{router.updated.get() ? "new version" : "home"}</p>;
}

function site(): Routes {
	return createRoutes([
		{ path: "/", component: Home },
		{ path: "/page", component: Home },
	]);
}

function opened(url: string, root: MockNode): Router {
	const made = createRouter(site(), createMemoryRoutingHistory({ url, state: "" }));
	if (!made.ok) { throw new Error("router " + made.error.toString()); }
	render(element(<RouterProvider router={made.value} />), mockHost(), root as unknown as HostNode);
	return made.value;
}

test "once the router is updated, a navigation loads its address as a document" {
	const root: MockNode = mockNode("root");
	const router = opened("/", root);
	let left = "";
	let replaced = false;
	router.leaveWith((url: string, replace: boolean): void => {
		left = url;
		replaced = replace;
	});
	assert router.navigate("/page");
	flush();
	assert left === "", "a client transition went to the host: " + left;
	assert mockToString(root).includes("home"), mockToString(root);
	router.updated.set(true);
	flush();
	assert mockToString(root).includes("new version"), mockToString(root);
	assert router.navigate("?q=1", { replace: true });
	flush();
	assert left === "/page?q=1", left;
	assert replaced;
	assert router.location().search.size === 0;
	router.dispose();
}

test "an updated router asks beforeLeave before it loads a document" {
	const router = opened("/", mockNode("root"));
	let left = "";
	router.leaveWith((url: string, replace: boolean): void => { left = url; });
	router.beforeLeave((event: BeforeLeaveEvent): void => { event.preventDefault(); });
	router.updated.set(true);
	assert router.navigate("/page");
	assert left === "", left;
	router.dispose();
}

test "an updated router without a host that loads documents names the address" {
	const router = opened("/", mockNode("root"));
	router.updated.set(true);
	let message = "";
	try { router.navigate("/page"); } catch (e) { message = e.message; }
	assert message.includes("/page") && message.includes("leaveWith"), message;
	router.dispose();
}
