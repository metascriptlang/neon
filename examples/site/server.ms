import { App, Request, Response, fetchPage, htmlDocument } from "../../src/render/serve";
import { Note, NotFound, noteOf, routes } from "./site";

export { staticPaths } from "./site";

const app: App = { routes: routes, notFound: <NotFound />, document: htmlDocument("site", "/client.js") };

export function noteJson(slug: string): string {
	return JSON.stringify<Note>(noteOf(slug, "from the api"));
}

export function respond(request: Request): Promise<Response> {
	return fetchPage(app, request);
}
