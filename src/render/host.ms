// Host abstraction — the renderer is platform-neutral; each platform supplies a
// Host adapter (DOM, native widgets, terminal, ...). renderToHost walks a NeonNode
// tree once, creating host nodes, binding reactive text, applying attrs/events.

import { createEffect } from "../core/effect";
import { NeonNode, VAttr, VEvent, RegionFn, ComponentProducer } from "./node";
import { Style } from "./style";
import { reconcileArrays } from "./reconcile";
import { Host, HostNode } from "./hostTypes";

export { Host, HostNode } from "./hostTypes";

// Build a single host node from a vnode (recursing into children). dynText binds a
// push-effect; a region child mounts an anchor + reconcile effect into this node.
export function renderNode(vnode: NeonNode, host: Host): HostNode {
	const comp = vnode.componentFn;
	if (comp !== null) {
		const producer = comp as ComponentProducer;
		return renderNode(producer(), host);
	}
	if (vnode.region !== null) {
		throw "renderNode cannot mount a region (For/Show/Index) without a parent anchor — mount via renderToHost, or wrap the region in an element";
	}
	if (vnode.tag === "") {
		if (vnode.isDyn) {
			const tn = host.createText("");
			createEffect(() => { host.setText(tn, vnode.dyn()); });
			return tn;
		}
		return host.createText(vnode.text);
	}
	const node = host.createElement(vnode.tag);
	for (const a of vnode.attrs) { host.setAttr(node, a.name, a.value); }
	const vstyle = vnode.style;
	if (vstyle !== null) { host.setStyle(node, vstyle as Style); }
	for (const e of vnode.events) { host.addEvent(node, e.name, e.handler); }
	for (const k of vnode.children) {
		let kv = k;
		while (kv.componentFn !== null) {
			const producer = kv.componentFn as ComponentProducer;
			kv = producer();
		}
		if (kv.region !== null) { mountRegion(kv, host, node); }
		else { host.append(node, renderNode(kv, host)); }
	}
	return node;
}

// A region owns the span before its end anchor. The effect re-runs when the region's
// list source changes, reconciling host nodes between the start of the span and anchor.
function mountRegion(vnode: NeonNode, host: Host, parent: HostNode): void {
	const anchor = host.createText("");
	host.append(parent, anchor);
	let current: HostNode[] = [];
	const fn = vnode.region as RegionFn;
	const memo = fn(host);
	createEffect(() => {
		const next = memo() as HostNode[];
		reconcileArrays(host, parent, current, next, anchor);
		current = next;
	});
}

export function renderToHost(vnode: NeonNode, host: Host, parent: HostNode): void {
	const comp = vnode.componentFn;
	if (comp !== null) {
		const producer = comp as ComponentProducer;
		renderToHost(producer(), host, parent);
		return;
	}
	const reg = vnode.region;
	if (reg !== null) { mountRegion(vnode, host, parent); return; }
	host.append(parent, renderNode(vnode, host));
}

// ---- Mock host: in-memory tree for tests/SSR (no browser needed) ----

export interface MockNode {
	tag: string;
	text: string;
	children: MockNode[];
	attrs: VAttr[];
	events: VEvent[];
	style: Style | null;
	parent: MockNode | null;
}

export function mockNode(tag: string): MockNode {
	return { tag, text: "", children: [], attrs: [], events: [], style: null, parent: null };
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
		setStyle: (node: HostNode, style: Style): void => {
			(node as unknown as MockNode).style = style;
		},
		addEvent: (node: HostNode, name: string, handler: () => void): void => {
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
			let target = ref === null ? p.children.length : childIndex(p, ref as unknown as MockNode);
			if (target < 0) { target = p.children.length; }
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
			if (idx >= 0) { p.children.splice(idx, 1); }
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
