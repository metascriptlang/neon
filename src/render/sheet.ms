// CSS rule registry for hosts that speak CSS (docs/STYLE.md §5).
//
// The macro bakes each sheet entry's rule text at expansion; this only keeps
// the rules a program actually mounted, so SSR can print them and the browser
// can inject them in one shot.
//
// Registration is keyed by class id and REPLACES: a module re-executed by HMR
// re-registers the same ids and must not grow the sheet. Content-hashed ids
// mean a changed rule arrives under a new id, so a node still carrying the old
// class keeps rendering the old rule until it remounts.

let ids: string[] = [];
let rules: string[] = [];

export function registerCss(id: string, css: string): void {
	for (let i = 0; i < ids.length; i += 1) {
		if (ids[i] === id) { rules[i] = css; return; }
	}
	ids.push(id);
	rules.push(css);
}

export function collectCss(): string {
	let s = "";
	for (const r of rules) { s = s + r; }
	return s;
}

export function cssRuleCount(): number {
	return ids.length;
}

export function resetCss(): void {
	ids.splice(0, ids.length);
	rules.splice(0, rules.length);
}
