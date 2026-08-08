// Terminal Host — implements Neon's Host interface for terminal rendering.
//
// The Host creates TerminalNode objects (a retained tree), same as mockHost
// creates MockNode and domHost creates DOM nodes. The paint pass (paint.ms)
// walks the resulting TerminalNode tree and emits ANSI string lines.
//
// Supported tags:
//   <box>    — container with optional border, padding, color
//   <row>    — horizontal container (children side by side)
//   <text>   — text block (wraps within parent width)
//   <span>   — inline text fragment
//   <line>   — single-line text (no wrapping, truncates)
//   <hr>     — horizontal rule (fills width with ─)
//   <gap>    — vertical spacer (height attribute = number of blank lines)

import { Host, HostNode } from "../../render/hostTypes";
import { Style } from "../../render/style";
import {
	TerminalNode, TerminalEvent, TerminalStyle,
	createTerminalNode, createTerminalTextNode,
} from "./types";

function hexNibble(c: string): number {
	if (c >= "0" && c <= "9") { return c.charCodeAt(0) - 48; }
	if (c >= "a" && c <= "f") { return c.charCodeAt(0) - 87; }
	if (c >= "A" && c <= "F") { return c.charCodeAt(0) - 55; }
	return -1;
}

// "#rgb" / "#rrggbb" → the nearest of the 8 ANSI base colors, which is all a
// terminal can render. Any other string is passed through as a colour name.
function ansiNameFor(css: string): string {
	if (css === "") { return ""; }
	if (css.charAt(0) !== "#") { return css; }
	const body = css.substring(1, css.length);
	let r = -1;
	let g = -1;
	let b = -1;
	if (body.length === 3) {
		r = hexNibble(body.charAt(0)) * 17;
		g = hexNibble(body.charAt(1)) * 17;
		b = hexNibble(body.charAt(2)) * 17;
	} else if (body.length === 6) {
		r = hexNibble(body.charAt(0)) * 16 + hexNibble(body.charAt(1));
		g = hexNibble(body.charAt(2)) * 16 + hexNibble(body.charAt(3));
		b = hexNibble(body.charAt(4)) * 16 + hexNibble(body.charAt(5));
	}
	if (r < 0 || g < 0 || b < 0) { return ""; }

	const names = ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"];
	const reds = [0, 205, 0, 205, 0, 205, 0, 229];
	const greens = [0, 0, 205, 205, 0, 0, 205, 229];
	const blues = [0, 0, 0, 0, 238, 205, 205, 229];
	let best = 0;
	let bestDist = -1;
	for (let i = 0; i < names.length; i += 1) {
		const dr = r - reds[i];
		const dg = g - greens[i];
		const db = b - blues[i];
		const dist = dr * dr + dg * dg + db * db;
		if (bestDist < 0 || dist < bestDist) { bestDist = dist; best = i; }
	}
	return names[best];
}

// docs/STYLE.md §5 — the terminal's projection of the portable Style IR.
// A terminal has no flexbox, so the layout half is dropped on purpose.
export function asTerminalStyle(this s: Style): TerminalStyle {
	const color = s.color;
	const bg = s.backgroundColor;
	return {
		color: color !== null ? ansiNameFor(color as string) : "",
		bg: bg !== null ? ansiNameFor(bg as string) : "",
		bold: s.fontWeight !== null && (s.fontWeight as string) === "bold",
		dim: s.opacity !== null && (s.opacity as number) < 1.0,
		italic: false,
		underline: false,
	};
}

function childIndex(parent: TerminalNode, node: TerminalNode): number {
	for (let i = 0; i < parent.children.length; i += 1) {
		if (parent.children[i] === node) { return i; }
	}
	return -1;
}

function detach(n: TerminalNode): void {
	const p = n.parent;
	if (p === null) { return; }
	const idx = childIndex(p, n);
	if (idx >= 0) { p.children.splice(idx, 1); }
	n.parent = null;
}

function applyAttr(node: TerminalNode, name: string, value: string): void {
	node.attrs.set(name, value);
	node.dirty = true;
	match (name) {
		"color" => { node.style.color = value; },
		"bg" => { node.style.bg = value; },
		"bold" => { node.style.bold = value === "true"; },
		"dim" => { node.style.dim = value === "true"; },
		"italic" => { node.style.italic = value === "true"; },
		"underline" => { node.style.underline = value === "true"; },
		_ => {},
	};
}

export function terminalHost(): Host {
	return {
		createElement: (tag: string): HostNode => {
			return createTerminalNode(tag) as unknown as HostNode;
		},
		createText: (s: string): HostNode => {
			return createTerminalTextNode(s) as unknown as HostNode;
		},
		setText: (node: HostNode, s: string): void => {
			const n = node as unknown as TerminalNode;
			n.text = s;
			n.dirty = true;
		},
		setAttr: (node: HostNode, name: string, value: string): void => {
			applyAttr(node as unknown as TerminalNode, name, value);
		},
		setStyle: (node: HostNode, style: Style): void => {
			const n = node as unknown as TerminalNode;
			n.style = asTerminalStyle(style);
			n.dirty = true;
		},
		addEvent: (node: HostNode, name: string, handler: () => void): void => {
			const n = node as unknown as TerminalNode;
			const ev: TerminalEvent = { name, handler };
			n.events.push(ev);
		},
		append: (parent: HostNode, child: HostNode): void => {
			const p = parent as unknown as TerminalNode;
			const c = child as unknown as TerminalNode;
			detach(c);
			c.parent = p;
			p.children.push(c);
		},
		insertBefore: (parent: HostNode, node: HostNode, ref: HostNode | null): void => {
			const p = parent as unknown as TerminalNode;
			const n = node as unknown as TerminalNode;
			let target = ref === null ? p.children.length : childIndex(p, ref as unknown as TerminalNode);
			if (target < 0) { target = p.children.length; }
			const curIdx = childIndex(p, n);
			if (curIdx >= 0) {
				p.children.splice(curIdx, 1);
				if (curIdx < target) { target -= 1; }
			} else {
				detach(n);
			}
			n.parent = p;
			const shifted: TerminalNode[] = [];
			let i = target;
			while (i < p.children.length) {
				shifted.push(p.children[i]);
				i += 1;
			}
			p.children.splice(target, p.children.length - target);
			p.children.push(n);
			let j = 0;
			while (j < shifted.length) {
				p.children.push(shifted[j]);
				j += 1;
			}
		},
		removeChild: (parent: HostNode, node: HostNode): void => {
			const p = parent as unknown as TerminalNode;
			const n = node as unknown as TerminalNode;
			const idx = childIndex(p, n);
			if (idx >= 0) { p.children.splice(idx, 1); }
			n.parent = null;
		},
		nextSibling: (node: HostNode): HostNode | null => {
			const n = node as unknown as TerminalNode;
			const p = n.parent;
			if (p === null) { return null; }
			const idx = childIndex(p, n);
			if (idx < 0 || idx + 1 >= p.children.length) { return null; }
			return p.children[idx + 1] as unknown as HostNode;
		},
		firstChild: (node: HostNode): HostNode | null => {
			const n = node as unknown as TerminalNode;
			if (n.children.length === 0) { return null; }
			return n.children[0] as unknown as HostNode;
		},
		cloneNode: null,
	};
}

export function fireTerminalEvent(node: TerminalNode, name: string): void {
	for (const e of node.events) {
		if (e.name === name) { e.handler(); }
	}
}
