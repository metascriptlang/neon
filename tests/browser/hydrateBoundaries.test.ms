import { HostNode } from "../../src/render/host";
import { hydrate } from "../../src/render/hydrate";

when (js) {
	import { domHost } from "../../src/platform/browser/dom";
	import { loadingApp, erroringApp, erroringChildApp, loadingHtml, erroringHtml, erroringChildHtml } from "./boundaryPages";

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

	test "a served Errored whose content throws while hydrating takes the served fallback" {
		const mount = parsedPage(erroringHtml);
		const served = pageNode(mount, "em");
		const dispose = hydrate(erroringApp(), domHost(), mount as unknown as HostNode);
		try {
			assert mount.innerHTML === erroringHtml.replace("<!---->", ""), mount.innerHTML;
			assert sameNode(pageNode(mount, "em"), served), "the fallback is the page's own <em>";
			assert notServed(mount) === 0, notServed(mount).toString() + " elements are not the page's own";
		} finally {
			dispose();
			mount.remove();
		}
	}

	test "an error in a child component after the content claimed its nodes takes the served fallback, and a reset then mounts the content" {
		const mount = parsedPage(erroringChildHtml);
		const served = pageNode(mount, "section");
		const attempts = [0];
		const resets: (() => void)[] = [];
		const dispose = hydrate(erroringChildApp(attempts, resets), domHost(), mount as unknown as HostNode);
		try {
			assert mount.innerHTML === erroringChildHtml.replace("<!---->", ""), mount.innerHTML;
			assert sameNode(pageNode(mount, "section"), served), "the fallback is the page's own <section>";
			assert notServed(mount) === 0, notServed(mount).toString() + " elements are not the page's own";
			resets[0]();
			assert mount.innerHTML === "<div><i>lead</i><section>fine</section></div>", mount.innerHTML;
		} finally {
			dispose();
			mount.remove();
		}
	}
}
