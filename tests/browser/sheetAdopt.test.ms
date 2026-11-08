// A served page's <style> is the client's sheet: hydrating it mounts no second
// one, so every rule the server wrote applies once. Alone in its file because
// only the first domHost() of a page takes the served sheet over.

import { hydrate } from "../../src/render/hydrate";
import { HostNode } from "../../src/render/hostTypes";

when (js) {
	import { domHost } from "../../src/platform/browser/dom";
	import { breakpointsApp, servedPart } from "./servedApps";

	extern class Page {
		extern remove(): void;
	}
	extern function servedPage(sheet: cstring, html: cstring): Page from
		"((s, h) => { document.head.insertAdjacentHTML('beforeend', s); const r = document.createElement('div'); r.style.width = '1440px'; r.innerHTML = h; document.body.appendChild(r); return r; })(#, #)";
	extern function styleCount(): number from "(() => document.querySelectorAll('style').length)()";
	extern function ruleCount(): number from "(() => document.querySelector('style[data-neon-sheet]').sheet.cssRules.length)()";
	extern function listedIds(): number from "(() => document.querySelector('style[data-neon-sheet]').getAttribute('data-neon-sheet').split(' ').length)()";
	extern function groupsNaming(cls: cstring): number from
		"(c => [...document.styleSheets].flatMap(s => [...s.cssRules]).filter(r => r.cssText.includes('.' + c + ' ')).length)(#)";
	extern function sideWidth(root: Page): number from "(r => r.querySelector('\\x23side').getBoundingClientRect().width)(#)";
	extern function sideClass(root: Page): string from "(r => [...r.querySelector('\\x23side').classList].find(c => c !== 'neon-view') ?? '')(#)";

	test "hydrating a served page keeps one Neon sheet, and each rule in it once" {
		const sheet = servedPart("breakpoints", "sheet");
		assert sheet.startsWith("<style data-neon-sheet=\""), "the server writes its sheet for the client to take: " + sheet;
		const mount = servedPage(sheet, servedPart("breakpoints", "html"));
		const served = ruleCount();
		assert served === listedIds(), `the served sheet lists ${listedIds()} ids for ${served} groups`;
		const dispose = hydrate(breakpointsApp(), domHost(), mount as unknown as HostNode);
		try {
			assert styleCount() === 1, `hydrate mounted a second sheet: ${styleCount()} <style> elements`;
			assert ruleCount() === listedIds(), `the sheet holds ${ruleCount()} groups for ${listedIds()} ids`;
			const cls = sideClass(mount);
			assert cls !== "", "the served entry carries its sheet class";
			assert groupsNaming(cls) === 1, `the rule of ${cls} applies ${groupsNaming(cls)} times`;
			assert sideWidth(mount) === 280, "the wide block keeps its media rule, got " + sideWidth(mount).toString();
		} finally { dispose(); mount.remove(); }
	}
}
