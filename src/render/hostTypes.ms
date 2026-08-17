import { Style, StyleValue } from "./style";

export type HostNode = unknown;

export interface Host {
	createElement: (tag: string) => HostNode;
	createText: (s: string) => HostNode;
	setText: (node: HostNode, s: string) => void;
	setAttr: (node: HostNode, name: string, value: string) => void;
	setStyle: (node: HostNode, style: Style) => void;
	// Optional capability, like `cloneNode`: a host that can write ONE style
	// property without touching the rest advertises it here (docs/STYLE.md §6).
	// `null` means "no partial write" and src/render/host.ms folds the field into
	// the node's own Style and re-applies — same result, coarser.
	setStyleProp: ((node: HostNode, name: string, value: StyleValue) => void) | null;
	addEvent: (node: HostNode, name: string, handler: () => void) => void;
	append: (parent: HostNode, child: HostNode) => void;
	insertBefore: (parent: HostNode, node: HostNode, ref: HostNode | null) => void;
	removeChild: (parent: HostNode, node: HostNode) => void;
	nextSibling: (node: HostNode) => HostNode | null;
	firstChild: (node: HostNode) => HostNode | null;
	// Optional capability: a host that can duplicate a built subtree cheaply
	// (DOM cloneNode) advertises it here. `null` means "no cheap clone" and
	// src/render/template.ms transparently rebuilds instead — same result,
	// slower, so a host is never forced to implement it.
	cloneNode: ((node: HostNode) => HostNode) | null;
}
