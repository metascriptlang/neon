// Host abstraction — the renderer is platform-neutral; each platform supplies a
// Host adapter (DOM, native widgets, terminal, ...). renderToHost walks a VNode
// tree once, creating host nodes, binding reactive text, applying attrs/events.

import { createEffect } from "../core/effect";
import { VNode, VAttr, VEvent } from "./node";

// Opaque per-host node handle. Each adapter casts it to its own node type.
export type HostNode = unknown;

export interface Host {
	createElement: (tag: string) => HostNode;
	createText: (s: string) => HostNode;
	setText: (node: HostNode, s: string) => void;
	setAttr: (node: HostNode, name: string, value: string) => void;
	addEvent: (node: HostNode, name: string, handler: () => void) => void;
	append: (parent: HostNode, child: HostNode) => void;
}

export function renderToHost(vnode: VNode, host: Host, parent: HostNode): void {
	if (vnode.tag === "") {
		if (vnode.isDyn) {
			const tn = host.createText("");
			host.append(parent, tn);
			// Push model: re-runs on signal change, writing straight into the host node.
			createEffect(() => { host.setText(tn, vnode.dyn()); });
		} else {
			const tn = host.createText(vnode.text);
			host.append(parent, tn);
		}
		return;
	}
	const node = host.createElement(vnode.tag);
	for (const a of vnode.attrs) { host.setAttr(node, a.name, a.value); }
	for (const e of vnode.events) { host.addEvent(node, e.name, e.handler); }
	host.append(parent, node);
	for (const k of vnode.children) { renderToHost(k, host, node); }
}

// ---- Mock host: in-memory tree for tests/SSR (no browser needed) ----

export interface MockNode {
	tag: string;
	text: string;
	children: MockNode[];
	attrs: VAttr[];
	events: VEvent[];
}

export function mockNode(tag: string): MockNode {
	return { tag, text: "", children: [], attrs: [], events: [] };
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
			(node as unknown as MockNode).attrs.push({ name, value });
		},
		addEvent: (node: HostNode, name: string, handler: () => void): void => {
			(node as unknown as MockNode).events.push({ name, handler });
		},
		append: (parent: HostNode, child: HostNode): void => {
			(parent as unknown as MockNode).children.push(child as unknown as MockNode);
		},
	};
}

// Fire a recorded event by name (test helper — simulates a user interaction).
export function fireEvent(node: MockNode, name: string): void {
	for (const e of node.events) {
		if (e.name === name) { e.handler(); }
	}
}

export function mockToString(n: MockNode): string {
	if (n.tag === "") { return n.text; }
	let open = "<" + n.tag;
	for (const a of n.attrs) { open = open + " " + a.name + "=\"" + a.value + "\""; }
	let s = open + ">";
	for (const k of n.children) { s = s + mockToString(k); }
	return s + "</" + n.tag + ">";
}
