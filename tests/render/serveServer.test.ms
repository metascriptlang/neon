import { View, Text } from "../../src/components/primitives";
import { Head } from "../../src/render/head";
import { NeonNode } from "../../src/render/hostTypes";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import { GuardDecision, RouteMatch, redirect } from "../../src/navigation/route";
import { Routes, createRoutes } from "../../src/navigation/router";
import { App, htmlDocument, serve } from "../../src/render/serve";

const looks = createStyles({ page: { padding: 7 } });

function Home(): NeonNode {
	return <View style={looks.page}><Head><title>Served home</title></Head><Text>home body</Text></View>;
}

function Gone(): NeonNode {
	return <Text>this page is gone</Text>;
}

function Missing(): NeonNode {
	return <View><Head><title>Missing</title></Head><Text>no such page</Text></View>;
}

function moved(params: Map<string, string>, found: RouteMatch): GuardDecision {
	return redirect("/");
}

const routes: Routes = createRoutes([
	{ path: "/", component: Home },
	{ path: "/old", component: Gone, guard: moved },
	{ path: "/gone", status: 410, component: Gone },
]);

const app: App = { routes: routes, notFound: <Text>app not found</Text>, document: htmlDocument("site", "/client.js") };

test "a matched route is a 200 document with head, css, body and client script placed" {
	const served = await serve(app, "/");
	assert served.status === 200 && served.location === null, served.status.toString();
	const body = served.body;
	assert body.startsWith("<!doctype html><html><head><meta charset=\"utf-8\"><title data-neon-head=\"\">Served home</title><style>"), body;
	const root = body.indexOf("</style></head><body><div id=\"site\">");
	assert root > 0 && body.indexOf("home body") > root, body;
	assert body.indexOf("</div>", root) > body.indexOf("home body"), body;
	assert body.endsWith("<script type=\"module\" src=\"/client.js\"></script></body></html>"), body;
}

test "a redirect route answers its status and location with no body" {
	const served = await serve(app, "/old");
	assert served.status === 307, served.status.toString();
	assert served.location === "/" && served.body === "", served.body;
}

test "a route that declares a status serves its page under that status" {
	const served = await serve(app, "/gone");
	assert served.status === 410 && served.location === null, served.status.toString();
	assert served.body.indexOf("this page is gone") > 0, served.body;
}

test "an address no route takes is a 404 through the app's not-found page" {
	const served = await serve(app, "/nowhere");
	assert served.status === 404 && served.location === null, served.status.toString();
	assert served.body.indexOf("app not found") > 0 && served.body.startsWith("<!doctype html>"), served.body;
}

test "two requests do not share a head or a response" {
	const first = await serve(app, "/");
	const second = await serve(app, "/gone");
	assert second.body.indexOf("Served home") < 0 && first.body.indexOf("this page is gone") < 0, second.body;
}
