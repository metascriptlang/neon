import { hydrate } from "../../src/render/hydrate";
import { HostNode } from "../../src/render/hostTypes";
import { sleepAsync } from "std/core/promise";

when (js) {
	import { domHost } from "../../src/platform/browser/dom";
	import { breakpointsApp, servedPart } from "./servedApps";

	extern class Page {
		extern remove(): void;
	}
	extern function framedPage(css: cstring, html: cstring, width: number): Page from
		"((c, h, w) => { const f=document.createElement('iframe');f.style.width=w+'px';f.style.height='100px';f.style.border='0';f.srcdoc='<!doctype html><style>body{margin:0}'+c+'</style>'+h;document.body.appendChild(f);return f; })(#, #, #)";
	extern function frameReady(frame: Page): boolean from
		"(f => { try { return f.contentDocument.readyState === 'complete' && f.contentWindow.location.href === 'about:srcdoc'; } catch (e) { return false; } })(#)";
	extern function frameScripts(frame: Page): number from "(f => f.contentDocument.scripts.length)(#)";
	extern function frameSideWidth(frame: Page): number from
		"(f => f.contentDocument.getElementById('side').getBoundingClientRect().width)(#)";
	extern function parsedPage(css: cstring, html: cstring): Page from
		"((c, h) => { const r=document.createElement('div');r.style.width='1440px';const s=document.createElement('style');s.textContent=c;document.head.appendChild(s);r.innerHTML=h;document.body.appendChild(r);return r; })(#, #)";
	extern function sideWidth(root: Page): number from "(r => r.querySelector('\\x23side').getBoundingClientRect().width)(#)";
	extern function markup(root: Page): string from "(r => r.innerHTML)(#)";

	async function laidOut(width: number): Promise<number> {
		const frame = framedPage(servedPart("breakpoints", "css"), servedPart("breakpoints", "html"), width);
		const end = performance.now() + 5000;
		while (!frameReady(frame)) {
			if (performance.now() > end) { throw new Error("timed out waiting for the framed page at " + width.toString()); }
			await sleepAsync(20);
		}
		if (frameScripts(frame) !== 0) { throw new Error("the framed page carries a script"); }
		const w = frameSideWidth(frame);
		frame.remove();
		return w;
	}

	test "served markup lays out each breakpoint before any script runs" {
		assert servedPart("breakpoints", "css").indexOf("@media (min-width:900px)") >= 0, servedPart("breakpoints", "css");
		const narrow = await laidOut(412);
		assert narrow === 412, "the base width at 412, got " + narrow.toString();
		const wide = await laidOut(1440);
		assert wide === 280, "the wide block at 1440, got " + wide.toString();
	}

	test "hydrating a served breakpoint entry changes nothing" {
		const mount = parsedPage(servedPart("breakpoints", "css"), servedPart("breakpoints", "html"));
		const before = markup(mount);
		const widthBefore = sideWidth(mount);
		const dispose = hydrate(breakpointsApp(), domHost(), mount as unknown as HostNode);
		try {
			assert markup(mount) === before, markup(mount) + " vs " + before;
			assert sideWidth(mount) === widthBefore && widthBefore === 280, "width " + sideWidth(mount).toString();
		} finally { dispose(); mount.remove(); }
	}
}
