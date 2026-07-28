// Void host — renders Neon VNode trees into a void2d Node2D scene graph.
// The same renderToHost(vnode, host, parent) that drives the DOM host drives
// this; element tags all become group() containers, text nodes become label().
// A "style" attr is a points-only string ("width:200;flexDirection:column")
// parsed into FlexStyle → node.layoutStyle; run layoutPass(root, w, h) each
// frame before the render walk.
//
// Node2D has no parent pointer and no event system, so the host keeps both in
// side registries: parent links power insertBefore/nextSibling/move semantics,
// the event registry powers clickAt(x, y) hit-testing (world coords = summed
// ancestor x/y — layout output is translation-only).

import { Host, HostNode } from "../../render/host";
import { Node2D, group, label, addChild, addChildAt, removeChild } from "../../../../void/src/void2d/node";
import { FlexStyle } from "../../../../yoga/src/index";
import { Style } from "../../render/style";

export { layoutPass, freeLayout } from "../../../../void/src/void2d/layout";
export { Node2D, DrawKind, group } from "../../../../void/src/void2d/node";

interface ParentLink {
	child: Node2D;
	parent: Node2D | null;
}

interface EventEntry {
	node: Node2D;
	name: string;
	handler: () => void;
}

export interface VoidHost {
	host: Host;
	root: Node2D;
	clickAt: (x: float32, y: float32) => void;
}

function parentOf(links: ParentLink[], child: Node2D): Node2D | null {
	for (const l of links) {
		if (l.child === child) { return l.parent; }
	}
	return null;
}

function linkParent(links: ParentLink[], child: Node2D, parent: Node2D | null): void {
	for (const l of links) {
		if (l.child === child) { l.parent = parent; return; }
	}
	links.push({ child, parent });
}

function detachNode(links: ParentLink[], child: Node2D): void {
	const p = parentOf(links, child);
	if (p !== null) { p.removeChild(child); }
	linkParent(links, child, null);
}

function childIndexOf(parent: Node2D, node: Node2D): int32 {
	let i: int32 = 0;
	while (i < (parent.children.length as int32)) {
		if (parent.children[i] === node) { return i; }
		i = i + 1;
	}
	return -1 as int32;
}

function styleNum(st: FlexStyle, key: string, v: float32): void {
	if (key === "width") { st.width = v; }
	else if (key === "height") { st.height = v; }
	else if (key === "flexGrow") { st.flexGrow = v; }
	else if (key === "flexShrink") { st.flexShrink = v; }
	else if (key === "padding") { st.padding = v; }
	else if (key === "margin") { st.margin = v; }
	else if (key === "gap") { st.gap = v; }
	else if (key === "left") { st.left = v; }
	else if (key === "top") { st.top = v; }
	else if (key === "right") { st.right = v; }
	else if (key === "bottom") { st.bottom = v; }
}

function styleEnum(st: FlexStyle, key: string, v: string): void {
	if (key === "flexDirection") {
		if (v === "column") { st.flexDirection = "column"; }
		else if (v === "row") { st.flexDirection = "row"; }
		else if (v === "column-reverse") { st.flexDirection = "column-reverse"; }
		else if (v === "row-reverse") { st.flexDirection = "row-reverse"; }
	} else if (key === "justifyContent") {
		if (v === "center") { st.justifyContent = "center"; }
		else if (v === "flex-start") { st.justifyContent = "flex-start"; }
		else if (v === "flex-end") { st.justifyContent = "flex-end"; }
		else if (v === "space-between") { st.justifyContent = "space-between"; }
		else if (v === "space-around") { st.justifyContent = "space-around"; }
		else if (v === "space-evenly") { st.justifyContent = "space-evenly"; }
	} else if (key === "alignItems") {
		if (v === "center") { st.alignItems = "center"; }
		else if (v === "flex-start") { st.alignItems = "flex-start"; }
		else if (v === "flex-end") { st.alignItems = "flex-end"; }
		else if (v === "stretch") { st.alignItems = "stretch"; }
	} else if (key === "position") {
		if (v === "absolute") { st.position = "absolute"; }
		else if (v === "relative") { st.position = "relative"; }
	}
}

const NUMERIC_KEYS = ["width", "height", "flexGrow", "flexShrink", "padding", "margin", "gap", "left", "top", "right", "bottom"];

export function parseFlexStyle(s: string): FlexStyle {
	const st: FlexStyle = {};
	for (const part of s.split(";")) {
		const kv = part.split(":");
		if (kv.length !== 2) { continue; }
		const key = kv[0].trim();
		const val = kv[1].trim();
		let numeric = false;
		for (const nk of NUMERIC_KEYS) {
			if (nk === key) { numeric = true; break; }
		}
		if (numeric) { styleNum(st, key, parseFloat(val) as float32); }
		else { styleEnum(st, key, val); }
	}
	return st;
}

function setDimStr(st: FlexStyle, key: string, v: string): void {
	if (key === "width") { st.width = v; }
	else if (key === "height") { st.height = v; }
	else if (key === "padding") { st.padding = v; }
	else if (key === "margin") { st.margin = v; }
	else if (key === "gap") { st.gap = v; }
	else if (key === "left") { st.left = v; }
	else if (key === "top") { st.top = v; }
	else if (key === "right") { st.right = v; }
	else if (key === "bottom") { st.bottom = v; }
}

function setDim(st: FlexStyle, key: string, v: number | string | null): void {
	if (v === null) { return; }
	if (typeof v === "string") { setDimStr(st, key, v as string); }
	else { styleNum(st, key, v as number); }
}

// Style → FlexStyle projection (docs/STYLE.md §5). S1 projects the layout subset only;
// paint and text fields of Style land in S2.
export function asFlexStyle(this s: Style): FlexStyle {
	const st: FlexStyle = {};
	if (s.flexDirection !== null) { styleEnum(st, "flexDirection", s.flexDirection as string); }
	if (s.justifyContent !== null) { styleEnum(st, "justifyContent", s.justifyContent as string); }
	if (s.alignItems !== null) { styleEnum(st, "alignItems", s.alignItems as string); }
	if (s.position !== null) { styleEnum(st, "position", s.position as string); }
	if (s.flexGrow !== null) { styleNum(st, "flexGrow", s.flexGrow as float32); }
	if (s.flexShrink !== null) { styleNum(st, "flexShrink", s.flexShrink as float32); }
	setDim(st, "width", s.width);
	setDim(st, "height", s.height);
	setDim(st, "padding", s.padding);
	setDim(st, "margin", s.margin);
	setDim(st, "gap", s.gap);
	setDim(st, "left", s.left);
	setDim(st, "top", s.top);
	setDim(st, "right", s.right);
	setDim(st, "bottom", s.bottom);
	return st;
}

function worldX(links: ParentLink[], n: Node2D): float32 {
	let x = n.x;
	let p = parentOf(links, n);
	while (p !== null) {
		x = x + p.x;
		p = parentOf(links, p);
	}
	return x;
}

function worldY(links: ParentLink[], n: Node2D): float32 {
	let y = n.y;
	let p = parentOf(links, n);
	while (p !== null) {
		y = y + p.y;
		p = parentOf(links, p);
	}
	return y;
}

const TEXT_SIZE: float32 = 16.0;

export function createVoidHost(): VoidHost {
	const links: ParentLink[] = [];
	const events: EventEntry[] = [];
	const root = group();

	const host: Host = {
		createElement: (tag: string): HostNode => group() as unknown as HostNode,
		createText: (s: string): HostNode => {
			return label(s, TEXT_SIZE, { r: 1.0, g: 1.0, b: 1.0, a: 1.0 }) as unknown as HostNode;
		},
		setText: (node: HostNode, s: string): void => {
			(node as unknown as Node2D).text = s;
		},
		setAttr: (node: HostNode, name: string, value: string): void => {
			if (name === "style") {
				(node as unknown as Node2D).layoutStyle = parseFlexStyle(value);
			}
		},
		setStyle: (node: HostNode, style: Style): void => {
			(node as unknown as Node2D).layoutStyle = style;
		},
		addEvent: (node: HostNode, name: string, handler: () => void): void => {
			events.push({ node: node as unknown as Node2D, name, handler });
		},
		append: (parent: HostNode, child: HostNode): void => {
			const p = parent as unknown as Node2D;
			const c = child as unknown as Node2D;
			detachNode(links, c);
			p.addChild(c);
			linkParent(links, c, p);
		},
		insertBefore: (parent: HostNode, node: HostNode, ref: HostNode | null): void => {
			const p = parent as unknown as Node2D;
			const n = node as unknown as Node2D;
			detachNode(links, n);
			if (ref === null) {
				p.addChild(n);
			} else {
				const idx = childIndexOf(p, ref as unknown as Node2D);
				if (idx < 0) { p.addChild(n); }
				else { p.addChildAt(n, idx); }
			}
			linkParent(links, n, p);
		},
		removeChild: (parent: HostNode, node: HostNode): void => {
			(parent as unknown as Node2D).removeChild(node as unknown as Node2D);
			linkParent(links, node as unknown as Node2D, null);
		},
		nextSibling: (node: HostNode): HostNode | null => {
			const n = node as unknown as Node2D;
			const p = parentOf(links, n);
			if (p === null) { return null; }
			const idx = childIndexOf(p, n);
			if (idx < 0 || idx + 1 >= (p.children.length as int32)) { return null; }
			return p.children[idx + 1] as unknown as HostNode;
		},
	};

	const clickAt = (x: float32, y: float32): void => {
		for (const e of events) {
			if (e.name !== "onClick") { continue; }
			const wx = worldX(links, e.node);
			const wy = worldY(links, e.node);
			if (x >= wx && x <= wx + e.node.w && y >= wy && y <= wy + e.node.h) {
				e.handler();
			}
		}
	};

	return { host, root, clickAt };
}
