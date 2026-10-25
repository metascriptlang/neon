import { hydrate, HostNode } from "../../src/render/host";
import { clearRecords } from "../../src/render/hydrationRecords";
import { hydrating } from "../../src/render/claim";
import { flush } from "../../src/core/runtime";

when (js) {
	import { sleepAsync } from "std/core/promise";
	import { domHost } from "../../src/platform/browser/dom";
	import { lazyCounterPage, servedPart } from "./servedApps";

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
	extern function keepResourceEntries(): void from "(performance.setResourceTimingBufferSize(5000))";
	extern function fetched(): boolean from
		"(performance.getEntriesByType('resource').some(e => e.name.includes('/lazy/counter')))";

	test "a served page with a lazy the client has not fetched hydrates once its module loads and keeps the served button" {
		keepResourceEntries();
		clearRecords();
		const mount = parsedPage(servedPart("lazyCounter", "html"));
		parseScripts(servedPart("lazyCounter", "records"));
		const sent = mount.textContent;
		const button = pageNode(mount, "#lazyCount");
		assert sent === "count 0", sent;
		assert !fetched(), "the module was fetched before hydrate";
		const dispose = hydrate(lazyCounterPage(), domHost(), mount as unknown as HostNode);
		try {
			assert !hydrating() && mount.textContent === sent, "the claim waits for the module: " + mount.textContent;
			let polls: int32 = 0;
			while (!fetched() && polls < 500) { await sleepAsync(10); polls += 1; }
			await sleepAsync(10);
			assert fetched(), "the module was never fetched";
			assert !hydrating(), "the claim ended";
			assert mount.textContent === sent, "the page kept the server's text: " + mount.textContent;
			assert notServed(mount) === 0, notServed(mount).toString() + " elements are not the page's own";
			button.click();
			flush();
			assert pageNode(mount, "#lazyCount") === button && button.textContent === "count 1", "the served button is the live one: " + mount.textContent;
		} finally {
			dispose();
			mount.remove();
			clearRecords();
		}
	}
}
