// Browser DOM host — JS backend only. Same renderToHost(vnode, host, parent)
// drives this; here the host ops map to real document.* / Node APIs.

import { Host, HostNode } from "../../render/host";
import { Style, StyleValue } from "../../render/style";
import { registerCss, collectCss, onCssChange } from "../../render/sheet";
import { NeonEvent, neonEvent, eventType } from "../../render/event";
import { htmlTagFor } from "../../render/node";
import { applyCssPropBody, applyCssBody } from "../../macros/style/fields";

extern class CssStyle {
	color: cstring;
	backgroundColor: cstring;
	display: cstring;
	opacity: cstring;
	width: cstring;
	height: cstring;
	margin: cstring;
	padding: cstring;
	borderRadius: cstring;
	boxShadow: cstring;
	position: cstring;
	top: cstring;
	left: cstring;
	right: cstring;
	bottom: cstring;
	zIndex: cstring;
	overflow: cstring;
	flexDirection: cstring;
	justifyContent: cstring;
	alignItems: cstring;
	gap: cstring;
	fontSize: cstring;
	fontWeight: cstring;
	fontFamily: cstring;
	textAlign: cstring;
	cursor: cstring;
	transform: cstring;
	cssText: cstring;
	alignContent: cstring;
	alignSelf: cstring;
	aspectRatio: cstring;
	borderColor: cstring;
	borderWidth: cstring;
	columnGap: cstring;
	flex: cstring;
	flexBasis: cstring;
	flexGrow: cstring;
	flexShrink: cstring;
	flexWrap: cstring;
	marginBottom: cstring;
	marginLeft: cstring;
	marginRight: cstring;
	marginTop: cstring;
	maxHeight: cstring;
	maxWidth: cstring;
	minHeight: cstring;
	minWidth: cstring;
	paddingBottom: cstring;
	paddingLeft: cstring;
	paddingRight: cstring;
	paddingTop: cstring;
	rowGap: cstring;
}

extern class ClassList {
	extern add(name: cstring): void;
	extern remove(name: cstring): void;
	extern toggle(name: cstring): void;
	extern contains(name: cstring): boolean;
}

extern class DomNode {
	textContent: cstring;
	style: CssStyle;
	classList: ClassList;
	nextSibling: DomNode;
	firstChild: DomNode;
	extern cloneNode(deep: boolean): DomNode;
	extern appendChild(child: DomNode): void;
	extern insertBefore(node: DomNode, ref: DomNode | null): void;
	extern removeChild(child: DomNode): void;
	value: cstring;
	extern setAttribute(name: cstring, value: cstring): void;
	extern addEventListener(name: cstring, handler: (e: DomEvent) => void): void;
}

// Only the fields Neon projects onto NeonEvent. Each is read ONLY for the event
// types that always carry it (`value` on input/change, `key` on the key events,
// clientX/Y on the mouse ones) — a DOM event object simply lacks the others, and
// there is no way to probe for absence across the extern boundary.
extern class DomEventTarget {
	value: string;
}

extern class DomEvent {
	target: DomEventTarget;
	clientX: number;
	clientY: number;
	key: string;
}

extern class document {
	static body: DomNode;
	static head: DomNode;
	static extern createElement(tag: cstring): DomNode;
	static extern createTextNode(s: cstring): DomNode;
}

// One <style> element owns every rule the program registered. Rewriting its
// whole text on each new rule is fine because registration happens as sheets
// are first mounted, not per element, and the browser reparses one small block.
let sheetNode: DomNode | null = null;

function flushSheet(): void {
	if (sheetNode === null) {
		const n = document.createElement("style");
		document.head.appendChild(n);
		sheetNode = n;
	}
	(sheetNode as DomNode).textContent = collectCss();
}

// docs/STYLE.md §5 — the browser's projection of the portable Style IR.
// A bare number is points, which on the web means px; a string ("50%", "auto")
// is already CSS.
function len(v: number | string | null): string {
	if (v === null) { return ""; }
	if (typeof v === "string") { return v as string; }
	return `${v as number}px`;
}

function num(v: number | null): string {
	return v === null ? "" : `${v as number}`;
}

function word(v: string | null): string {
	return v === null ? "" : v as string;
}

applyCssPropBody(0);

applyCssBody(0);

export function documentBody(): HostNode {
	return document.body as unknown as HostNode;
}

export function domHost(): Host {
	// The registry may already hold rules from module init — a theme's :root
	// among them — and from here on every change mounts itself, including a
	// swap that touches no node.
	onCssChange(flushSheet);
	flushSheet();
	return {
		createElement: (tag: string): HostNode => document.createElement(htmlTagFor(tag)) as unknown as HostNode,
		createText: (s: string): HostNode => document.createTextNode(s) as unknown as HostNode,
		setText: (node: HostNode, s: string): void => {
			(node as unknown as DomNode).textContent = s;
		},
		setAttr: (node: HostNode, name: string, value: string): void => {
			const el = node as unknown as DomNode;
			if (name === "value") { el.value = value; return; }
			el.setAttribute(name, value);
		},
		setStyle: (node: HostNode, style: Style): void => {
			applyCss((node as unknown as DomNode).style, style);
		},
		setStyleProp: (node: HostNode, name: string, value: StyleValue): void => {
			applyCssProp((node as unknown as DomNode).style, name, value);
		},
		setStyleClass: (node: HostNode, id: string, css: string): void => {
			registerCss(id, css);
			(node as unknown as DomNode).classList.add(id);
		},
		addEvent: (node: HostNode, name: string, handler: (e: NeonEvent) => void): void => {
			const type = eventType(name);
			// RN surface names project onto DOM listeners; e.type keeps the neon
			// spelling so handlers compare one vocabulary on every host.
			let domType = type;
			if (type === "press") { domType = "click"; }
			else if (type === "changetext") { domType = "input"; }
			(node as unknown as DomNode).addEventListener(domType, (de: DomEvent): void => {
				const ev = neonEvent(type);
				if (type === "changetext" || type === "input" || type === "change") { ev.value = de.target.value; }
				else if (type === "keydown" || type === "keyup" || type === "keypress") { ev.key = de.key; }
				else if (type === "press" || type === "click" || type === "dblclick" || type === "mousedown" || type === "mouseup" || type === "mousemove") {
					ev.x = de.clientX;
					ev.y = de.clientY;
				}
				handler(ev);
			});
		},
		append: (parent: HostNode, child: HostNode): void => {
			(parent as unknown as DomNode).appendChild(child as unknown as DomNode);
		},
		insertBefore: (parent: HostNode, node: HostNode, ref: HostNode | null): void => {
			(parent as unknown as DomNode).insertBefore(
				node as unknown as DomNode,
				ref === null ? null : (ref as unknown as DomNode),
			);
		},
		removeChild: (parent: HostNode, node: HostNode): void => {
			(parent as unknown as DomNode).removeChild(node as unknown as DomNode);
		},
		nextSibling: (node: HostNode): HostNode | null => {
			return (node as unknown as DomNode).nextSibling as unknown as HostNode;
		},
		firstChild: (node: HostNode): HostNode | null => {
			return (node as unknown as DomNode).firstChild as unknown as HostNode;
		},
		cloneNode: (node: HostNode): HostNode => {
			return (node as unknown as DomNode).cloneNode(true) as unknown as HostNode;
		},
	};
}
