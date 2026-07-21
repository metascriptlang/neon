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
import {
	TerminalNode, TerminalEvent,
	createTerminalNode, createTerminalTextNode,
} from "./types";

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
	};
}

export function fireTerminalEvent(node: TerminalNode, name: string): void {
	for (const e of node.events) {
		if (e.name === name) { e.handler(); }
	}
}
