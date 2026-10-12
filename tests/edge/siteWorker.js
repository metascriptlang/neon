import "./out/site.js";
import client from "./out/siteClient.js";

export default {
	fetch(request) {
		const url = new URL(request.url);
		if (url.pathname === "/client.js") {
			return new Response(client, { headers: { "content-type": "text/javascript; charset=utf-8" } });
		}
		const page = globalThis.neonSite(url.pathname + url.search);
		return new Response(page.body, { status: page.status, headers: { "content-type": "text/html; charset=utf-8" } });
	},
};
