import "./out/pages.js";

export default {
	fetch(request) {
		const html = globalThis.neonEdgePage(new URL(request.url).pathname);
		return new Response(html, { headers: { "content-type": "text/html; charset=utf-8" } });
	},
};
