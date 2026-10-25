import { App, Served, htmlDocument, serve } from "../../src/render/serve";
import { Note, NotFound, noteOf, routes } from "./site";

export { staticPaths } from "./site";

const app: App = { routes: routes, notFound: <NotFound />, client: "/client.js", document: htmlDocument };

export function noteJson(slug: string): string {
	return JSON.stringify<Note>(noteOf(slug, "from the api"));
}

export function answer(url: string): Promise<Served> {
	return serve(app, url);
}

when (js) {
	import { Request, Response, fetchPage } from "../../src/render/serve";

	export function respond(request: Request): Promise<Response> {
		return fetchPage(app, request);
	}
}
