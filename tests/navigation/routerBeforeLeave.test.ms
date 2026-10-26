import { flush } from "../../src/core/runtime";
import { NeonNode } from "../../src/render/hostTypes";
import { element } from "../../src/macros/ui/element";
import { HostNode, MockNode, mockNode, mockHost, render } from "../../src/render/host";
import { RoutingHistory, createMemoryRoutingHistory } from "../../src/navigation/routingHistory";
import { BeforeLeaveEvent, NavigateOptions, Router, RouterProvider, createRouter, createRoutes, useBeforeLeave } from "../../src/navigation/router";

const seen: string[] = [];
let held: BeforeLeaveEvent | null = null;
let block = true;
let second = false;

function Form(): NeonNode {
	useBeforeLeave((e: BeforeLeaveEvent): void => {
		const target = typeof e.to === "string" ? e.to : "go " + (e.to as int32).toString();
		seen.push(target + " from " + e.from.pathname + (e.options === null ? "" : " replace=" + ((e.options as NavigateOptions).replace ?? false).toString()));
		if (block) {
			e.preventDefault();
			held = e;
		}
	});
	if (second) {
		useBeforeLeave((e: BeforeLeaveEvent): void => { seen.push("second sees " + e.defaultPrevented.toString()); });
	}
	return <p>form</p>;
}

function Other(): NeonNode { return <p>other</p>; }

function opened(history: RoutingHistory): Router {
	const made = createRouter(createRoutes([
		{ path: "/form", component: Form },
		{ path: "/other", component: Other },
		{ path: "/third", component: Other },
	]), history);
	if (!made.ok) { throw new Error("router " + made.error.toString()); }
	const root: MockNode = mockNode("root");
	render(element(<RouterProvider router={made.value} />), mockHost(), root as unknown as HostNode);
	return made.value;
}

function reset(): void {
	seen.length = 0;
	held = null;
	block = true;
	second = false;
}

test "a before-leave listener that prevents the default keeps the route and takes the navigation" {
	reset();
	const router = opened(createMemoryRoutingHistory({ url: "/form", state: "" }));
	assert router.navigate("/other", { replace: true });
	flush();
	assert router.location().pathname === "/form", router.location().pathname;
	assert seen.join(" | ") === "/other from /form replace=true", seen.join(" | ");
	router.dispose();
}

test "retry with force completes the blocked navigation without asking again, and without force asks again" {
	reset();
	const router = opened(createMemoryRoutingHistory({ url: "/form", state: "" }));
	assert router.navigate("/other");
	const first = held as BeforeLeaveEvent;
	first.retry();
	assert router.location().pathname === "/form";
	assert seen.length === 2, seen.join(" | ");
	(held as BeforeLeaveEvent).retry(true);
	flush();
	assert router.location().pathname === "/other", router.location().pathname;
	assert seen.length === 2, seen.join(" | ");
	router.dispose();
}

test "a listener that does not prevent lets the navigation through, and a later listener sees an earlier prevention" {
	reset();
	block = false;
	const router = opened(createMemoryRoutingHistory({ url: "/form", state: "" }));
	assert router.navigate("/other");
	flush();
	assert router.location().pathname === "/other", router.location().pathname;
	router.dispose();
	reset();
	second = true;
	const again = opened(createMemoryRoutingHistory({ url: "/form", state: "" }));
	assert again.navigate("/other");
	assert seen.join(" | ") === "/other from /form | second sees true", seen.join(" | ");
	assert again.location().pathname === "/form";
	again.dispose();
}

test "going back is asked as a delta, stays put when prevented, and goes with retry force" {
	reset();
	const history = createMemoryRoutingHistory({ url: "/other", state: "" });
	const router = opened(history);
	assert router.navigate("/form");
	flush();
	block = true;
	assert router.go(-1);
	flush();
	assert router.location().pathname === "/form", router.location().pathname;
	assert history.index() === 1, history.index().toString();
	assert seen.join(" | ") === "go -1 from /form", seen.join(" | ");
	(held as BeforeLeaveEvent).retry(true);
	flush();
	assert router.location().pathname === "/other", router.location().pathname;
	assert history.index() === 0, history.index().toString();
	router.dispose();
}

test "leaving the route that holds the listener removes it" {
	reset();
	block = false;
	const router = opened(createMemoryRoutingHistory({ url: "/form", state: "" }));
	assert router.navigate("/other");
	flush();
	assert router.navigate("/third");
	flush();
	assert seen.length === 1, seen.join(" | ");
	router.dispose();
}
