import { Host, HostNode, NeonNode } from "../../render/host";
import { Accessor } from "../../core/signal";
import { flush } from "../../core/runtime";
import { TextSpan, TextMeasure } from "../../render/hostTypes";
import { spanParagraph, spanText } from "../../render/spanHost";
import { NeonEvent, neonEvent, eventType } from "../../render/event";
import { AreaKeyMod, LayerAnchor, setEventMods } from "../../render/voidAreaHandle";
import {
	Scene2D, NodeRef, DrawKind, group, label, mask, addChild, addChildAt, getChildIndex, dispose, kind,
	setPosition, setSize, setX, setZIndex, setAlpha, setVisible, setColor, setBackground, clearBackground,
	setText, text as labelText, setFont, textStyle, setTextStyle, setCursorIndex, setCursorBlinkTime,
	local, content, scrollTo as scrollNodeTo, setScrollBounds, localToGlobal, globalToLocal,
	setTextRuns, setMaxWidth, setForceWidth, setBoxStyle, setLayerSlot, order,
} from "../../../../void/src/void2d/node";
import { TextRun, TextLayout, Align as TextAlign } from "../../../../void/src/void2d/textLayout";
import { BoxStyle, BoxShadow, uniformRadii, uniformBorders } from "../../../../void/src/void2d/boxStyle";
import { hitTest, xForIndex, lineBoxAt, indexAt } from "../../../../void/src/void2d/render";
import { create, add, isDirty, isClosed } from "../../../../void/src/void2d/scene";
import { Color, rgba, vec2 } from "../../../../void/src/void2d/types";
import { FontId, FontError, DEFAULT_FONT, FontStyle as FaceStyle, SizeAdjust, resolveFont } from "../../../../void/src/void2d/font";
import { FlexStyle, YGNode, PositionType, layoutPass, freeLayoutTree } from "../../../../yoga/src/index";
import { Style, FontWeight, PositionType as StylePositionType } from "../../render/style";
import { asFlexStyleBody } from "../../macros/style/fields";
import { DevNode } from "../../devtools/driver";
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
	raw: boolean;
	tag: string = "";
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
	// A Text draws its spans (src/render/spanHost.ms) as one paragraph label.
	isText: boolean = false;
	para: NodeRef | null = null;
	slot: NodeRef | null = null;
	styledRuns: boolean = false;
	paraStale: boolean = false;
	cell: float32 = 0.0;
	spans: TextSpan[] | null = null;
	boxed: boolean = false;

	constructor(ref: NodeRef, raw: boolean = false) {
		this.ref = ref;
		this.raw = raw;
	}
}

function childHolder(n: VoidNode): NodeRef {
	const s = n.scroller;
	return s !== null ? s as NodeRef : n.ref;
}

export function layoutGetChildren(this n: VoidNode): VoidNode[] { return n.children; }
export function layoutGetStyle(this n: VoidNode): FlexStyle | null {
	return n.raw ? null : n.flex;
}
export function layoutGetLastStyle(this n: VoidNode): FlexStyle | null { return n.lastFlex; }
export function layoutSetLastStyle(this n: VoidNode, s: FlexStyle | null): void { n.lastFlex = s; }
function freeNestedLayouts(n: VoidNode): void {
	for (const c of n.children) {
		freeNestedLayouts(c);
		if (n.raw && c.yg !== null) { freeLayoutTree(c); }
	}
}

export function freeVoidLayoutTree(n: VoidNode): void {
	// Yoga's recursive clear cannot retain pointers to independently owned nested islands.
	freeNestedLayouts(n);
	freeLayoutTree(n);
}

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
	pointerDown: (x: float32, y: float32, button: int32, mods?: number) => void;
	pointerMove: (x: float32, y: float32, button: int32, pressed: boolean, mods?: number) => void;
	pointerUp: (x: float32, y: float32, button: int32, mods?: number) => void;
	wheel: (x: float32, y: float32, dx: float32, dy: float32, mods?: number) => void;
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
	mutate: (body: () => void) => void;
	snapshot: () => DevNode;
	layerSlot: (anchor: LayerAnchor) => NodeRef | null;
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

const LAYOUT_PASSES = 8;

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

// "#rgb", "#rrggbb", "#rrggbbaa", rgb() and rgba() → normalized rgba. Returns null for anything else so
// the caller leaves the node's existing colour alone.
const parsedColors = new Map<string, Color>();

export function parseColor(css: string): Color | null {
	const known = parsedColors.get(css);
	if (known !== undefined) { return known; }
	const c = parseColorString(css);
	if (c === null) { return null; }
	if (parsedColors.size >= 1024) { parsedColors.clear(); }
	parsedColors.set(css, c as Color);
	return c;
}

function parseColorString(css: string): Color | null {
	if (css.startsWith("rgb(") || css.startsWith("rgba(")) { return parseRgbFunction(css); }
	if (css.length < 4 || css.charAt(0) !== "#") { return null; }
	const body = css.substring(1, css.length);
	let r = -1;
	let g = -1;
	let b = -1;
	let a = 255;
	if (body.length === 3) {
		r = hexNibble(body.charAt(0)) * 17;
		g = hexNibble(body.charAt(1)) * 17;
		b = hexNibble(body.charAt(2)) * 17;
	} else if (body.length === 6 || body.length === 8) {
		r = hexNibble(body.charAt(0)) * 16 + hexNibble(body.charAt(1));
		g = hexNibble(body.charAt(2)) * 16 + hexNibble(body.charAt(3));
		b = hexNibble(body.charAt(4)) * 16 + hexNibble(body.charAt(5));
		if (body.length === 8) { a = hexNibble(body.charAt(6)) * 16 + hexNibble(body.charAt(7)); }
	}
	if (r < 0 || g < 0 || b < 0 || a < 0) { return null; }
	const scale = 255.0 as float32;
	return { r: (r as float32) / scale, g: (g as float32) / scale, b: (b as float32) / scale, a: (a as float32) / scale };
}

function parseRgbFunction(css: string): Color | null {
	const open = css.indexOf("(");
	if (!css.endsWith(")")) { return null; }
	const parts = css.substring(open + 1, css.length - 1).split(",");
	if (parts.length !== 3 && parts.length !== 4) { return null; }
	const channel: float32[] = [];
	for (const p of parts) {
		const v = parseFloat(p.trim());
		if (Number.isNaN(v)) { return null; }
		channel.push(v as float32);
	}
	const scale = 255.0 as float32;
	const alpha: float32 = parts.length === 4 ? channel[3] : 1.0;
	return { r: channel[0] / scale, g: channel[1] / scale, b: channel[2] / scale, a: alpha };
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

function position(v: StylePositionType | null): PositionType | null {
	if (v === null || v === "fixed") { return null; }
	return v;
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
const BLACK: Color = rgba(0.0, 0.0, 0.0, 1.0);

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
	if (mode !== "box-only") {
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
	if (!child.raw && parent.style !== null && child.ref.kind() === DrawKind.Label) { applyTextPaint(child.ref, parent.style as Style); }
}

export function applyPaint(n: VoidNode, s: Style): void {
	const ref = n.ref;
	ref.setVisible(s.display !== "none");
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
	const box = boxStyleOf(s);
	if (box !== null) {
		const now = ref.kind();
		if (now !== DrawKind.Group && now !== DrawKind.Rect) {
			throw new Error(`void host: a border, borderRadius or boxShadow on a ${now.toString()} node; Void paints them on a plain view only`);
		}
		ref.setBoxStyle(box as BoxStyle);
		n.boxed = true;
	} else if (n.boxed) {
		if (ref.kind() === DrawKind.Rect) { ref.setBoxStyle(BoxStyle.create(uniformRadii(0.0), uniformBorders(0.0), CLEAR)); }
		n.boxed = false;
	}
}

function colorOf(css: string, field: string): Color {
	const c = parseColor(css);
	if (c === null) { throw new Error(`void host: ${field} "${css}" is not a colour the Void host reads (#rgb, #rrggbb, #rrggbbaa, rgb(), rgba())`); }
	return c as Color;
}

function boxStyleOf(s: Style): BoxStyle | null {
	if (s.borderWidth === null && s.borderRadius === null && s.borderColor === null && s.boxShadow === null) { return null; }
	const radius: float32 = s.borderRadius !== null ? s.borderRadius as float32 : 0.0;
	const width: float32 = s.borderWidth !== null ? s.borderWidth as float32 : 0.0;
	const color = s.borderColor !== null ? colorOf(s.borderColor as string, "borderColor") : BLACK;
	const box = BoxStyle.create(uniformRadii(radius), uniformBorders(width), color);
	return s.boxShadow !== null ? box.castShadows(boxShadows(s.boxShadow as string)) : box;
}

function splitOutsideParens(text: string, sep: string): string[] {
	const out: string[] = [];
	let depth = 0;
	let start = 0;
	for (let i = 0; i < text.length; i++) {
		const c = text.charAt(i);
		if (c === "(") { depth += 1; }
		else if (c === ")") { depth -= 1; }
		else if (c === sep && depth === 0) {
			out.push(text.substring(start, i));
			start = i + 1;
		}
	}
	out.push(text.substring(start, text.length));
	return out;
}

function cssLength(word: string): float32 | null {
	const bare = word.endsWith("px") ? word.substring(0, word.length - 2) : word;
	let digits = 0;
	for (let i = 0; i < bare.length; i++) {
		const c = bare.charAt(i);
		if (c >= "0" && c <= "9") { digits += 1; }
		else if (c !== "." && !(c === "-" && i === 0)) { return null; }
	}
	return digits > 0 ? parseFloat(bare) as float32 : null;
}

// CSS box-shadow, one shadow per comma: "x y [blur [spread]] [colour] [inset]". CSS's blur radius is
// twice the Gaussian sigma void2d's BoxShadow takes.
function boxShadows(css: string): BoxShadow[] {
	const out: BoxShadow[] = [];
	for (const layer of splitOutsideParens(css, ",")) {
		const lengths: float32[] = [];
		let inset = false;
		let color: Color = BLACK;
		for (const word of splitOutsideParens(layer.trim(), " ")) {
			if (word === "") { continue; }
			if (word === "inset") {
				inset = true;
				continue;
			}
			const len = cssLength(word);
			if (len !== null) {
				lengths.push(len as float32);
				continue;
			}
			color = colorOf(word, "boxShadow");
		}
		if (lengths.length < 2 || lengths.length > 4) {
			throw new Error(`void host: boxShadow "${css}" needs two to four lengths per shadow (x y [blur [spread]])`);
		}
		out.push({
			color, inset,
			offsetX: lengths[0], offsetY: lengths[1],
			blur: lengths.length > 2 ? lengths[2] / 2.0 : 0.0,
			spread: lengths.length > 3 ? lengths[3] : 0.0,
		});
	}
	return out;
}

function colorOr(css: string | null, fallback: Color): Color {
	if (css === null) { return fallback; }
	const c = parseColor(css as string);
	return c !== null ? c as Color : fallback;
}

function lineColor(s: Style, line: string, color: Color): Color {
	const d = s.textDecorationLine;
	return d !== null && (d as string).indexOf(line) >= 0 ? color : CLEAR;
}

// A data span's run, read straight from its own style over the Text's, with no merged Style built.
function spanRun(text: string, own: Style, base: Style, font: FontId, baseColor: Color): TextRun {
	if (own.fontSize !== null && own.fontSize !== base.fontSize) {
		throw new Error("void host: a span changes fontSize, and a Void paragraph has one size; set fontSize on the Text");
	}
	const color = colorOr(own.color !== null ? own.color : base.color, baseColor);
	const bg = own.backgroundColor !== null ? own.backgroundColor : base.backgroundColor;
	const deco: Style = own.textDecorationLine !== null ? own : base;
	const line = own.textDecorationStyle !== null ? own.textDecorationStyle : base.textDecorationStyle;
	if (line !== null && line !== "solid" && line !== "wavy") {
		throw new Error(`void host: textDecorationStyle "${line as string}" is not drawn on the Void host yet; solid and wavy are`);
	}
	const decoCss = own.textDecorationColor !== null ? own.textDecorationColor : base.textDecorationColor;
	const decoColor = decoCss !== null ? colorOf(decoCss as string, "textDecorationColor") : color;
	return {
		len: text.length as int32, font, color, background: colorOr(bg, CLEAR),
		underline: lineColor(deco, "underline", decoColor), wavy: line === "wavy", strikethrough: lineColor(deco, "line-through", decoColor),
	};
}

function weightOf(w: FontWeight | null): int32 {
	if (w === null || w === "normal") { return 400; }
	if (w === "bold") { return 700; }
	return parseInt(w as string) as int32;
}

function decorated(s: Style): boolean {
	const d = s.textDecorationLine;
	return d !== null && d !== "none";
}

interface ResolvedFont {
	family: string;
	weight: int32;
	italic: boolean;
	id: FontId;
}

function familyName(families: string, part: string): string {
	const name = part.trim();
	const quote = name.length > 0 ? name.charAt(0) : "";
	if (quote === "\"" || quote === "'") {
		if (name.length < 2 || name.charAt(name.length - 1) !== quote) {
			throw new Error(`void host: fontFamily "${families}" has an unclosed quote in ${name}`);
		}
		return name.substring(1, name.length - 1);
	}
	if (name.length === 0) { throw new Error(`void host: fontFamily "${families}" names an empty family`); }
	return name;
}

export function familyFont(families: string, weight: int32, italic: boolean): Result<FontId, FontError> {
	const names: string[] = [];
	for (const part of families.split(",")) { names.push(familyName(families, part)); }
	return resolveFont({
		family: names[0], weight, style: italic ? FaceStyle.Italic : FaceStyle.Normal, features: [], fallbacks: names.slice(1), sizeAdjust: SizeAdjust.None,
	});
}

export function createVoidHost(): VoidHost {
	return createVoidHostWith(Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0)), DEFAULT_FONT);
}

export function createVoidHostWith(
	scene: Scene2D,
	font: FontId,
	defaultFamily: string | null = null,
	scene2dScope: boolean = false,
): VoidHost {
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
	let sceneChangePending = false;

	const wasDirty = (): boolean => {
		const dirty = scene.isDirty() || sceneChangePending;
		if (!dirty) { signaled = false; }
		return dirty;
	};

	const woke = (was: boolean): void => {
		if (was || signaled || dirtyListener === null) { return; }
		if (sceneChangePending || scene.isDirty()) {
			signaled = true;
			(dirtyListener as () => void)();
		}
	};

	const attached = (n: VoidNode): boolean => within(n, root);

	const askLayout = (): void => {
		if (signaled || dirtyListener === null) { return; }
		signaled = true;
		(dirtyListener as () => void)();
	};

	const fire = (n: VoidNode, name: string, e: NeonEvent): boolean => {
		const due: ((e: NeonEvent) => void)[] = [];
		for (const entry of events) {
			if (entry.node === n && entry.name === name) { due.push(entry.handler); }
		}
		for (const handler of due) {
			if (n.disposed) { break; }
			handler(e);
		}
		return due.length > 0;
	};

	const pathFrom = (n: VoidNode | null): VoidNode[] => {
		const path: VoidNode[] = [];
		let cur = n;
		while (cur !== null) {
			path.push(cur as VoidNode);
			cur = (cur as VoidNode).parent;
		}
		return path;
	};

	const fireAlong = (path: VoidNode[], name: string, e: NeonEvent): void => {
		for (const n of path) {
			if (!n.disposed) { fire(n, name, e); }
		}
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

	const resolved: ResolvedFont[] = [];

	const fontOf = (own: Style, base: Style): FontId => {
		const named = own.fontFamily !== null ? own.fontFamily : base.fontFamily;
		const weight = weightOf(own.fontWeight !== null ? own.fontWeight : base.fontWeight);
		const slant = own.fontStyle !== null ? own.fontStyle : base.fontStyle;
		const italic = slant === "italic";
		if (named === null && weight === 400 && !italic) { return font; }
		const fam = named !== null ? named as string : defaultFamily;
		if (fam === null) {
			throw new Error(`void host: a Text asks for weight ${weight}${italic ? " italic" : ""} and names no fontFamily, and this host has no default family`);
		}
		const family = fam as string;
		for (const r of resolved) {
			if (r.weight === weight && r.italic === italic && r.family === family) { return r.id; }
		}
		const got = familyFont(family, weight, italic);
		if (!got.ok && got.error === FontError.NoFallbackFamily) {
			throw new Error(`void host: a fallback family in fontFamily "${family}" has no registered face; register its files with registerFace`);
		}
		if (!got.ok) {
			throw new Error(`void host: font family "${family}" has no registered face (${got.error.toString()}); register its files with registerFace`);
		}
		resolved.push({ family, weight, italic, id: got.value });
		return got.value;
	};

	const waiting: VoidNode[] = [];

	// One label per Text: its spans in order, and a run per span once a span is styled or the Text is decorated.
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
		const spans: TextSpan[] = root.spans !== null ? root.spans as TextSpan[] : [];
		let text = "";
		let styled = false;
		for (const s of spans) {
			text += s.text;
			if (s.style !== null) { styled = true; }
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
		const none: Style = {};
		const baseFont = fontOf(none, base);
		if (label.textStyle().font !== baseFont) { label.setFont(baseFont); }
		label.setText(text);
		if (styled || decorated(base)) {
			const runs: TextRun[] = [];
			for (const s of spans) {
				const own: Style = s.style !== null ? s.style as Style : none;
				runs.push(spanRun(s.text, own, base, s.style !== null ? fontOf(own, base) : baseFont, baseColor));
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
			if (n.disposed || !n.paraStale) {
				waiting.splice(i, 1);
			} else if (attached(n)) {
				waiting.splice(i, 1);
				refreshParagraph(n);
			}
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
		fireAlong(pathFrom(focusedNode), name, e);
	};

	const unlink = (c: VoidNode, into: VoidNode): void => {
		const old = c.parent;
		if (old === null) { return; }
		const from = old as VoidNode;
		const at = from.children.indexOf(c);
		if (at >= 0) { from.children.splice(at, 1); }
		if (from !== into) { freeVoidLayoutTree(c); }
	};

	const refuseIntoText = (p: VoidNode, op: string): void => {
		if (p.isText) { throw new Error(`void host: ${op} into a Text; a Text's content arrives through its paragraph, so render it with the Text component`); }
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
		freeVoidLayoutTree(n);
		if (n.ref.isLive()) { n.ref.dispose(); }
		release(n);
	};

	const deliverSpans = (node: HostNode, spans: TextSpan[]): void => {
		const n = live(node, "setSpans");
		if (!n.isText) { throw new Error("void host: spans belong on a Text"); }
		const was = wasDirty();
		n.spans = spans;
		refreshParagraph(n);
		woke(was);
		askLayout();
	};

	const validatePlacement = (parent: VoidNode, child: VoidNode): void => {
		if (scene2dScope && (parent === root || parent.raw) && !child.raw &&
			child.ref.kind() === DrawKind.Label && child.ref.labelText() !== "") {
			throw new Error("Scene2D: raw text requires Label");
		}
	};

	const host: Host = {
		createElement: (tag: string): HostNode => {
			if (scene2dScope && tag !== "view" && tag !== "text" && tag !== "textinput" &&
				tag !== "pressable" && tag !== "scrollview") {
				throw new Error("Scene2D: host element <" + tag + "> needs its UI host");
			}
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
			n.tag = tag;
			woke(was);
			return n;
		},
		createText: (s: string): HostNode => {
			const was = wasDirty();
			const n = new VoidNode(textLabel(s));
			woke(was);
			return n;
		},
		setText: (node: HostNode, s: string): void => {
			const n = live(node, "setText");
			const up = n.parent;
			if (scene2dScope && s !== "" && !n.raw && up !== null &&
				(up === root || up.raw)) {
				throw new Error("Scene2D: raw text requires Label");
			}
			const was = wasDirty();
			n.ref.setText(s);
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
				if (!n.isText) { throw new Error("void host: cellWidth belongs on a Text"); }
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
			const laidBefore = n.flex;
			n.flex = asFlexStyle(style);
			n.style = style;
			applyPaint(n, style);
			if (n.isText) { refreshParagraph(n); }
			else { for (const c of n.children) { inheritTextPaint(c, n); } }
			const f = fieldOf(n);
			if (f !== null) {
				applyTextPaint((f as Field).label, style);
				showField(f as Field, (clientOf(n) as ClientEntry).value);
			}
			woke(was);
			if ((laidBefore !== null || n.flex !== null) && attached(n)) { askLayout(); }
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
			refuseIntoText(p, "append");
			validatePlacement(p, c);
			const was = wasDirty();
			unlink(c, p);
			c.parent = p;
			p.children.push(c);
			childHolder(p).addChild(c.ref);
			inheritTextPaint(c, p);
			if (waiting.length > 0) { refreshWaiting(); }
			woke(was);
		},
		insertBefore: (parent: HostNode, node: HostNode, before: HostNode | null): void => {
			const p = live(parent, "insertBefore");
			const n = live(node, "insertBefore");
			refuseCycle(p, n, "insertBefore");
			refuseIntoText(p, "insertBefore");
			if (focusedNode !== null && within(focusedNode as VoidNode, n) && !attached(p)) { focus(null); }
			validatePlacement(p, n);
			const was = wasDirty();
			if (before === null) {
				unlink(n, p);
				childHolder(p).addChild(n.ref);
				n.parent = p;
				p.children.push(n);
				inheritTextPaint(n, p);
				if (waiting.length > 0) { refreshWaiting(); }
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
		paragraph: (host: Host, node: HostNode, before: HostNode | null, kids: NeonNode | null, spans: Accessor<TextSpan[]> | null): void => {
			spanParagraph(deliverSpans, node, kids, spans);
		},
		focus: (node: HostNode, focused: boolean): void => {
			const n = live(node, "focus");
			if (focused) { focus(n); }
			else if (focusedNode === n) { focus(null); }
		},
		scrollTo: (node: HostNode, x: number, y: number, animated: boolean): void => {
			const n = live(node, "scrollTo");
			const m = n.scroller;
			if (m === null) { throw new Error("void host: scrollTo needs a scroll view, and this node is not one"); }
			const was = wasDirty();
			(m as NodeRef).scrollNodeTo(x as float32, y as float32);
			woke(was);
		},
		measureText: (text: string, style: Style): TextMeasure => {
			const size: float32 = style.fontSize !== null ? style.fontSize as float32 : TEXT_SIZE;
			const laid = TextLayout.layout(text, {
				font: fontOf(style, {}), size, letterSpacing: 0.0, lineSpacing: 0.0, maxWidth: 0.0, align: TextAlign.Left,
			});
			if (!laid.ok) { throw new Error(`void host: measureText could not lay out "${text}": ${laid.error.toString()}`); }
			return {
				width: laid.value.width as number,
				height: laid.value.lineHeight as number,
				ascender: laid.value.ascent as number,
				descender: laid.value.descent as number,
			};
		},
	};

	// The span of a Text under a point: the grapheme the point falls in, none past a line's end.
	const spanAt = (n: VoidNode, x: float32, y: float32): TextSpan | null => {
		if (!n.isText || n.para === null || n.spans === null) { return null; }
		const label = n.para as NodeRef;
		const at = label.globalToLocal(vec2(x, y));
		let index = label.indexAt(at.x, at.y);
		if (index > 0 && label.xForIndex(index) > at.x) { index -= 1; }
		const line = label.lineBoxAt(index);
		if (at.x < line.x || at.x > line.x + line.width) { return null; }
		let start: int32 = 0;
		for (const s of n.spans as TextSpan[]) {
			const end = start + (s.text.length as int32);
			if (index >= start && index < end) { return s; }
			start = end;
		}
		return null;
	};

	const clickAt = (x: float32, y: float32): void => {
		const target = deepestAt(root, x, y, focusable);
		focus(target);
		const under = deepestAt(root, x, y, null);
		let spanText: VoidNode | null = null;
		if (under !== null) {
			const span = spanAt(under as VoidNode, x, y);
			if (span !== null && span.onPress !== null) {
				spanText = under;
				const ev = neonEvent("press");
				ev.x = x;
				ev.y = y;
				(span.onPress as (e: NeonEvent) => void)(ev);
			}
		}
		for (const e of events.slice(0)) {
			if (e.name !== "onPress" || e.node.disposed || !attached(e.node) || e.node === spanText) { continue; }
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

	let captured: VoidNode | null = null;
	let capturedButton: int32 = 0;

	// From onPointerDown until that button's release, the pressed node keeps the pointer, as RN's touch target does.
	const pointerTarget = (x: float32, y: float32): VoidNode | null => {
		if (captured !== null && !(captured as VoidNode).disposed && attached(captured as VoidNode)) { return captured; }
		return deepestAt(root, x, y, null);
	};

	// Bubbles from the target; locationX/Y are relative to it, even outside its box.
	const pointerAt = (name: string, target: VoidNode | null, x: float32, y: float32, ev: NeonEvent): void => {
		if (target === null || !anyHandler(name)) { return; }
		const at = (target as VoidNode).ref.globalToLocal(vec2(x, y));
		ev.locationX = at.x;
		ev.locationY = at.y;
		fireAlong(pathFrom(target), name, ev);
	};

	const pointerEvent = (type: string, x: float32, y: float32, button: int32, pressed: boolean, mods?: number): NeonEvent => {
		const ev = neonEvent(type);
		ev.timeStamp = performance.now();
		ev.x = x;
		ev.y = y;
		ev.button = button;
		ev.pressed = pressed;
		setEventMods(ev, ((mods ?? 0) as uint16) as BitSet<AreaKeyMod>);
		return ev;
	};

	const pointerDown = (x: float32, y: float32, button: int32, mods?: number): void => {
		const target = pointerTarget(x, y);
		if (captured === null && target !== null) {
			captured = target;
			capturedButton = button;
		}
		pointerAt("onPointerDown", target, x, y, pointerEvent("pointerdown", x, y, button, true, mods));
	};

	const pointerMove = (x: float32, y: float32, button: int32, pressed: boolean, mods?: number): void => {
		pointerAt("onPointerMove", pointerTarget(x, y), x, y, pointerEvent("pointermove", x, y, button, pressed, mods));
	};

	const pointerUp = (x: float32, y: float32, button: int32, mods?: number): void => {
		const target = pointerTarget(x, y);
		if (captured !== null && button === capturedButton) { captured = null; }
		pointerAt("onPointerUp", target, x, y, pointerEvent("pointerup", x, y, button, false, mods));
	};

	const wheel = (x: float32, y: float32, dx: float32, dy: float32, mods?: number): void => {
		const ev = pointerEvent("wheel", x, y, 0 as int32, false, mods);
		ev.deltaX = dx;
		ev.deltaY = dy;
		pointerAt("onWheel", deepestAt(root, x, y, null), x, y, ev);
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
			if (n.para !== null && w > 0.0 && n.cell <= 0.0) { (n.para as NodeRef).setMaxWidth(w); }
			return;
		}
		let x: float32 = 0.0;
		for (const c of n.children) {
			if (!c.raw && c.ref.kind() === DrawKind.Label && c.flex === null) {
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

	const layoutIslands = (n: VoidNode): void => {
		for (const c of n.children) {
			if (n.raw && !c.raw && c.flex !== null) {
				const box = n.ref.content();
				layoutPass(c, box.w, box.h);
			}
			layoutIslands(c);
		}
	};

	const fireLayoutsFiredAny = (): boolean => {
		let fired = false;
		for (const e of events.slice(0)) {
			if (scene.isClosed()) { return fired; }
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
			fired = true;
		}
		return fired;
	};

	const layout = (w: float32, h: float32): void => {
		flush();
		for (let pass = 0; pass < LAYOUT_PASSES; pass += 1) {
			if (scene.isClosed()) { return; }
			layoutPass(root, w, h);
			layoutIslands(root);
			flowText(root);
			fitScrollers();
			const settled = !flush((): boolean => fireLayoutsFiredAny());
			sceneChangePending = false;
			if (settled) { return; }
		}
		throw new Error(`void host: onLayout handlers still change the layout after ${LAYOUT_PASSES} passes in one frame; a handler that sets what it measures must settle`);
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

	const ownText = (n: VoidNode): string => {
		if (n.isText) {
			let out = "";
			if (n.spans !== null) { for (const span of n.spans as TextSpan[]) { out += span.text; } }
			return out;
		}
		return n.ref.kind() === DrawKind.Label ? n.ref.labelText() : "";
	};

	const valueOf = (n: VoidNode): string | null => {
		const c = clientOf(n);
		if (c !== null) { return (c as ClientEntry).value.text; }
		const f = fieldOf(n);
		return f !== null ? (f as Field).committed : null;
	};

	const pressable = (n: VoidNode): boolean => {
		for (const e of events) {
			if (e.node === n && e.name === "onPress") { return true; }
		}
		return false;
	};

	const snapshot = (n: VoidNode): DevNode => {
		const at = n.ref.localToGlobal(vec2(0.0, 0.0));
		const f = frameOf(n);
		const children: DevNode[] = [];
		for (const c of n.children) {
			if (!c.disposed) { children.push(snapshot(c)); }
		}
		return {
			tag: n.tag,
			text: ownText(n),
			value: valueOf(n),
			focused: focusedNode === n,
			pressable: pressable(n),
			x: at.x,
			y: at.y,
			w: f.w,
			h: f.h,
			children,
		};
	};

	// A layer inside a Text paints after the Text's paragraph, at a slot kept as the Text's last child.
	const layerSlot = (anchor: LayerAnchor): NodeRef | null => {
		if (!anchor.inText) {
			const n = live(anchor.node, "layerSlot");
			if (!n.ref.order().layerSlot) {
				const was = wasDirty();
				n.ref.setLayerSlot(true);
				woke(was);
			}
			return n.ref;
		}
		const text = spanText(anchor.node);
		if (text === null) { return null; }
		const t = live(text as HostNode, "layerSlot");
		if (t.slot === null) {
			const was = wasDirty();
			const made = scene.group();
			made.setLayerSlot(true);
			t.ref.addChild(made);
			t.slot = made;
			woke(was);
		}
		return t.slot as NodeRef;
	};

	return {
		host, root, scene, clickAt, pointerDown, pointerMove, pointerUp, wheel, textInput, keyDown, keyUp,
		commitText: commit, composeText: compose, setWindowFocus, layout,
		focus: (n: VoidNode | null): void => { focus(n); },
		focused: (): VoidNode | null => focusedNode,
		imeRect, attachTextInput, setEditingState, layerSlot,
		onDirty: (fn: () => void): void => { dirtyListener = fn; },
		mutate: (body: () => void): void => {
			const was = wasDirty();
			const clear = scene.clear;
			const camera = scene.cam;
			const smooth = scene.defaultSmooth;
			const scale = scene.scaleMode;
			const width = scene.designW;
			const height = scene.designH;
			try { body(); } finally {
				if (clear != scene.clear || camera != scene.cam || smooth !== scene.defaultSmooth ||
					scale !== scene.scaleMode || width !== scene.designW || height !== scene.designH) {
					sceneChangePending = true;
				}
				woke(was);
			}
		},
		snapshot: (): DevNode => snapshot(root),
	};
}
