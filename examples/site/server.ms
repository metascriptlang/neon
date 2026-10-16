import { NeonNode } from "../../src/render/hostTypes";
import { renderToStream } from "../../src/render/ssr";
import { RoutingError } from "../../src/navigation/routing";
import { createRequestRoutingHistory } from "../../src/navigation/routingHistory";
import { RouterProvider, createRouter } from "../../src/navigation/router";
import { Note, NotFound, noteOf, routes } from "./site";

export { staticPaths } from "./site";

struct SiteResponse {
	status: int32;
	location: string | null;
	body: string;
}

async function document(page: NeonNode): Promise<string> {
	const markup = await renderToStream(page);
	return "<!doctype html><html><head><meta charset=\"utf-8\">" + markup.head +
		"<style>" + markup.css + "</style></head><body><div id=\"site\">" + markup.html +
		"</div>" + markup.records + "<script type=\"module\" src=\"/client.js\"></script></body></html>";
}

export function noteJson(slug: string): string {
	return JSON.stringify<Note>(noteOf(slug, "from the api"));
}

export async function respond(url: string): Promise<SiteResponse> {
	const opened = createRouter(routes, createRequestRoutingHistory(url));
	if (!opened.ok) {
		return {
			status: opened.error === RoutingError.NoMatch ? 404 : 400,
			location: null,
			body: await document(<NotFound />),
		};
	}
	const router = opened.value;
	try {
		const response = router.response();
		if (response.location !== null) {
			return { status: response.status, location: response.location, body: "" };
		}
		return { status: response.status, location: null, body: await document(<RouterProvider router={router} />) };
	} finally {
		router.dispose();
	}
}
