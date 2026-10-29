import { Host, HostNode, TextMeasure } from "../../render/hostTypes";
import { NeonEvent, neonEvent, eventType } from "../../render/event";
import { Style, isBoldWeight } from "../../render/style";
import { terminalStyleCoverage } from "../../macros/style/fields";
import {
	TerminalNode, TerminalEvent, TerminalStyle,
	createTerminalNode, createTerminalTextNode, makeStyle,
} from "./types";
import { cells } from "./paint";
import { parseColor } from "../../components/svg/color";

function ansiNameFor(css: string): string {
	if (css === "") { return ""; }
	const parsed = parseColor(css);
	if (!parsed.ok) { throw new Error(`terminal host: "${css}" is not a CSS colour`); }
	const c = parsed.value;
	if (c.a === 0.0) { return ""; }

	const names = ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"];
	const reds = [0, 205, 0, 205, 0, 205, 0, 229];
	const greens = [0, 0, 205, 205, 0, 0, 205, 229];
	const blues = [0, 0, 0, 0, 238, 205, 205, 229];
	let best = 0;
	let bestDist = -1;
	for (let i = 0; i < names.length; i += 1) {
		const dr = c.r - reds[i];
		const dg = c.g - greens[i];
		const db = c.b - blues[i];
		const dist = dr * dr + dg * dg + db * db;
		if (bestDist < 0 || dist < bestDist) { bestDist = dist; best = i; }
	}
	return names[best];
}

// docs/STYLE.md §5 — the terminal's projection of the portable Style IR.
// A terminal has no flexbox, so the layout half is dropped on purpose; only
// display: "none" is kept, because React Native lays out and paints neither
// that view nor its descendants.
terminalStyleCoverage(0);

export function asTerminalStyle(this s: Style): TerminalStyle {
	const color = s.color;
	const bg = s.backgroundColor;
	return {
		color: color !== null ? ansiNameFor(color as string) : "",
		bg: bg !== null ? ansiNameFor(bg as string) : "",
		bold: isBoldWeight(s.fontWeight),
		dim: s.opacity !== null && (s.opacity as number) < 1.0,
		italic: s.fontStyle !== null && (s.fontStyle as string) === "italic",
		underline: s.textDecorationLine !== null && (s.textDecorationLine as string) === "underline",
		hidden: s.display !== null && (s.display as string) === "none",
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

// The universal vocabulary (view/text/textinput/pressable) lands on the
// terminal's box — a container in every case, text arrives as text-node
// children. Native terminal tags (box/row/hr) pass unchanged.
function termTag(tag: string): string {
	if (tag === "view" || tag === "holder" || tag === "text" || tag === "textinput" || tag === "pressable") { return "box"; }
	return tag;
}

export function terminalHost(): Host {
	return {
		createElement: (tag: string): HostNode => {
			return createTerminalNode(termTag(tag)) as unknown as HostNode;
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
		removeAttr: (node: HostNode, name: string): void => {
			const n = node as unknown as TerminalNode;
			if (!n.attrs.has(name)) { return; }
			n.attrs.delete(name);
			const base = makeStyle();
			match (name) {
				"color" => { n.style.color = base.color; },
				"bg" => { n.style.bg = base.bg; },
				"bold" => { n.style.bold = base.bold; },
				"dim" => { n.style.dim = base.dim; },
				"italic" => { n.style.italic = base.italic; },
				"underline" => { n.style.underline = base.underline; },
				_ => {},
			};
			n.dirty = true;
		},
		setStyle: (node: HostNode, style: Style): void => {
			const n = node as unknown as TerminalNode;
			n.style = asTerminalStyle(style);
			n.dirty = true;
		},
		setStyleProp: null,
		setStyleClass: null,
		addEvent: (node: HostNode, name: string, handler: (e: NeonEvent) => void): void => {
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
			let target: number = p.children.length;
			if (ref !== null) {
				target = childIndex(p, ref as unknown as TerminalNode);
				if (target < 0) { throw "insertBefore: the reference node is not a child of the parent"; }
			}
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
			if (idx < 0) { throw "removeChild: the node is not a child of the parent"; }
			p.children.splice(idx, 1);
			n.parent = null;
		},
		parentOf: (node: HostNode): HostNode | null => {
			const p = (node as unknown as TerminalNode).parent;
			if (p === null) { return null; }
			return p as unknown as HostNode;
		},
		release: (node: HostNode): void => {
			if ((node as unknown as TerminalNode).parent !== null) { throw "release: the node still has a parent; remove it first"; }
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
		voidArea: null,
		scrollTo: null,
		measureText: (text: string, style: Style): TextMeasure => ({ width: cells(text), height: 1, ascender: 1, descender: 0 }),
	};
}

export function fireTerminalEvent(node: TerminalNode, name: string): void {
	const ev = neonEvent(eventType(name));
	for (const e of node.events) {
		if (e.name === name) { e.handler(ev); }
	}
}
