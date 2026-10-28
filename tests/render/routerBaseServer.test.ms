import { NeonNode } from "../../src/render/hostTypes";
import { element } from "../../src/macros/ui/element";
import { GuardDecision, RouteMatch, redirect } from "../../src/navigation/route";
import { A, Routes, createRoutes } from "../../src/navigation/router";
import { App, DocumentProps, serve } from "../../src/render/serve";

function Home(): NeonNode { return <nav><A href="/docs">Docs</A><h1>home</h1></nav>; }
function Page(props: DocumentProps): NeonNode { return <html><head></head><body>{props.children}</body></html>; }

const routes: Routes = createRoutes([
	{ path: "/", component: Home },
	{ path: "/docs", component: Home },
	{ path: "/old", component: Home, guard: (p: Map<string, string>, f: RouteMatch): GuardDecision => redirect("/docs") },
], "/app");
const app: App = { routes: routes, notFound: <h1>missing</h1>, client: "", document: Page };

test "a server under a base serves the pages under it and renders their links with it" {
	const served = await serve(app, "/app/docs");
	assert served.status === 200, served.status.toString();
	assert served.body.indexOf("<a href=\"/app/docs\" aria-current=\"page\"") >= 0, served.body;
	const root = await serve(app, "/app");
	assert root.status === 200, root.status.toString();
}

test "a server under a base answers an address outside it with 404 and a redirect with the base" {
	const outside = await serve(app, "/docs");
	assert outside.status === 404, outside.status.toString();
	const moved = await serve(app, "/app/old");
	assert moved.status === 307, moved.status.toString();
	assert moved.location === "/app/docs", moved.location ?? "-";
}
