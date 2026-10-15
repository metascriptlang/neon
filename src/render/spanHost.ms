// RN Fabric's paragraph: a Text inside a Text, and every string in one, has no host node of its own;
// ParagraphShadowNode flattens them into one AttributedString. Here a Text's children render into
// SPAN_HOST, whose nodes are plain records, and a host with setSpans gets the flattened spans of each
// outermost Text once per update.

import { Host, HostNode, NeonNode, TextSpan } from "./hostTypes";
import { Style, mergeStyle, emptyStyle } from "./style";
import { NeonEvent } from "./event";
import { Accessor, createSignal, untrack } from "../core/signal";
import { createEffect, createBindingEffect } from "../core/effect";

class Paragraph {
	version: number = 0;
	delivered: number = -1;
	changed: (v: number) => void;
	// A paragraph of one string has nothing to coalesce, so its change goes straight to the host.
	single: SpanNode | null = null;
	deliver: (text: string) => void;

	constructor(changed: (v: number) => void, deliver: (text: string) => void) {
		this.changed = changed;
		this.deliver = deliver;
	}
}

class SpanNode {
	isString: boolean;
	text: string = "";
	style: Style | null = null;
	children: SpanNode[] = [];
	parent: SpanNode | null = null;
	paragraph: Paragraph | null = null;
	press: ((e: NeonEvent) => void) | null = null;

	constructor(isString: boolean) {
		this.isString = isString;
	}
}

function spanOf(node: HostNode): SpanNode {
	return node as SpanNode;
}

function touched(n: SpanNode): void {
	let cur: SpanNode | null = n;
	while (cur !== null) {
		const p = (cur as SpanNode).paragraph;
		if (p !== null) {
			const para = p as Paragraph;
			para.version += 1;
			if (para.single === n) {
				para.delivered = para.version;
				para.deliver(n.text);
				return;
			}
			para.single = null;
			para.changed(para.version);
			return;
		}
		cur = (cur as SpanNode).parent;
	}
}

function detach(n: SpanNode): void {
	const p = n.parent;
	if (p === null) { return; }
	const sibs = (p as SpanNode).children;
	const at = sibs.indexOf(n);
	if (at >= 0) { sibs.splice(at, 1); }
	n.parent = null;
	touched(p as SpanNode);
}

const SPAN_ATTRS = ["class", "accessible", "accessibilityLabel", "accessibilityHint", "accessibilityRole"];

export const SPAN_HOST: Host = {
	createElement: (tag: string): HostNode => {
		if (tag !== "text") {
			throw new Error(`a <${tag}> inside a Text is an inline view, which a paragraph does not place yet; put it beside the Text`);
		}
		return new SpanNode(false);
	},
	createText: (s: string): HostNode => {
		const n = new SpanNode(true);
		n.text = s;
		return n;
	},
	setText: (node: HostNode, s: string): void => {
		const n = spanOf(node);
		if (n.text === s) { return; }
		n.text = s;
		touched(n);
	},
	setAttr: (node: HostNode, name: string, value: string): void => {
		if (SPAN_ATTRS.indexOf(name) < 0) { throw new Error(`${name} belongs on the outermost Text, not on a Text inside one`); }
	},
	removeAttr: (node: HostNode, name: string): void => {},
	setStyle: (node: HostNode, style: Style): void => {
		const n = spanOf(node);
		n.style = style;
		touched(n);
	},
	setStyleProp: null,
	setStyleClass: null,
	addEvent: (node: HostNode, name: string, handler: (e: NeonEvent) => void): void => {
		if (name !== "onPress") { throw new Error(`${name} on a Text inside a Text: a span takes onPress only`); }
		spanOf(node).press = handler;
	},
	append: (parent: HostNode, child: HostNode): void => {
		const p = spanOf(parent);
		const c = spanOf(child);
		detach(c);
		c.parent = p;
		p.children.push(c);
		touched(p);
	},
	insertBefore: (parent: HostNode, node: HostNode, before: HostNode | null): void => {
		const p = spanOf(parent);
		const n = spanOf(node);
		detach(n);
		const at = before === null ? p.children.length : p.children.indexOf(spanOf(before as HostNode));
		if (at < 0) { throw new Error("insertBefore: the reference span is not a child of the parent"); }
		p.children.splice(at, 0, n);
		n.parent = p;
		touched(p);
	},
	removeChild: (parent: HostNode, node: HostNode): void => {
		const n = spanOf(node);
		if (n.parent !== spanOf(parent)) { throw new Error("removeChild: the span is not a child of the parent"); }
		detach(n);
	},
	nextSibling: (node: HostNode): HostNode | null => {
		const n = spanOf(node);
		const p = n.parent;
		if (p === null) { return null; }
		const sibs = (p as SpanNode).children;
		const at = sibs.indexOf(n);
		return at >= 0 && at + 1 < sibs.length ? sibs[at + 1] : null;
	},
	firstChild: (node: HostNode): HostNode | null => {
		const n = spanOf(node);
		return n.children.length > 0 ? n.children[0] : null;
	},
	cloneNode: null,
	voidArea: null,
	scrollTo: null,
};

// The spans in order, each with the styles of the Texts around it merged; a run with no own style keeps null.
function flatten(n: SpanNode, style: Style | null, press: ((e: NeonEvent) => void) | null, out: TextSpan[]): void {
	for (const c of n.children) {
		if (c.isString) {
			if (c.text !== "") { out.push({ text: c.text, style, onPress: press }); }
		} else {
			const own = c.style;
			const merged: Style | null = own === null ? style : style === null ? own : mergeStyle(style as Style, own as Style);
			flatten(c, merged, c.press !== null ? c.press : press, out);
		}
	}
}

// A host with setSpans gets the spans whole; any other lays them out as nested Texts, kept by position.
function spanNodes(read: Accessor<TextSpan[]>): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		const shown: HostNode[] = [];
		const words: HostNode[] = [];
		const styles: (Style | null)[] = [];
		createBindingEffect((): void => {
			const spans = read();
			for (let i = 0; i < spans.length; i += 1) {
				const s = spans[i];
				if (i >= shown.length) {
					const el = host.createElement("text");
					const word = host.createText(s.text);
					host.append(el, word);
					host.insertBefore(parent, el, before);
					shown.push(el);
					words.push(word);
					styles.push(null);
				} else {
					host.setText(words[i], s.text);
				}
				const own: Style | null = s.style !== null ? s.style as Style : null;
				if (own !== styles[i]) {
					host.setStyle(shown[i], own !== null ? own as Style : emptyStyle());
					styles[i] = own;
				}
			}
			while (shown.length > spans.length) {
				host.removeChild(parent, shown.pop() as HostNode);
				words.pop();
				styles.pop();
			}
		});
	};
}

// What a Text puts inside itself. Inside another Text it renders into the same records; an outermost
// Text on a host with setSpans flattens its records after every render effect of an update has run.
export function paragraphChildren(kids: NeonNode | null, spans: Accessor<TextSpan[]> | null): NeonNode {
	return (host: Host, node: HostNode, before: HostNode | null): void => {
		if (host === SPAN_HOST) {
			if (spans !== null) { throw new Error("spans belong on the outermost Text"); }
			if (kids !== null) { (kids as NeonNode)(host, node, before); }
			return;
		}
		const set = host.setSpans;
		if (set === null) {
			if (spans !== null) { spanNodes(spans as Accessor<TextSpan[]>)(host, node, before); }
			else if (kids !== null) { (kids as NeonNode)(host, node, before); }
			return;
		}
		const deliver = set as (node: HostNode, spans: TextSpan[]) => void;
		if (spans !== null) {
			const read = spans as Accessor<TextSpan[]>;
			createBindingEffect((): void => { deliver(node, read()); });
			return;
		}
		const root = new SpanNode(false);
		const [changed, setChanged] = createSignal<number>(0);
		const para = new Paragraph((v: number): void => { setChanged(v); }, (text: string): void => {
			const one: TextSpan[] = [{ text }];
			deliver(node, one);
		});
		root.paragraph = para;
		if (kids !== null) { (kids as NeonNode)(SPAN_HOST, root, null); }
		const flush = (): void => {
			const out: TextSpan[] = [];
			flatten(root, null, null, out);
			para.delivered = para.version;
			para.single = root.children.length === 1 && root.children[0].isString ? root.children[0] : null;
			deliver(node, out);
		};
		flush();
		createEffect((): void => {
			changed();
			if (para.version !== para.delivered) { untrack(flush); }
		});
	};
}

// A label a framework site builds by hand: its one string goes through setSpans where the host takes them.
export function setTextContent(host: Host, label: HostNode, s: string): void {
	const set = host.setSpans;
	if (set !== null) {
		const one: TextSpan[] = [{ text: s }];
		(set as (node: HostNode, spans: TextSpan[]) => void)(label, one);
		return;
	}
	host.append(label, host.createText(s));
}
