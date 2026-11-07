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

// A theme swap replaces the `:root` rule with no node involved, so nothing on
// the render path would tell a host to re-mount the sheet. The host leaves its
// flush here and the registry calls it with the slot that changed; slots only
// append, so a host can keep one rule per slot in registration order.
let changed: ((slot: number) => void) | null = null;

export function onCssChange(f: ((slot: number) => void) | null): void {
	changed = f;
}

export function registerCss(id: string, css: string): void {
	for (let i = 0; i < ids.length; i += 1) {
		if (ids[i] === id) {
			if (rules[i] === css) { return; }
			rules[i] = css;
			if (changed !== null) { (changed as (slot: number) => void)(i); }
			return;
		}
	}
	ids.push(id);
	rules.push(css);
	if (changed !== null) { (changed as (slot: number) => void)(rules.length - 1); }
}

export function cssIds(): string[] {
	return ids.slice(0);
}

export function collectCss(): string {
	let s = "";
	for (const r of rules) { s = s + r; }
	return s;
}

// Server rendering has no host to flush into: renderToString registers every
// rule it meets, and the page emits the whole registry in one block.
export function mountSheet(): string {
	const css = collectCss();
	return css === "" ? "" : "<style>" + css + "</style>";
}

export function cssAt(slot: number): string {
	return rules[slot];
}

export function cssRuleCount(): number {
	return ids.length;
}

export function resetCss(): void {
	ids.splice(0, ids.length);
	rules.splice(0, rules.length);
}
