import { createBrowserRoutingHistory } from "../../src/platform/browser/routingHistory";
import { NeonNode } from "../../src/render/hostTypes";
import { element } from "../../src/macros/ui/element";
import { flush } from "../../src/core/runtime";
import { Router, Routes, createRouter, createRoutes } from "../../src/navigation/router";

extern function js(code: cstring): string from "String((0, eval)(#))";

function Doc(): NeonNode { return <h1>doc</h1>; }

function site(): Routes {
	return createRoutes([{ path: "/docs/:slug", component: Doc }]);
}

test "a browser router reads a repeated query key from the real address with every value" {
	const history = createBrowserRoutingHistory();
	const original = history.read();
	history.replace({ url: "/docs/a?tag=a&tag=b&flag", state: "" });
	const opened = createRouter(site(), history);
	assert opened.ok;
	if (opened.ok) {
		const router: Router = opened.value;
		assert router.location().search.getAll("tag").join(",") === "a,b";
		assert router.location().search.get("tag") === "a";
		assert router.location().search.get("flag") === "";
		router.dispose();
	}
	history.replace(original);
}

test "a browser router writes a repeated query key back to the address bar with every value" {
	const history = createBrowserRoutingHistory();
	const original = history.read();
	history.replace({ url: "/docs/a", state: "" });
	const opened = createRouter(site(), history);
	assert opened.ok;
	if (opened.ok) {
		const router: Router = opened.value;
		assert router.navigate("/docs/a?tag=a&tag=b");
		flush();
		assert js("location.pathname + location.search") === "/docs/a?tag=a&tag=b", js("location.pathname + location.search");
		router.dispose();
	}
	history.replace(original);
}

test "a browser router leaves an opened address with a repeated key and a bare flag as it was" {
	const history = createBrowserRoutingHistory();
	const original = history.read();
	history.replace({ url: "/docs/a?tag=a&tag=b&flag", state: "" });
	const opened = createRouter(site(), history);
	assert opened.ok;
	if (opened.ok) {
		const router: Router = opened.value;
		flush();
		assert js("location.pathname + location.search") === "/docs/a?tag=a&tag=b&flag", js("location.pathname + location.search");
		router.dispose();
	}
	history.replace(original);
}
