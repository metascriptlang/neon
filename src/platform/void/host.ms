import { Host, HostNode } from "../../render/host";
import { NeonEvent, neonEvent, eventType } from "../../render/event";
import {
	Scene2D, NodeRef, DrawKind, group, label, mask, addChild, addChildAt, getChildIndex, dispose, kind,
	setPosition, setSize, setX, setZIndex, setAlpha, setColor, setBackground, clearBackground,
	setText, setFont, textStyle, setTextStyle, setCursorIndex, setCursorBlinkTime,
	local, content, scrollTo as scrollNodeTo, setScrollBounds, localToGlobal,
} from "../../../../void/src/void2d/node";
import { hitTest, textWidth, xForIndex, lineBoxAt } from "../../../../void/src/void2d/render";
import { create, add, isDirty } from "../../../../void/src/void2d/scene";
import { Color, rgba, vec2 } from "../../../../void/src/void2d/types";
import { FontId, DEFAULT_FONT } from "../../../../void/src/void2d/font";
import { FlexStyle, YGNode, FlexDirection, Justify, Align, PositionType, Wrap, Display, Overflow, layoutPass, freeLayoutTree } from "../../../../yoga/src/index";
import { Style } from "../../render/style";
import { asFlexStyleBody } from "../../macros/style/fields";
import {
	TextEditingValue, editingValue, isEmptyRange,
	commitText, composeText, deleteBackward, deleteForward, moveCaret,
} from "./editing";

export { layoutPass, freeLayoutTree } from "../../../../yoga/src/index";
export { DrawKind } from "../../../../void/src/void2d/node";
export { TextEditingValue, TextRange, editingValue, textRange, noRange } from "./editing";

interface EventEntry {
	node: VoidNode;
	name: string;
	handler: (e: NeonEvent) => void;
}

struct Frame {
	x: float32;
	y: float32;
	w: float32;
	h: float32;
}

export class VoidNode {
	ref: NodeRef;
	parent: VoidNode | null = null;
	children: VoidNode[] = [];
	scrolls: boolean = false;
	disposed: boolean = false;
	laid: Frame | null = null;
	flex: FlexStyle | null = null;
	lastFlex: FlexStyle | null = null;
	yg: Ptr<YGNode> | null = null;

	constructor(ref: NodeRef) {
		this.ref = ref;
	}
}

export function layoutGetChildren(this n: VoidNode): VoidNode[] { return n.children; }
export function layoutGetStyle(this n: VoidNode): FlexStyle | null { return n.flex; }
export function layoutGetLastStyle(this n: VoidNode): FlexStyle | null { return n.lastFlex; }
export function layoutSetLastStyle(this n: VoidNode, s: FlexStyle | null): void { n.lastFlex = s; }
export function layoutGetYg(this n: VoidNode): Ptr<YGNode> | null { return n.yg; }
export function layoutSetYg(this n: VoidNode, yg: Ptr<YGNode> | null): void { n.yg = yg; }
export function layoutSetFrame(this n: VoidNode, x: float32, y: float32, w: float32, h: float32): void {
	n.ref.setPosition(x, y).setSize(w, h);
}

export interface VoidHost {
	host: Host;
	root: HostNode;
	scene: Scene2D;
	clickAt: (x: float32, y: float32) => void;
	keyDown: (e: NeonEvent) => void;
	keyUp: (e: NeonEvent) => void;
	commitText: (text: string) => void;
	composeText: (text: string, cursor: int32) => void;
	setWindowFocus: (focused: boolean) => void;
	layout: (width: float32, height: float32) => void;
	focus: (node: VoidNode | null) => void;
	focused: () => VoidNode | null;
	imeRect: () => CaretRect | null;
	attachTextInput: (node: VoidNode, client: TextInputClient, value: TextEditingValue) => void;
	setEditingState: (node: VoidNode, value: TextEditingValue) => void;
	onDirty: (fn: () => void) => void;
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
const TEXT_SIZE: float32 = 16.0;
const CARET_WIDTH: float32 = 1.0;
const WHITE: Color = rgba(1.0, 1.0, 1.0, 1.0);

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
	node: VoidNode;
	client: TextInputClient;
	value: TextEditingValue;
}

interface Field {
	node: VoidNode;
	label: NodeRef;
	committed: string;
	caret: int32;
}

function live(node: HostNode, op: string): VoidNode {
	const n = node as VoidNode;
	if (n.disposed) { throw new Error(`void host: ${op} on a node that was removed and freed`); }
	return n;
}

function within(node: VoidNode, top: VoidNode): boolean {
	let cur: VoidNode | null = node;
	while (cur !== null) {
		if (cur === top) { return true; }
		cur = (cur as VoidNode).parent;
	}
	return false;
}

function markDisposed(n: VoidNode): void {
	n.disposed = true;
	for (const c of n.children) { markDisposed(c); }
}

function applyTextPaint(label: NodeRef, s: Style): void {
	if (s.fontSize !== null) { label.setTextStyle({ ...label.textStyle(), size: s.fontSize as float32 }); }
	if (s.color !== null) {
		const c = parseColor(s.color as string);
		if (c !== null) { label.setColor(c); }
	}
}

export function applyPaint(n: VoidNode, s: Style): void {
	const ref = n.ref;
	if (s.opacity !== null) { ref.setAlpha(s.opacity as float32); }
	if (s.zIndex !== null) { const z = s.zIndex as number; ref.setZIndex(z as int32); }
	const k = ref.kind();
	if (k === DrawKind.Label) { applyTextPaint(ref, s); }
	const bg = s.backgroundColor;
	if (bg !== null) {
		const c = parseColor(bg as string);
		if (c !== null) {
			if (k !== DrawKind.Group && k !== DrawKind.Rect) { throw new Error(`void host: backgroundColor on a ${k.toString()} node; Void paints a background on a plain view only`); }
			ref.setBackground(c);
		}
	} else if (k === DrawKind.Rect) {
		ref.clearBackground();
	}
}

export function createVoidHost(): VoidHost {
	return createVoidHostWith(Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0)), DEFAULT_FONT);
}

export function createVoidHostWith(scene: Scene2D, font: FontId): VoidHost {
	const events: EventEntry[] = [];
	const clients: ClientEntry[] = [];
	const fields: Field[] = [];
	const scrollers: VoidNode[] = [];
	const root = new VoidNode(scene.group());
	root.flex = {};
	scene.add(root.ref);
	let focusedNode: VoidNode | null = null;
	let windowFocused = true;
	let dirtyListener: (() => void) | null = null;

	let signaled = false;

	const wasDirty = (): boolean => {
		const dirty = scene.isDirty();
		if (!dirty) { signaled = false; }
		return dirty;
	};

	const woke = (was: boolean): void => {
		if (was || signaled || dirtyListener === null) { return; }
		if (scene.isDirty()) {
			signaled = true;
			(dirtyListener as () => void)();
		}
	};

	const attached = (n: VoidNode): boolean => within(n, root);

	const fire = (n: VoidNode, name: string, e: NeonEvent): boolean => {
		let hit = false;
		for (const entry of events) {
			if (entry.node === n && entry.name === name) {
				entry.handler(e);
				hit = true;
			}
		}
		return hit;
	};

	const hasHandler = (n: VoidNode, name: string): boolean => {
		for (const entry of events) {
			if (entry.node === n && entry.name === name) { return true; }
		}
		return false;
	};

	const clientOf = (n: VoidNode): ClientEntry | null => {
		for (const c of clients) {
			if (c.node === n) { return c; }
		}
		return null;
	};

	const fieldOf = (n: VoidNode): Field | null => {
		for (const f of fields) {
			if (f.node === n) { return f; }
		}
		return null;
	};

	const focusable = (n: VoidNode): boolean => {
		return clientOf(n) !== null || hasHandler(n, "onKeyDown") || hasHandler(n, "onKeyUp")
			|| hasHandler(n, "onFocus") || hasHandler(n, "onBlur");
	};

	const depth = (n: VoidNode): int32 => {
		let d: int32 = 0;
		let p = n.parent;
		while (p !== null) {
			d = d + 1;
			p = (p as VoidNode).parent;
		}
		return d;
	};

	const contains = (n: VoidNode, x: float32, y: float32): boolean => {
		return n.ref.hitTest(vec2(x, y));
	};

	const showField = (f: Field, v: TextEditingValue): void => {
		f.label.setText(v.text);
		f.caret = v.selection.end;
		f.label.setCursorIndex(windowFocused && focusedNode === f.node ? f.caret : -1, WHITE);
	};

	const hideCaret = (f: Field): void => {
		f.label.setCursorIndex(-1, WHITE);
	};

	const setValue = (c: ClientEntry, v: TextEditingValue): void => {
		const was = wasDirty();
		c.value = v;
		c.client.updateEditingValue(v);
		woke(was);
	};

	const focus = (n: VoidNode | null): void => {
		if (n === focusedNode) { return; }
		const was = wasDirty();
		const old = focusedNode;
		focusedNode = n;
		if (old !== null) {
			fire(old as VoidNode, "onBlur", neonEvent("blur"));
			const of = fieldOf(old as VoidNode);
			if (of !== null) { hideCaret(of as Field); }
		}
		if (n !== null) {
			fire(n as VoidNode, "onFocus", neonEvent("focus"));
			const nf = fieldOf(n as VoidNode);
			if (nf !== null && windowFocused) { (nf as Field).label.setCursorIndex((nf as Field).caret, WHITE); }
		}
		woke(was);
	};

	const attachTextInput = (node: VoidNode, client: TextInputClient, value: TextEditingValue): void => {
		if (clientOf(node) !== null) { throw new Error("attachTextInput: this node already has a text input client"); }
		clients.push({ node, client, value });
	};

	const setEditingState = (node: VoidNode, value: TextEditingValue): void => {
		const c = clientOf(node);
		if (c === null) { throw new Error("setEditingState: this node has no text input client"); }
		setValue(c as ClientEntry, value);
	};

	const makeField = (): VoidNode => {
		const node = new VoidNode(scene.group());
		const inner = scene.label("", TEXT_SIZE, WHITE);
		inner.setFont(font);
		inner.setCursorBlinkTime(0.0);
		inner.setCursorIndex(-1, WHITE);
		node.ref.addChild(inner);
		const f: Field = { node, label: inner, committed: "", caret: 0 };
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
				const box = f.label.lineBoxAt(f.caret);
				return { x: f.label.xForIndex(f.caret), y: box.top, w: CARET_WIDTH, h: box.height };
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
		let cur: VoidNode | null = focusedNode;
		while (cur !== null) {
			fire(cur as VoidNode, name, e);
			cur = (cur as VoidNode).parent;
		}
	};

	const unlink = (c: VoidNode, into: VoidNode): void => {
		const old = c.parent;
		if (old === null) { return; }
		const from = old as VoidNode;
		const at = from.children.indexOf(c);
		if (at >= 0) { from.children.splice(at, 1); }
		if (from !== into) { freeLayoutTree(c); }
	};

	const refuseCycle = (p: VoidNode, c: VoidNode, op: string): void => {
		if (within(p, c)) { throw new Error(`${op}: a node cannot be placed inside itself or its own descendant`); }
	};

	const release = (n: VoidNode): void => {
		markDisposed(n);
		for (let i = events.length - 1; i >= 0; i -= 1) {
			if (events[i].node.disposed) { events.splice(i, 1); }
		}
		for (let i = clients.length - 1; i >= 0; i -= 1) {
			if (clients[i].node.disposed) { clients.splice(i, 1); }
		}
		for (let i = fields.length - 1; i >= 0; i -= 1) {
			if (fields[i].node.disposed) { fields.splice(i, 1); }
		}
		for (let i = scrollers.length - 1; i >= 0; i -= 1) {
			if (scrollers[i].disposed) { scrollers.splice(i, 1); }
		}
	};

	const host: Host = {
		createElement: (tag: string): HostNode => {
			const was = wasDirty();
			let n: VoidNode;
			if (tag === "textinput") {
				n = makeField();
			} else if (tag === "scrollview") {
				n = new VoidNode(scene.mask(0.0, 0.0));
				n.scrolls = true;
				scrollers.push(n);
			} else {
				n = new VoidNode(scene.group());
			}
			woke(was);
			return n;
		},
		createText: (s: string): HostNode => {
			const was = wasDirty();
			const l = scene.label(s, TEXT_SIZE, WHITE);
			l.setFont(font);
			woke(was);
			return new VoidNode(l);
		},
		setText: (node: HostNode, s: string): void => {
			const n = live(node, "setText");
			const was = wasDirty();
			n.ref.setText(s);
			woke(was);
		},
		setAttr: (node: HostNode, name: string, value: string): void => {
			const n = live(node, "setAttr");
			const was = wasDirty();
			if (name === "style") {
				n.flex = parseFlexStyle(value);
			} else if (name === "value") {
				const f = fieldOf(n);
				if (f !== null && (f as Field).committed !== value) {
					(f as Field).committed = value;
					setValue(clientOf(n) as ClientEntry, editingValue(value));
				}
			}
			woke(was);
		},
		removeAttr: (node: HostNode, name: string): void => {
			const n = live(node, "removeAttr");
			if (name === "style") { n.flex = parseFlexStyle(""); }
		},
		setStyle: (node: HostNode, style: Style): void => {
			const n = live(node, "setStyle");
			const was = wasDirty();
			n.flex = asFlexStyle(style);
			applyPaint(n, style);
			const f = fieldOf(n);
			if (f !== null) {
				applyTextPaint((f as Field).label, style);
				showField(f as Field, (clientOf(n) as ClientEntry).value);
			}
			woke(was);
		},
		setStyleProp: null,
		setStyleClass: null,
		addEvent: (node: HostNode, name: string, handler: (e: NeonEvent) => void): void => {
			events.push({ node: live(node, "addEvent"), name, handler });
		},
		append: (parent: HostNode, child: HostNode): void => {
			const p = live(parent, "append");
			const c = live(child, "append");
			refuseCycle(p, c, "append");
			const was = wasDirty();
			unlink(c, p);
			p.ref.addChild(c.ref);
			c.parent = p;
			p.children.push(c);
			woke(was);
		},
		insertBefore: (parent: HostNode, node: HostNode, before: HostNode | null): void => {
			const p = live(parent, "insertBefore");
			const n = live(node, "insertBefore");
			refuseCycle(p, n, "insertBefore");
			const was = wasDirty();
			if (before === null) {
				unlink(n, p);
				p.ref.addChild(n.ref);
				n.parent = p;
				p.children.push(n);
				woke(was);
				return;
			}
			const r = live(before, "insertBefore");
			let idx = p.children.indexOf(r);
			if (idx < 0) { throw new Error("insertBefore: the reference node is not a child of the parent"); }
			let at = p.ref.getChildIndex(r.ref);
			const cur = p.children.indexOf(n);
			const voidCur = p.ref.getChildIndex(n.ref);
			if (cur >= 0) {
				p.children.splice(cur, 1);
				if (cur < idx) { idx = idx - 1; }
				if (voidCur >= 0 && voidCur < at) { at = at - 1; }
			} else {
				unlink(n, p);
			}
			p.ref.addChildAt(n.ref, at);
			n.parent = p;
			p.children.splice(idx, 0, n);
			woke(was);
		},
		removeChild: (parent: HostNode, node: HostNode): void => {
			const p = live(parent, "removeChild");
			const n = live(node, "removeChild");
			const idx = p.children.indexOf(n);
			if (idx < 0) { throw new Error("removeChild: the node is not a child of the parent"); }
			const was = wasDirty();
			p.children.splice(idx, 1);
			n.parent = null;
			if (focusedNode !== null && within(focusedNode as VoidNode, n)) { focus(null); }
			freeLayoutTree(n);
			n.ref.dispose();
			release(n);
			woke(was);
		},
		nextSibling: (node: HostNode): HostNode | null => {
			const n = live(node, "nextSibling");
			const p = n.parent;
			if (p === null) { return null; }
			const sibs = (p as VoidNode).children;
			const idx = sibs.indexOf(n);
			if (idx < 0 || idx + 1 >= sibs.length) { return null; }
			return sibs[idx + 1];
		},
		firstChild: (node: HostNode): HostNode | null => {
			const n = live(node, "firstChild");
			if (n.children.length === 0) { return null; }
			return n.children[0];
		},
		cloneNode: null,
		voidArea: null,
		scrollTo: (node: HostNode, x: number, y: number, animated: boolean): void => {
			const n = live(node, "scrollTo");
			if (!n.scrolls) { throw new Error("void host: scrollTo needs a scroll view, and this node is not one"); }
			const was = wasDirty();
			n.ref.scrollNodeTo(x as float32, y as float32);
			woke(was);
		},
	};

	const clickAt = (x: float32, y: float32): void => {
		let target: VoidNode | null = null;
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
		for (const e of events.slice(0)) {
			if (e.name !== "onPress" || e.node.disposed || !attached(e.node)) { continue; }
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
		const f = fieldOf(focusedNode as VoidNode);
		if (f === null) { return; }
		const press = neonEvent("keypress");
		press.key = e.key;
		fire((f as Field).node, "onKeyPress", press);
		editField(f as Field, e);
	};

	const keyUp = (e: NeonEvent): void => {
		bubble("onKeyUp", e);
	};

	const commit = (s: string): void => {
		if (focusedNode === null) { return; }
		const c = clientOf(focusedNode as VoidNode);
		if (c === null) { return; }
		setValue(c as ClientEntry, commitText((c as ClientEntry).value, s));
	};

	const compose = (s: string, cursor: int32): void => {
		if (focusedNode === null) { return; }
		const c = clientOf(focusedNode as VoidNode);
		if (c === null) { return; }
		setValue(c as ClientEntry, composeText((c as ClientEntry).value, s, cursor));
	};

	const setWindowFocus = (focused: boolean): void => {
		if (focused === windowFocused) { return; }
		const was = wasDirty();
		windowFocused = focused;
		if (focusedNode === null) { return; }
		fire(focusedNode as VoidNode, focused ? "onFocus" : "onBlur", neonEvent(focused ? "focus" : "blur"));
		const f = fieldOf(focusedNode as VoidNode);
		if (f !== null) { (f as Field).label.setCursorIndex(focused ? (f as Field).caret : -1, WHITE); }
		woke(was);
	};

	const flowText = (n: VoidNode): void => {
		let x: float32 = 0.0;
		for (const c of n.children) {
			if (c.ref.kind() === DrawKind.Label && c.flex === null) {
				c.ref.setX(x);
				x = x + c.ref.textWidth();
			}
			flowText(c);
		}
	};

	const frameOf = (n: VoidNode): Frame => {
		const l = n.ref.local();
		const c = n.ref.content();
		return { x: l.x, y: l.y, w: c.w, h: c.h };
	};

	const fitScrollers = (): void => {
		for (const n of scrollers) {
			const own = frameOf(n);
			let right = own.w;
			let bottom = own.h;
			for (const c of n.children) {
				const f = frameOf(c);
				if (f.x + f.w > right) { right = f.x + f.w; }
				if (f.y + f.h > bottom) { bottom = f.y + f.h; }
			}
			n.ref.setScrollBounds({ xMin: 0.0, yMin: 0.0, xMax: right, yMax: bottom });
		}
	};

	const layout = (w: float32, h: float32): void => {
		layoutPass(root, w, h);
		flowText(root);
		fitScrollers();
		for (const e of events.slice(0)) {
			if (e.name !== "onLayout" || e.node.disposed || !attached(e.node)) { continue; }
			const n = e.node;
			const now = frameOf(n);
			const last = n.laid;
			if (last !== null && last.x === now.x && last.y === now.y && last.w === now.w && last.h === now.h) { continue; }
			n.laid = now;
			const ev = neonEvent("layout");
			ev.x = now.x;
			ev.y = now.y;
			ev.width = now.w;
			ev.height = now.h;
			e.handler(ev);
		}
	};

	const imeRect = (): CaretRect | null => {
		if (focusedNode === null) { return null; }
		const n = focusedNode as VoidNode;
		const c = clientOf(n);
		if (c === null) { return null; }
		const r = (c as ClientEntry).client.caretRect();
		const at = n.ref.localToGlobal(vec2(r.x, r.y));
		return { x: at.x, y: at.y, w: r.w, h: r.h };
	};

	return {
		host, root, scene, clickAt, keyDown, keyUp,
		commitText: commit, composeText: compose, setWindowFocus, layout,
		focus: (n: VoidNode | null): void => { focus(n); },
		focused: (): VoidNode | null => focusedNode,
		imeRect, attachTextInput, setEditingState,
		onDirty: (fn: () => void): void => { dirtyListener = fn; },
	};
}
