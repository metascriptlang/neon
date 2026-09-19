// Void host — renders Neon NeonNode trees into a void2d Node2D scene graph.
// The same render(vnode, host, parent) that drives the DOM host drives
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
import { NeonEvent, neonEvent, eventType } from "../../render/event";
import { Node2D, DrawKind, group, label, addChild, addChildAt, removeChild } from "../../../../void/src/void2d/node";
import { Color } from "../../../../void/src/void2d/types";
import { FlexStyle } from "../../../../yoga/src/index";
import { Style } from "../../render/style";
import { asFlexStyleBody } from "../../macros/style/fields";

export { layoutPass, freeLayout } from "../../../../void/src/void2d/layout";
export { Node2D, DrawKind, group } from "../../../../void/src/void2d/node";

interface ParentLink {
	child: Node2D;
	parent: Node2D | null;
}

interface EventEntry {
	node: Node2D;
	name: string;
	handler: (e: NeonEvent) => void;
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

function hexNibble(c: string): int32 {
	if (c >= "0" && c <= "9") { return c.charCodeAt(0) - 48; }
	if (c >= "a" && c <= "f") { return c.charCodeAt(0) - 87; }
	if (c >= "A" && c <= "F") { return c.charCodeAt(0) - 55; }
	return -1;
}

// "#rgb" / "#rrggbb" → normalized rgba. Returns null for anything else so the
// caller leaves the node's existing colour alone.
export function parseColor(css: string): Color | null {
	if (css.length < 4 || css.charAt(0) !== "#") { return null; }
	const body = css.substring(1, css.length);
	let r = -1;
	let g = -1;
	let b = -1;
	if (body.length === 3) {
		r = hexNibble(body.charAt(0)) * 17;
		g = hexNibble(body.charAt(1)) * 17;
		b = hexNibble(body.charAt(2)) * 17;
	} else if (body.length === 6) {
		r = hexNibble(body.charAt(0)) * 16 + hexNibble(body.charAt(1));
		g = hexNibble(body.charAt(2)) * 16 + hexNibble(body.charAt(3));
		b = hexNibble(body.charAt(4)) * 16 + hexNibble(body.charAt(5));
	}
	if (r < 0 || g < 0 || b < 0) { return null; }
	const scale = 255.0 as float32;
	return { r: (r as float32) / scale, g: (g as float32) / scale, b: (b as float32) / scale, a: 1.0 };
}

// The paint half of the projection (docs/STYLE.md §5). A Group carrying a
// background becomes a Rect — a Group draws nothing on its own.
export function applyPaint(n: Node2D, s: Style): void {
	if (s.opacity !== null) { n.alpha = s.opacity as float32; }
	if (s.zIndex !== null) { const z = s.zIndex as number; n.zIndex = z as int32; }
	if (s.fontSize !== null && n.kind === DrawKind.Label) { n.size = s.fontSize as float32; }
	const fg = s.color;
	if (fg !== null && n.kind === DrawKind.Label) {
		const c = parseColor(fg as string);
		if (c !== null) { n.color = c; }
	}
	const bg = s.backgroundColor;
	if (bg !== null) {
		const c = parseColor(bg as string);
		if (c !== null) {
			if (n.kind === DrawKind.Group) { n.kind = DrawKind.Rect; }
			n.color = c;
		}
	}
}

function num(v: number | null): float32 | null {
	if (v === null) { return null; }
	const n = v as number;
	return n as float32;
}

function dim(v: number | string | null): float32 | string | null {
	if (v === null) { return null; }
	if (typeof v === "string") { return v as string; }
	const n = v as number;
	return n as float32;
}

asFlexStyleBody(0);

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
		removeAttr: (node: HostNode, name: string): void => {
			if (name === "style") {
				(node as unknown as Node2D).layoutStyle = parseFlexStyle("");
			}
		},
		setStyle: (node: HostNode, style: Style): void => {
			const n = node as unknown as Node2D;
			n.layoutStyle = asFlexStyle(style);
			applyPaint(n, style);
		},
		setStyleProp: null,
		setStyleClass: null,
		addEvent: (node: HostNode, name: string, handler: (e: NeonEvent) => void): void => {
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
			if (ref === null) {
				detachNode(links, n);
				p.addChild(n);
				linkParent(links, n, p);
				return;
			}
			let idx = childIndexOf(p, ref as unknown as Node2D);
			if (idx < 0) { throw "insertBefore: the reference node is not a child of the parent"; }
			const cur = childIndexOf(p, n);
			if (cur >= 0) {
				p.removeChild(n);
				if (cur < idx) { idx = idx - 1; }
			} else {
				detachNode(links, n);
			}
			p.addChildAt(n, idx);
			linkParent(links, n, p);
		},
		removeChild: (parent: HostNode, node: HostNode): void => {
			const p = parent as unknown as Node2D;
			const n = node as unknown as Node2D;
			if (childIndexOf(p, n) < 0) { throw "removeChild: the node is not a child of the parent"; }
			p.removeChild(n);
			linkParent(links, n, null);
		},
		nextSibling: (node: HostNode): HostNode | null => {
			const n = node as unknown as Node2D;
			const p = parentOf(links, n);
			if (p === null) { return null; }
			const idx = childIndexOf(p, n);
			if (idx < 0 || idx + 1 >= (p.children.length as int32)) { return null; }
			return p.children[idx + 1] as unknown as HostNode;
		},
		firstChild: (node: HostNode): HostNode | null => {
			const n = node as unknown as Node2D;
			if ((n.children.length as int32) === 0) { return null; }
			return n.children[0] as unknown as HostNode;
		},
		cloneNode: null,
	};

	const clickAt = (x: float32, y: float32): void => {
		for (const e of events) {
			if (e.name !== "onPress") { continue; }
			const wx = worldX(links, e.node);
			const wy = worldY(links, e.node);
			if (x >= wx && x <= wx + e.node.w && y >= wy && y <= wy + e.node.h) {
				const ev = neonEvent(eventType(e.name));
				ev.x = x;
				ev.y = y;
				e.handler(ev);
			}
		}
	};

	return { host, root, clickAt };
}
