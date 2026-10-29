import { Host, HostNode, NeonNode, render } from "../../render/host";
import { TextSpan } from "../../render/hostTypes";
import { spanParagraph } from "../../render/spanHost";
import { Accessor, createSignal } from "../../core/signal";
import { Dispose } from "../../core/types";
import { MeasureRect, MeasureError } from "../../render/hostTypes";
import { NeonEvent, neonEvent } from "../../render/event";
import { extractResponderTerminal } from "../../render/responder";
import { I18nManager } from "../../api/i18nManager";
import { FlexStyle, YGNode, Direction, freeLayoutTreeAt, layoutPassAt } from "../../../../yoga/src/index";
import { YGNodeGetParent, YGNodeRemoveChild, YGNodeLayoutGetPadding, YGNodeLayoutGetBorder, YGNodeLayoutGetMargin, YGEdge } from "../../../../yoga/src/yogaH";
import { Style, mergeStyle, isBoldWeight } from "../../render/style";
import { NativeElementKind, NativeEventPacket, NativeEventDelivery, createNativeEventRegistry, nativeComponentOf, nativeElementKind, nativeFlexStyle, nativeTransform } from "./contract";
import { nativeElement } from "./elements";
import { WindowDimensions, publishWindow, publishRootWindow, publishKeyboard, publishColorScheme, publishSafeArea } from "../../render/environment";
import { VisibleContentPosition, parseVisibleContent } from "../../render/visibleContent";
import { installNativeAppServices } from "./appServices";
import { installFrameDriver } from "../../animation/frame";
import { LayoutAnimationPlan, LayoutPhase, takeLayoutAnimation, runLayoutTween } from "../../animation/layoutAnimation";
import "../android/library";
when (hcr) {
	import { pollReload, RELOAD_POLL_MS } from "../reloadPoll";
}
when (hcr || testBuild) {
	import { DevNode, setDevDriver } from "../../devtools/driver";
}

@passC("-I./");

when (ios) {
	@compile("../ios/bridge.m", "-fobjc-arc");
	@passL("-framework UIKit");
	@passL("-framework Foundation");
	@passL("-framework CoreGraphics");
	@passL("-framework QuartzCore");
	@passL("-framework CoreImage");
} else when (android) {
	when (hcr) {
		@compile("../android/bridge.c", "-DNEON_HCR");
	} else {
		@compile("../android/bridge.c");
	}
	@passL("-llog");
	@passL("-landroid");
}

import {
	niViewCreate, niTextCreate, niAddChild, niBringChildToFront, niRemoveFromParent, niViewRelease, niSetFrame,
	niSetBackgroundColor, niSetCornerRadius, niSetOpacity, niSetTransform, niSetRotation,
	niSetText, niSetTextColor, niSetFont, niMeasureText, niMeasuredW, niMeasuredH,
	niMeasureInWindow, niMeasurementX, niMeasurementY, niMeasurementW, niMeasurementH,
	niContainerView, niScreenWidth, niScreenHeight, niViewSetTag, niViewSetPressable,
	niLastTouchTag, niLastTouchPhase, niLastTouchX, niLastTouchY, niLastTouchTime, niSetResponder, niClearResponder,
	niScrollCreate, niScrollSetTag, niScrollSetContentSize, niScrollTo, niScrollSetOption,
	niScrollShift, niScrollOffsetX, niScrollOffsetY,
	niLastScrollTag, niLastScrollPhase, niLastScrollX, niLastScrollY, niLastScrollWidth, niLastScrollHeight,
	niLastScrollContentWidth, niLastScrollContentHeight,
	niInputCreate, niImageCreate, niControlSetTag, niSetProp, niSetFocused, niAccessibilityFocus, niTextAreaCreate,
	niLastControlTag, niLastControlPhase, niLastControlValue, niLastControlWidth, niLastControlHeight,
	niKeyboardHeight, niColorScheme, niRequestFrame, niSafeAreaInset,
} from "./bridge.h";
import { flush, getOwner } from "../../core/runtime";
import { niLoopRun } from "./loop.h";

extern function niRegisterApp(mount: () => void): void;
extern function niRunApp(): int32;
extern function niSetReloadPoll(poll: () => void): void;
extern function niSetTouchHandler(handler: () => void): void;
extern function niSetScrollHandler(handler: () => void): void;
extern function niSetResizeHandler(handler: () => void): void;
extern function niSetTeardownHandler(handler: () => void): void;
extern function niSetLoopHandler(handler: () => void): void;
extern function niSetFrameHandler(handler: () => void): void;
extern function niSetControlHandler(handler: () => void): void;
extern function niSetEnvironmentHandler(handler: () => void): void;


class NativeNode {
	view: Ptr<void> | null = null;
	tag: string = "";
	isText: boolean = false;
	isString: boolean = false;
	isScroll: boolean = false;
	isInput: boolean = false;
	inputValue: string = "";
	multiline: boolean = false;
	control: NativeElementKind = NativeElementKind.View;
	sizesItself: boolean = false;
	spanTags: int32[] = [];
	pressable: boolean = false;
	text: string = "";
	row: int32 = -1;
	eventTag: int32 = 0;
	styleCache: Style | null = null;
	transformCss: string | null = null;
	rotation: float32 = 0.0;
	clip: string = "visible";
	tween: int32 = 0;
	fadePass: int32 = 0;
	shownX: float32 = 0.0;
	shownY: float32 = 0.0;
	shownW: float32 = 0.0;
	shownH: float32 = 0.0;
	painted: boolean = false;
	rounded: boolean = false;
	faded: boolean = false;
	zIndex: number = 0;
	zChildren: int32 = 0;
	flex: FlexStyle | null = null;
	lastFlex: FlexStyle | null = null;
	yg: Ptr<YGNode> | null = null;
	x: float32 = 0.0;
	y: float32 = 0.0;
	w: float32 = 0.0;
	h: float32 = 0.0;
	firedX: float32 = -1.0;
	firedY: float32 = -1.0;
	firedW: float32 = -1.0;
	firedH: float32 = -1.0;
	framed: boolean = false;
	contentW: float32 = -1.0;
	measuredFor: float32 = -1.0;
	measuredW: float32 = 0.0;
	textInsets: string = "";
	textAlign: string = "";
	writingDirection: string = "";
	fontFamily: string = "";
	minFromMeasure: boolean = false;
	contentH: float32 = -1.0;
	horizontal: boolean = false;
	visibleContent: VisibleContentPosition | null = null;
	anchorX: float32 = 0.0;
	anchorY: float32 = 0.0;

	constructor(view: Ptr<void> | null, isText: boolean, isString: boolean) {
		this.view = view;
		this.isText = isText;
		this.isString = isString;
	}
}

const NO_CHILDREN: NativeNode[] = [];

// The host's node tree. A node holds no reference to another node, so NativeNode stays out of the cycle collector:
// its parent, children, paint order and scroll anchor live here, in the row the node enters on its first append or
// insert. A node that never entered has no parent and no children; a freed subtree leaves its rows, which later nodes reuse.
class NativeTree {
	nodes: (NativeNode | null)[] = [];
	ups: (NativeNode | null)[] = [];
	downs: NativeNode[][] = [];
	stacks: NativeNode[][] = [];
	anchors: (NativeNode | null)[] = [];
	spans: (TextSpan[] | null)[] = [];
	open: int32[] = [];

	rowOf(n: NativeNode): int32 {
		const at = n.row;
		if (at < 0) { return -1; }
		if (at >= this.nodes.length || this.nodes[at] !== n) { throw new Error("native host: a node's row belongs to another node"); }
		return at;
	}

	enter(n: NativeNode): int32 {
		const known = this.rowOf(n);
		if (known >= 0) { return known; }
		let at: int32;
		if (this.open.length > 0) {
			at = this.open[this.open.length - 1];
			this.open.splice(this.open.length - 1, 1);
			this.nodes[at] = n;
			this.ups[at] = null;
			this.downs[at] = [];
			this.stacks[at] = [];
			this.anchors[at] = null;
			this.spans[at] = null;
		} else {
			at = this.nodes.length as int32;
			this.nodes.push(n);
			this.ups.push(null);
			this.downs.push([]);
			this.stacks.push([]);
			this.anchors.push(null);
			this.spans.push(null);
		}
		n.row = at;
		return at;
	}

	parentOf(n: NativeNode): NativeNode | null {
		const at = this.rowOf(n);
		return at < 0 ? null : this.ups[at];
	}

	childrenOf(n: NativeNode): NativeNode[] {
		const at = this.rowOf(n);
		return at < 0 ? NO_CHILDREN : this.downs[at];
	}

	attach(c: NativeNode, p: NativeNode, at: int32): void {
		const row = this.enter(c);
		if (this.ups[row] !== null) { throw new Error("native host: attach a node that still has a parent"); }
		const kids = this.downs[this.enter(p)];
		if (at < 0) { kids.push(c); } else { kids.splice(at, 0, c); }
		this.ups[row] = p;
	}

	detach(c: NativeNode): void {
		const row = this.rowOf(c);
		if (row < 0) { return; }
		const up = this.ups[row];
		if (up === null) { return; }
		const kids = this.downs[this.rowOf(up as NativeNode)];
		const at = kids.indexOf(c);
		if (at < 0) { throw new Error("native host: a node is missing from its parent's children"); }
		kids.splice(at, 1);
		this.ups[row] = null;
	}

	paintOrderOf(n: NativeNode): NativeNode[] {
		return this.stacks[this.enter(n)];
	}

	anchorOf(n: NativeNode): NativeNode | null {
		const at = this.rowOf(n);
		return at < 0 ? null : this.anchors[at];
	}

	setAnchor(n: NativeNode, anchor: NativeNode | null): void {
		if (anchor === null) {
			const at = this.rowOf(n);
			if (at >= 0) { this.anchors[at] = null; }
			return;
		}
		this.anchors[this.enter(n)] = anchor;
	}

	spansOf(n: NativeNode): TextSpan[] | null {
		const at = this.rowOf(n);
		return at < 0 ? null : this.spans[at];
	}

	setSpans(n: NativeNode, spans: TextSpan[] | null): void {
		if (spans === null && this.rowOf(n) < 0) { return; }
		this.spans[this.enter(n)] = spans;
	}

	drop(n: NativeNode): void {
		const row = this.rowOf(n);
		if (row < 0) { return; }
		for (const c of this.downs[row]) { this.drop(c); }
		this.nodes[row] = null;
		this.ups[row] = null;
		this.downs[row] = [];
		this.stacks[row] = [];
		this.anchors[row] = null;
		this.spans[row] = null;
		this.open.push(row);
		n.row = -1;
	}
}

const tree = new NativeTree();

function nativeNode(view: Ptr<void> | null, isText: boolean, isString: boolean): NativeNode {
	return new NativeNode(view, isText, isString);
}

// ---- the yoga sync protocol (yoga/src/sync.ms) on NativeNode ----

export function layoutChildCount(this n: NativeNode): int32 { return tree.childrenOf(n).length as int32; }
export function layoutChildAt(this n: NativeNode, i: int32): NativeNode { return tree.childrenOf(n)[i]; }
export function layoutGetStyle(this n: NativeNode): FlexStyle | null { return n.flex; }
export function layoutGetLastStyle(this n: NativeNode): FlexStyle | null { return n.lastFlex; }
export function layoutSetLastStyle(this n: NativeNode, s: FlexStyle | null): void { n.lastFlex = s; }
export function layoutGetYg(this n: NativeNode): Ptr<YGNode> | null { return n.yg; }
export function layoutSetYg(this n: NativeNode, yg: Ptr<YGNode> | null): void { n.yg = yg; }
let layoutPlan: LayoutAnimationPlan | null = null;
let nextTween: int32 = 1;
let layoutPassId: int32 = 0;

function showFrame(n: NativeNode, x: float32, y: float32, w: float32, h: float32): void {
	n.shownX = x; n.shownY = y; n.shownW = w; n.shownH = h;
	if (n.view !== null) { niSetFrame(n.view, x, y, w, h); }
}

function lerp(a: float32, b: float32, t: number): float32 {
	return (a + (b - a) * t) as float32;
}

function tweenFrame(n: NativeNode, phase: LayoutPhase): void {
	const id = nextTween;
	nextTween += 1;
	n.tween = id;
	const fromX = n.shownX;
	const fromY = n.shownY;
	const fromW = n.shownW;
	const fromH = n.shownH;
	runLayoutTween(phase, (t: number): void => {
		if (n.tween !== id || n.view === null) { return; }
		showFrame(n, lerp(fromX, n.x, t), lerp(fromY, n.y, t), lerp(fromW, n.w, t), lerp(fromH, n.h, t));
	}, (): void => {
		if (n.tween === id) { n.tween = 0; }
	});
}

function fadeIn(n: NativeNode, phase: LayoutPhase): void {
	const view = n.view;
	if (view === null) { return; }
	const style = n.styleCache;
	const target = style !== null && (style as Style).opacity !== null ? ((style as Style).opacity as number) : 1.0;
	runLayoutTween(phase, (t: number): void => {
		if (n.view !== null) { niSetOpacity(n.view, (target * t) as float32); }
	}, (): void => {});
}

export function layoutSetFrame(this n: NativeNode, x: float32, y: float32, w: float32, h: float32): void {
	const moved = !n.framed || n.x !== x || n.y !== y || n.w !== w || n.h !== h;
	n.x = x; n.y = y; n.w = w; n.h = h;
	if (!moved || n.view === null || isRootNode(n)) { return; }
	const plan = layoutPlan;
	if (plan !== null && n.framed && (plan as LayoutAnimationPlan).update !== null) {
		tweenFrame(n, (plan as LayoutAnimationPlan).update as LayoutPhase);
		return;
	}
	const fresh = !n.framed;
	n.framed = true;
	n.tween = 0;
	showFrame(n, x, y, w, h);
	if (fresh && plan !== null && (plan as LayoutAnimationPlan).create !== null && !n.isString) {
		const parent = tree.parentOf(n);
		if (parent !== null && (parent as NativeNode).fadePass === layoutPassId) {
			n.fadePass = layoutPassId;
			return;
		}
		n.fadePass = layoutPassId;
		fadeIn(n, (plan as LayoutAnimationPlan).create as LayoutPhase);
	}
}

// ---- style projection + paint ----


function hexNibble(c: string): int32 {
	if (c >= "0" && c <= "9") { return c.charCodeAt(0) - 48; }
	if (c >= "a" && c <= "f") { return c.charCodeAt(0) - 87; }
	if (c >= "A" && c <= "F") { return c.charCodeAt(0) - 55; }
	return -1;
}

interface Rgba { r: float32; g: float32; b: float32; a: float32; }

function parseRgbFunction(css: string): Rgba | null {
	const open = css.indexOf("(");
	const close = css.lastIndexOf(")");
	if (open < 0 || close < open) { return null; }
	const name = css.substring(0, open).trim();
	if (name !== "rgb" && name !== "rgba") { return null; }
	const parts = css.substring(open + 1, close).split(",");
	if (parts.length !== 3 && parts.length !== 4) { return null; }
	const r = parseFloat(parts[0].trim());
	const g = parseFloat(parts[1].trim());
	const b = parseFloat(parts[2].trim());
	const a = parts.length === 4 ? parseFloat(parts[3].trim()) : 1.0;
	if (r !== r || g !== g || b !== b || a !== a) { return null; }
	const s = 255.0;
	return { r: (r / s) as float32, g: (g / s) as float32, b: (b / s) as float32, a: Math.min(1.0, Math.max(0.0, a)) as float32 };
}

function parseHex(css: string): Rgba | null {
	if (css.startsWith("rgb")) { return parseRgbFunction(css); }
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
	const s = 255.0 as float32;
	return { r: (r as float32) / s, g: (g as float32) / s, b: (b as float32) / s, a: 1.0 };
}


function points(v: number | string | null): number {
	if (v === null || typeof v === "string") { return -1; }
	return v as number;
}

function inset(side: number | string | null, all: number | string | null): number {
	const own = points(side);
	if (own >= 0) { return own; }
	return Math.max(0, points(all));
}

function writeTextInsets(n: NativeNode, s: Style): void {
	if (!n.isInput || n.view === null) { return; }
	if (s.padding === null && s.paddingLeft === null && s.paddingTop === null && s.paddingRight === null && s.paddingBottom === null && n.textInsets === "") { return; }
	const insets = `${inset(s.paddingLeft, s.padding)},${inset(s.paddingTop, s.padding)},${inset(s.paddingRight, s.padding)},${inset(s.paddingBottom, s.padding)}`;
	if (insets === n.textInsets) { return; }
	n.textInsets = insets;
	niSetProp(n.view, "textInsets", insets);
}

// The paint half of the projection (docs/STYLE.md §5), onto the platform view.
function applyPaint(n: NativeNode, s: Style): void {
	if (s.transform !== n.transformCss) {
		const transform = nativeTransform(s.transform);
		if (n.view !== null) {
			niSetTransform(n.view, transform.scaleX, transform.scaleY, transform.translateX, transform.translateY);
			if (transform.rotate !== n.rotation) { niSetRotation(n.view, transform.rotate); }
		}
		n.rotation = transform.rotate;
		n.transformCss = s.transform;
	}
	if (n.view === null || !n.isText) {
		if (n.view !== null) {
			const bg = s.backgroundColor;
			if (bg !== null) {
				const c = parseHex(bg as string);
				if (c !== null) {
					niSetBackgroundColor(n.view, c.r, c.g, c.b, c.a);
					n.painted = true;
				} else if (bg === "transparent") {
					niSetBackgroundColor(n.view, 0.0, 0.0, 0.0, 0.0);
					n.painted = true;
				}
			} else if (n.painted) {
				niSetBackgroundColor(n.view, 0.0, 0.0, 0.0, 0.0);
				n.painted = false;
			}
			if (s.borderRadius !== null) {
				niSetCornerRadius(n.view, s.borderRadius as float32);
				n.rounded = true;
			} else if (n.rounded) {
				niSetCornerRadius(n.view, 0.0);
				n.rounded = false;
			}
			if (s.opacity !== null) {
				niSetOpacity(n.view, s.opacity as float32);
				n.faded = true;
			} else if (n.faded) {
				niSetOpacity(n.view, 1.0);
				n.faded = false;
			}
			const clip = s.overflow === "hidden" || s.overflow === "clip" ? "hidden" : "visible";
			if (clip !== n.clip && !n.isScroll) {
				n.clip = clip;
				niSetProp(n.view, "overflow", clip);
			}
		}
	}
	if ((n.isText || n.isInput) && n.view !== null) {
		const fg = s.color;
		if (fg !== null) {
			const c = parseHex(fg as string);
			if (c !== null) { niSetTextColor(n.view, c.r, c.g, c.b, c.a); }
		}
		const size = s.fontSize !== null ? (s.fontSize as number) : 17.0;
		const bold = isBoldWeight(s.fontWeight);
		niSetFont(n.view, size as float32, bold ? 1 : 0);
		sendFontFamily(n, s.fontFamily !== null ? s.fontFamily as string : "");
		const align = s.textAlign !== null ? (s.textAlign as string) : "";
		if (align !== n.textAlign) {
			n.textAlign = align;
			const shown = align === "" ? "auto" : align;
			niSetProp(n.view, "textAlign", shown);
		}
		const writing = s.writingDirection !== null ? (s.writingDirection as string) : "";
		if (writing !== n.writingDirection) {
			n.writingDirection = writing;
			const shownWriting = writing === "" ? "auto" : writing;
			niSetProp(n.view, "writingDirection", shownWriting);
		}
	}
}

// A centred, right or justified label spans the width its parent gives it (RN Text stretches
// like any flex item), at least as wide as its text; a left-aligned one keeps its text's width.
function alignsAcross(n: NativeNode): boolean {
	return n.textAlign === "center" || n.textAlign === "right" || n.textAlign === "justify";
}


// Eager text measure: the bridge's measured size becomes the node's fixed w/h so yoga lays
// out text without a measure func. Fresh FlexStyle object every time — the
function remeasureText(n: NativeNode): void {
	measureTextWithin(n, niScreenWidth());
}

function measureTextWithin(n: NativeNode, available: float32): void {
	if (!n.isText || n.view === null) { return; }
	niMeasureText(n.view, available);
	const w = niMeasuredW();
	const h = niMeasuredH();
	n.measuredFor = available;
	n.measuredW = w;
	const old = n.flex;
	const fresh: FlexStyle = {};
	if (old !== null) {
		fresh.flexDirection = old.flexDirection;
		fresh.justifyContent = old.justifyContent;
		fresh.alignItems = old.alignItems;
		fresh.alignSelf = old.alignSelf;
		fresh.alignContent = old.alignContent;
		fresh.position = old.position;
		fresh.flexWrap = old.flexWrap;
		fresh.display = old.display;
		fresh.flex = old.flex;
		fresh.flexGrow = old.flexGrow;
		fresh.flexShrink = old.flexShrink;
		fresh.flexBasis = old.flexBasis;
		fresh.minWidth = old.minWidth;
		fresh.minHeight = old.minHeight;
		fresh.maxWidth = old.maxWidth;
		fresh.maxHeight = old.maxHeight;
		fresh.aspectRatio = old.aspectRatio;
		fresh.margin = old.margin;
		fresh.marginTop = old.marginTop;
		fresh.marginBottom = old.marginBottom;
		fresh.marginLeft = old.marginLeft;
		fresh.marginRight = old.marginRight;
		fresh.padding = old.padding;
		fresh.paddingTop = old.paddingTop;
		fresh.paddingBottom = old.paddingBottom;
		fresh.paddingLeft = old.paddingLeft;
		fresh.paddingRight = old.paddingRight;
		fresh.top = old.top;
		fresh.left = old.left;
		fresh.right = old.right;
		fresh.bottom = old.bottom;
		fresh.gap = old.gap;
		fresh.rowGap = old.rowGap;
		fresh.columnGap = old.columnGap;
	}
	if (alignsAcross(n)) {
		fresh.width = old !== null ? old.width : null;
		if (fresh.minWidth === null || n.minFromMeasure) {
			fresh.minWidth = w;
			n.minFromMeasure = true;
		}
	} else {
		fresh.width = w;
	}
	fresh.height = h;
	if (n.isString) { fresh.display = n.text === "" ? "none" : null; }
	n.flex = fresh;
}
function horizontalInset(yg: Ptr<YGNode>, padding: boolean): float32 {
	if (padding) {
		return YGNodeLayoutGetPadding(yg, YGEdge.YGEdgeLeft) + YGNodeLayoutGetPadding(yg, YGEdge.YGEdgeRight)
			+ YGNodeLayoutGetBorder(yg, YGEdge.YGEdgeLeft) + YGNodeLayoutGetBorder(yg, YGEdge.YGEdgeRight);
	}
	return YGNodeLayoutGetMargin(yg, YGEdge.YGEdgeLeft) + YGNodeLayoutGetMargin(yg, YGEdge.YGEdgeRight);
}

function availableTextWidth(n: NativeNode): float32 {
	const p = tree.parentOf(n);
	if (p === null || p.yg === null || p.w <= 0) { return niScreenWidth(); }
	let width = p.w - horizontalInset(p.yg as Ptr<YGNode>, true);
	if (n.yg !== null) { width -= horizontalInset(n.yg as Ptr<YGNode>, false); }
	return Math.max(0, width) as float32;
}

function textNeedsRemeasure(n: NativeNode): boolean {
	if (!n.isText || n.view === null || !isMounted(n)) { return false; }
	const available = availableTextWidth(n);
	if (Math.abs(available - n.measuredFor) < 0.5) { return false; }
	const unwrapped = n.measuredW < n.measuredFor - 0.5;
	return !(unwrapped && available >= n.measuredW);
}

// ---- the host ----

let nextTag: int32 = 1;
const eventRegistry = createNativeEventRegistry();
const nodesByTag = new Map<int32, NativeNode>();

class NativeRoot {
	node: NativeNode;
	followsScreen: boolean;
	width: float32 = 0.0;
	height: float32 = 0.0;
	direction: Direction = "ltr";
	scrollNodes: NativeNode[] = [];
	layoutNodes: NativeNode[] = [];
	textNodes: NativeNode[] = [];
	inputNodes: NativeNode[] = [];
	focusedInput: NativeNode | null = null;
	layoutDirty: boolean = false;
	mountedApp: (() => NeonNode) | null = null;
	mounted: Dispose | null = null;

	constructor(node: NativeNode, followsScreen: boolean) {
		this.node = node;
		this.followsScreen = followsScreen;
	}
}

const mainRoot = new NativeRoot(nativeNode(null, false, false), true);
const roots: NativeRoot[] = [mainRoot];

function isRootNode(n: NativeNode): boolean {
	for (const r of roots) {
		if (r.node === n) { return true; }
	}
	return false;
}

function rootOf(n: NativeNode): NativeRoot | null {
	let top = n;
	let up = tree.parentOf(top);
	while (up !== null) {
		top = up as NativeNode;
		up = tree.parentOf(top);
	}
	for (const r of roots) {
		if (r.node === top) { return r; }
	}
	return null;
}

function kindOf(n: NativeNode): NativeElementKind {
	if (n.isText) { return NativeElementKind.Text; }
	if (n.isScroll) { return NativeElementKind.Scroll; }
	if (n.control !== NativeElementKind.View) { return n.control; }
	return NativeElementKind.View;
}

function writeContentSizes(r: NativeRoot): void {
	for (const s of r.scrollNodes) {
		if (s.view === null || !isMounted(s)) { continue; }
		let w: float32 = 0.0;
		let h: float32 = 0.0;
		for (const c of tree.childrenOf(s)) {
			if (c.x + c.w > w) { w = c.x + c.w; }
			if (c.y + c.h > h) { h = c.y + c.h; }
		}
		if (w === s.contentW && h === s.contentH) { continue; }
		s.contentW = w;
		s.contentH = h;
		niScrollSetContentSize(s.view, w, h);
	}
}

// RN RCTScrollViewComponentView _prepareForMaintainVisibleScrollPosition and
// _adjustForMaintainVisibleContentPosition, around the layout pass instead of a mount.
function prepareVisibleContent(r: NativeRoot): void {
	for (const s of r.scrollNodes) {
		tree.setAnchor(s, null);
		const position = s.visibleContent;
		if (position === null || s.view === null || tree.childrenOf(s).length === 0) { continue; }
		if (!isMounted(s)) { continue; }
		const offset = s.horizontal ? niScrollOffsetX(s.view) : niScrollOffsetY(s.view);
		let index: int32 = 0;
		for (const child of tree.childrenOf(tree.childrenOf(s)[0])) {
			if (child.isString || !child.framed) { continue; }
			index += 1;
			if (index <= position.minIndexForVisible) { continue; }
			tree.setAnchor(s, child);
			s.anchorX = child.x;
			s.anchorY = child.y;
			if ((s.horizontal ? child.x + child.w : child.y + child.h) > offset) { break; }
		}
	}
}

function adjustVisibleContent(r: NativeRoot): void {
	for (const s of r.scrollNodes.slice(0, r.scrollNodes.length)) {
		const anchor = tree.anchorOf(s);
		const position = s.visibleContent;
		tree.setAnchor(s, null);
		if (anchor === null || position === null || s.view === null) { continue; }
		const kids = tree.childrenOf(s);
		if (kids.length === 0 || tree.parentOf(anchor) !== kids[0]) { continue; }
		const delta = s.horizontal ? anchor.x - s.anchorX : anchor.y - s.anchorY;
		if (Math.abs(delta) <= 0.5) { continue; }
		const x = niScrollOffsetX(s.view);
		const y = niScrollOffsetY(s.view);
		niScrollShift(s.view, s.horizontal ? delta : 0.0, s.horizontal ? 0.0 : delta);
		const threshold = position.autoscrollToTopThreshold;
		const before = s.horizontal ? x : y;
		if (threshold !== null && s.view !== null && before <= (threshold as number)) {
			const keptY: float32 = s.horizontal ? niScrollOffsetY(s.view) : 0.0;
			niScrollTo(s.view, s.horizontal ? 0.0 : x, keptY, 1);
		}
	}
}

function fireLayouts(r: NativeRoot): void {
	for (const n of r.layoutNodes.slice(0, r.layoutNodes.length)) {
		if (n.eventTag === 0 || !isMounted(n)) { continue; }
		if (n.x === n.firedX && n.y === n.firedY && n.w === n.firedW && n.h === n.firedH) { continue; }
		n.firedX = n.x;
		n.firedY = n.y;
		n.firedW = n.w;
		n.firedH = n.h;
		eventRegistry.layout(n.eventTag, n.x, n.y, n.w, n.h);
	}
}

function childIndex(parent: NativeNode, node: NativeNode): int32 {
	return tree.childrenOf(parent).indexOf(node) as int32;
}

function isMounted(n: NativeNode): boolean {
	return rootOf(n) !== null;
}

function blurInputs(n: NativeNode): void {
	if (n.isInput && n.view !== null) { niSetFocused(n.view, 0); }
	for (const child of tree.childrenOf(n)) { blurInputs(child); }
}

function releaseNativeTree(r: NativeRoot, n: NativeNode): void {
	for (const child of tree.childrenOf(n)) { releaseNativeTree(r, child); }
	if (n.eventTag !== 0) {
		retirePressTag(n.eventTag);
		eventRegistry.remove(n.eventTag);
		nodesByTag.delete(n.eventTag);
		n.eventTag = 0;
	}
	if (n.isScroll) {
		const at = r.scrollNodes.indexOf(n);
		if (at >= 0) { r.scrollNodes.splice(at, 1); }
	}
	const laid = r.layoutNodes.indexOf(n);
	if (laid >= 0) { r.layoutNodes.splice(laid, 1); }
	if (n.isText) {
		const at = r.textNodes.indexOf(n);
		if (at >= 0) { r.textNodes.splice(at, 1); }
	}
	if (n.multiline) {
		const at = r.inputNodes.indexOf(n);
		if (at >= 0) { r.inputNodes.splice(at, 1); }
	}
	if (n.view !== null) {
		niRemoveFromParent(n.view);
		niViewRelease(n.view);
		n.view = null;
	}
	tree.drop(n);
	n.zChildren = 0;
	n.styleCache = null;
	n.flex = null;
	for (const tag of n.spanTags) {
		if (tag !== 0) { dropSpanTag(tag); }
	}
	n.spanTags = [];
	tree.setSpans(n, null);
}

function onResize(): void {
	relayout(mainRoot);
}

const SPAN_RECORD = "\u001e";
const SPAN_FIELD = "\u001f";

when (ios || android) {
	function sendFontFamily(n: NativeNode, family: string): void {
		if (family !== "") { throw `native host: fontFamily "${family}" is not wired to this platform's text stack yet`; }
	}
} else {
	function sendFontFamily(n: NativeNode, family: string): void {
		if (family.indexOf(",") >= 0) { throw `native host: fontFamily "${family}" is a family list; this host draws one installed family and takes no fallback list yet`; }
		if (family === n.fontFamily || n.view === null) { return; }
		n.fontFamily = family;
		niSetProp(n.view, "fontFamily", family);
	}
}

// The Text a pressable span's tag belongs to, for touches that bubble up from the span.
const spanTagOwner: Map<int32, NativeNode> = new Map();

function styledRun(s: Style | null): boolean {
	if (s === null) { return false; }
	const deco = s.textDecorationLine;
	return s.fontStyle === "italic" || (deco !== null && deco !== "none");
}

// One run on the wire: text, colour, size, bold, italic, underline, line-through, press tag.
// A span's own style lays over the Text's field by field.
function encodeSpan(text: string, own: Style | null, base: Style, tag: int32): string {
	if (own !== null && own.fontFamily !== null && own.fontFamily !== base.fontFamily) {
		throw `native host: a span changes fontFamily to "${own.fontFamily as string}", and a native label has one family; set fontFamily on the Text`;
	}
	const color = own !== null && own.color !== null ? own.color : base.color;
	const size = own !== null && own.fontSize !== null ? own.fontSize : base.fontSize;
	const weight = own !== null && own.fontWeight !== null ? own.fontWeight : base.fontWeight;
	const italic = own !== null && own.fontStyle !== null ? own.fontStyle === "italic" : base.fontStyle === "italic";
	const line = own !== null && own.textDecorationLine !== null ? own.textDecorationLine : base.textDecorationLine;
	const deco = line !== null ? (line as string) : "none";
	return text + SPAN_FIELD + (color !== null ? (color as string) : "") + SPAN_FIELD + (size !== null ? (size as number) : 17).toString()
		+ SPAN_FIELD + (isBoldWeight(weight) ? "1" : "0")
		+ SPAN_FIELD + (italic ? "1" : "0")
		+ SPAN_FIELD + (deco.indexOf("underline") >= 0 ? "1" : "0")
		+ SPAN_FIELD + (deco.indexOf("line-through") >= 0 ? "1" : "0")
		+ SPAN_FIELD + tag.toString();
}

function refuseLineStyle(s: Style | null): void {
	if (s === null) { return; }
	if (s.textDecorationColor !== null) {
		throw `native host: textDecorationColor "${s.textDecorationColor as string}" is not drawn by the platform text stacks yet; the line takes the text colour`;
	}
	if (s.textDecorationLine !== null && (s.textDecorationLine as string).indexOf("overline") >= 0) {
		throw `native host: textDecorationLine "${s.textDecorationLine as string}" is not drawn by the platform text stacks yet; underline and line-through are`;
	}
	if (s.textDecorationStyle === null || s.textDecorationStyle === "solid") { return; }
	throw `native host: textDecorationStyle "${s.textDecorationStyle as string}" is not drawn by the platform text stacks yet; solid is`;
}

// Writes the label's whole content: plain text when no span styles it, else the runs.
function refreshLabel(n: NativeNode): void {
	if (n.view === null) { return; }
	const base: Style = n.styleCache !== null ? n.styleCache as Style : {};
	const known = tree.spansOf(n);
	const spans: TextSpan[] = known !== null ? known as TextSpan[] : [];
	refuseLineStyle(base);
	let rich = styledRun(base);
	for (const span of spans) {
		refuseLineStyle(span.style);
		if (span.style !== null || span.onPress !== null || span.onTouch !== null) { rich = true; }
	}
	if (!rich) {
		let text = "";
		for (const span of spans) { text += span.text; }
		const joined = text;
		niSetText(n.view, joined);
	} else {
		let encoded = "";
		for (let i = 0; i < spans.length; i += 1) {
			if (i > 0) { encoded += SPAN_RECORD; }
			const own: Style | null = spans[i].style !== null ? spans[i].style as Style : null;
			encoded += encodeSpan(spans[i].text, own, base, i < n.spanTags.length ? n.spanTags[i] : 0);
		}
		const record = encoded;
		niSetProp(n.view, "textSpans", record);
	}
	remeasureText(n);
}

function ensureTag(n: NativeNode): void {
	if (n.eventTag !== 0) { return; }
	n.eventTag = nextTag;
	nextTag += 1;
	nodesByTag.set(n.eventTag, n);
	if (n.view !== null && n.isScroll) { niScrollSetTag(n.view, n.eventTag); }
	else if (n.view !== null && n.control !== NativeElementKind.View) { niControlSetTag(n.view, n.eventTag); }
	else if (n.view !== null) { niViewSetTag(n.view, n.eventTag); }
}

// A pressable span needs its label to take touches and find the span under the finger.
function markPressable(n: NativeNode): void {
	ensureTag(n);
	if (n.view !== null) { niViewSetPressable(n.view); }
}

function refuseIntoText(p: NativeNode, op: string): void {
	if (p.isText && !p.isString) { throw `native host: ${op} into a Text; a Text's content arrives through its paragraph, so render it with the Text component`; }
}

function dropSpanTag(tag: int32): void {
	retirePressTag(tag);
	eventRegistry.remove(tag);
	spanTagOwner.delete(tag);
}

const SPAN_TOUCHES = ["onTouchStart", "onTouchMove", "onTouchEnd", "onTouchCancel"];

function spanTouchRoute(touch: (name: string, e: NeonEvent) => void, name: string): (e: NeonEvent) => void {
	return (e: NeonEvent): void => { touch(name, e); };
}

// A span with onPress or touches keeps its own tag by position, so the label finds the span under the finger.
function deliverSpans(r: NativeRoot, node: HostNode, spans: TextSpan[]): void {
	const n = node as unknown as NativeNode;
	if (!n.isText || n.isString) { throw "native host: spans belong on a Text"; }
	setSpansOf(r, n, spans);
}

function setSpansOf(r: NativeRoot, n: NativeNode, spans: TextSpan[]): void {
	tree.setSpans(n, spans);
	let pressable = false;
	for (let i = 0; i < spans.length; i += 1) {
		if (i >= n.spanTags.length) { n.spanTags.push(0); }
		const had = n.spanTags[i];
		const press = spans[i].onPress;
		const touch = spans[i].onTouch;
		if (press !== null || touch !== null) {
			let tag = had;
			if (tag === 0) {
				tag = nextTag;
				nextTag += 1;
				n.spanTags[i] = tag;
				spanTagOwner.set(tag, n);
			} else {
				eventRegistry.remove(tag);
			}
			if (press !== null) { eventRegistry.add(tag, "onPress", press as (e: NeonEvent) => void); }
			if (touch !== null) {
				for (const name of SPAN_TOUCHES) {
					eventRegistry.addPhases(tag, name, spanTouchRoute(touch as (name: string, e: NeonEvent) => void, name), (e: NeonEvent): void => {});
				}
			}
			pressable = true;
		} else if (had !== 0) {
			dropSpanTag(had);
			n.spanTags[i] = 0;
		}
	}
	while (n.spanTags.length > spans.length) {
		const tag = n.spanTags.pop() as int32;
		if (tag !== 0) { dropSpanTag(tag); }
	}
	if (pressable) { markPressable(n); }
	refreshLabel(n);
	if (isMounted(n)) { requestLayout(r); }
}

// A string under a Text element merges onto the parent's label (the reference
// hosts' rule — no nested labels); under anything else it materialises its
// own label, inheriting the parent's text paint (RN color/fontSize cascade,
// first cut).
function materializeString(r: NativeRoot, child: NativeNode, parent: NativeNode): void {
	if (child.view === null) { child.view = niTextCreate(); }
	if (r.textNodes.indexOf(child) < 0) { r.textNodes.push(child); }
	child.isText = true;
	niSetText(child.view, child.text);
	const ps = parent.styleCache;
	if (ps !== null && child.view !== null) {
		const fg = ps.color;
		if (fg !== null) {
			const c = parseHex(fg as string);
			if (c !== null) { niSetTextColor(child.view, c.r, c.g, c.b, c.a); }
		}
		const size = ps.fontSize !== null ? (ps.fontSize as number) : 17.0;
		const bold = isBoldWeight(ps.fontWeight);
		niSetFont(child.view, size as float32, bold ? 1 : 0);
		sendFontFamily(child, ps.fontFamily !== null ? ps.fontFamily as string : "");
	}
	remeasureText(child);
	if (child.styleCache !== null) { applyPaint(child, child.styleCache); }
	if (parent.view !== null && child.view !== null) { niAddChild(parent.view, child.view); }
}


function onScroll(): void {
	batched((): void => {
		eventRegistry.scrollPhase(
			niLastScrollTag(), niLastScrollPhase(), niLastScrollX(), niLastScrollY(), niLastScrollWidth(), niLastScrollHeight(),
			niLastScrollContentWidth(), niLastScrollContentHeight(),
		);
	});
}

function onControl(): void {
	const tag = niLastControlTag();
	const phase = niLastControlPhase();
	const value: string = niLastControlValue();
	const width = niLastControlWidth();
	const height = niLastControlHeight();
	const input = nodesByTag.has(tag) ? nodesByTag.get(tag) as NativeNode : null;
	const owner = input !== null ? rootOf(input as NativeNode) : null;
	if (input !== null && phase === 0) { input.inputValue = value; }
	if (owner !== null && phase === 1) { owner.focusedInput = input; }
	if (owner !== null && phase === 2 && owner.focusedInput === input) { owner.focusedInput = null; }
	batched((): void => {
		if (phase === 0 && nodesByTag.has(tag) && growInput(nodesByTag.get(tag) as NativeNode) && owner !== null) { requestLayout(owner as NativeRoot); }
		eventRegistry.control(tag, phase, value, width, height);
	});
}

function publishEnvironment(): void {
	publishKeyboard(niKeyboardHeight());
	publishColorScheme(niColorScheme() === 1 ? "dark" : "light");
}

function onEnvironment(): void {
	batched(publishEnvironment);
}

function intrinsicFlex(n: NativeNode, flex: FlexStyle): FlexStyle {
	if (n.view === null) { return flex; }
	if (n.isInput && flex.height === null) {
		const width: float32 = n.multiline && n.w > 0 ? n.w : niScreenWidth();
		niMeasureText(n.view, width);
		n.measuredFor = width;
		flex.height = niMeasuredH();
	} else if (n.sizesItself && (flex.width === null || flex.height === null)) {
		niMeasureText(n.view, niScreenWidth());
		if (flex.width === null) { flex.width = niMeasuredW(); }
		if (flex.height === null) { flex.height = niMeasuredH(); }
	}
	return flex;
}

// RN multiline TextInput: without a height it grows with its content; maxHeight caps it
// through yoga and the native view scrolls past that.
function growsWithContent(n: NativeNode): boolean {
	if (!n.multiline || n.view === null) { return false; }
	const own = n.styleCache;
	return own === null || own.height === null;
}

function growInput(n: NativeNode): boolean {
	if (!growsWithContent(n)) { return false; }
	const before = n.flex !== null ? (n.flex as FlexStyle).height : null;
	const own: Style = n.styleCache !== null ? n.styleCache as Style : {};
	n.flex = intrinsicFlex(n, nativeFlexStyle(own, kindOf(n)));
	return n.flex === null || (n.flex as FlexStyle).height !== before;
}

let frameFire: (() => void) | null = null;

function onFrame(): void {
	const fire = frameFire;
	frameFire = null;
	if (fire !== null) { batched(fire as () => void); }
}

function scheduleFrame(fire: () => void): void {
	frameFire = fire;
	if (niRequestFrame() === 0) {
		frameFire = null;
		setTimeout(fire, 16);
	}
}

function runLoop(): void {
	batched((): void => { niLoopRun(); });
}

let pressSourceTag: int32 = 0;
let pressOwnerTag: int32 = 0;
let pressPhase: int32 = -1;
let pressTime: float64 = -1;
let pressX: float64 = 0;
let pressY: float64 = 0;
let releasedPressTag: int32 = 0;
let releasedPressSourceTag: int32 = 0;
let releasedPressTime: float64 = -1;
let releasedPressX: float64 = 0;
let releasedPressY: float64 = 0;
let releasedPressDispatched = false;

function resetPress(): void {
	pressSourceTag = 0;
	pressOwnerTag = 0;
	pressPhase = -1;
	pressTime = -1;
	releasedPressTag = 0;
	releasedPressSourceTag = 0;
	releasedPressTime = -1;
	releasedPressDispatched = false;
	bubbledPhase = -1;
	bubbledTime = -1;
}

function settlePress(): void {
	if (pressSourceTag !== 0 && livePressTag(pressSourceTag)) { return; }
	resetPress();
}

function retirePressTag(tag: int32): void {
	if (pressOwnerTag === tag) { pressOwnerTag = 0; }
	if (releasedPressTag === tag) {
		releasedPressTag = 0;
		releasedPressDispatched = true;
	}
}

function livePressTag(tag: int32): boolean {
	return nodesByTag.has(tag) || spanTagOwner.has(tag);
}

function ownsPress(tag: int32): boolean {
	if (spanTagOwner.has(tag)) { return true; }
	return nodesByTag.has(tag) && (nodesByTag.get(tag) as NativeNode).pressable;
}

function nearestPress(tag: int32): int32 {
	if (spanTagOwner.has(tag)) { return tag; }
	let at: NativeNode | null = nodesByTag.has(tag) ? nodesByTag.get(tag) as NativeNode : null;
	while (at !== null) {
		const n = at as NativeNode;
		if (n.pressable) { return n.eventTag; }
		at = tree.parentOf(n);
	}
	return 0;
}

function normalizePress(tag: int32, phase: int32, x: float64, y: float64, time: float64): int32 {
	const released = time === releasedPressTime && x === releasedPressX && y === releasedPressY;
	if (!livePressTag(tag) && tag !== pressSourceTag &&
		!(phase === 2 && released && tag === releasedPressSourceTag)) { return 0; }
	const repeated = phase === pressPhase && time === pressTime && x === pressX && y === pressY;
	pressPhase = phase;
	pressTime = time;
	pressX = x;
	pressY = y;
	if (phase === 0) {
		if (repeated || pressSourceTag !== 0) { return 0; }
		pressSourceTag = tag;
		pressOwnerTag = nearestPress(tag);
		return pressOwnerTag;
	}
	if (phase === 4) { return repeated ? 0 : pressOwnerTag; }
	if (phase === 2) {
		if (!released) { return tag; }
		if (releasedPressDispatched) { return 0; }
		releasedPressDispatched = true;
		return releasedPressTag;
	}
	if (phase === 1 || phase === 3) {
		if (released && pressSourceTag === 0) { return 0; }
		const owner = pressOwnerTag;
		pressSourceTag = 0;
		pressOwnerTag = 0;
		releasedPressTag = phase === 1 ? owner : 0;
		releasedPressSourceTag = tag;
		releasedPressTime = time;
		releasedPressX = x;
		releasedPressY = y;
		releasedPressDispatched = phase === 3;
		return owner;
	}
	return 0;
}

let bubbledPhase: int32 = -1;
let bubbledTime: number = -1;
let bubbledX: number = 0;
let bubbledY: number = 0;

// iOS forwards a touch up the superview chain, so one native event can arrive once per tagged view.
function touchTags(tag: int32, phase: int32, x: number, y: number, timeStamp: number): int32[] {
	const owner: NativeNode | null = spanTagOwner.has(tag) ? spanTagOwner.get(tag) as NativeNode : null;
	if (phase === 2 || (!nodesByTag.has(tag) && owner === null)) { return []; }
	if (phase === bubbledPhase && timeStamp === bubbledTime && x === bubbledX && y === bubbledY) { return []; }
	bubbledPhase = phase;
	bubbledTime = timeStamp;
	bubbledX = x;
	bubbledY = y;
	const tags: int32[] = [];
	let at: NativeNode | null = owner;
	if (owner !== null) { tags.push(tag); }
	else { at = nodesByTag.get(tag) as NativeNode; }
	while (at !== null) {
		const n = at as NativeNode;
		if (n.eventTag !== 0) { tags.push(n.eventTag); }
		at = tree.parentOf(n);
	}
	return tags;
}

function appendPacket(target: NativeEventPacket, source: NativeEventPacket): void {
	for (const delivery of source.lifecycle) { target.lifecycle.push(delivery); }
	for (const delivery of source.listeners) { target.listeners.push(delivery); }
}

function deliverEvents(deliveries: NativeEventDelivery[]): void {
	for (const delivery of deliveries) { delivery.handler(delivery.event); }
}

function onTouch(): void {
	deliverTouch(niLastTouchTag(), niLastTouchPhase(), niLastTouchX() as number, niLastTouchY() as number, niLastTouchTime());
}

function deliverTouch(tag: int32, phase: int32, x: number, y: number, timeStamp: number): void {
	if (phase === 1 || phase === 3) {
		if (!livePressTag(tag) && tag !== pressSourceTag) { return; }
		if (timeStamp === releasedPressTime && x === releasedPressX && y === releasedPressY &&
			(pressSourceTag === 0 || timeStamp < pressTime)) { return; }
	}
	const owner = normalizePress(tag, phase, x, y, timeStamp);
	const raw = !ownsPress(tag);
	batched((): void => {
		const tags = touchTags(tag, phase, x, y, timeStamp);
		const touches: NativeEventPacket = { lifecycle: [], listeners: [] };
		for (const target of tags) {
			appendPacket(touches, eventRegistry.capture(target, phase, x, y, timeStamp, true));
		}
		const pointers: NativeEventPacket = { lifecycle: [], listeners: [] };
		if (raw && phase !== 2) {
			appendPacket(pointers, eventRegistry.capture(tag, phase, x, y, timeStamp, false));
		}
		if (owner !== 0 && livePressTag(owner) &&
			((phase !== 0 && phase !== 4) || pressOwnerTag === owner) &&
			(phase !== 1 || releasedPressTag === owner)) {
			appendPacket(pointers, eventRegistry.capture(owner, phase, x, y, timeStamp, false));
		}
		if (phase === 1 || phase === 3) {
			const event = neonEvent(phase === 1 ? "touchend" : "touchcancel");
			event.x = x; event.y = y; event.timeStamp = timeStamp; event.pointerOrigin = true;
			const responderEvents = extractResponderTerminal(event, phase === 1);
			deliverEvents(touches.lifecycle);
			for (const delivery of responderEvents) { delivery.handler(delivery.event); }
			deliverEvents(pointers.lifecycle);
			deliverEvents(touches.listeners);
			deliverEvents(pointers.listeners);
		} else {
			deliverEvents(touches.lifecycle);
			deliverEvents(touches.listeners);
			deliverEvents(pointers.lifecycle);
			deliverEvents(pointers.listeners);
		}
	});
}

export interface NativeHost {
	host: Host;
	rootNode: HostNode;
	relayout: () => void;
}

let bridgeInstalled = false;

function installBridge(): void {
	if (bridgeInstalled) { return; }
	bridgeInstalled = true;
	niSetTouchHandler(onTouch);
	niSetScrollHandler(onScroll);
	niSetResizeHandler(onResize);
	niSetLoopHandler(runLoop);
	niSetFrameHandler(onFrame);
	installFrameDriver({ now: (): number => performance.now(), schedule: scheduleFrame });
	niSetControlHandler(onControl);
	niSetEnvironmentHandler(onEnvironment);
}

export function createNativeHost(): NativeHost {
	resetPress();
	mainRoot.node = nativeNode(niContainerView(), false, false);
	mainRoot.direction = I18nManager.isRTL() ? "rtl" : "ltr";
	mainRoot.node.flex = { width: niScreenWidth(), height: niScreenHeight() };
	installBridge();
	publishEnvironment();
	installNativeAppServices(batched);
	return nativeHostOf(mainRoot);
}

function nativeHostOf(r: NativeRoot): NativeHost {
	const ownedNode = r.node;
	const spansTo = (node: HostNode, spans: TextSpan[]): void => { deliverSpans(r, node, spans); };
	const host: Host = {
		createElement: (tag: string): HostNode => {
			const kind = nativeElementKind(tag);
			let n: NativeNode;
			if (kind === NativeElementKind.Text) {
				n = nativeNode(niTextCreate(), true, false);
				r.textNodes.push(n);
			} else if (kind === NativeElementKind.Scroll) {
				n = nativeNode(niScrollCreate(), false, false);
				n.isScroll = true;
				r.scrollNodes.push(n);
			} else if (kind === NativeElementKind.Input) {
				n = nativeNode(tag === "multilinetextinput" ? niTextAreaCreate() : niInputCreate(), false, false);
				n.isInput = true;
				n.multiline = tag === "multilinetextinput";
				if (n.multiline) { r.inputNodes.push(n); }
			} else if (kind === NativeElementKind.Image) {
				n = nativeNode(niImageCreate(), false, false);
			} else if (kind === NativeElementKind.Component) {
				const element = nativeElement(tag, nativeComponentOf(tag));
				n = nativeNode(element.create(), false, false);
				n.sizesItself = element.sizesItself;
			} else {
				n = nativeNode(niViewCreate(), false, false);
			}
			n.control = kind === NativeElementKind.Text || kind === NativeElementKind.Scroll ? NativeElementKind.View : kind;
			if (tag === "pressable" || kind === NativeElementKind.Input || tag === "switch" ||
				tag === "webview" || tag === "video" || tag === "camera") {
				n.pressable = true;
				ensureTag(n);
				if (tag === "pressable" && n.view !== null) { niViewSetPressable(n.view); }
			}
			n.flex = intrinsicFlex(n, nativeFlexStyle({} as Style, kind));
			n.tag = tag;
			return n as unknown as HostNode;
		},
		createText: (s: string): HostNode => {
			const n = nativeNode(null, false, true);
			n.text = s;
			return n as unknown as HostNode;
		},
		setText: (node: HostNode, s: string): void => {
			const n = node as unknown as NativeNode;
			n.text = s;
			if (n.isText && n.view !== null) {
				niSetText(n.view, s);
				remeasureText(n);
				requestLayout(r);
			}
		},
		setAttr: (node: HostNode, name: string, value: string): void => {
			writeProp(r, node as unknown as NativeNode, name, value);
		},
		removeAttr: (node: HostNode, name: string): void => {
			writeProp(r, node as unknown as NativeNode, name, "");
		},
		setStyle: (node: HostNode, style: Style): void => {
			const n = node as unknown as NativeNode;
			const zIndex = style.zIndex ?? 0;
			if (zIndex !== n.zIndex) {
				const p = tree.parentOf(n);
				if (p !== null) {
					if (n.zIndex !== 0) { p.zChildren -= 1; }
					if (zIndex !== 0) { p.zChildren += 1; }
				}
				n.zIndex = zIndex;
				if (p !== null) { restack(p); }
			}
			n.styleCache = style;
			writeTextInsets(n, style);
			n.flex = intrinsicFlex(n, nativeFlexStyle(style, kindOf(n)));
			n.minFromMeasure = false;
			applyPaint(n, style);
			if (n.isText && !n.isString && tree.spansOf(n) !== null) { refreshLabel(n); }
			else if (n.isText) { remeasureText(n); }
			if (isMounted(n)) { requestLayout(r); }
		},
		setStyleProp: null,
		setStyleClass: null,
		addEvent: (node: HostNode, name: string, handler: (e: NeonEvent) => void): void => {
			const n = node as unknown as NativeNode;
			ensureTag(n);
			eventRegistry.add(n.eventTag, name, handler);
			if (name === "onPress" && n.view !== null) {
				niViewSetPressable(n.view);
				n.pressable = true;
			}
			if (name === "onLayout" && r.layoutNodes.indexOf(n) < 0) { r.layoutNodes.push(n); }
		},
		addEventPhases: (node: HostNode, name: string, lifecycle: (e: NeonEvent) => void,
			listener: (e: NeonEvent) => void): void => {
			const n = node as unknown as NativeNode;
			ensureTag(n);
			eventRegistry.addPhases(n.eventTag, name, lifecycle, listener);
			if (name === "onPress" && n.view !== null) {
				niViewSetPressable(n.view);
				n.pressable = true;
			}
			if (name === "onLayout" && r.layoutNodes.indexOf(n) < 0) { r.layoutNodes.push(n); }
		},
		append: (parent: HostNode, child: HostNode): void => {
			const p = parent as unknown as NativeNode;
			const c = child as unknown as NativeNode;
			refuseIntoText(p, "append");
			if (tree.parentOf(c) === p && childIndex(p, c) === (tree.childrenOf(p).length as int32) - 1) { return; }
			const sameParent = tree.parentOf(c) === p;
			const wasMounted = isMounted(c);
			unlinkChild(c, p);
			tree.attach(c, p, -1);
			if (c.zIndex !== 0) { p.zChildren += 1; }
			if (c.isString && !sameParent) {
				materializeString(r, c, p);
			} else if (!sameParent && p.view !== null && c.view !== null) {
				niAddChild(p.view, c.view);
			} else if (sameParent && p.zChildren === 0 && c.view !== null) {
				niBringChildToFront(c.view);
			}
			if (p.zChildren > 0) { restack(p); }
			if (wasMounted || isMounted(p)) { requestLayout(r); }
		},
		insertBefore: (parent: HostNode, node: HostNode, ref: HostNode | null): void => {
			const p = parent as unknown as NativeNode;
			const n = node as unknown as NativeNode;
			refuseIntoText(p, "insertBefore");
			let idx: int32;
			if (ref === null) {
				idx = tree.childrenOf(p).length as int32;
			} else {
				idx = childIndex(p, ref as unknown as NativeNode);
				if (idx < 0) { throw "insertBefore: the reference node is not a child of the parent"; }
			}
			if (ref === node) { return; }
			const sameParent = tree.parentOf(n) === p;
			const wasMounted = isMounted(n);
			if (wasMounted && !isMounted(p)) { blurInputs(n); }
			const current = sameParent ? childIndex(p, n) : -1;
			if (sameParent && current === idx - 1) { return; }
			if (sameParent && current < idx) { idx -= 1; }
			unlinkChild(n, p);
			tree.attach(n, p, idx);
			if (n.zIndex !== 0) { p.zChildren += 1; }
			if (n.isString && !sameParent) {
				materializeString(r, n, p);
			} else if (!sameParent && p.view !== null && n.view !== null) {
				niAddChild(p.view, n.view);
			}
			if (ref !== null || sameParent || p.zChildren > 0) { restack(p); }
			if (wasMounted || isMounted(p)) { requestLayout(r); }
		},
		removeChild: (parent: HostNode, node: HostNode): void => {
			const p = parent as unknown as NativeNode;
			const n = node as unknown as NativeNode;
			const idx = childIndex(p, n);
			if (idx < 0) { throw "removeChild: the node is not a child of the parent"; }
			tree.detach(n);
			if (n.zIndex !== 0) { p.zChildren -= 1; }
			removePaintChild(p, n);
			if (isMounted(p)) { requestLayout(r); }
			freeLayoutTreeAt(n);
			releaseNativeTree(r, n);
		},
		parentOf: (node: HostNode): HostNode | null => {
			const p = tree.parentOf(node as unknown as NativeNode);
			if (p === null) { return null; }
			return p as unknown as HostNode;
		},
		release: (node: HostNode): void => {
			const n = node as unknown as NativeNode;
			if (tree.parentOf(n) !== null) { throw "release: the node still has a parent; remove it first"; }
			freeLayoutTreeAt(n);
			releaseNativeTree(r, n);
		},
		nextSibling: (node: HostNode): HostNode | null => {
			const n = node as unknown as NativeNode;
			const p = tree.parentOf(n);
			if (p === null) { return null; }
			const idx = childIndex(p, n);
			if (idx < 0 || idx + 1 >= (tree.childrenOf(p).length as int32)) { return null; }
			return tree.childrenOf(p)[idx + 1] as unknown as HostNode;
		},
		firstChild: (node: HostNode): HostNode | null => {
			const n = node as unknown as NativeNode;
			if ((tree.childrenOf(n).length as int32) === 0) { return null; }
			return tree.childrenOf(n)[0] as unknown as HostNode;
		},
		cloneNode: null,
		voidArea: null,
		paragraph: (host: Host, node: HostNode, before: HostNode | null, kids: NeonNode | null, spans: Accessor<TextSpan[]> | null): void => {
			spanParagraph(spansTo, node, kids, spans);
		},
		measureInWindow: (node: HostNode): Result<MeasureRect, MeasureError> => measureNativeWindow(node as unknown as NativeNode, r, ownedNode),
		measureLayout: (node: HostNode, ancestor: HostNode): Result<MeasureRect, MeasureError> => measureNativeLayout(node as unknown as NativeNode, ancestor as unknown as NativeNode, r, ownedNode),
		overlayRoot: (node: HostNode): HostNode => r.node as unknown as HostNode,
		focus: (node: HostNode, focused: boolean): void => {
			const n = node as unknown as NativeNode;
			if (!n.isInput || n.view === null) { throw "native host: focus needs a mounted text input"; }
			niSetFocused(n.view, focused ? 1 : 0);
		},
		accessibilityFocus: nativeAccessibilityFocus(),
		scrollTo: (node: HostNode, x: number, y: number, animated: boolean): void => {
			const n = node as unknown as NativeNode;
			if (!n.isScroll || n.view === null) { throw "native host: scrollTo needs a mounted scroll view"; }
			niScrollTo(n.view, x as float32, y as float32, animated ? 1 : 0);
		},
		measureText: null,
		setResponder: (node: HostNode | null, blockNativeResponder: boolean): void => {
			if (node === null) {
				niClearResponder();
				return;
			}
			const n = node as unknown as NativeNode;
			if (n.view !== null) { niSetResponder(n.view, blockNativeResponder ? 1 : 0); }
		},
	};

	return {
		host,
		rootNode: ownedNode as unknown as HostNode,
		relayout: (): void => { relayout(r); },
	};
}

function writeProp(r: NativeRoot, n: NativeNode, name: string, value: string): void {
	if (n.view === null) { return; }
	if (name === "cellWidth" || name === "cellWidths") { throw new Error(`${name}: the native host has no cell grid; it is a Void-host Text prop`); }
	if (n.isScroll && name === "maintainVisibleContentPosition") {
		n.visibleContent = parseVisibleContent(value);
		return;
	}
	if (n.isScroll && name === "horizontal") { n.horizontal = value === "true"; }
	if (n.isScroll && !name.startsWith("accessib") && name !== "role" && name !== "importantForAccessibility" && name !== "focusable" && name !== "nativeID") {
		niScrollSetOption(n.view, name, value);
		return;
	}
	niSetProp(n.view, name, value);
	if (n.isInput && name === "value") { n.inputValue = value; }
	if (name === "statusBarTranslucent") { requestLayout(r); }
	if (n.isInput && (name === "value" || name === "defaultValue") && growInput(n) && isMounted(n)) { requestLayout(r); }
	if (n.isText && name === "numberOfLines") {
		remeasureText(n);
		if (isMounted(n)) { requestLayout(r); }
	}
}

function removePaintChild(p: NativeNode, n: NativeNode): void {
	if (tree.rowOf(p) < 0) { return; }
	const order = tree.paintOrderOf(p);
	const at = order.indexOf(n);
	if (at < 0) { return; }
	order.splice(at, 1);
}

function unlinkChild(n: NativeNode, nextParent: NativeNode): void {
	const old = tree.parentOf(n);
	if (old === null) { return; }
	if (old !== nextParent && n.yg !== null) {
		const owner = YGNodeGetParent(n.yg);
		if (owner !== null) { YGNodeRemoveChild(owner, n.yg); }
	}
	tree.detach(n);
	if (n.zIndex !== 0) { old.zChildren -= 1; }
	removePaintChild(old, n);
}

function restack(p: NativeNode): void {
	if (p.view === null) { return; }
	if (p.zChildren === 0) {
		for (const child of tree.childrenOf(p)) {
			if (child.view !== null) { niBringChildToFront(child.view); }
		}
		return;
	}
	const order = tree.paintOrderOf(p);
	let count: int32 = 0;
	for (const child of tree.childrenOf(p)) {
		if (child.view === null) { continue; }
		if (count < order.length) { order[count] = child; }
		else { order.push(child); }
		let at = count;
		while (at > 0 && order[at - 1].zIndex > child.zIndex) {
			order[at] = order[at - 1];
			at -= 1;
		}
		order[at] = child;
		count += 1;
	}
	while (order.length > count) { order.pop(); }
	for (const child of order) {
		if (child.view !== null) { niBringChildToFront(child.view); }
	}
}

let batchDepth = 0;

function requestLayout(r: NativeRoot): void {
	if (batchDepth > 0 || getOwner() !== null) {
		r.layoutDirty = true;
		return;
	}
	relayout(r);
}

function batched(fn: () => void): void {
	batchDepth += 1;
	try {
		if (batchDepth === 1) { flush(fn); } else { fn(); }
	} finally {
		batchDepth -= 1;
	}
	if (batchDepth === 0) { relayoutDirty(); }
}

function relayoutDirty(): void {
	for (const r of roots.slice(0, roots.length)) {
		if (r.layoutDirty && roots.indexOf(r) >= 0) { relayout(r); }
	}
}

function relayout(r: NativeRoot): void {
	r.layoutDirty = false;
	const plan = takeLayoutAnimation();
	if (plan !== null) { layoutPlan = plan; }
	layoutPassId += 1;
	const width = r.followsScreen ? niScreenWidth() : r.width;
	const height = r.followsScreen ? niScreenHeight() : r.height;
	if (r.followsScreen) {
		batchDepth += 1;
		try {
			publishWindow(width, height);
			publishSafeArea(niSafeAreaInset(0), niSafeAreaInset(1), niSafeAreaInset(2), niSafeAreaInset(3));
		} finally {
			batchDepth -= 1;
		}
	}
	r.layoutDirty = false;
	const top = r.node;
	top.flex = { width, height };
	prepareVisibleContent(r);
	layoutPassAt(top, width, height, r.direction);
	for (let pass = 0; pass < 3; pass += 1) {
		let changed = false;
		for (const t of r.textNodes) {
			if (!textNeedsRemeasure(t)) { continue; }
			measureTextWithin(t, availableTextWidth(t));
			changed = true;
		}
		for (const field of r.inputNodes) {
			if (!growsWithContent(field) || !isMounted(field) || Math.abs(field.w - field.measuredFor) < 0.5) { continue; }
			if (growInput(field)) { changed = true; }
		}
		if (!changed) { break; }
		layoutPassAt(top, width, height, r.direction);
	}
	layoutPlan = null;
	writeContentSizes(r);
	adjustVisibleContent(r);
	batched((): void => { fireLayouts(r); });
}

function nativeMeasurementError(node: NativeNode, r: NativeRoot, ownedNode: NativeNode): MeasureError | null {
	if (r.node !== ownedNode || roots.indexOf(r) < 0) { return MeasureError.NotMounted; }
	if (r.layoutDirty) { relayout(r); }
	if (rootOf(node) !== r) { return MeasureError.NotMounted; }
	if (node.view === null || node.isString) { return MeasureError.Unsupported; }
	if (node !== ownedNode && !node.framed) { return MeasureError.NotLaidOut; }
	let at: NativeNode | null = node;
	while (at !== null) {
		const current = at as NativeNode;
		const style = current.styleCache;
		if (style !== null && (style as Style).display === "none") { return MeasureError.NotLaidOut; }
		at = tree.parentOf(current);
	}
	return null;
}

function nativeAccessibilityFocus(): ((node: HostNode) => void) | null {
	when (windows) {
		return null;
	} else {
		return (node: HostNode): void => {
			const n = node as unknown as NativeNode;
			if (n.view === null || n.isString || !isMounted(n)) { return; }
			niAccessibilityFocus(n.view);
		};
	}
}

function measureNativeWindow(node: NativeNode, r: NativeRoot, ownedNode: NativeNode): Result<MeasureRect, MeasureError> {
	const error = nativeMeasurementError(node, r, ownedNode);
	if (error !== null) { return Result.err(error as MeasureError); }
	const ready = niMeasureInWindow(node.view);
	if (ready < 0) { return Result.err(MeasureError.NotMounted); }
	if (ready === 0) { return Result.err(MeasureError.NotLaidOut); }
	return Result.ok({ x: niMeasurementX(), y: niMeasurementY(), width: niMeasurementW(), height: niMeasurementH() });
}

function measureNativeLayout(node: NativeNode, ancestor: NativeNode, r: NativeRoot, ownedNode: NativeNode): Result<MeasureRect, MeasureError> {
	const error = nativeMeasurementError(node, r, ownedNode);
	if (error !== null) { return Result.err(error as MeasureError); }
	const parentError = nativeMeasurementError(ancestor, r, ownedNode);
	if (parentError !== null) { return Result.err(parentError as MeasureError); }
	let x = 0.0;
	let y = 0.0;
	let at: NativeNode | null = node;
	while (at !== ancestor) {
		if (at === null) { return Result.err(MeasureError.NotAncestor); }
		const current = at as NativeNode;
		x += current.x;
		y += current.y;
		at = tree.parentOf(current);
	}
	return Result.ok({ x, y, width: node.w, height: node.h });
}

when (hcr || testBuild) {
	function devNode(r: NativeRoot, n: NativeNode, x: float32, y: float32): DevNode {
		const children: DevNode[] = [];
		for (const c of tree.childrenOf(n)) { children.push(devNode(r, c, x + c.x, y + c.y)); }
		let text = n.isString ? n.text : "";
		const spans = tree.spansOf(n);
		if (spans !== null) { for (const span of spans as TextSpan[]) { text += span.text; } }
		return {
			tag: n.tag,
			text,
			value: n.isInput ? n.inputValue : null,
			focused: n === r.focusedInput,
			pressable: n.pressable,
			x, y, w: n.w, h: n.h,
			children,
		};
	}

	function touchTarget(n: NativeNode, x: float32, y: float32, ox: float32, oy: float32): NativeNode | null {
		if (x < ox || y < oy || x >= ox + n.w || y >= oy + n.h) { return null; }
		for (let i = tree.childrenOf(n).length - 1; i >= 0; i -= 1) {
			const c = tree.childrenOf(n)[i];
			const hit = touchTarget(c, x, y, ox + c.x, oy + c.y);
			if (hit !== null) { return hit; }
		}
		return n.eventTag !== 0 ? n : null;
	}

	function nativeDriverPress(x: float32, y: float32): void {
		const target = touchTarget(mainRoot.node, x, y, 0.0, 0.0);
		if (target === null) { throw new Error(`native host: nothing at ${x},${y} takes a touch`); }
		const tag = (target as NativeNode).eventTag;
		const at = performance.now();
		for (const phase of [0, 1, 2]) {
			deliverTouch(tag, phase as int32, x as number, y as number, at);
		}
	}
}

function mountInto(r: NativeRoot, native: NativeHost): void {
	batched((): void => {
		const app = r.mountedApp as () => NeonNode;
		r.mounted = render((h: Host, p: HostNode, b: HostNode | null): void => { app()(h, p, b); }, native.host, native.rootNode);
	});
	native.relayout();
}

function closeRoot(r: NativeRoot): void {
	r.focusedInput = null;
	if (r.mounted !== null) {
		const dispose = r.mounted as Dispose;
		r.mounted = null;
		dispose();
	}
	const top = r.node;
	freeLayoutTreeAt(top);
	for (const child of tree.childrenOf(top)) { releaseNativeTree(r, child); }
	tree.drop(top);
	top.zChildren = 0;
	settlePress();
}

function mountApp(): void {
	mountInto(mainRoot, createNativeHost());
	when (hcr || testBuild) {
		setDevDriver({
			host: "native",
			tree: (): DevNode => devNode(mainRoot, mainRoot.node, 0.0, 0.0),
			pressAt: nativeDriverPress,
			type: (text: string): void => {
				throw new Error("native host: type needs a bridge call that inserts text into the focused platform input; the bridges have none yet (docs/DEVTOOLS.md)");
			},
		});
	}
}

function teardownApp(): void {
	when (hcr || testBuild) {
		setDevDriver(null);
	}
	closeRoot(mainRoot);
}

export interface NativeRootHandle {
	resize: (width: float32, height: float32) => void;
	dispose: Dispose;
}

export function mountNativeRoot(container: Ptr<void>, width: float32, height: float32, app: () => NeonNode): NativeRootHandle {
	installBridge();
	const r = new NativeRoot(nativeNode(container, false, false), false);
	r.width = width;
	r.height = height;
	r.direction = I18nManager.isRTL() ? "rtl" : "ltr";
	const [size, setSize] = createSignal<WindowDimensions>({ width: width, height: height });
	r.mountedApp = (): NeonNode => {
		publishRootWindow(size);
		return app();
	};
	roots.push(r);
	mountInto(r, nativeHostOf(r));
	return {
		resize: (w: float32, h: float32): void => {
			if (roots.indexOf(r) < 0) { throw new Error("native host: resize of a disposed root"); }
			r.width = w;
			r.height = h;
			flush((): void => { setSize({ width: w, height: h }); });
			relayout(r);
		},
		dispose: (): void => {
			if (roots.indexOf(r) < 0) { return; }
			closeRoot(r);
			roots.splice(roots.indexOf(r), 1);
		},
	};
}

export function runApp(app: () => NeonNode): int32 {
	mainRoot.mountedApp = app;
	when (android && hcr) {
		niSetReloadPoll((): void => { batched(pollReload); });
	} else when (hcr) {
		setInterval((): void => { batched(pollReload); }, RELOAD_POLL_MS);
	}
	niRegisterApp(mountApp);
	niSetTeardownHandler(teardownApp);
	return niRunApp();
}
