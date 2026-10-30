import { RoutingError, QueryParams } from "../../src/navigation/routing";
import { createMemoryRoutingHistory, createRequestRoutingHistory } from "../../src/navigation/routingHistory";
import { NeonNode } from "../../src/render/hostTypes";
import { element } from "../../src/macros/ui/element";
import { Router, Routes, createRouter, createRoutes } from "../../src/navigation/router";

function Doc(): NeonNode { return <h1>doc</h1>; }

function site(): Routes {
	return createRoutes([{ path: "/docs/:slug", component: Doc }]);
}

function searchOf(url: string): QueryParams {
	const opened = createRouter(site(), createRequestRoutingHistory(url));
	if (!opened.ok) { throw new Error("router " + opened.error.toString() + " for " + url); }
	const router: Router = opened.value;
	const search = router.location().search;
	router.dispose();
	return search;
}

test "a malformed percent escape in the query is kept literally" {
	assert searchOf("/docs/a?q=%zz").get("q") === "%zz";
	assert searchOf("/docs/a?utm=100%").get("utm") === "100%";
	assert searchOf("/docs/a?q=%4").get("q") === "%4";
}

test "a valid escape beside a malformed one still decodes" {
	assert searchOf("/docs/a?q=%41%zz+b").get("q") === "A%zz b";
}

test "an invalid utf8 query byte becomes the replacement character" {
	assert searchOf("/docs/a?q=%E0%A4").get("q") === "�";
	assert searchOf("/docs/a?q=%FF").get("q") === "�";
}

test "a malformed percent escape in the path is an invalid address" {
	const opened = createRouter(site(), createRequestRoutingHistory("/docs/%zz"));
	assert !opened.ok;
	if (!opened.ok) { assert opened.error === RoutingError.InvalidAddress; }
}

test "a router opens on an address with a malformed query" {
	const opened = createRouter(site(), createMemoryRoutingHistory({ url: "/docs/a?q=%zz#h", state: "" }));
	assert opened.ok;
	if (opened.ok) { opened.value.dispose(); }
}

test "a repeated query key reaches the router location with every value in order" {
	const search = searchOf("/docs/a?tag=a&tag=b&q=1");
	assert search.get("tag") === "a";
	assert search.getAll("tag").join(",") === "a,b";
	assert search.getAll("q").join(",") === "1";
}

test "a bare query key is present and empty on the router location" {
	const search = searchOf("/docs/a?flag");
	assert search.has("flag");
	assert search.get("flag") === "";
}
