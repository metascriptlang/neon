// RN Fabric's paragraph: a Text inside a Text, and every string in one, has no host node of its own;
// ParagraphShadowNode flattens them into one AttributedString. Here a Text's children render into
// SPAN_HOST, whose nodes are plain records, and a host whose paragraph is spanParagraph gets the flattened spans of each
// outermost Text once per update.

import { Host, HostNode, NeonNode, TextSpan } from "./hostTypes";
import { VEvent } from "./node";
import { Style, mergeStyle } from "./style";
import { NeonEvent } from "./event";
import { Accessor, createSignal, untrack } from "../core/signal";
import { createRenderEffect } from "../core/effect";
import { Cleanup } from "../core/types";

class Paragraph {
	version: number = 0;
	delivered: number = -1;
	changed: (v: number) => void;
	// A paragraph of one string has nothing to coalesce, so its change goes straight to the host.
	single: SpanNode | null = null;
	deliver: (text: string) => void;
	node: HostNode;

	constructor(node: HostNode, changed: (v: number) => void, deliver: (text: string) => void) {
		this.node = node;
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
	touches: VEvent[] = [];
	touch: ((name: string, e: NeonEvent) => void) | null = null;
	// The tag of an element that is not a Text: a region's detached holder, or an inline view, which is refused
	// when it is placed in a paragraph.
	inline: string | null = null;

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

// A Text inside a Text renders into the same records.
function nestedParagraph(host: Host, node: HostNode, before: HostNode | null, kids: NeonNode | null, spans: Accessor<TextSpan[]> | null): void {
	if (spans !== null) { throw new Error("spans belong on the outermost Text"); }
	if (kids !== null) { (kids as NeonNode)(host, node, before); }
}

// The host node of the outermost Text whose paragraph holds the span, or null while the span is in none.
export function spanText(node: HostNode): HostNode | null {
	let cur: SpanNode | null = spanOf(node);
	while (cur !== null) {
		const p = (cur as SpanNode).paragraph;
		if (p !== null) { return (p as Paragraph).node; }
		cur = (cur as SpanNode).parent;
	}
	return null;
}

function refuseInline(n: SpanNode): void {
	const tag = n.inline;
	if (tag !== null) {
		throw new Error(`a <${tag}> inside a Text is an inline view, which a paragraph does not place yet; put it beside the Text`);
	}
}

const SPAN_ATTRS = ["class", "accessible", "accessibilityLabel", "accessibilityHint", "accessibilityRole"];

const SPAN_TOUCHES = ["onTouchStart", "onTouchMove", "onTouchEnd", "onTouchCancel"];

export const SPAN_HOST: Host = {
	createElement: (tag: string): HostNode => {
		const n = new SpanNode(false);
		if (tag !== "text") { n.inline = tag; }
		return n;
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
		if (spanOf(node).inline !== null) { return; }
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
		const n = spanOf(node);
		if (n.inline !== null) { return; }
		if (SPAN_TOUCHES.indexOf(name) >= 0) {
			n.touches.push({ name, handler });
			n.touch = (touch: string, e: NeonEvent): void => {
				for (const route of n.touches) {
					if (route.name === touch) { route.handler(e); }
				}
			};
			return;
		}
		if (name !== "onPress") { throw new Error(`${name} on a Text inside a Text: a span takes onPress and touches only`); }
		n.press = handler;
	},
	append: (parent: HostNode, child: HostNode): void => {
		const p = spanOf(parent);
		const c = spanOf(child);
		refuseInline(c);
		detach(c);
		c.parent = p;
		p.children.push(c);
		touched(p);
	},
	insertBefore: (parent: HostNode, node: HostNode, before: HostNode | null): void => {
		const p = spanOf(parent);
		const n = spanOf(node);
		refuseInline(n);
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
	parentOf: (node: HostNode): HostNode | null => spanOf(node).parent,
	release: (node: HostNode): void => {
		if (spanOf(node).parent !== null) { throw new Error("release: the span still has a parent; remove it first"); }
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
	measureText: null,
	paragraph: nestedParagraph,
};

// The spans in order, each with the styles of the Texts around it merged; a run with no own style keeps null.
function flatten(n: SpanNode, style: Style | null, press: ((e: NeonEvent) => void) | null,
	touch: ((name: string, e: NeonEvent) => void) | null, out: TextSpan[]): void {
	for (const c of n.children) {
		if (c.isString) {
			if (c.text !== "") { out.push({ text: c.text, style, onPress: press, onTouch: touch }); }
		} else {
			const own = c.style;
			const merged: Style | null = own === null ? style : style === null ? own : mergeStyle(style as Style, own as Style);
			const owns = c.press !== null || c.touch !== null;
			flatten(c, merged, owns ? c.press : press, owns ? c.touch : touch, out);
		}
	}
}

// What the paragraph capability of a host that draws a Text as one paragraph runs: an outermost Text flattens
// its records after every render effect of an update has run, and `deliver` hands the host the spans whole.
export function spanParagraph(deliver: (node: HostNode, spans: TextSpan[]) => void, node: HostNode, kids: NeonNode | null, spans: Accessor<TextSpan[]> | null): void {
	if (spans !== null) {
		const read = spans as Accessor<TextSpan[]>;
		createRenderEffect<TextSpan[]>(
			(prev: TextSpan[] | null): TextSpan[] => read(),
			(value: TextSpan[], prev: TextSpan[] | null): Cleanup | null => { deliver(node, value); return null; },
			{ transparent: true },
		);
		return;
	}
	const root = new SpanNode(false);
	const [changed, setChanged] = createSignal<number>(0, { ownedWrite: true });
	const para = new Paragraph(node, (v: number): void => { setChanged(v); }, (text: string): void => {
		const one: TextSpan[] = [{ text }];
		deliver(node, one);
	});
	root.paragraph = para;
	if (kids !== null) { (kids as NeonNode)(SPAN_HOST, root, null); }
	const flush = (): void => {
		const out: TextSpan[] = [];
		flatten(root, null, null, null, out);
		para.delivered = para.version;
		para.single = root.children.length === 1 && root.children[0].isString ? root.children[0] : null;
		deliver(node, out);
	};
	flush();
	createRenderEffect<number>(
		(prev: number | null): number => changed(),
		(value: number, prev: number | null): Cleanup | null => {
			if (para.version !== para.delivered) { untrack(flush); }
			return null;
		},
	);
}
