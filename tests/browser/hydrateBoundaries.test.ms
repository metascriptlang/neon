import { hydrate, HostNode } from "../../src/render/host";

when (js) {
	import { domHost } from "../../src/platform/browser/dom";
	import { loadingApp, loadingHtml } from "./boundaryPages";

	extern class Page {
		textContent: string;
		innerHTML: string;
		extern remove(): void;
	}
	extern function parsedPage(html: cstring): Page from
		"(s => { const r=document.createElement('div');r.innerHTML=s;document.body.appendChild(r);r.querySelectorAll('*').forEach(n=>{n.neonServed=true;});return r; })(#)";
	extern function pageNode(root: Page, selector: cstring): Page from "(#).querySelector(#)";
	extern function sameNode(a: Page, b: Page): boolean from "((#) === (#))";
	extern function notServed(root: Page): number from
		"(r => Array.from(r.querySelectorAll('*')).filter(n=>n.neonServed!==true).length)(#)";

	test "a served Loading with static content hydrates onto the page's own nodes" {
		const mount = parsedPage(loadingHtml);
		const served = pageNode(mount, "p");
		const dispose = hydrate(loadingApp(), domHost(), mount as unknown as HostNode);
		try {
			assert mount.innerHTML === loadingHtml.replace("<!---->", ""), mount.innerHTML;
			assert sameNode(pageNode(mount, "p"), served), "the content is the page's own <p>";
			assert notServed(mount) === 0, notServed(mount).toString() + " elements are not the page's own";
		} finally {
			dispose();
			mount.remove();
		}
	}
}
