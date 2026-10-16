import { slowStream, slowAwaited } from "./out/streamPages.js";

let release = () => {};

export default {
	async fetch(request) {
		const path = new URL(request.url).pathname;
		const headers = { "content-type": "text/html; charset=utf-8" };
		if (path === "/release") {
			release(1);
			return new Response("released");
		}
		if (path === "/awaited") {
			return new Response(await slowAwaited(Promise.resolve(1)), { headers });
		}
		const gate = new Promise((open) => { release = open; });
		return new Response(slowStream(gate), { headers });
	},
};
