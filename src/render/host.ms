// Host abstraction — the renderer is platform-neutral; each platform supplies a
// Host adapter (DOM, native widgets, terminal, ...). renderToHost walks a NeonNode
// tree once, creating host nodes, binding reactive text, applying attrs/events.

import { createEffect } from "../core/effect";
import { NeonNode, VAttr, VEvent, RegionFn, ComponentProducer, attr } from "./node";
import { Style, StyleValue, emptyStyle, mergeStyle, setStyleField } from "./style";
import { reconcileArrays } from "./reconcile";
import { Host, HostNode } from "./hostTypes";

export { Host, HostNode } from "./hostTypes";

// A dynamic spot re-runs whenever a source signal changes, but a derived expression
// often maps several source values onto the SAME output ("big"/"small", a formatted
// count). Writing it again is a host touch that changes nothing, so the last written
// value is kept and an identical one is dropped. Both emissions bind through these,
// which is what keeps their host-op sequences identical.
export function bindText(host: Host, node: HostNode, get: () => string): void {
	let prev = "";
	let bound = false;
	createEffect(() => {
		const v = get();
		if (bound && v === prev) { return; }
		bound = true;
		prev = v;
		host.setText(node, v);
	});
}

export function bindAttr(host: Host, node: HostNode, name: string, get: () => string): void {
	let prev = "";
	let bound = false;
	createEffect(() => {
		const v = get();
		if (bound && v === prev) { return; }
		bound = true;
		prev = v;
		host.setAttr(node, name, v);
	});
}

export function bindStyleProp(host: Host, node: HostNode, own: Style, name: string, get: () => StyleValue): void {
	let prev: StyleValue = null;
	let bound = false;
	createEffect(() => {
		const v = get();
		if (bound && v === prev) { return; }
		bound = true;
		prev = v;
		const setProp = host.setStyleProp;
		if (setProp !== null) { setProp(node, name, v); return; }
		setStyleField(own, name, v);
		host.setStyle(node, own);
	});
}

// One effect re-applying the whole style (reactive variant selection, layered
// calls — any style EXPRESSION that reads a signal). Per-property precision is
// impossible here: which fields the result carries is only known per run, and
// a field can fall back to an earlier layer when deselected, so the effect
// hands the fresh merge to setStyle each time.
export function bindStyleAll(host: Host, node: HostNode, get: () => Style): void {
	createEffect(() => {
		host.setStyle(node, get());
	});
}

// Build a single host node from a vnode (recursing into children). dynText binds a
// push-effect; a region child mounts an anchor + reconcile effect into this node.
// What a JSX expression becomes, on every target: the mount closure itself.
// Everything that accepts JSX takes `NeonView` and mounts it through `mountView`,
// so the row path in flow.ms is one line everywhere. Tree emission stays the
// substrate underneath — the direct emitter calls renderNode for components and
// regions, and `viewOf` adapts a description built by hand.
export type NeonView = (host: Host) => HostNode;

export function mountView(view: NeonView, host: Host): HostNode {
	return view(host);
}

// Escape hatch for a description built by hand (`el(...)`, `element(...)`) where
// a view is expected. Bare JSX never needs it — the converter already emits the
// right shape.
export function viewOf(node: NeonNode): NeonView {
	return (host: Host) => renderNode(node, host);
}

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
			bindText(host, tn, () => vnode.dyn());
			return tn;
		}
		return host.createText(vnode.text);
	}
	const node = host.createElement(vnode.tag);
	for (const a of vnode.attrs) {
		if (a.isDyn) {
			const da = a;
			bindAttr(host, node, da.name, () => da.dyn());
		} else {
			host.setAttr(node, a.name, a.value);
		}
	}
	const vstyle = vnode.style;
	const dyns = vnode.dynStyle;
	const dynAll = vnode.dynStyleAll;
	if (dynAll !== null) {
		bindStyleAll(host, node, dynAll as () => Style);
	} else if (dyns !== null) {
		// The static style may be a shared sheet constant (or a template-cloned
		// pointer); per-property writes must land on a private copy, never on it.
		const own = vstyle !== null ? mergeStyle(vstyle as Style, emptyStyle()) : emptyStyle();
		host.setStyle(node, own);
		for (const p of dyns) { bindStyleProp(host, node, own, p.name, p.get); }
	} else if (vstyle !== null) {
		const s = vstyle as Style;
		const setCls = host.setStyleClass;
		const id = s.cssId;
		if (id !== null && setCls !== null) {
			setCls(node, id as string, s.css === null ? "" : s.css as string);
		} else { host.setStyle(node, s); }
	}
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
