import { createBrowserRoutingHistory, followExternalRedirects } from "../../src/platform/browser/routingHistory";
import { NeonNode } from "../../src/render/hostTypes";
import { element } from "../../src/macros/ui/element";
import { flush } from "../../src/core/runtime";
import { GuardDecision, RouteMatch, redirect } from "../../src/navigation/route";
import { Dispose } from "../../src/core/types";
import { Router, Routes, createRouter, createRoutes } from "../../src/navigation/router";

extern function js(code: cstring): string from "String((0, eval)(#))";

function Doc(): NeonNode { return <h1>doc</h1>; }
function Home(): NeonNode { return <h1>home</h1>; }

function site(): Routes {
	return createRoutes([
		{ path: "/", component: Home },
		{ path: "/docs/:slug", component: Doc },
		{ path: "/docs/:slug/edit", component: Doc },
		{ path: "/out", component: Home, guard: (p: Map<string, string>, f: RouteMatch): GuardDecision => redirect(js("location.origin + location.pathname + location.search") + "#left") },
	]);
}

test "a browser router opens on a malformed query escape and reads it literally" {
	const history = createBrowserRoutingHistory();
	const original = history.read();
	history.replace({ url: "/docs/a?q=%zz&utm=100%", state: "" });
	const opened = createRouter(site(), history);
	assert opened.ok;
	if (opened.ok) {
		const router: Router = opened.value;
		assert router.location().search.get("q") === "%zz";
		assert router.location().search.get("utm") === "100%";
		router.dispose();
	}
	history.replace(original);
}

test "a browser router navigate keeps the current path for a query only target" {
	const history = createBrowserRoutingHistory();
	const original = history.read();
	history.replace({ url: "/docs/start/edit", state: "" });
	const opened = createRouter(site(), history);
	assert opened.ok;
	if (opened.ok) {
		const router: Router = opened.value;
		assert router.navigate("?q=2");
		flush();
		assert js("location.pathname + location.search") === "/docs/start/edit?q=2", js("location.pathname + location.search");
		assert router.navigate("docs/b");
		flush();
		assert js("location.pathname") === "/docs/b", js("location.pathname");
		router.dispose();
	}
	history.replace(original);
}

test "a browser router sends the document to a redirect target outside the app" {
	const history = createBrowserRoutingHistory();
	const original = history.read();
	history.replace({ url: "/docs/a", state: "" });
	const opened = createRouter(site(), history);
	assert opened.ok;
	if (opened.ok) {
		const router: Router = opened.value;
		const stop: Dispose = followExternalRedirects(router);
		assert router.navigate("/out");
		assert js("location.hash") === "#left", js("location.hash");
		stop();
		router.dispose();
	}
	history.replace(original);
}
