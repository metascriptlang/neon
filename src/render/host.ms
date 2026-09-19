// Host abstraction — the renderer is platform-neutral; each platform supplies a
// Host adapter (DOM, native widgets, terminal, ...). A NeonNode performs the host
// ops itself, so rendering one is calling it.

import { VAttr, VEvent, attr } from "./node";
import { Style, StyleValue, emptyStyle, setStyleField } from "./style";
import { Host, HostNode, NeonNode } from "./hostTypes";
import { NeonEvent, neonEvent, eventType } from "./event";

export { Host, HostNode, NeonNode } from "./hostTypes";
export { bindText, writeAttr, bindAttr, bindStyleProp, applyStaticStyle, bindStyleAll, applyRef } from "./bind";

export function render(node: NeonNode, host: Host, parent: HostNode): void {
	node(host, parent, null);
}

// ---- Mock host: in-memory tree for tests/SSR (no browser needed) ----

export interface MockNode {
	tag: string;
	text: string;
	children: MockNode[];
	attrs: VAttr[];
	events: VEvent[];
	style: Style | null;
	className: string;
	parent: MockNode | null;
}

export function mockNode(tag: string): MockNode {
	return { tag, text: "", children: [], attrs: [], events: [], style: null, className: "", parent: null };
}

function childIndex(parent: MockNode, node: MockNode): number {
	for (let i = 0; i < parent.children.length; i += 1) {
		if (parent.children[i] === node) { return i; }
	}
	return -1;
}

// Mirror DOM move semantics: inserting a node already in the tree first detaches it.
function detach(n: MockNode): void {
	const p = n.parent;
	if (p === null) { return; }
	const idx = childIndex(p, n);
	if (idx >= 0) { p.children.splice(idx, 1); }
	n.parent = null;
}

// Template instantiation copies structure + attrs + style, never event
// listeners — DOM cloneNode(true) has the same rule, and the mock is the
// differential oracle for it.
function cloneMock(n: MockNode): MockNode {
	const c = mockNode(n.tag);
	c.text = n.text;
	c.style = n.style;
	for (const a of n.attrs) { c.attrs.push(attr(a.name, a.value)); }
	for (const k of n.children) {
		const kc = cloneMock(k);
		kc.parent = c;
		c.children.push(kc);
	}
	return c;
}

export function mockHost(): Host {
	return {
		createElement: (tag: string): HostNode => mockNode(tag) as unknown as HostNode,
		createText: (s: string): HostNode => {
			const n = mockNode("");
			n.text = s;
			return n as unknown as HostNode;
		},
		setText: (node: HostNode, s: string): void => {
			(node as unknown as MockNode).text = s;
		},
		setAttr: (node: HostNode, name: string, value: string): void => {
			const n = node as unknown as MockNode;
			for (let i = 0; i < n.attrs.length; i += 1) {
				if (n.attrs[i].name === name) { n.attrs[i].value = value; return; }
			}
			n.attrs.push(attr(name, value));
		},
		removeAttr: (node: HostNode, name: string): void => {
			const n = node as unknown as MockNode;
			for (let i = 0; i < n.attrs.length; i += 1) {
				if (n.attrs[i].name === name) { n.attrs.splice(i, 1); return; }
			}
		},
		setStyle: (node: HostNode, style: Style): void => {
			(node as unknown as MockNode).style = style;
		},
		setStyleProp: (node: HostNode, name: string, value: StyleValue): void => {
			const n = node as unknown as MockNode;
			if (n.style === null) { n.style = emptyStyle(); }
			setStyleField(n.style as Style, name, value);
		},
		// The default mock stands in for a native host: no stylesheet, so a
		// sheet entry lands through setStyle exactly as it does on void or
		// terminal. A test that wants the browser's routing supplies its own.
		setStyleClass: null,
		addEvent: (node: HostNode, name: string, handler: (e: NeonEvent) => void): void => {
			(node as unknown as MockNode).events.push({ name, handler });
		},
		append: (parent: HostNode, child: HostNode): void => {
			const p = parent as unknown as MockNode;
			const c = child as unknown as MockNode;
			detach(c);
			c.parent = p;
			p.children.push(c);
		},
		insertBefore: (parent: HostNode, node: HostNode, ref: HostNode | null): void => {
			const p = parent as unknown as MockNode;
			const n = node as unknown as MockNode;
			let target: number = p.children.length;
			if (ref !== null) {
				target = childIndex(p, ref as unknown as MockNode);
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
			p.children.splice(target, 0, n);
		},
		removeChild: (parent: HostNode, node: HostNode): void => {
			const p = parent as unknown as MockNode;
			const n = node as unknown as MockNode;
			const idx = childIndex(p, n);
			if (idx < 0) { throw "removeChild: the node is not a child of the parent"; }
			p.children.splice(idx, 1);
			n.parent = null;
		},
		nextSibling: (node: HostNode): HostNode | null => {
			const n = node as unknown as MockNode;
			const p = n.parent;
			if (p === null) { return null; }
			const idx = childIndex(p, n);
			if (idx < 0 || idx + 1 >= p.children.length) { return null; }
			return p.children[idx + 1] as unknown as HostNode;
		},
		firstChild: (node: HostNode): HostNode | null => {
			const n = node as unknown as MockNode;
			if (n.children.length === 0) { return null; }
			return n.children[0] as unknown as HostNode;
		},
		cloneNode: (node: HostNode): HostNode => {
			return cloneMock(node as unknown as MockNode) as unknown as HostNode;
		},
	};
}

// Fire a recorded event by name (test helper — simulates a user interaction).
export function fireEvent(node: MockNode, name: string): void {
	fireEventWith(node, name, neonEvent(eventType(name)));
}

// The same dispatch, but the test supplies the event — how a handler reading
// `e.value` or `e.x` is pinned without a real browser.
export function fireEventWith(node: MockNode, name: string, e: NeonEvent): void {
	for (const h of node.events) {
		if (h.name === name) { h.handler(e); }
	}
}

export function mockToString(n: MockNode): string {
	if (n.tag === "") { return n.text; }
	let open = "<" + n.tag;
	for (const a of n.attrs) { open = open + " " + a.name + "=\"" + (a.value ?? "") + "\""; }
	let s = open + ">";
	for (const k of n.children) { s = s + mockToString(k); }
	return s + "</" + n.tag + ">";
}
