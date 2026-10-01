// Browser DOM host — JS backend only. Same render(node, host, parent)
// drives this; here the host ops map to real document.* / Node APIs.

import { Host, HostNode } from "../../render/host";
import { Style, StyleValue } from "../../render/style";
import { registerCss, collectCss, onCssChange } from "../../render/sheet";
import { NeonEvent, neonEvent, eventType } from "../../render/event";
import { htmlTagFor } from "../../render/node";
import { CssStyle, applyCss, applyCssProp } from "./domCss";

extern class ClassList {
	extern add(name: cstring): void;
	extern remove(name: cstring): void;
	extern toggle(name: cstring): void;
	extern contains(name: cstring): boolean;
}

extern class Node {
	textContent: cstring;
	style: CssStyle;
	classList: ClassList;
	nextSibling: Node;
	firstChild: Node;
	extern cloneNode(deep: boolean): Node;
	extern appendChild(child: Node): void;
	extern insertBefore(node: Node, ref: Node | null): void;
	extern removeChild(child: Node): void;
	value: cstring;
	extern setAttribute(name: cstring, value: cstring): void;
	extern removeAttribute(name: cstring): void;
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
	code: string;
	altKey: boolean;
	ctrlKey: boolean;
	metaKey: boolean;
	shiftKey: boolean;
	repeat: boolean;
	isComposing: boolean;
}

extern class document {
	static body: Node;
	static head: Node;
	static extern createElement(tag: cstring): Node;
	static extern createTextNode(s: cstring): Node;
}

// One <style> element owns every rule the program registered. Rewriting its
// whole text on each new rule is fine because registration happens as sheets
// are first mounted, not per element, and the browser reparses one small block.
let sheetNode: Node | null = null;

function flushSheet(): void {
	if (sheetNode === null) {
		const n = document.createElement("style");
		document.head.appendChild(n);
		sheetNode = n;
	}
	(sheetNode as Node).textContent = collectCss();
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
			(node as unknown as Node).textContent = s;
		},
		setAttr: (node: HostNode, name: string, value: string): void => {
			const el = node as unknown as Node;
			if (name === "value") { el.value = value; return; }
			el.setAttribute(name, value);
		},
		removeAttr: (node: HostNode, name: string): void => {
			const el = node as unknown as Node;
			if (name === "value") { el.value = ""; }
			el.removeAttribute(name);
		},
		setStyle: (node: HostNode, style: Style): void => {
			applyCss((node as unknown as Node).style, style);
		},
		setStyleProp: (node: HostNode, name: string, value: StyleValue): void => {
			applyCssProp((node as unknown as Node).style, name, value);
		},
		setStyleClass: (node: HostNode, id: string, css: string): void => {
			registerCss(id, css);
			(node as unknown as Node).classList.add(id);
		},
		addEvent: (node: HostNode, name: string, handler: (e: NeonEvent) => void): void => {
			const type = eventType(name);
			// RN surface names project onto DOM listeners; e.type keeps the neon
			// spelling so handlers compare one vocabulary on every host.
			let domType = type;
			if (type === "press") { domType = "click"; }
			else if (type === "changetext") { domType = "input"; }
			(node as unknown as Node).addEventListener(domType, (de: DomEvent): void => {
				const ev = neonEvent(type);
				if (type === "changetext" || type === "input" || type === "change") { ev.value = de.target.value; }
				else if (type === "keydown" || type === "keyup" || type === "keypress") {
					ev.key = de.key;
					ev.code = de.code;
					ev.altKey = de.altKey;
					ev.ctrlKey = de.ctrlKey;
					ev.metaKey = de.metaKey;
					ev.shiftKey = de.shiftKey;
					ev.repeat = de.repeat;
					ev.isComposing = de.isComposing;
				}
				else if (type === "press" || type === "click" || type === "dblclick" || type === "mousedown" || type === "mouseup" || type === "mousemove") {
					ev.x = de.clientX;
					ev.y = de.clientY;
				}
				handler(ev);
			});
		},
		append: (parent: HostNode, child: HostNode): void => {
			(parent as unknown as Node).appendChild(child as unknown as Node);
		},
		insertBefore: (parent: HostNode, node: HostNode, ref: HostNode | null): void => {
			(parent as unknown as Node).insertBefore(
				node as unknown as Node,
				ref === null ? null : (ref as unknown as Node),
			);
		},
		removeChild: (parent: HostNode, node: HostNode): void => {
			(parent as unknown as Node).removeChild(node as unknown as Node);
		},
		nextSibling: (node: HostNode): HostNode | null => {
			return (node as unknown as Node).nextSibling as unknown as HostNode;
		},
		firstChild: (node: HostNode): HostNode | null => {
			return (node as unknown as Node).firstChild as unknown as HostNode;
		},
		cloneNode: (node: HostNode): HostNode => {
			return (node as unknown as Node).cloneNode(true) as unknown as HostNode;
		},
		voidArea: null,
	};
}
