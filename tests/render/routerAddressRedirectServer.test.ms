import { NeonNode } from "../../src/render/hostTypes";
import { element } from "../../src/macros/ui/element";
import { GuardDecision, RouteMatch, redirect } from "../../src/navigation/route";
import { Routes, createRoutes } from "../../src/navigation/router";
import { App, DocumentProps, serve } from "../../src/render/serve";

function Home(): NeonNode { return <h1>home</h1>; }
function Page(props: DocumentProps): NeonNode { return <html><head></head><body>{props.children}</body></html>; }

const routes: Routes = createRoutes([
	{ path: "/", component: Home },
	{ path: "/out", component: Home, guard: (p: Map<string, string>, f: RouteMatch): GuardDecision => redirect("https://example.com/x") },
]);
const app: App = { routes: routes, notFound: <Home />, client: "", document: Page };

test "a route that redirects outside the app is a 307 with that location" {
	const served = await serve(app, "/out");
	assert served.status === 307, served.status.toString();
	assert served.location === "https://example.com/x", served.location ?? "-";
	assert served.body === "";
}
