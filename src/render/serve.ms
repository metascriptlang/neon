import { NeonNode } from "./hostTypes";
import { SsrMarkup } from "./ssr";
import { Routes } from "../navigation/router";

export struct Served {
	status: int32;
	location: string | null;
	body: string;
}

export struct App {
	routes: Routes;
	notFound: NeonNode;
	document: (markup: SsrMarkup) => string;
}

when (server) {
	import { renderToStream } from "./ssr";
	import { RoutingError } from "../navigation/routing";
	import { createRequestRoutingHistory } from "../navigation/routingHistory";
	import { RouterProvider, createRouter } from "../navigation/router";

	export function htmlDocument(root: string, client: string): (markup: SsrMarkup) => string {
		return (markup: SsrMarkup): string => "<!doctype html><html><head><meta charset=\"utf-8\">" + markup.head +
			"<style>" + markup.css + "</style></head><body><div id=\"" + root + "\">" + markup.html +
			"</div>" + markup.records + "<script type=\"module\" src=\"" + client + "\"></script></body></html>";
	}

	async function page(app: App, node: NeonNode): Promise<string> {
		return app.document(await renderToStream(node));
	}

	export async function serve(app: App, url: string): Promise<Served> {
		const opened = createRouter(app.routes, createRequestRoutingHistory(url));
		if (!opened.ok) {
			return {
				status: opened.error === RoutingError.NoMatch ? 404 : 400,
				location: null,
				body: await page(app, app.notFound),
			};
		}
		const router = opened.value;
		try {
			const response = router.response();
			if (response.location !== null) {
				return { status: response.status, location: response.location, body: "" };
			}
			return { status: response.status, location: null, body: await page(app, <RouterProvider router={router} />) };
		} finally {
			router.dispose();
		}
	}

	when (js) {
		export extern class Request {
			url: string;
			method: string;
		}
		export extern class Response {}

		extern function answer(status: int32, location: string | null, body: string, allow: string): Response from
			"((s, l, b, a) => a !== '' ? new Response(null, { status: s, headers: { allow: a } }) : l !== null ? new Response(null, { status: s, headers: { location: l } }) : new Response(b, { status: s, headers: { 'content-type': 'text/html; charset=utf-8' } }))(#, #, #, #)";
		extern function pathOf(url: string): string from "((u) => { const p = new URL(u); return p.pathname + p.search; })(#)";

		export async function fetchPage(app: App, request: Request): Promise<Response> {
			if (request.method !== "GET" && request.method !== "HEAD") { return answer(405, null, "", "GET, HEAD"); }
			const served = await serve(app, pathOf(request.url));
			return answer(served.status, served.location, request.method === "HEAD" ? "" : served.body, "");
		}
	}
} else {
	import { Node } from "std/meta";

	export macro htmlDocument(root: Node, client: Node): Node {
		error("htmlDocument needs a -d:server build", root);
	}

	export macro serve(app: Node, url: Node): Node {
		error("serve needs a -d:server build", app);
	}
}
