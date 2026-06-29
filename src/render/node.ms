// Reactive view-node tree — backend-agnostic description of UI.
// A node is either an element (tag + attrs + events + children) or a text node
// (static `text` or reactive `dyn` thunk). Renderers consume this: renderToString
// pulls a snapshot; renderToHost (host.ms) pushes live updates into a host node.

export interface VAttr {
	name: string;
	value: string;
}

export interface VEvent {
	name: string;          // raw JSX name, e.g. "onClick" (host maps to "click")
	handler: () => void;
}

export interface VNode {
	tag: string;           // "" marks a text node
	children: VNode[];
	text: string;          // static text
	isDyn: boolean;        // true → `dyn` is the live text source
	dyn: () => string;
	attrs: VAttr[];
	events: VEvent[];
}

export function attr(name: string, value: string): VAttr {
	return { name, value };
}

export function evt(name: string, handler: () => void): VEvent {
	return { name, handler };
}

export function el(tag: string, attrs: VAttr[], events: VEvent[], children: VNode[]): VNode {
	return { tag, children, text: "", isDyn: false, dyn: () => "", attrs, events };
}

export function text(s: string): VNode {
	return { tag: "", children: [], text: s, isDyn: false, dyn: () => "", attrs: [], events: [] };
}

export function dynText(thunk: () => string): VNode {
	return { tag: "", children: [], text: "", isDyn: true, dyn: thunk, attrs: [], events: [] };
}

export function renderToString(n: VNode): string {
	if (n.tag === "") { return n.isDyn ? n.dyn() : n.text; }
	let open = "<" + n.tag;
	for (const a of n.attrs) { open = open + " " + a.name + "=\"" + a.value + "\""; }
	let s = open + ">";
	for (const k of n.children) { s = s + renderToString(k); }
	return s + "</" + n.tag + ">";
}
