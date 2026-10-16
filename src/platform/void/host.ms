import { Host, HostNode } from "../../render/host";
import { NeonEvent, neonEvent, eventType } from "../../render/event";
import {
	Scene2D, NodeRef, DrawKind, group, label, mask, addChild, addChildAt, getChildIndex, dispose, kind,
	setPosition, setSize, setX, setZIndex, setAlpha, setColor, setBackground, clearBackground,
	setText, text as labelText, setFont, textStyle, setTextStyle, setCursorIndex, setCursorBlinkTime,
	local, content, scrollTo as scrollNodeTo, setScrollBounds, localToGlobal, globalToLocal,
	isLive, setTextRuns, setMaxWidth, setForceWidth,
} from "../../../../void/src/void2d/node";
import { TextRun } from "../../../../void/src/void2d/textLayout";
import { hitTest, xForIndex, lineBoxAt } from "../../../../void/src/void2d/render";
import { create, add, isDirty } from "../../../../void/src/void2d/scene";
import { Color, rgba, vec2 } from "../../../../void/src/void2d/types";
import { FontId, DEFAULT_FONT } from "../../../../void/src/void2d/font";
import { FlexStyle, YGNode, FlexDirection, Justify, Align, PositionType, Wrap, Display, Overflow, layoutPass, freeLayoutTree } from "../../../../yoga/src/index";
import { Style, mergeStyle } from "../../render/style";
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
	scroller: NodeRef | null = null;
	disposed: boolean = false;
	laid: Frame | null = null;
	style: Style | null = null;
	flex: FlexStyle | null = null;
	lastFlex: FlexStyle | null = null;
	yg: Ptr<YGNode> | null = null;
	focusAttr: boolean = false;
	imeBox: CaretRect | null = null;
	// RN nested Text: a Text inside a Text, and every string in one, is a span of the outermost Text,
	// which draws them all as one paragraph label; a span has no scene node of its own.
	isText: boolean = false;
	isString: boolean = false;
	chars: string = "";
	spanOwner: VoidNode | null = null;
	para: NodeRef | null = null;
	styledRuns: boolean = false;
	paraStale: boolean = false;
	cell: float32 = 0.0;

	constructor(ref: NodeRef) {
		this.ref = ref;
	}
}

function childHolder(n: VoidNode): NodeRef {
	const s = n.scroller;
	return s !== null ? s as NodeRef : n.ref;
}

const NO_CHILDREN: VoidNode[] = [];

export function layoutGetChildren(this n: VoidNode): VoidNode[] { return n.isText ? NO_CHILDREN : n.children; }
export function layoutGetStyle(this n: VoidNode): FlexStyle | null { return n.flex; }
export function layoutGetLastStyle(this n: VoidNode): FlexStyle | null { return n.lastFlex; }
export function layoutSetLastStyle(this n: VoidNode, s: FlexStyle | null): void { n.lastFlex = s; }
export function layoutGetYg(this n: VoidNode): Ptr<YGNode> | null { return n.yg; }
export function layoutSetYg(this n: VoidNode, yg: Ptr<YGNode> | null): void { n.yg = yg; }
export function layoutSetFrame(this n: VoidNode, x: float32, y: float32, w: float32, h: float32): void {
	n.ref.setPosition(x, y).setSize(w, h);
	const s = n.scroller;
	if (s !== null) { (s as NodeRef).setSize(w, h); }
}

export interface VoidHost {
	host: Host;
	root: HostNode;
	scene: Scene2D;
	clickAt: (x: float32, y: float32) => void;
	pointerDown: (x: float32, y: float32, button: int32) => void;
	pointerMove: (x: float32, y: float32, button: int32, pressed: boolean) => void;
	pointerUp: (x: float32, y: float32, button: int32) => void;
	wheel: (x: float32, y: float32, dx: float32, dy: float32) => void;
	textInput: (text: string) => void;
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
const FOCUS_HANDLERS = [
	"onKeyDown", "onKeyUp", "onFocus", "onBlur", "onTextInput", "onPreedit",
	"onPointerDown", "onPointerMove", "onPointerUp", "onWheel",
];
const CARET_WIDTH: float32 = 1.0;
const WHITE: Color = rgba(1.0, 1.0, 1.0, 1.0);
const CLEAR: Color = rgba(0.0, 0.0, 0.0, 0.0);

export interface CaretRect {
	x: float32;
	y: float32;
	w: float32;
	h: float32;
}

// "x,y,w,h" from the imeRect attribute; anything else is a bug in the producer, so it fails loud.
function parseCaretRect(s: string): CaretRect {
	const p = s.split(",");
	if (p.length !== 4) { throw new Error(`void host: imeRect "${s}" is not "x,y,width,height"`); }
	return { x: parseFloat(p[0]) as float32, y: parseFloat(p[1]) as float32, w: parseFloat(p[2]) as float32, h: parseFloat(p[3]) as float32 };
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

// RN's pointerEvents: "none" hides the node and its subtree, "box-none" only the node, "box-only" only its children.
function pointerMode(n: VoidNode): string {
	if (n.style === null) { return "auto"; }
	const m = (n.style as Style).pointerEvents;
	if (m === null) { return "auto"; }
	const mode = m as string;
	if (mode !== "auto" && mode !== "none" && mode !== "box-none" && mode !== "box-only") {
		throw new Error(`void host: pointerEvents "${mode}" is not auto, none, box-none or box-only`);
	}
	return mode;
}

function deepestAt(n: VoidNode, x: float32, y: float32, accepts: ((n: VoidNode) => boolean) | null): VoidNode | null {
	const mode = pointerMode(n);
	if (mode === "none") { return null; }
	if (mode !== "box-only" && !n.isText) {
		for (let i = n.children.length - 1; i >= 0; i -= 1) {
			const c = n.children[i];
			if (c.disposed) { continue; }
			const hit = deepestAt(c, x, y, accepts);
			if (hit !== null) { return hit; }
		}
	}
	if (mode === "box-none") { return null; }
	if (accepts !== null && !(accepts as (n: VoidNode) => boolean)(n)) { return null; }
	return n.ref.hitTest(vec2(x, y)) ? n : null;
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

function inheritTextPaint(child: VoidNode, parent: VoidNode): void {
	if (parent.style !== null && child.ref.kind() === DrawKind.Label) { applyTextPaint(child.ref, parent.style as Style); }
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

function inParagraph(p: VoidNode): boolean {
	return p.isText || p.spanOwner !== null;
}

function paragraphOf(n: VoidNode): VoidNode {
	return n.spanOwner !== null ? n.spanOwner as VoidNode : n;
}

function colorOr(css: string | null, fallback: Color): Color {
	if (css === null) { return fallback; }
	const c = parseColor(css as string);
	return c !== null ? c as Color : fallback;
}

interface Piece {
	text: string;
	style: Style;
	own: boolean;
}

function collectPieces(n: VoidNode, style: Style, own: boolean, out: Piece[]): void {
	for (const c of n.children) {
		if (c.isString) {
			if (c.chars !== "") { out.push({ text: c.chars, style, own }); }
		} else {
			const s = c.style;
			collectPieces(c, s === null ? style : mergeStyle(style, s as Style), own || s !== null, out);
		}
	}
}

function lineColor(s: Style, line: string, color: Color): Color {
	const d = s.textDecorationLine;
	return d !== null && (d as string).indexOf(line) >= 0 ? color : CLEAR;
}

function runOf(piece: Piece, font: FontId, base: Color): TextRun {
	const s = piece.style;
	const color = colorOr(s.color, base);
	return {
		len: piece.text.length as int32, font, color, background: colorOr(s.backgroundColor, CLEAR),
		underline: lineColor(s, "underline", color), wavy: false, strikethrough: lineColor(s, "line-through", color),
	};
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
		if (clientOf(n) !== null || n.focusAttr) { return true; }
		for (const name of FOCUS_HANDLERS) {
			if (hasHandler(n, name)) { return true; }
		}
		return false;
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
			if ((n as VoidNode).imeBox !== null && dirtyListener !== null) { (dirtyListener as () => void)(); }
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

	const textLabel = (s: string): NodeRef => {
		const l = scene.label(s, TEXT_SIZE, WHITE);
		l.setFont(font);
		return l;
	};

	// The handle a string holds until it draws on its own: a freed row, so any use of it fails loud.
	const undrawn: NodeRef = scene.group();
	undrawn.dispose();

	const drawn = (n: VoidNode): void => {
		if (!n.ref.isLive()) {
			n.ref = n.isString ? textLabel(n.chars) : scene.group();
			if (n.style !== null && !n.isString) { applyPaint(n, n.style as Style); }
		}
	};

	// The strings of a Text with no nested Text, joined; null when a span needs runs.
	const plainText = (root: VoidNode): string | null => {
		let text = "";
		for (const c of root.children) {
			if (!c.isString) { return null; }
			text += c.chars;
		}
		return text;
	};

	const waiting: VoidNode[] = [];

	// One label per outermost Text: its strings in order, a run per piece once any span styles one.
	const refreshParagraph = (root: VoidNode): void => {
		if (root.disposed) { return; }
		if (!attached(root)) {
			if (!root.paraStale) {
				root.paraStale = true;
				waiting.push(root);
			}
			return;
		}
		root.paraStale = false;
		const base: Style = root.style !== null ? root.style as Style : {};
		const plain = plainText(root);
		const pieces: Piece[] = [];
		let text = "";
		let styled = false;
		if (plain !== null) {
			text = plain as string;
		} else {
			collectPieces(root, base, false, pieces);
			for (const piece of pieces) {
				text += piece.text;
				if (piece.own) { styled = true; }
			}
		}
		if (root.para === null) {
			const made = textLabel("");
			if (root.cell > 0.0) { made.setForceWidth(root.cell); }
			root.ref.addChild(made);
			root.para = made;
		}
		const label = root.para as NodeRef;
		if (base.fontSize !== null && label.textStyle().size !== base.fontSize as float32) {
			label.setTextStyle({ ...label.textStyle(), size: base.fontSize as float32 });
		}
		const baseColor = colorOr(base.color, WHITE);
		label.setText(text);
		if (styled) {
			const runs: TextRun[] = [];
			for (const piece of pieces) {
				if (piece.style.fontSize !== base.fontSize) {
					throw new Error("void host: a Text inside a Text changes fontSize, and a Void paragraph has one size; set fontSize on the outer Text");
				}
				runs.push(runOf(piece, font, baseColor));
			}
			label.setColor(WHITE);
			label.setTextRuns(runs);
			root.styledRuns = true;
		} else {
			if (root.styledRuns) {
				const none: TextRun[] = [];
				label.setTextRuns(none);
				root.styledRuns = false;
			}
			label.setColor(baseColor);
		}
	};

	const refreshWaiting = (): void => {
		for (let i = waiting.length - 1; i >= 0; i -= 1) {
			const n = waiting[i];
			if (n.disposed || !n.paraStale || n.spanOwner !== null) {
				waiting.splice(i, 1);
			} else if (attached(n)) {
				waiting.splice(i, 1);
				refreshParagraph(n);
			}
		}
	};

	const adopt = (n: VoidNode, root: VoidNode): void => {
		if (!n.isString && !n.isText) {
			throw new Error("void host: a View inside a Text is an inline view, which the Void host does not place yet; put it beside the Text");
		}
		if (n.isText && n.cell > 0.0) { throw new Error("void host: cellWidth belongs on the outermost Text"); }
		if (n.isText && hasHandler(n, "onPress")) {
			throw new Error("void host: onPress on a Text inside a Text needs per-span hit-testing, which the Void host does not do yet");
		}
		n.spanOwner = root;
		if (n.para !== null) {
			(n.para as NodeRef).dispose();
			n.para = null;
			n.styledRuns = false;
		}
		if (n.ref.isLive()) { n.ref.dispose(); }
		for (const c of n.children) { adopt(c, root); }
	};

	// A span moved out of every Text draws on its own again.
	const unadopt = (n: VoidNode): void => {
		n.spanOwner = null;
		drawn(n);
		if (n.isText) {
			for (const c of n.children) { adopt(c, n); }
			refreshParagraph(n);
		}
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

	const free = (n: VoidNode): void => {
		if (focusedNode !== null && within(focusedNode as VoidNode, n)) { focus(null); }
		freeLayoutTree(n);
		if (n.ref.isLive()) { n.ref.dispose(); }
		release(n);
	};

	const host: Host = {
		createElement: (tag: string): HostNode => {
			const was = wasDirty();
			let n: VoidNode;
			if (tag === "textinput") {
				n = makeField();
			} else if (tag === "scrollview") {
				n = new VoidNode(scene.group());
				const m = scene.mask(0.0, 0.0);
				n.ref.addChild(m);
				n.scroller = m;
				scrollers.push(n);
			} else {
				n = new VoidNode(scene.group());
				if (tag === "text") {
					n.isText = true;
					n.flex = {};
				}
			}
			woke(was);
			return n;
		},
		createText: (s: string): HostNode => {
			const n = new VoidNode(undrawn);
			n.isString = true;
			n.chars = s;
			return n;
		},
		setText: (node: HostNode, s: string): void => {
			const n = live(node, "setText");
			const was = wasDirty();
			n.chars = s;
			if (n.spanOwner !== null) { refreshParagraph(n.spanOwner as VoidNode); }
			else if (n.ref.isLive()) { n.ref.setText(s); }
			woke(was);
		},
		setAttr: (node: HostNode, name: string, value: string): void => {
			const n = live(node, "setAttr");
			const was = wasDirty();
			if (name === "style") {
				n.flex = parseFlexStyle(value);
			} else if (name === "focusable") {
				n.focusAttr = value === "true";
			} else if (name === "cellWidth") {
				if (!n.isText || n.spanOwner !== null) { throw new Error("void host: cellWidth belongs on the outermost Text"); }
				const cell = parseFloat(value) as float32;
				if (!(cell >= 0.0)) { throw new Error(`void host: cellWidth "${value}" is not zero or more points`); }
				n.cell = cell;
				if (n.para !== null) { (n.para as NodeRef).setForceWidth(cell); }
			} else if (name === "imeRect") {
				n.imeBox = parseCaretRect(value);
				if (focusedNode === n && dirtyListener !== null) { (dirtyListener as () => void)(); }
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
			else if (name === "focusable") { n.focusAttr = false; }
			else if (name === "imeRect") { n.imeBox = null; }
			else if (name === "cellWidth") {
				n.cell = 0.0;
				if (n.para !== null) { (n.para as NodeRef).setForceWidth(0.0); }
			}
		},
		setStyle: (node: HostNode, style: Style): void => {
			const n = live(node, "setStyle");
			const was = wasDirty();
			n.flex = asFlexStyle(style);
			n.style = style;
			if (n.spanOwner !== null) {
				refreshParagraph(n.spanOwner as VoidNode);
				woke(was);
				return;
			}
			applyPaint(n, style);
			if (n.isText) { refreshParagraph(n); }
			else { for (const c of n.children) { inheritTextPaint(c, n); } }
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
			const old = c.spanOwner;
			unlink(c, p);
			c.parent = p;
			p.children.push(c);
			if (inParagraph(p)) {
				adopt(c, paragraphOf(p));
				refreshParagraph(paragraphOf(p));
			} else {
				if (old !== null) { unadopt(c); } else { drawn(c); }
				childHolder(p).addChild(c.ref);
				inheritTextPaint(c, p);
				if (waiting.length > 0) { refreshWaiting(); }
			}
			if (old !== null && old !== c.spanOwner) { refreshParagraph(old as VoidNode); }
			woke(was);
		},
		insertBefore: (parent: HostNode, node: HostNode, before: HostNode | null): void => {
			const p = live(parent, "insertBefore");
			const n = live(node, "insertBefore");
			refuseCycle(p, n, "insertBefore");
			const was = wasDirty();
			const old = n.spanOwner;
			if (inParagraph(p)) {
				const cur = p.children.indexOf(n);
				if (cur >= 0) { p.children.splice(cur, 1); } else { unlink(n, p); }
				const idx = before === null ? p.children.length : p.children.indexOf(live(before, "insertBefore"));
				if (idx < 0) { throw new Error("insertBefore: the reference node is not a child of the parent"); }
				p.children.splice(idx, 0, n);
				n.parent = p;
				adopt(n, paragraphOf(p));
				refreshParagraph(paragraphOf(p));
				if (old !== null && old !== n.spanOwner) { refreshParagraph(old as VoidNode); }
				woke(was);
				return;
			}
			if (old !== null) { unadopt(n); } else { drawn(n); }
			if (before === null) {
				unlink(n, p);
				childHolder(p).addChild(n.ref);
				n.parent = p;
				p.children.push(n);
				inheritTextPaint(n, p);
				if (waiting.length > 0) { refreshWaiting(); }
				if (old !== null) { refreshParagraph(old as VoidNode); }
				woke(was);
				return;
			}
			const r = live(before, "insertBefore");
			let idx = p.children.indexOf(r);
			if (idx < 0) { throw new Error("insertBefore: the reference node is not a child of the parent"); }
			let at = childHolder(p).getChildIndex(r.ref);
			const cur = p.children.indexOf(n);
			const voidCur = childHolder(p).getChildIndex(n.ref);
			if (cur >= 0) {
				p.children.splice(cur, 1);
				if (cur < idx) { idx = idx - 1; }
				if (voidCur >= 0 && voidCur < at) { at = at - 1; }
			} else {
				unlink(n, p);
			}
			childHolder(p).addChildAt(n.ref, at);
			n.parent = p;
			p.children.splice(idx, 0, n);
			inheritTextPaint(n, p);
			if (waiting.length > 0) { refreshWaiting(); }
			if (old !== null) { refreshParagraph(old as VoidNode); }
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
			free(n);
			if (inParagraph(p)) { refreshParagraph(paragraphOf(p)); }
			woke(was);
		},
		parentOf: (node: HostNode): HostNode | null => {
			const p = live(node, "parentOf").parent;
			if (p === null) { return null; }
			return p as HostNode;
		},
		release: (node: HostNode): void => {
			const n = live(node, "release");
			if (n.parent !== null) { throw new Error("release: the node still has a parent; remove it first"); }
			const was = wasDirty();
			free(n);
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
			const m = n.scroller;
			if (m === null) { throw new Error("void host: scrollTo needs a scroll view, and this node is not one"); }
			const was = wasDirty();
			(m as NodeRef).scrollNodeTo(x as float32, y as float32);
			woke(was);
		},
	};

	const clickAt = (x: float32, y: float32): void => {
		const target = deepestAt(root, x, y, focusable);
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

	const anyHandler = (name: string): boolean => {
		for (const entry of events) {
			if (entry.name === name && !entry.node.disposed && attached(entry.node)) { return true; }
		}
		return false;
	};

	// Bubbles from the deepest node under the point; locationX/Y are relative to that target.
	const pointerAt = (name: string, x: float32, y: float32, ev: NeonEvent): void => {
		if (!anyHandler(name)) { return; }
		const target = deepestAt(root, x, y, null);
		if (target === null) { return; }
		const at = (target as VoidNode).ref.globalToLocal(vec2(x, y));
		ev.locationX = at.x;
		ev.locationY = at.y;
		let cur: VoidNode | null = target;
		while (cur !== null) {
			const n = cur as VoidNode;
			if (!n.disposed) { fire(n, name, ev); }
			cur = n.parent;
		}
	};

	const pointerEvent = (type: string, x: float32, y: float32, button: int32, pressed: boolean): NeonEvent => {
		const ev = neonEvent(type);
		ev.x = x;
		ev.y = y;
		ev.button = button;
		ev.pressed = pressed;
		return ev;
	};

	const pointerDown = (x: float32, y: float32, button: int32): void => {
		pointerAt("onPointerDown", x, y, pointerEvent("pointerdown", x, y, button, true));
	};

	const pointerMove = (x: float32, y: float32, button: int32, pressed: boolean): void => {
		pointerAt("onPointerMove", x, y, pointerEvent("pointermove", x, y, button, pressed));
	};

	const pointerUp = (x: float32, y: float32, button: int32): void => {
		pointerAt("onPointerUp", x, y, pointerEvent("pointerup", x, y, button, false));
	};

	const wheel = (x: float32, y: float32, dx: float32, dy: float32): void => {
		const ev = pointerEvent("wheel", x, y, 0 as int32, false);
		ev.deltaX = dx;
		ev.deltaY = dy;
		pointerAt("onWheel", x, y, ev);
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
		if (c === null) {
			const ev = neonEvent("preedit");
			ev.text = s;
			ev.cursor = cursor;
			bubble("onPreedit", ev);
			return;
		}
		setValue(c as ClientEntry, composeText((c as ClientEntry).value, s, cursor));
	};

	// Text the window delivers on its own (an IME commit): a text input client edits, any other focused node hears onTextInput.
	// A typed key's text reaches a client through commitText and a handler through the key event's `text`, so no key is heard twice.
	const textInput = (s: string): void => {
		if (focusedNode === null) { return; }
		if (clientOf(focusedNode as VoidNode) !== null) {
			commit(s);
			return;
		}
		const ev = neonEvent("textinput");
		ev.text = s;
		bubble("onTextInput", ev);
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
		if (n.isText) {
			const w = n.ref.content().w;
			if (n.para !== null && w > 0.0) { (n.para as NodeRef).setMaxWidth(w); }
			return;
		}
		let x: float32 = 0.0;
		for (const c of n.children) {
			if (c.ref.kind() === DrawKind.Label && c.flex === null) {
				c.ref.setX(x);
				x = x + c.ref.xForIndex(c.ref.labelText().length as int32);
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
			(n.scroller as NodeRef).setScrollBounds({ xMin: 0.0, yMin: 0.0, xMax: right, yMax: bottom });
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
		if (c === null) {
			if (n.imeBox === null) { return null; }
			const box = n.imeBox as CaretRect;
			const at = n.ref.localToGlobal(vec2(box.x, box.y));
			return { x: at.x, y: at.y, w: box.w, h: box.h };
		}
		const r = (c as ClientEntry).client.caretRect();
		const at = n.ref.localToGlobal(vec2(r.x, r.y));
		return { x: at.x, y: at.y, w: r.w, h: r.h };
	};

	return {
		host, root, scene, clickAt, pointerDown, pointerMove, pointerUp, wheel, textInput, keyDown, keyUp,
		commitText: commit, composeText: compose, setWindowFocus, layout,
		focus: (n: VoidNode | null): void => { focus(n); },
		focused: (): VoidNode | null => focusedNode,
		imeRect, attachTextInput, setEditingState,
		onDirty: (fn: () => void): void => { dirtyListener = fn; },
	};
}
