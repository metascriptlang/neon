import { HostNode } from "../../src/render/host";
import { hydrate } from "../../src/render/hydrate";
import { clearRecords } from "../../src/render/hydrationRecords";
import { flush } from "../../src/core/runtime";

when (js) {
	import { sleepAsync } from "std/core/promise";
	import { domHost } from "../../src/platform/browser/dom";
	import { asyncPage, Note } from "./asyncPage";
	import { servedPart } from "./servedApps";

	extern class Page {
		textContent: string;
		extern remove(): void;
		extern click(): void;
	}
	extern function parsedPage(html: cstring): Page from
		"(s => { const r=document.createElement('div');r.innerHTML=s;document.body.appendChild(r);r.querySelectorAll('*').forEach(n=>{n.neonServed=true;});return r; })(#)";
	extern function parseScripts(html: cstring): void from
		"(h => { document.body.appendChild(document.createRange().createContextualFragment(h)); })(#)";
	extern function pageNode(root: Page, selector: cstring): Page from "(#).querySelector(#)";
	extern function notServed(root: Page): number from
		"(r => Array.from(r.querySelectorAll('*')).filter(n=>n.neonServed!==true).length)(#)";
	extern function spyFetch(): void from
		"(() => { const spy = () => { globalThis.neonFetchCalls++; return Promise.resolve(new Response('')); }; globalThis.neonFetchCalls = 0; globalThis.neonRealFetch = globalThis.fetch; globalThis.fetch = spy; })()";
	extern function unspyFetch(): void from "(() => { globalThis.fetch = globalThis.neonRealFetch; })()";
	extern function callFetch(url: cstring): void from "(u => { fetch(u); })(#)";
	extern function fetchCalls(): int32 from "(globalThis.neonFetchCalls)";

	async function fromClient(n: int32): Promise<Note> {
		callFetch("/note?n=" + n.toString());
		await sleepAsync(1);
		return { text: "client says", n: n };
	}

	test "a page the server rendered with an async read hydrates with no request, and an interaction then updates it" {
		clearRecords();
		const mount = parsedPage(servedPart("async", "html"));
		parseScripts(servedPart("async", "records"));
		const sent = mount.textContent;
		assert sent === "server says 1next", sent;
		spyFetch();
		const dispose = hydrate(asyncPage(fromClient), domHost(), mount as unknown as HostNode);
		try {
			assert fetchCalls() === 0, "hydrate sent " + fetchCalls().toString() + " requests";
			assert mount.textContent === sent, "the page kept the server's text: " + mount.textContent;
			assert notServed(mount) === 0, notServed(mount).toString() + " elements are not the page's own";

			pageNode(mount, "#next").click();
			flush();
			await sleepAsync(30);
			assert fetchCalls() === 1, "the interaction sent " + fetchCalls().toString() + " requests";
			assert mount.textContent === "client says 2next", mount.textContent;
		} finally {
			unspyFetch();
			dispose();
			mount.remove();
			clearRecords();
		}
	}

	test "the same server page hydrates once more after a second interaction without a request from hydrate" {
		clearRecords();
		const mount = parsedPage(servedPart("async", "html"));
		parseScripts(servedPart("async", "records"));
		spyFetch();
		const dispose = hydrate(asyncPage(fromClient), domHost(), mount as unknown as HostNode);
		try {
			assert fetchCalls() === 0, "hydrate sent " + fetchCalls().toString() + " requests";
			pageNode(mount, "#next").click();
			flush();
			pageNode(mount, "#next").click();
			flush();
			await sleepAsync(30);
			assert mount.textContent === "client says 3next", mount.textContent;
			assert fetchCalls() === 2, fetchCalls().toString();
		} finally {
			unspyFetch();
			dispose();
			mount.remove();
			clearRecords();
		}
	}
}
