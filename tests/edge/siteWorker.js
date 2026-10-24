import { noteJson, respond } from "./out/site.js";
import client from "./out/siteClient.js";

export default {
	fetch(request) {
		const { pathname } = new URL(request.url);
		if (pathname === "/client.js") {
			return new Response(client, { headers: { "content-type": "text/javascript; charset=utf-8" } });
		}
		if (pathname.startsWith("/api/note/")) {
			return new Response(noteJson(pathname.slice("/api/note/".length)), { headers: { "content-type": "application/json" } });
		}
		return respond(request);
	},
};
