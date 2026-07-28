// Browser DOM host — JS backend only. Same renderToHost(vnode, host, parent)
// drives this; here the host ops map to real document.* / Node APIs.

import { Host, HostNode } from "../../render/host";
import { Style } from "../../render/style";

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
	extern appendChild(child: DomNode): void;
	extern insertBefore(node: DomNode, ref: DomNode | null): void;
	extern removeChild(child: DomNode): void;
	extern setAttribute(name: cstring, value: cstring): void;
	extern addEventListener(name: cstring, handler: () => void): void;
}

extern class document {
	static body: DomNode;
	static extern createElement(tag: cstring): DomNode;
	static extern createTextNode(s: cstring): DomNode;
}

// "onClick" → "click" (DOM listener names are lowercase, no "on").
function eventName(name: string): string {
	return name.slice(2, name.length).toLower();
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

export function applyCss(css: CssStyle, s: Style): void {
	css.flexDirection = word(s.flexDirection as string | null);
	css.justifyContent = word(s.justifyContent as string | null);
	css.alignItems = word(s.alignItems as string | null);
	css.position = word(s.position as string | null);
	css.display = word(s.display as string | null);

	css.width = len(s.width);
	css.height = len(s.height);
	css.margin = len(s.margin);
	css.padding = len(s.padding);
	css.gap = len(s.gap);
	css.top = len(s.top);
	css.left = len(s.left);
	css.right = len(s.right);
	css.bottom = len(s.bottom);

	css.color = word(s.color);
	css.backgroundColor = word(s.backgroundColor);
	css.borderRadius = s.borderRadius === null ? "" : `${s.borderRadius as number}px`;
	css.opacity = num(s.opacity);
	css.fontSize = s.fontSize === null ? "" : `${s.fontSize as number}px`;
	css.fontWeight = word(s.fontWeight as string | null);
	css.textAlign = word(s.textAlign as string | null);
}

export function documentBody(): HostNode {
	return document.body as unknown as HostNode;
}

export function domHost(): Host {
	return {
		createElement: (tag: string): HostNode => document.createElement(tag) as unknown as HostNode,
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
		addEvent: (node: HostNode, name: string, handler: () => void): void => {
			(node as unknown as DomNode).addEventListener(eventName(name), handler);
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
	};
}
