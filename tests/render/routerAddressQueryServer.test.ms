import { NeonNode } from "../../src/render/hostTypes";
import { element } from "../../src/macros/ui/element";
import { Routes, createRoutes, useLocation, useParams } from "../../src/navigation/router";
import { App, DocumentProps, serve } from "../../src/render/serve";

function Doc(): NeonNode {
	return <h1>{"doc " + (useParams().get("slug") ?? "") + "|" + (useLocation()().search.get("q") ?? "")}</h1>;
}
function Missing(): NeonNode { return <h1>catchall</h1>; }
function Page(props: DocumentProps): NeonNode { return <html><head></head><body>{props.children}</body></html>; }

const routes: Routes = createRoutes([
	{ path: "/docs/:slug", component: Doc },
	{ path: "*", status: 404, component: Missing },
]);
const app: App = { routes: routes, notFound: <Missing />, client: "", document: Page };

test "a request with a malformed percent escape in the query is served" {
	const served = await serve(app, "/docs/a?q=%zz");
	assert served.status === 200, served.status.toString();
	assert served.body.includes("doc a|%zz"), served.body;
	const percent = await serve(app, "/docs/a?utm=100%");
	assert percent.status === 200, percent.status.toString();
}

test "a request with a malformed percent escape in the path is a 400" {
	const served = await serve(app, "/docs/%zz");
	assert served.status === 400, served.status.toString();
}
