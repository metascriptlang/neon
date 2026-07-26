// Browser DOM host — JS backend only. Same renderToHost(vnode, host, parent)
// drives this; here the host ops map to real document.* / Node APIs.

import { Host, HostNode } from "../../render/host";

extern class Style {
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
	style: Style;
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
