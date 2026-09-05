// Reactive view-node tree — backend-agnostic description of UI.
// A node is either an element (tag + attrs + events + children) or a text node
// (static `text` or reactive `dyn` thunk). Renderers consume this: renderToString
// pulls a snapshot; renderToHost (host.ms) pushes live updates into a host node.

import { Style, StyleValue, emptyStyle, mergeStyle, setStyleField } from "./style";
import { styleToCss } from "./css";
import { registerCss } from "./sheet";
import { NeonEvent } from "./event";

// One reactive style field: `width: w()` becomes { name: "width", get: () => w() }.
// The host layer binds each entry to one effect writing exactly that property.
export interface VDynStyle {
	name: string;
	get: () => StyleValue;
}

export interface VAttr {
	name: string;
	value: string;         // static value ("" when dynamic)
	isDyn: boolean;        // true → `dyn` is the live value source
	dyn: () => string;
}

export interface VEvent {
	name: string;          // raw JSX name, e.g. "onPress" (host maps to "click")
	handler: (e: NeonEvent) => void;
}

// A region produces a reactive list of host nodes (For/Show/Index). Typed loosely
// (unknown) so this layer stays below the host: host.ms supplies the real Host and the
// returned thunk yields host nodes that renderToHost reconciles into the DOM.
export type RegionFn = (host: unknown) => () => unknown[];

// The host node is `unknown` here for the same reason a region's is: this layer
// stays below the host. A caller casts to whatever its host really builds.
export type RefFn = (node: unknown) => void;

// A Component (function component) is a function from props to a NeonNode. Props values
// are callables (signals/memos) or plain values — see Reactive<T> + read() in component.ms.
// The producer form (() => NeonNode) is the deferred expansion of an already-bound call:
// createComponent wraps Comp(props) in untrack and returns a NeonNode whose componentFn field
// holds the deferred call. Renderer expands it lazily at mount.
export type ComponentFn<P = unknown> = (props: P) => NeonNode;
export type ComponentProducer = () => NeonNode;

// A scoped node wraps the MOUNT of children[0] in an owner scope (Solid's
// Provider is exactly this: a transparent component that sets context around
// children resolution). Neon creates host nodes at mount, so the scope must
// travel with the node and wrap mounting, not description building.
export type ScopeFn = (body: () => unknown) => unknown;

export interface NeonNode {
	tag: string;           // "" marks a text node
	children: NeonNode[];
	text: string;          // static text
	isDyn: boolean;        // true → `dyn` is the live text source
	dyn: () => string;
	attrs: VAttr[];
	events: VEvent[];
	style: Style | null;                // typed style channel (docs/STYLE.md); host projects it
	dynStyle: VDynStyle[] | null;       // reactive style fields — one per-property effect each (§6)
	dynStyleAll: (() => Style) | null;  // reactive whole-style thunk — one effect re-applying setStyle
	region: RegionFn | null;            // non-null → reactive list region (host reconciles it)
	componentFn: ComponentProducer | null; // non-null → Component variant (renderer expands lazily)
	componentProps: Map<string, unknown> | null; // attached for debug/introspection
	ref: RefFn | null;                  // called once at mount with the host node
	scope: ScopeFn | null;              // non-null → mount children[0] inside this scope
}

export function attr(name: string, value: string): VAttr {
	return { name, value, isDyn: false, dyn: () => "" };
}

export function dynAttr(name: string, thunk: () => string): VAttr {
	return { name, value: "", isDyn: true, dyn: thunk };
}

export function evt(name: string, handler: (e: NeonEvent) => void): VEvent {
	return { name, handler };
}

export function el(tag: string, attrs: VAttr[], events: VEvent[], children: NeonNode[]): NeonNode {
	return { tag, children, text: "", isDyn: false, dyn: () => "", attrs, events, style: null, dynStyle: null, dynStyleAll: null, region: null, componentFn: null, componentProps: null, ref: null, scope: null };
}

export function withStyle(n: NeonNode, s: Style): NeonNode {
	n.style = s;
	return n;
}

export function withDynStyle(n: NeonNode, name: string, get: () => StyleValue): NeonNode {
	if (n.dynStyle === null) { n.dynStyle = []; }
	(n.dynStyle as VDynStyle[]).push({ name, get });
	return n;
}

export function withDynStyleAll(n: NeonNode, get: () => Style): NeonNode {
	n.dynStyleAll = get;
	return n;
}

export function withRef(n: NeonNode, f: RefFn): NeonNode {
	n.ref = f;
	return n;
}

export function text(s: string): NeonNode {
	return { tag: "", children: [], text: s, isDyn: false, dyn: () => "", attrs: [], events: [], style: null, dynStyle: null, dynStyleAll: null, region: null, componentFn: null, componentProps: null, ref: null, scope: null };
}

export function dynText(thunk: () => string): NeonNode {
	return { tag: "", children: [], text: "", isDyn: true, dyn: thunk, attrs: [], events: [], style: null, dynStyle: null, dynStyleAll: null, region: null, componentFn: null, componentProps: null, ref: null, scope: null };
}

// A static {expr} child, routed by type: a string becomes a text node, a NeonNode
// (a nested view, props.children) passes through unchanged. The macro picks this for
// a child that isReactiveExpr rejects, so the branch is chosen by the value's type
// rather than hard-lowered to text() — which is what let a node child reach text()
// and fail. Overloaded on the argument value (string vs NeonNode), the form proven
// to resolve on both backends; no thunk overload (return-type discrimination).
export function insChild(s: string): NeonNode {
	return text(s);
}

export function insChild(n: NeonNode): NeonNode {
	return n;
}

export function regionNode(fn: RegionFn): NeonNode {
	return { tag: "", children: [], text: "", isDyn: false, dyn: () => "", attrs: [], events: [], style: null, dynStyle: null, dynStyleAll: null, region: fn, componentFn: null, componentProps: null, ref: null, scope: null };
}

export function scopedNode(scope: ScopeFn, child: NeonNode): NeonNode {
	return { tag: "", children: [child], text: "", isDyn: false, dyn: () => "", attrs: [], events: [], style: null, dynStyle: null, dynStyleAll: null, region: null, componentFn: null, componentProps: null, ref: null, scope };
}

export function componentNode(fn: ComponentProducer, props: Map<string, unknown>): NeonNode {
	return { tag: "", children: [], text: "", isDyn: false, dyn: () => "", attrs: [], events: [], style: null, dynStyle: null, dynStyleAll: null, region: null, componentFn: fn, componentProps: props, ref: null, scope: null };
}

// Universal wire tags → html. One table shared by SSR (renderToString) and the
// browser host's createElement — the user-facing names (View/Text/…) are the
// starter components in src/starter/rn.ms; hosts receive the lowercase wire
// tag and translate (browser: this table; terminal: its boxes; void ignores).
export function htmlTagFor(tag: string): string {
	if (tag === "view") { return "div"; }
	if (tag === "text") { return "span"; }
	if (tag === "textinput") { return "input"; }
	if (tag === "pressable") { return "button"; }
	return tag;
}

export function renderToString(n: NeonNode): string {
	const comp = n.componentFn;
	if (comp !== null) {
		const producer = comp as ComponentProducer;
		return renderToString(producer());
	}
	const sc = n.scope;
	if (sc !== null) {
		let out = "";
		(sc as ScopeFn)(() => { out = renderToString(n.children[0]); return null; });
		return out;
	}
	const reg = n.region;
	if (reg !== null) {
		throw "renderToString does not render reactive regions (For/Show/Index) — render via renderToHost with a host adapter";
	}
	if (n.tag === "") { return n.isDyn ? n.dyn() : n.text; }
	let open = "<" + htmlTagFor(n.tag);
	let cls = "";
	let inline = "";
	// The three style channels resolve exactly as renderNode (host.ms) resolves
	// them, so the markup a server sends matches what the browser would build:
	// a whole-style thunk wins, then per-property thunks over the static base,
	// and only a purely static style can travel as a class.
	const dynAll = n.dynStyleAll;
	const dyns = n.dynStyle;
	const base = n.style;
	if (dynAll !== null) {
		inline = styleToCss((dynAll as () => Style)());
	} else if (dyns !== null) {
		const own = base !== null ? mergeStyle(base as Style, emptyStyle()) : emptyStyle();
		for (const p of (dyns as VDynStyle[])) { setStyleField(own, p.name, p.get()); }
		inline = styleToCss(own);
	} else if (base !== null) {
		const st = base as Style;
		const id = st.cssId;
		if (id !== null) {
			registerCss(id as string, st.css === null ? "" : st.css as string);
			cls = id as string;
		} else {
			inline = styleToCss(st);
		}
	}
	for (const a of n.attrs) {
		let v = a.isDyn ? a.dyn() : a.value;
		if (a.name === "class" && cls !== "") { v = v === "" ? cls : v + " " + cls; cls = ""; }
		open = open + " " + a.name + "=\"" + v + "\"";
	}
	if (cls !== "") { open = open + " class=\"" + cls + "\""; }
	if (inline !== "") { open = open + " style=\"" + inline + "\""; }
	let s = open + ">";
	for (const k of n.children) { s = s + renderToString(k); }
	return s + "</" + htmlTagFor(n.tag) + ">";
}
