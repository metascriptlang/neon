import { Style, StyleValue } from "./style";
import { NeonEvent } from "./event";
import { AreaHub } from "./voidAreaHandle";

export type HostNode = unknown;

export type RefFn = (node: HostNode) => void;

// What a JSX expression becomes on every target: a function that puts the nodes
// it owns into `parent`, in front of `before`.
export type NeonNode = (host: Host, parent: HostNode, before: HostNode | null) => void;

// A run of text and the style it lays over its Text's: the data form of a nested <Text>.
export interface TextSpan {
	text: string;
	style?: Style | null;
}

export interface VoidArea {
	host: Host;
	root: HostNode;
	hub: AreaHub;
	release: () => void;
}

export interface Host {
	createElement: (tag: string) => HostNode;
	createText: (s: string) => HostNode;
	setText: (node: HostNode, s: string) => void;
	setAttr: (node: HostNode, name: string, value: string) => void;
	removeAttr: (node: HostNode, name: string) => void;
	setStyle: (node: HostNode, style: Style) => void;
	// Optional capability, like `cloneNode`: a host that can write ONE style
	// property without touching the rest advertises it here (docs/STYLE.md §6).
	// `null` means "no partial write" and src/render/host.ms folds the field into
	// the node's own Style and re-applies — same result, coarser.
	setStyleProp: ((node: HostNode, name: string, value: StyleValue) => void) | null;
	// Optional capability: a host with a stylesheet takes a shared style as a
	// named rule plus a class instead of writing every field onto the node.
	// `null` means "no stylesheet" (every native host) and src/render/host.ms
	// applies the fields through setStyle — same pixels, more writes. A node
	// holds one sheet class: a new id replaces the last, and "" removes it.
	setStyleClass: ((node: HostNode, id: string, css: string) => void) | null;
	addEvent: (node: HostNode, name: string, handler: (e: NeonEvent) => void) => void;
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
	voidArea: ((node: HostNode) => VoidArea) | null;
	scrollTo: ((node: HostNode, x: number, y: number, animated: boolean) => void) | null;
	focus?: ((node: HostNode, focused: boolean) => void) | null;
	// Optional capability: the host's top layer, where a Portal that names no
	// mount node puts its content (the DOM body, the native root). `node` is
	// where the Portal sits in the tree.
	overlayRoot?: ((node: HostNode) => HostNode) | null;
	setResponder?: ((node: HostNode | null, blockNativeResponder: boolean) => void) | null;
	claim?: ((parent: HostNode, after: HostNode | null, tag: string) => HostNode | null) | null;
	headRoot?: ((node: HostNode) => HostNode) | null;
	// Optional capability: a host that draws a Text as one paragraph takes its spans whole.
	// `null` means src/components/primitives.ms lays the spans out as nested Texts —
	// the same text, a node per span.
	setSpans?: ((node: HostNode, spans: TextSpan[]) => void) | null;
}
