import { slowStream, slowAwaited } from "./out/streamPages.js";

export default {
	async fetch(request) {
		const url = new URL(request.url);
		const headers = { "content-type": "text/html; charset=utf-8" };
		if (url.pathname === "/awaited") {
			return new Response(await slowAwaited(Promise.resolve(1)), { headers });
		}
		const slowRead = fetch(url.searchParams.get("gate")).then((answer) => answer.text()).then(Number);
		return new Response(slowStream(slowRead), { headers });
	},
};
