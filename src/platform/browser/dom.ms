// Browser DOM host — JS backend only. Same renderToHost(vnode, host, parent)
// drives this; here the host ops map to real document.* / Node APIs.

import { Host, HostNode } from "../../render/host";
import { Style, StyleValue } from "../../render/style";
import { registerCss, collectCss, onCssChange } from "../../render/sheet";
import { NeonEvent, neonEvent, eventType } from "../../render/event";
import { htmlTagFor } from "../../render/node";

extern class CssStyle {
	color: cstring;
	backgroundColor: cstring;
	display: cstring;
	visibility: cstring;
	opacity: cstring;
	width: cstring;
	height: cstring;
	margin: cstring;
	padding: cstring;
	border: cstring;
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
	transition: cstring;
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

// The one projection table: applyCss routes every field through here, so the
// static and per-property paths cannot drift apart.
export function applyCssProp(css: CssStyle, name: string, v: StyleValue): void {
	match (name) {
		"flexDirection" => { css.flexDirection = word(v as string | null); },
		"justifyContent" => { css.justifyContent = word(v as string | null); },
		"alignItems" => { css.alignItems = word(v as string | null); },
		"alignSelf" => { css.alignSelf = word(v as string | null); },
		"alignContent" => { css.alignContent = word(v as string | null); },
		"position" => { css.position = word(v as string | null); },
		"flexWrap" => { css.flexWrap = word(v as string | null); },
		"display" => { css.display = word(v as string | null); },
		"color" => { css.color = word(v as string | null); },
		"backgroundColor" => { css.backgroundColor = word(v as string | null); },
		"borderColor" => { css.borderColor = word(v as string | null); },
		"fontWeight" => { css.fontWeight = word(v as string | null); },
		"textAlign" => { css.textAlign = word(v as string | null); },
		"width" => { css.width = len(v); },
		"height" => { css.height = len(v); },
		"minWidth" => { css.minWidth = len(v); },
		"minHeight" => { css.minHeight = len(v); },
		"maxWidth" => { css.maxWidth = len(v); },
		"maxHeight" => { css.maxHeight = len(v); },
		"margin" => { css.margin = len(v); },
		"marginTop" => { css.marginTop = len(v); },
		"marginRight" => { css.marginRight = len(v); },
		"marginBottom" => { css.marginBottom = len(v); },
		"marginLeft" => { css.marginLeft = len(v); },
		"padding" => { css.padding = len(v); },
		"paddingTop" => { css.paddingTop = len(v); },
		"paddingRight" => { css.paddingRight = len(v); },
		"paddingBottom" => { css.paddingBottom = len(v); },
		"paddingLeft" => { css.paddingLeft = len(v); },
		"top" => { css.top = len(v); },
		"left" => { css.left = len(v); },
		"right" => { css.right = len(v); },
		"bottom" => { css.bottom = len(v); },
		"gap" => { css.gap = len(v); },
		"rowGap" => { css.rowGap = len(v); },
		"columnGap" => { css.columnGap = len(v); },
		"flexBasis" => { css.flexBasis = len(v); },
		"borderRadius" => { css.borderRadius = len(v); },
		"borderWidth" => { css.borderWidth = len(v); },
		"fontSize" => { css.fontSize = len(v); },
		"flex" => { css.flex = num(v as number | null); },
		"flexGrow" => { css.flexGrow = num(v as number | null); },
		"flexShrink" => { css.flexShrink = num(v as number | null); },
		"opacity" => { css.opacity = num(v as number | null); },
		"aspectRatio" => { css.aspectRatio = num(v as number | null); },
		_ => { throw new Error(`no browser projection for style field ${name}`); },
	};
}

export function applyCss(css: CssStyle, s: Style): void {
	css.cssText = "";
	if (s.flexDirection !== null) { applyCssProp(css, "flexDirection", s.flexDirection as unknown as StyleValue); }
	if (s.justifyContent !== null) { applyCssProp(css, "justifyContent", s.justifyContent as unknown as StyleValue); }
	if (s.alignItems !== null) { applyCssProp(css, "alignItems", s.alignItems as unknown as StyleValue); }
	if (s.alignSelf !== null) { applyCssProp(css, "alignSelf", s.alignSelf as unknown as StyleValue); }
	if (s.alignContent !== null) { applyCssProp(css, "alignContent", s.alignContent as unknown as StyleValue); }
	if (s.position !== null) { applyCssProp(css, "position", s.position as unknown as StyleValue); }
	if (s.flexWrap !== null) { applyCssProp(css, "flexWrap", s.flexWrap as unknown as StyleValue); }
	if (s.display !== null) { applyCssProp(css, "display", s.display as unknown as StyleValue); }
	if (s.color !== null) { applyCssProp(css, "color", s.color as unknown as StyleValue); }
	if (s.backgroundColor !== null) { applyCssProp(css, "backgroundColor", s.backgroundColor as unknown as StyleValue); }
	if (s.borderColor !== null) { applyCssProp(css, "borderColor", s.borderColor as unknown as StyleValue); }
	if (s.fontWeight !== null) { applyCssProp(css, "fontWeight", s.fontWeight as unknown as StyleValue); }
	if (s.textAlign !== null) { applyCssProp(css, "textAlign", s.textAlign as unknown as StyleValue); }
	if (s.flex !== null) { applyCssProp(css, "flex", s.flex as unknown as StyleValue); }
	if (s.flexGrow !== null) { applyCssProp(css, "flexGrow", s.flexGrow as unknown as StyleValue); }
	if (s.flexShrink !== null) { applyCssProp(css, "flexShrink", s.flexShrink as unknown as StyleValue); }
	if (s.flexBasis !== null) { applyCssProp(css, "flexBasis", s.flexBasis as unknown as StyleValue); }
	if (s.width !== null) { applyCssProp(css, "width", s.width as unknown as StyleValue); }
	if (s.height !== null) { applyCssProp(css, "height", s.height as unknown as StyleValue); }
	if (s.minWidth !== null) { applyCssProp(css, "minWidth", s.minWidth as unknown as StyleValue); }
	if (s.minHeight !== null) { applyCssProp(css, "minHeight", s.minHeight as unknown as StyleValue); }
	if (s.maxWidth !== null) { applyCssProp(css, "maxWidth", s.maxWidth as unknown as StyleValue); }
	if (s.maxHeight !== null) { applyCssProp(css, "maxHeight", s.maxHeight as unknown as StyleValue); }
	if (s.margin !== null) { applyCssProp(css, "margin", s.margin as unknown as StyleValue); }
	if (s.marginTop !== null) { applyCssProp(css, "marginTop", s.marginTop as unknown as StyleValue); }
	if (s.marginRight !== null) { applyCssProp(css, "marginRight", s.marginRight as unknown as StyleValue); }
	if (s.marginBottom !== null) { applyCssProp(css, "marginBottom", s.marginBottom as unknown as StyleValue); }
	if (s.marginLeft !== null) { applyCssProp(css, "marginLeft", s.marginLeft as unknown as StyleValue); }
	if (s.padding !== null) { applyCssProp(css, "padding", s.padding as unknown as StyleValue); }
	if (s.paddingTop !== null) { applyCssProp(css, "paddingTop", s.paddingTop as unknown as StyleValue); }
	if (s.paddingRight !== null) { applyCssProp(css, "paddingRight", s.paddingRight as unknown as StyleValue); }
	if (s.paddingBottom !== null) { applyCssProp(css, "paddingBottom", s.paddingBottom as unknown as StyleValue); }
	if (s.paddingLeft !== null) { applyCssProp(css, "paddingLeft", s.paddingLeft as unknown as StyleValue); }
	if (s.top !== null) { applyCssProp(css, "top", s.top as unknown as StyleValue); }
	if (s.left !== null) { applyCssProp(css, "left", s.left as unknown as StyleValue); }
	if (s.right !== null) { applyCssProp(css, "right", s.right as unknown as StyleValue); }
	if (s.bottom !== null) { applyCssProp(css, "bottom", s.bottom as unknown as StyleValue); }
	if (s.gap !== null) { applyCssProp(css, "gap", s.gap as unknown as StyleValue); }
	if (s.rowGap !== null) { applyCssProp(css, "rowGap", s.rowGap as unknown as StyleValue); }
	if (s.columnGap !== null) { applyCssProp(css, "columnGap", s.columnGap as unknown as StyleValue); }
	if (s.borderRadius !== null) { applyCssProp(css, "borderRadius", s.borderRadius as unknown as StyleValue); }
	if (s.borderWidth !== null) { applyCssProp(css, "borderWidth", s.borderWidth as unknown as StyleValue); }
	if (s.fontSize !== null) { applyCssProp(css, "fontSize", s.fontSize as unknown as StyleValue); }
	if (s.opacity !== null) { applyCssProp(css, "opacity", s.opacity as unknown as StyleValue); }
	if (s.aspectRatio !== null) { applyCssProp(css, "aspectRatio", s.aspectRatio as unknown as StyleValue); }
}

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
			(node as unknown as DomNode).setAttribute(name, value);
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
