import { renderToString } from "../../src/render/ssr";
import { NeonNode } from "../../src/render/hostTypes";
import { element } from "../../src/macros/ui/element";
import { createRequestRoutingHistory } from "../../src/navigation/routingHistory";
import { PreloadArgs } from "../../src/navigation/route";
import { RouterProvider, createRouter, createRoutes } from "../../src/navigation/router";

const trace: string[] = [];

function Doc(): NeonNode {
	trace.push("render");
	return <h1>doc</h1>;
}

test "a server render runs a route's preload as initial before its component" {
	const routes = createRoutes([
		{
			path: "/docs/:slug",
			component: Doc,
			preload: (args: PreloadArgs<Map<string, string>>): void => {
				trace.push("preload " + (args.params.get("slug") ?? "") + " " + args.intent + " " + args.location.pathname);
			},
		},
	]);
	const opened = createRouter(routes, createRequestRoutingHistory("/docs/start"));
	assert opened.ok;
	if (opened.ok) {
		const router = opened.value;
		const html = renderToString(<RouterProvider router={router} />);
		assert html.indexOf("<h1>doc</h1>") >= 0, html;
		assert trace.join(" | ") === "preload start initial /docs/start | render", trace.join(" | ");
		router.dispose();
	}
}
