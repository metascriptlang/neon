// Reactive view-node tree — backend-agnostic description of UI.
// A node is either an element (tag + attrs + events + children) or a text node
// (static `text` or reactive `dyn` thunk). Renderers consume this: renderToString
// pulls a snapshot; renderToHost (host.ms) pushes live updates into a host node.

import { Style } from "./style";

export interface VAttr {
	name: string;
	value: string;         // static value ("" when dynamic)
	isDyn: boolean;        // true → `dyn` is the live value source
	dyn: () => string;
}

export interface VEvent {
	name: string;          // raw JSX name, e.g. "onClick" (host maps to "click")
	handler: () => void;
}

// A region produces a reactive list of host nodes (For/Show/Index). Typed loosely
// (unknown) so this layer stays below the host: host.ms supplies the real Host and the
// returned thunk yields host nodes that renderToHost reconciles into the DOM.
export type RegionFn = (host: unknown) => () => unknown[];

// A Component (function component) is a function from props to a NeonNode. Props values
// are callables (signals/memos) or plain values — see Reactive<T> + read() in component.ms.
// The producer form (() => NeonNode) is the deferred expansion of an already-bound call:
// createComponent wraps Comp(props) in untrack and returns a NeonNode whose componentFn field
// holds the deferred call. Renderer expands it lazily at mount.
export type ComponentFn<P = unknown> = (props: P) => NeonNode;
export type ComponentProducer = () => NeonNode;

export interface NeonNode {
	tag: string;           // "" marks a text node
	children: NeonNode[];
	text: string;          // static text
	isDyn: boolean;        // true → `dyn` is the live text source
	dyn: () => string;
	attrs: VAttr[];
	events: VEvent[];
	style: Style | null;                // typed style channel (docs/STYLE.md); host projects it
	region: RegionFn | null;            // non-null → reactive list region (host reconciles it)
	componentFn: ComponentProducer | null; // non-null → Component variant (renderer expands lazily)
	componentProps: Map<string, unknown> | null; // attached for debug/introspection
}

export function attr(name: string, value: string): VAttr {
	return { name, value, isDyn: false, dyn: () => "" };
}

export function dynAttr(name: string, thunk: () => string): VAttr {
	return { name, value: "", isDyn: true, dyn: thunk };
}

export function evt(name: string, handler: () => void): VEvent {
	return { name, handler };
}

export function el(tag: string, attrs: VAttr[], events: VEvent[], children: NeonNode[]): NeonNode {
	return { tag, children, text: "", isDyn: false, dyn: () => "", attrs, events, style: null, region: null, componentFn: null, componentProps: null };
}

export function withStyle(n: NeonNode, s: Style): NeonNode {
	n.style = s;
	return n;
}

export function text(s: string): NeonNode {
	return { tag: "", children: [], text: s, isDyn: false, dyn: () => "", attrs: [], events: [], style: null, region: null, componentFn: null, componentProps: null };
}

export function dynText(thunk: () => string): NeonNode {
	return { tag: "", children: [], text: "", isDyn: true, dyn: thunk, attrs: [], events: [], style: null, region: null, componentFn: null, componentProps: null };
}

export function regionNode(fn: RegionFn): NeonNode {
	return { tag: "", children: [], text: "", isDyn: false, dyn: () => "", attrs: [], events: [], style: null, region: fn, componentFn: null, componentProps: null };
}

export function componentNode(fn: ComponentProducer, props: Map<string, unknown>): NeonNode {
	return { tag: "", children: [], text: "", isDyn: false, dyn: () => "", attrs: [], events: [], style: null, region: null, componentFn: fn, componentProps: props };
}

export function renderToString(n: NeonNode): string {
	const comp = n.componentFn;
	if (comp !== null) {
		const producer = comp as ComponentProducer;
		return renderToString(producer());
	}
	const reg = n.region;
	if (reg !== null) {
		throw "renderToString does not render reactive regions (For/Show/Index) — render via renderToHost with a host adapter";
	}
	if (n.tag === "") { return n.isDyn ? n.dyn() : n.text; }
	let open = "<" + n.tag;
	for (const a of n.attrs) { open = open + " " + a.name + "=\"" + (a.isDyn ? a.dyn() : a.value) + "\""; }
	let s = open + ">";
	for (const k of n.children) { s = s + renderToString(k); }
	return s + "</" + n.tag + ">";
}
