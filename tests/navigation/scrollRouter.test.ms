import { flush } from "../../src/core/runtime";
import { NeonNode, el, text } from "../../src/render/node";
import { createMemoryRoutingHistory } from "../../src/navigation/routingHistory";
import { Scroller } from "../../src/navigation/scroll";
import { createRouter, createRoutes } from "../../src/navigation/router";

function page(): NeonNode {
	return el("p", [], [], text("page"));
}

function opened(seen: string[]) {
	const routes = createRoutes([
		{ path: "/a", component: page },
		{ path: "/b", component: page },
	]);
	const created = createRouter(routes, createMemoryRoutingHistory({ url: "/a", state: "" }));
	if (!created.ok) { throw new Error("router: " + created.error.toString()); }
	const router = created.value;
	const scroller: Scroller = {
		arrived: (address: string, replace: boolean, scroll: boolean): void => {
			seen.push(address + (replace ? " replace" : " push") + (scroll ? " scroll" : " keep"));
		},
	};
	router.scrollWith(scroller);
	return router;
}

test "a router tells its scroller each history write with the scroll choice of the navigation" {
	const seen: string[] = [];
	const router = opened(seen);
	assert router.navigate("/b");
	flush();
	assert router.navigate("/a", { scroll: false });
	flush();
	assert router.navigate("/b", { replace: true });
	flush();
	assert seen.join(" | ") === "/b push scroll | /a push keep | /b replace scroll", seen.join(" | ");
}

test "a navigation to the address it is on tells the scroller nothing and leaves no choice behind" {
	const seen: string[] = [];
	const router = opened(seen);
	assert router.navigate("/a", { scroll: false });
	flush();
	assert router.navigate("/b");
	flush();
	assert seen.join(" | ") === "/b push scroll", seen.join(" | ");
}
