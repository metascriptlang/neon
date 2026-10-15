import { NeonNode } from "../../src/render/hostTypes";
import { renderToMarkup } from "../../src/render/ssr";
import { RoutingError } from "../../src/navigation/routing";
import { createRequestRoutingHistory } from "../../src/navigation/routingHistory";
import { RouterProvider, createRouter } from "../../src/navigation/router";
import { NotFound, routes } from "./site";

export { staticPaths } from "./site";

struct SiteResponse {
	status: int32;
	location: string | null;
	body: string;
}

function document(page: NeonNode): string {
	const markup = renderToMarkup(page);
	return "<!doctype html><html><head><meta charset=\"utf-8\">" + markup.head +
		"<style>" + markup.css + "</style></head><body><div id=\"site\">" + markup.html +
		"</div><script type=\"module\" src=\"/client.js\"></script></body></html>";
}

export function respond(url: string): SiteResponse {
	const opened = createRouter(routes, createRequestRoutingHistory(url));
	if (!opened.ok) {
		return {
			status: opened.error === RoutingError.NoMatch ? 404 : 400,
			location: null,
			body: document(<NotFound />),
		};
	}
	const router = opened.value;
	try {
		const response = router.response();
		if (response.location !== null) {
			return { status: response.status, location: response.location, body: "" };
		}
		return { status: response.status, location: null, body: document(<RouterProvider router={router} />) };
	} finally {
		router.dispose();
	}
}
