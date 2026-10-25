import { NeonNode } from "./hostTypes";
import { Routes } from "../navigation/router";
import { getOwner } from "../core/runtime";
import { createContext, useContext } from "./context";

export struct Served {
	status: int32;
	location: string | null;
	body: string;
}

export struct DocumentProps {
	assets: NeonNode;
	scripts: NeonNode;
	children: NeonNode;
}

export struct App {
	routes: Routes;
	notFound: NeonNode;
	client: string;
	document: ((props: DocumentProps) => NeonNode) | null;
}

export function htmlDocument(props: DocumentProps): NeonNode {
	const assets = props.assets;
	const scripts = props.scripts;
	const children = props.children;
	return <html><head><meta charset="utf-8" />{assets}</head><body><div id="app">{children}</div>{scripts}</body></html>;
}

export struct RequestHeaders {
	byName: Map<string, string>;
}

export function get(this headers: RequestHeaders, name: string): string | null {
	return headers.byName.get(name.toLowerCase());
}

export struct ServedRequest {
	url: string;
	headers: RequestHeaders;
}

export struct RequestEvent {
	request: ServedRequest;
}

const requestEvents = createContext<RequestEvent | null>(null);

export function getRequestEvent(): RequestEvent | null {
	return getOwner() === null ? null : useContext(requestEvents);
}

when (server) {
	import { Host, HostNode } from "./hostTypes";
	import { setContext } from "./context";
	import { rawHtml, renderToStream, renderToString } from "./ssr";
	import { RoutingError } from "../navigation/routing";
	import { createRequestRoutingHistory } from "../navigation/routingHistory";
	import { RouterProvider, createRouter } from "../navigation/router";

	function injectAssets(assets: string, html: string): string {
		const at = html.indexOf("</head>");
		if (at < 0) { throw new Error("the App document wrote no <head>, so the page's Head content and styles have nowhere to go"); }
		return html.slice(0, at) + assets + html.slice(at);
	}

	function requestHeaders(given: Map<string, string>): RequestHeaders {
		const byName = new Map<string, string>();
		for (const [name, value] of given) {
			const key = name.toLowerCase();
			const held = byName.get(key);
			byName.set(key, held === null ? value : held + ", " + value);
		}
		return { byName: byName };
	}

	async function page(app: App, event: RequestEvent, node: NeonNode): Promise<string> {
		const markup = await renderToStream((host: Host, parent: HostNode, before: HostNode | null): void => {
			setContext<RequestEvent | null>(requestEvents, event);
			node(host, parent, before);
		});
		const document = app.document ?? htmlDocument;
		const props: DocumentProps = {
			assets: rawHtml(""),
			scripts: app.client === "" ? rawHtml(markup.records) : <>{rawHtml(markup.records)}<script type="module" src={app.client} /></>,
			children: rawHtml(markup.html),
		};
		const html = renderToString((host: Host, parent: HostNode, before: HostNode | null): void => {
			setContext<RequestEvent | null>(requestEvents, event);
			document(props)(host, parent, before);
		});
		return "<!doctype html>" + injectAssets(markup.head + "<style>" + markup.css + "</style>", html);
	}

	export async function serve(
		app: App,
		url: string,
		headers: Map<string, string> = new Map<string, string>(),
	): Promise<Served> {
		const event: RequestEvent = { request: { url: url, headers: requestHeaders(headers) } };
		const opened = createRouter(app.routes, createRequestRoutingHistory(url));
		if (!opened.ok) {
			return {
				status: opened.error === RoutingError.NoMatch ? 404 : 400,
				location: null,
				body: await page(app, event, app.notFound),
			};
		}
		const router = opened.value;
		try {
			const response = router.response();
			if (response.location !== null) {
				return { status: response.status, location: response.location, body: "" };
			}
			return { status: response.status, location: null, body: await page(app, event, <RouterProvider router={router} />) };
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
		extern function headerPairs(request: Request): string[] from "((r) => [...r.headers].flat())(#)";

		function fetchHeaders(request: Request): Map<string, string> {
			const pairs = headerPairs(request);
			const given = new Map<string, string>();
			for (let at = 0; at + 1 < pairs.length; at += 2) { given.set(pairs[at], pairs[at + 1]); }
			return given;
		}

		export async function fetchPage(app: App, request: Request): Promise<Response> {
			if (request.method !== "GET" && request.method !== "HEAD") { return answer(405, null, "", "GET, HEAD"); }
			const served = await serve(app, pathOf(request.url), fetchHeaders(request));
			return answer(served.status, served.location, request.method === "HEAD" ? "" : served.body, "");
		}
	}
} else {
	import { Node } from "std/meta";

	export macro serve(app: Node, url: Node): Node {
		error("serve needs a -d:server build", app);
	}
}
