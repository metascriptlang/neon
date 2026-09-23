// Void host — a NeonNode mounts into a void2d Node2D scene graph.
// The same render(node, host, parent) that drives the DOM host drives
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
import { Node2D, DrawKind, group, label, rect, addChild, addChildAt, removeChild } from "../../../../void/src/void2d/node";
import { Color } from "../../../../void/src/void2d/types";
import { layoutPass } from "../../../../void/src/void2d/layout";
import { FlexStyle, FlexDirection, Justify, Align, PositionType, Wrap, Display, Overflow } from "../../../../yoga/src/index";
import { Style } from "../../render/style";
import { asFlexStyleBody } from "../../macros/style/fields";
import {
	TextEditingValue, editingValue, isEmptyRange,
	commitText, composeText, deleteBackward, deleteForward, moveCaret,
} from "./editing";

export { layoutPass, freeLayout } from "../../../../void/src/void2d/layout";
export { Node2D, DrawKind, group } from "../../../../void/src/void2d/node";
export { TextEditingValue, TextRange, editingValue, textRange, noRange } from "./editing";

interface EventEntry {
	node: Node2D;
	name: string;
	handler: (e: NeonEvent) => void;
}

export interface VoidHost {
	host: Host;
	root: Node2D;
	clickAt: (x: float32, y: float32) => void;
	keyDown: (e: NeonEvent) => void;
	keyUp: (e: NeonEvent) => void;
	commitText: (text: string) => void;
	composeText: (text: string, cursor: number) => void;
	setWindowFocus: (focused: boolean) => void;
	layout: (width: float32, height: float32) => void;
	focus: (node: Node2D | null) => void;
	focused: () => Node2D | null;
	imeRect: () => CaretRect | null;
	attachTextInput: (node: Node2D, client: TextInputClient, value: TextEditingValue) => void;
	setEditingState: (node: Node2D, value: TextEditingValue) => void;
	onDirty: (fn: () => void) => void;
}

function parentOf(links: Map<Node2D, Node2D>, child: Node2D): Node2D | null {
	if (!links.has(child)) { return null; }
	return links.get(child) as Node2D;
}

function detachNode(links: Map<Node2D, Node2D>, child: Node2D): void {
	const p = parentOf(links, child);
	if (p !== null) { p.removeChild(child); }
	links.delete(child);
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

function dim(v: number | string | null, field: string): float32 | null {
	if (v === null) { return null; }
	if (typeof v === "string") { throw `void host: ${field} "${v as string}" is not supported, yoga takes points only`; }
	const n = v as number;
	return n as float32;
}

asFlexStyleBody(0);

function worldX(links: Map<Node2D, Node2D>, n: Node2D): float32 {
	let x = n.x;
	let p = parentOf(links, n);
	while (p !== null) {
		x = x + p.x;
		p = parentOf(links, p);
	}
	return x;
}

function worldY(links: Map<Node2D, Node2D>, n: Node2D): float32 {
	let y = n.y;
	let p = parentOf(links, n);
	while (p !== null) {
		y = y + p.y;
		p = parentOf(links, p);
	}
	return y;
}

const TEXT_SIZE: float32 = 16.0;
const LINE_HEIGHT: float32 = 1.25;
const CARET_WIDTH: float32 = 1.0;

export type MeasureText = (size: float32, text: string) => float32;

export interface CaretRect {
	x: float32;
	y: float32;
	w: float32;
	h: float32;
}

export interface TextInputClient {
	updateEditingValue: (value: TextEditingValue) => void;
	caretRect: () => CaretRect;
}

interface ClientEntry {
	node: Node2D;
	client: TextInputClient;
	value: TextEditingValue;
}

interface Field {
	node: Node2D;
	label: Node2D;
	caret: Node2D;
	committed: string;
}

interface LaidOut {
	node: Node2D;
	x: float32;
	y: float32;
	w: float32;
	h: float32;
}

function noMeasure(size: float32, text: string): float32 {
	throw "void host: a TextInput needs a text measurer; create the host with createVoidHostWith(measure)";
}

export function createVoidHost(): VoidHost {
	return createVoidHostWith(noMeasure);
}

export function createVoidHostWith(measure: MeasureText): VoidHost {
	const links = new Map<Node2D, Node2D>();
	const events: EventEntry[] = [];
	const clients: ClientEntry[] = [];
	const fields: Field[] = [];
	const laidOut: LaidOut[] = [];
	const root = group();
	let focusedNode: Node2D | null = null;
	let windowFocused = true;
	let dirtyListener: (() => void) | null = null;

	const markDirty = (): void => {
		if (dirtyListener !== null) { (dirtyListener as () => void)(); }
	};

	const attached = (n: Node2D): boolean => {
		let cur: Node2D | null = n;
		while (cur !== null) {
			if (cur === root) { return true; }
			cur = parentOf(links, cur as Node2D);
		}
		return false;
	};

	const fire = (n: Node2D, name: string, e: NeonEvent): boolean => {
		let hit = false;
		for (const entry of events) {
			if (entry.node === n && entry.name === name) {
				entry.handler(e);
				hit = true;
			}
		}
		return hit;
	};

	const hasHandler = (n: Node2D, name: string): boolean => {
		for (const entry of events) {
			if (entry.node === n && entry.name === name) { return true; }
		}
		return false;
	};

	const clientOf = (n: Node2D): ClientEntry | null => {
		for (const c of clients) {
			if (c.node === n) { return c; }
		}
		return null;
	};

	const fieldOf = (n: Node2D): Field | null => {
		for (const f of fields) {
			if (f.node === n) { return f; }
		}
		return null;
	};

	const focusable = (n: Node2D): boolean => {
		return clientOf(n) !== null || hasHandler(n, "onKeyDown") || hasHandler(n, "onKeyUp")
			|| hasHandler(n, "onFocus") || hasHandler(n, "onBlur");
	};

	const depth = (n: Node2D): int32 => {
		let d: int32 = 0;
		let p = parentOf(links, n);
		while (p !== null) {
			d = d + 1;
			p = parentOf(links, p as Node2D);
		}
		return d;
	};

	const contains = (n: Node2D, x: float32, y: float32): boolean => {
		const wx = worldX(links, n);
		const wy = worldY(links, n);
		return x >= wx && x <= wx + n.w && y >= wy && y <= wy + n.h;
	};

	const showField = (f: Field, v: TextEditingValue): void => {
		f.label.text = v.text;
		f.caret.x = measure(f.label.size, v.text.substring(0, v.selection.end));
		f.caret.h = f.label.size * LINE_HEIGHT;
		f.caret.visible = windowFocused && focusedNode === f.node;
	};

	const setValue = (c: ClientEntry, v: TextEditingValue): void => {
		c.value = v;
		c.client.updateEditingValue(v);
		markDirty();
	};

	const focus = (n: Node2D | null): void => {
		if (n === focusedNode) { return; }
		const old = focusedNode;
		focusedNode = n;
		if (old !== null) {
			fire(old as Node2D, "onBlur", neonEvent("blur"));
			const of = fieldOf(old as Node2D);
			if (of !== null) { (of as Field).caret.visible = false; }
		}
		if (n !== null) {
			fire(n as Node2D, "onFocus", neonEvent("focus"));
			const nf = fieldOf(n as Node2D);
			if (nf !== null) { (nf as Field).caret.visible = windowFocused; }
		}
		markDirty();
	};

	const attachTextInput = (node: Node2D, client: TextInputClient, value: TextEditingValue): void => {
		if (clientOf(node) !== null) { throw "attachTextInput: this node already has a text input client"; }
		clients.push({ node, client, value });
	};

	const setEditingState = (node: Node2D, value: TextEditingValue): void => {
		const c = clientOf(node);
		if (c === null) { throw "setEditingState: this node has no text input client"; }
		setValue(c as ClientEntry, value);
	};

	const makeField = (): Node2D => {
		const node = group();
		const text = label("", TEXT_SIZE, { r: 1.0, g: 1.0, b: 1.0, a: 1.0 });
		const caret = rect(CARET_WIDTH, TEXT_SIZE * LINE_HEIGHT, { r: 1.0, g: 1.0, b: 1.0, a: 1.0 });
		caret.visible = false;
		node.addChild(text);
		node.addChild(caret);
		const f: Field = { node, label: text, caret, committed: "" };
		fields.push(f);
		attachTextInput(node, {
			updateEditingValue: (v: TextEditingValue): void => {
				showField(f, v);
				if (isEmptyRange(v.composing) && v.text !== f.committed) {
					f.committed = v.text;
					const e = neonEvent("changetext");
					e.value = v.text;
					fire(node, "onChangeText", e);
				}
			},
			caretRect: (): CaretRect => {
				return { x: f.caret.x, y: 0.0, w: CARET_WIDTH, h: f.label.size * LINE_HEIGHT };
			},
		}, editingValue(""));
		return node;
	};

	const editField = (f: Field, e: NeonEvent): void => {
		const c = clientOf(f.node) as ClientEntry;
		const v = c.value;
		if (e.key === "Backspace") { setValue(c, deleteBackward(v)); }
		else if (e.key === "Delete") { setValue(c, deleteForward(v)); }
		else if (e.key === "ArrowLeft") { setValue(c, moveCaret(v, v.selection.end - 1)); }
		else if (e.key === "ArrowRight") { setValue(c, moveCaret(v, v.selection.end + 1)); }
		else if (e.key === "Home") { setValue(c, moveCaret(v, 0)); }
		else if (e.key === "End") { setValue(c, moveCaret(v, v.text.length)); }
		else if (e.key === "Enter") {
			const s = neonEvent("submitediting");
			s.value = v.text;
			fire(f.node, "onSubmitEditing", s);
		}
	};

	const bubble = (name: string, e: NeonEvent): void => {
		let cur: Node2D | null = focusedNode;
		while (cur !== null) {
			fire(cur as Node2D, name, e);
			cur = parentOf(links, cur as Node2D);
		}
	};

	const host: Host = {
		createElement: (tag: string): HostNode => {
			if (tag === "textinput") { return makeField() as unknown as HostNode; }
			return group() as unknown as HostNode;
		},
		createText: (s: string): HostNode => {
			return label(s, TEXT_SIZE, { r: 1.0, g: 1.0, b: 1.0, a: 1.0 }) as unknown as HostNode;
		},
		setText: (node: HostNode, s: string): void => {
			(node as unknown as Node2D).text = s;
			markDirty();
		},
		setAttr: (node: HostNode, name: string, value: string): void => {
			const n = node as unknown as Node2D;
			if (name === "style") {
				n.layoutStyle = parseFlexStyle(value);
			} else if (name === "value") {
				const f = fieldOf(n);
				if (f !== null && (f as Field).committed !== value) {
					(f as Field).committed = value;
					setValue(clientOf(n) as ClientEntry, editingValue(value));
				}
			}
			markDirty();
		},
		removeAttr: (node: HostNode, name: string): void => {
			if (name === "style") {
				(node as unknown as Node2D).layoutStyle = parseFlexStyle("");
			}
			markDirty();
		},
		setStyle: (node: HostNode, style: Style): void => {
			const n = node as unknown as Node2D;
			n.layoutStyle = asFlexStyle(style);
			applyPaint(n, style);
			const f = fieldOf(n);
			if (f !== null) {
				applyPaint((f as Field).label, style);
				showField(f as Field, (clientOf(n) as ClientEntry).value);
			}
			markDirty();
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
			links.set(c, p);
			markDirty();
		},
		insertBefore: (parent: HostNode, node: HostNode, ref: HostNode | null): void => {
			const p = parent as unknown as Node2D;
			const n = node as unknown as Node2D;
			if (ref === null) {
				detachNode(links, n);
				p.addChild(n);
				links.set(n, p);
				markDirty();
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
			links.set(n, p);
			markDirty();
		},
		removeChild: (parent: HostNode, node: HostNode): void => {
			const p = parent as unknown as Node2D;
			const n = node as unknown as Node2D;
			if (childIndexOf(p, n) < 0) { throw "removeChild: the node is not a child of the parent"; }
			p.removeChild(n);
			links.delete(n);
			if (focusedNode !== null && !attached(focusedNode as Node2D)) { focus(null); }
			markDirty();
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
		voidArea: null,
	};

	const clickAt = (x: float32, y: float32): void => {
		let target: Node2D | null = null;
		let targetDepth: int32 = -1 as int32;
		for (const c of clients) {
			if (attached(c.node) && contains(c.node, x, y) && depth(c.node) > targetDepth) {
				target = c.node;
				targetDepth = depth(c.node);
			}
		}
		for (const e of events) {
			if (attached(e.node) && focusable(e.node) && contains(e.node, x, y) && depth(e.node) > targetDepth) {
				target = e.node;
				targetDepth = depth(e.node);
			}
		}
		focus(target);
		for (const e of events) {
			if (e.name !== "onPress" || !attached(e.node)) { continue; }
			if (contains(e.node, x, y)) {
				const ev = neonEvent(eventType(e.name));
				ev.x = x;
				ev.y = y;
				e.handler(ev);
			}
		}
	};

	const keyDown = (e: NeonEvent): void => {
		bubble("onKeyDown", e);
		if (focusedNode === null) { return; }
		const f = fieldOf(focusedNode as Node2D);
		if (f === null) { return; }
		const press = neonEvent("keypress");
		press.key = e.key;
		fire((f as Field).node, "onKeyPress", press);
		editField(f as Field, e);
	};

	const keyUp = (e: NeonEvent): void => {
		bubble("onKeyUp", e);
	};

	const commit = (text: string): void => {
		if (focusedNode === null) { return; }
		const c = clientOf(focusedNode as Node2D);
		if (c === null) { return; }
		setValue(c as ClientEntry, commitText((c as ClientEntry).value, text));
	};

	const compose = (text: string, cursor: number): void => {
		if (focusedNode === null) { return; }
		const c = clientOf(focusedNode as Node2D);
		if (c === null) { return; }
		setValue(c as ClientEntry, composeText((c as ClientEntry).value, text, cursor));
	};

	const setWindowFocus = (focused: boolean): void => {
		if (focused === windowFocused) { return; }
		windowFocused = focused;
		if (focusedNode === null) { return; }
		fire(focusedNode as Node2D, focused ? "onFocus" : "onBlur", neonEvent(focused ? "focus" : "blur"));
		const f = fieldOf(focusedNode as Node2D);
		if (f !== null) { (f as Field).caret.visible = focused; }
		markDirty();
	};

	const lastFrame = (n: Node2D): LaidOut | null => {
		for (const l of laidOut) {
			if (l.node === n) { return l; }
		}
		return null;
	};

	const layout = (w: float32, h: float32): void => {
		if (root.layoutStyle === null) { root.layoutStyle = {}; }
		layoutPass(root, w, h);
		for (const e of events) {
			if (e.name !== "onLayout" || !attached(e.node)) { continue; }
			const n = e.node;
			const last = lastFrame(n);
			if (last !== null && last.x === n.x && last.y === n.y && last.w === n.w && last.h === n.h) { continue; }
			if (last === null) { laidOut.push({ node: n, x: n.x, y: n.y, w: n.w, h: n.h }); }
			else { last.x = n.x; last.y = n.y; last.w = n.w; last.h = n.h; }
			const ev = neonEvent("layout");
			ev.x = n.x;
			ev.y = n.y;
			ev.width = n.w;
			ev.height = n.h;
			e.handler(ev);
		}
	};

	const imeRect = (): CaretRect | null => {
		if (focusedNode === null) { return null; }
		const n = focusedNode as Node2D;
		const c = clientOf(n);
		if (c === null) { return null; }
		const r = (c as ClientEntry).client.caretRect();
		return { x: worldX(links, n) + r.x, y: worldY(links, n) + r.y, w: r.w, h: r.h };
	};

	return {
		host, root, clickAt, keyDown, keyUp,
		commitText: commit, composeText: compose, setWindowFocus, layout,
		focus: (n: Node2D | null): void => { focus(n); },
		focused: (): Node2D | null => focusedNode,
		imeRect, attachTextInput, setEditingState,
		onDirty: (fn: () => void): void => { dirtyListener = fn; },
	};
}
