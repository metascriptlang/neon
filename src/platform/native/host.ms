import { Host, HostNode, NeonNode, render } from "../../render/host";
import { Dispose } from "../../core/types";
import { NeonEvent } from "../../render/event";
import { FlexStyle, YGNode, freeLayoutTree, layoutPass as runLayoutPass } from "../../../../yoga/src/index";
import { YGNodeGetParent, YGNodeRemoveChild, YGNodeLayoutGetPadding, YGNodeLayoutGetBorder, YGNodeLayoutGetMargin, YGEdge } from "../../../../yoga/src/yogaH";
import { Style, mergeStyle } from "../../render/style";
import { NativeElementKind, createNativeEventRegistry, nativeElementKind, nativeFlexStyle, nativeTransform } from "./contract";
import { publishWindow, publishKeyboard, publishColorScheme, publishSafeArea } from "../../render/environment";
import { VisibleContentPosition, parseVisibleContent } from "../../render/visibleContent";
import { installNativeAppServices } from "./appServices";
import { installFrameDriver } from "../../animation/frame";
import { LayoutAnimationPlan, LayoutPhase, takeLayoutAnimation, runLayoutTween } from "../../animation/layoutAnimation";
import "../android/library";

@passC("-I./");

when (ios) {
	@compile("../ios/bridge.m", "-fobjc-arc");
	@passL("-framework UIKit");
	@passL("-framework Foundation");
	@passL("-framework CoreGraphics");
	@passL("-framework QuartzCore");
} else when (android) {
	@compile("../android/bridge.c");
	@passL("-llog");
	@passL("-landroid");
}

import {
	niViewCreate, niTextCreate, niAddChild, niBringChildToFront, niRemoveFromParent, niViewRelease, niSetFrame,
	niSetBackgroundColor, niSetCornerRadius, niSetOpacity, niSetTransform, niSetRotation,
	niSetText, niSetTextColor, niSetFont, niMeasureText, niMeasuredW, niMeasuredH,
	niContainerView, niScreenWidth, niScreenHeight, niViewSetTag, niViewSetPressable,
	niLastTouchTag, niLastTouchPhase, niLastTouchX, niLastTouchY, niLastTouchTime, niSetResponder, niClearResponder,
	niScrollCreate, niScrollSetTag, niScrollSetContentSize, niScrollTo, niScrollSetOption,
	niScrollShift, niScrollOffsetX, niScrollOffsetY,
	niLastScrollTag, niLastScrollPhase, niLastScrollX, niLastScrollY, niLastScrollWidth, niLastScrollHeight,
	niLastScrollContentWidth, niLastScrollContentHeight,
	niInputCreate, niSwitchCreate, niIndicatorCreate, niImageCreate, niControlCreate, niControlSetTag, niSetProp, niSetFocused,
	niModalCreate, niTextAreaCreate,
	niLastControlTag, niLastControlPhase, niLastControlValue, niLastControlWidth, niLastControlHeight,
	niKeyboardHeight, niColorScheme, niRequestFrame, niSafeAreaInset,
} from "./bridge.h";
import { niLoopRun } from "./loop.h";

extern function niRegisterApp(mount: () => void): void;
extern function niRunApp(): int32;
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
	isText: boolean = false;
	isString: boolean = false;
	isScroll: boolean = false;
	isInput: boolean = false;
	multiline: boolean = false;
	control: NativeElementKind = NativeElementKind.View;
	labelOwner: NativeNode | null = null;
	spanOwner: NativeNode | null = null;
	pressable: boolean = false;
	text: string = "";
	children: NativeNode[] = [];
	parent: NativeNode | null = null;
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
	paintOrder: NativeNode[] = [];
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
	contentH: float32 = -1.0;
	horizontal: boolean = false;
	visibleContent: VisibleContentPosition | null = null;
	anchor: NativeNode | null = null;
	anchorX: float32 = 0.0;
	anchorY: float32 = 0.0;

	constructor(view: Ptr<void> | null, isText: boolean, isString: boolean) {
		this.view = view;
		this.isText = isText;
		this.isString = isString;
	}
}

function nativeNode(view: Ptr<void> | null, isText: boolean, isString: boolean): NativeNode {
	return new NativeNode(view, isText, isString);
}

// ---- the yoga sync protocol (yoga/src/sync.ms) on NativeNode ----

export function layoutGetChildren(this n: NativeNode): NativeNode[] { return n.children; }
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
	if (!moved || n.view === null || n === root) { return; }
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
		const parent = n.parent;
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
			const clip = s.overflow === "hidden" ? "hidden" : "visible";
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
		const bold = s.fontWeight !== null && s.fontWeight !== "normal";
		niSetFont(n.view, size as float32, bold ? 1 : 0);
		const align = s.textAlign !== null ? (s.textAlign as string) : "";
		if (align !== n.textAlign) {
			n.textAlign = align;
			niSetProp(n.view, "textAlign", align === "" ? "auto" : align);
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
	if (!n.isText || n.view === null || n.spanOwner !== null) { return; }
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
		if (fresh.minWidth === null) { fresh.minWidth = w; }
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
	const p = n.parent;
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
let root: NativeNode;
const scrollNodes: NativeNode[] = [];
const layoutNodes: NativeNode[] = [];
const textNodes: NativeNode[] = [];
const inputNodes: NativeNode[] = [];

function kindOf(n: NativeNode): NativeElementKind {
	if (n.isText) { return NativeElementKind.Text; }
	if (n.isScroll) { return NativeElementKind.Scroll; }
	if (n.control !== NativeElementKind.View) { return n.control; }
	return NativeElementKind.View;
}

function writeContentSizes(): void {
	for (const s of scrollNodes) {
		if (s.view === null || !isMounted(s)) { continue; }
		let w: float32 = 0.0;
		let h: float32 = 0.0;
		for (const c of s.children) {
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
function prepareVisibleContent(): void {
	for (const s of scrollNodes) {
		s.anchor = null;
		const position = s.visibleContent;
		if (position === null || s.view === null || s.children.length === 0) { continue; }
		if (!isMounted(s)) { continue; }
		const offset = s.horizontal ? niScrollOffsetX(s.view) : niScrollOffsetY(s.view);
		let index: int32 = 0;
		for (const child of s.children[0].children) {
			if (child.isString || !child.framed) { continue; }
			index += 1;
			if (index <= position.minIndexForVisible) { continue; }
			s.anchor = child;
			s.anchorX = child.x;
			s.anchorY = child.y;
			if ((s.horizontal ? child.x + child.w : child.y + child.h) > offset) { break; }
		}
	}
}

function adjustVisibleContent(): void {
	for (const s of scrollNodes.slice(0, scrollNodes.length)) {
		const anchor = s.anchor;
		const position = s.visibleContent;
		s.anchor = null;
		if (anchor === null || position === null || s.view === null) { continue; }
		if (s.children.length === 0 || anchor.parent !== s.children[0]) { continue; }
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

function fireLayouts(): void {
	for (const n of layoutNodes.slice(0, layoutNodes.length)) {
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
	let i: int32 = 0;
	while (i < (parent.children.length as int32)) {
		if (parent.children[i] === node) { return i; }
		i += 1;
	}
	return -1;
}

function isMounted(n: NativeNode): boolean {
	let current: NativeNode | null = n;
	while (current !== null) {
		if (current === root) { return true; }
		current = current.parent;
	}
	return false;
}

function releaseNativeTree(n: NativeNode): void {
	for (const child of n.children) { releaseNativeTree(child); }
	if (n.eventTag !== 0) {
		eventRegistry.remove(n.eventTag);
		nodesByTag.delete(n.eventTag);
		n.eventTag = 0;
	}
	if (n.isScroll) {
		const at = scrollNodes.indexOf(n);
		if (at >= 0) { scrollNodes.splice(at, 1); }
	}
	const laid = layoutNodes.indexOf(n);
	if (laid >= 0) { layoutNodes.splice(laid, 1); }
	if (n.isText) {
		const at = textNodes.indexOf(n);
		if (at >= 0) { textNodes.splice(at, 1); }
	}
	if (n.multiline) {
		const at = inputNodes.indexOf(n);
		if (at >= 0) { inputNodes.splice(at, 1); }
	}
	if (n.view !== null) {
		niRemoveFromParent(n.view);
		niViewRelease(n.view);
		n.view = null;
	}
	n.children = [];
	n.paintOrder = [];
	n.zChildren = 0;
	n.labelOwner = null;
	n.styleCache = null;
	n.flex = null;
}

function onResize(): void {
	relayoutRoot();
}

// RN nested Text: a Text inside a Text is a span of the outermost label, not a view. The label
// shows its strings in order, each in the style its span ancestors layer over the label's.
class LabelRun {
	text: string;
	style: Style;
	tag: int32;

	constructor(text: string, style: Style, tag: int32) {
		this.text = text;
		this.style = style;
		this.tag = tag;
	}
}

const SPAN_RECORD = "\u001e";
const SPAN_FIELD = "\u001f";

function labelRoot(n: NativeNode): NativeNode {
	return n.spanOwner !== null ? n.spanOwner as NativeNode : n;
}

function inLabel(n: NativeNode): boolean {
	return (n.isText && !n.isString) || n.spanOwner !== null;
}

function hasSpans(n: NativeNode): boolean {
	for (const c of n.children) {
		if (c.spanOwner !== null) { return true; }
	}
	return false;
}

function styledRun(s: Style | null): boolean {
	if (s === null) { return false; }
	const deco = s.textDecorationLine;
	return s.fontStyle === "italic" || (deco !== null && deco !== "none");
}

function labelRuns(n: NativeNode, style: Style, tag: int32, out: LabelRun[]): void {
	for (const c of n.children) {
		if (c.isString) {
			if (c.text !== "") { out.push(new LabelRun(c.text, style, tag)); }
		} else if (c.spanOwner !== null) {
			const own = c.styleCache;
			labelRuns(c, own === null ? style : mergeStyle(style, own as Style), c.pressable ? c.eventTag : tag, out);
		}
	}
}

// One run on the wire: text, colour, size, bold, italic, underline, line-through, press tag.
function encodeRun(run: LabelRun): string {
	const s = run.style;
	const deco = s.textDecorationLine !== null ? (s.textDecorationLine as string) : "none";
	const size = s.fontSize !== null ? (s.fontSize as number) : 17;
	return run.text + SPAN_FIELD + (s.color !== null ? (s.color as string) : "") + SPAN_FIELD + size.toString()
		+ SPAN_FIELD + (s.fontWeight !== null && s.fontWeight !== "normal" ? "1" : "0")
		+ SPAN_FIELD + (s.fontStyle === "italic" ? "1" : "0")
		+ SPAN_FIELD + (deco.indexOf("underline") >= 0 ? "1" : "0")
		+ SPAN_FIELD + (deco.indexOf("line-through") >= 0 ? "1" : "0")
		+ SPAN_FIELD + run.tag.toString();
}

// Writes the label's whole content: plain text when no span styles it, else the runs.
function refreshLabel(root: NativeNode): void {
	if (root.view === null) { return; }
	if (root.isString) {
		niSetText(root.view, root.text);
		remeasureText(root);
		return;
	}
	const base: Style = root.styleCache !== null ? root.styleCache as Style : {};
	if (!hasSpans(root) && !styledRun(base)) {
		let text = "";
		for (const c of root.children) {
			if (c.isString) { text += c.text; }
		}
		niSetText(root.view, text);
	} else {
		const runs: LabelRun[] = [];
		labelRuns(root, base, 0, runs);
		let encoded = "";
		for (let i = 0; i < runs.length; i += 1) {
			if (i > 0) { encoded += SPAN_RECORD; }
			encoded += encodeRun(runs[i]);
		}
		niSetProp(root.view, "textSpans", encoded);
	}
	remeasureText(root);
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

function adoptSpan(span: NativeNode, root: NativeNode): void {
	span.spanOwner = root;
	span.flex = null;
	if (span.view !== null) { niRemoveFromParent(span.view); }
	const at = textNodes.indexOf(span);
	if (at >= 0) { textNodes.splice(at, 1); }
	if (span.pressable) { markPressable(root); }
	for (const c of span.children) {
		if (!c.isString && c.isText) { adoptSpan(c, root); }
	}
}

function releaseSpan(span: NativeNode): void {
	span.spanOwner = null;
	if (textNodes.indexOf(span) < 0) { textNodes.push(span); }
	const own: Style = span.styleCache !== null ? span.styleCache as Style : {};
	span.flex = nativeFlexStyle(own, NativeElementKind.Text);
	applyPaint(span, own);
	for (const c of span.children) {
		if (c.spanOwner !== null) { adoptSpan(c, span); }
	}
	refreshLabel(span);
}

// A string under a Text element merges onto the parent's label (the reference
// hosts' rule — no nested labels); under anything else it materialises its
// own label, inheriting the parent's text paint (RN color/fontSize cascade,
// first cut).
function materializeString(child: NativeNode, parent: NativeNode): void {
	if (inLabel(parent) && parent.view !== null) {
		child.labelOwner = parent;
		refreshLabel(labelRoot(parent));
		return;
	}
	if (child.view === null) { child.view = niTextCreate(); }
	if (textNodes.indexOf(child) < 0) { textNodes.push(child); }
	child.isText = true;
	child.labelOwner = child;
	niSetText(child.view, child.text);
	const ps = parent.styleCache;
	if (ps !== null && child.view !== null) {
		const fg = ps.color;
		if (fg !== null) {
			const c = parseHex(fg as string);
			if (c !== null) { niSetTextColor(child.view, c.r, c.g, c.b, c.a); }
		}
		const size = ps.fontSize !== null ? (ps.fontSize as number) : 17.0;
		const bold = ps.fontWeight !== null && ps.fontWeight !== "normal";
		niSetFont(child.view, size as float32, bold ? 1 : 0);
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
	batched((): void => {
		if (phase === 0 && nodesByTag.has(tag) && growInput(nodesByTag.get(tag) as NativeNode)) { requestLayout(); }
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
	} else if (n.control === NativeElementKind.Control && flex.height === null) {
		niMeasureText(n.view, niScreenWidth());
		flex.height = niMeasuredH();
		if (flex.width === null && niMeasuredW() > 0) { flex.width = niMeasuredW(); }
	} else if (n.control === NativeElementKind.Switch && (flex.width === null || flex.height === null)) {
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

let bubbledPhase: int32 = -1;
let bubbledTime: number = -1;
let bubbledX: number = 0;
let bubbledY: number = 0;

// iOS forwards a touch up the superview chain, so one native event can arrive once per tagged view.
function bubbleTouch(tag: int32, phase: int32, x: number, y: number, timeStamp: number): void {
	if (phase === 2 || !nodesByTag.has(tag)) { return; }
	if (phase === bubbledPhase && timeStamp === bubbledTime && x === bubbledX && y === bubbledY) { return; }
	bubbledPhase = phase;
	bubbledTime = timeStamp;
	bubbledX = x;
	bubbledY = y;
	let at: NativeNode | null = nodesByTag.get(tag) as NativeNode;
	while (at !== null) {
		const n = at as NativeNode;
		if (n.eventTag !== 0) { eventRegistry.touch(n.eventTag, phase, x, y, timeStamp); }
		at = n.parent;
	}
}

function onTouch(): void {
	const tag = niLastTouchTag();
	const phase = niLastTouchPhase();
	const x = niLastTouchX() as number;
	const y = niLastTouchY() as number;
	const timeStamp = niLastTouchTime();
	batched((): void => {
		bubbleTouch(tag, phase, x, y, timeStamp);
		eventRegistry.dispatch(tag, phase, x, y, timeStamp);
	});
}

export interface NativeHost {
	host: Host;
	rootNode: HostNode;
	relayout: () => void;
}

export function createNativeHost(): NativeHost {
	const container = niContainerView();
	root = nativeNode(container, false, false);
	root.flex = { width: niScreenWidth(), height: niScreenHeight() };
	niSetTouchHandler(onTouch);
	niSetScrollHandler(onScroll);
	niSetResizeHandler(onResize);
	niSetLoopHandler(runLoop);
	niSetFrameHandler(onFrame);
	installFrameDriver({ now: (): number => performance.now(), schedule: scheduleFrame });
	niSetControlHandler(onControl);
	niSetEnvironmentHandler(onEnvironment);
	publishEnvironment();
	installNativeAppServices(batched);

	const host: Host = {
		createElement: (tag: string): HostNode => {
			const kind = nativeElementKind(tag);
			let n: NativeNode;
			if (kind === NativeElementKind.Text) {
				n = nativeNode(niTextCreate(), true, false);
				textNodes.push(n);
			} else if (kind === NativeElementKind.Scroll) {
				n = nativeNode(niScrollCreate(), false, false);
				n.isScroll = true;
				scrollNodes.push(n);
			} else if (kind === NativeElementKind.Input) {
				n = nativeNode(tag === "multilinetextinput" ? niTextAreaCreate() : niInputCreate(), false, false);
				n.isInput = true;
				n.multiline = tag === "multilinetextinput";
				if (n.multiline) { inputNodes.push(n); }
			} else if (kind === NativeElementKind.Switch) {
				n = nativeNode(niSwitchCreate(), false, false);
			} else if (kind === NativeElementKind.Indicator) {
				n = nativeNode(niIndicatorCreate(), false, false);
			} else if (kind === NativeElementKind.Image) {
				n = nativeNode(niImageCreate(), false, false);
			} else if (kind === NativeElementKind.Modal) {
				n = nativeNode(niModalCreate(), false, false);
			} else if (kind === NativeElementKind.Control) {
				n = nativeNode(niControlCreate(tag), false, false);
			} else {
				n = nativeNode(niViewCreate(), false, false);
			}
			n.control = kind === NativeElementKind.Text || kind === NativeElementKind.Scroll ? NativeElementKind.View : kind;
			n.flex = intrinsicFlex(n, nativeFlexStyle({} as Style, kind));
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
			const owner = n.labelOwner !== null ? (n.labelOwner as NativeNode) : n;
			if (owner.isText && owner.view !== null) {
				refreshLabel(labelRoot(owner));
				requestLayout();
			}
		},
		setAttr: (node: HostNode, name: string, value: string): void => {
			writeProp(node as unknown as NativeNode, name, value);
		},
		removeAttr: (node: HostNode, name: string): void => {
			writeProp(node as unknown as NativeNode, name, "");
		},
		setStyle: (node: HostNode, style: Style): void => {
			const n = node as unknown as NativeNode;
			const zIndex = style.zIndex ?? 0;
			if (zIndex !== n.zIndex) {
				const p = n.parent;
				if (p !== null) {
					if (n.zIndex !== 0) { p.zChildren -= 1; }
					if (zIndex !== 0) { p.zChildren += 1; }
				}
				n.zIndex = zIndex;
				if (p !== null) { restack(p); }
			}
			n.styleCache = style;
			if (n.spanOwner !== null) {
				refreshLabel(n.spanOwner as NativeNode);
				if (isMounted(n)) { requestLayout(); }
				return;
			}
			writeTextInsets(n, style);
			n.flex = intrinsicFlex(n, nativeFlexStyle(style, kindOf(n)));
			applyPaint(n, style);
			if (n.isText && !n.isString && (hasSpans(n) || styledRun(style))) { refreshLabel(n); }
			else if (n.isText) { remeasureText(n); }
			if (isMounted(n)) { requestLayout(); }
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
				const owner = n.spanOwner;
				if (owner !== null) {
					markPressable(owner as NativeNode);
					refreshLabel(owner as NativeNode);
				}
			}
			if (name === "onLayout" && layoutNodes.indexOf(n) < 0) { layoutNodes.push(n); }
		},
		append: (parent: HostNode, child: HostNode): void => {
			const p = parent as unknown as NativeNode;
			const c = child as unknown as NativeNode;
			if (c.parent === p && childIndex(p, c) === (p.children.length as int32) - 1) { return; }
			const sameParent = c.parent === p;
			const wasMounted = isMounted(c);
			unlinkChild(c, p);
			c.parent = p;
			p.children.push(c);
			if (c.zIndex !== 0) { p.zChildren += 1; }
			if (c.isString && !sameParent) {
				materializeString(c, p);
			} else if (inLabel(p)) {
				if (!sameParent) { adoptSpan(c, labelRoot(p)); }
				refreshLabel(labelRoot(p));
			} else if (!sameParent && p.view !== null && c.view !== null) {
				niAddChild(p.view, c.view);
			} else if (sameParent && p.zChildren === 0 && c.view !== null) {
				niBringChildToFront(c.view);
			}
			if (p.zChildren > 0) { restack(p); }
			if (wasMounted || isMounted(p)) { requestLayout(); }
		},
		insertBefore: (parent: HostNode, node: HostNode, ref: HostNode | null): void => {
			const p = parent as unknown as NativeNode;
			const n = node as unknown as NativeNode;
			let idx: int32;
			if (ref === null) {
				idx = p.children.length as int32;
			} else {
				idx = childIndex(p, ref as unknown as NativeNode);
				if (idx < 0) { throw "insertBefore: the reference node is not a child of the parent"; }
			}
			if (ref === node) { return; }
			const sameParent = n.parent === p;
			const wasMounted = isMounted(n);
			const current = sameParent ? childIndex(p, n) : -1;
			if (sameParent && current === idx - 1) { return; }
			if (sameParent && current < idx) { idx -= 1; }
			unlinkChild(n, p);
			n.parent = p;
			p.children.splice(idx, 0, n);
			if (n.zIndex !== 0) { p.zChildren += 1; }
			if (n.isString && !sameParent) {
				materializeString(n, p);
			} else if (inLabel(p)) {
				if (!sameParent) { adoptSpan(n, labelRoot(p)); }
				refreshLabel(labelRoot(p));
			} else if (!sameParent && p.view !== null && n.view !== null) {
				niAddChild(p.view, n.view);
			}
			if (ref !== null || sameParent || p.zChildren > 0) { restack(p); }
			if (wasMounted || isMounted(p)) { requestLayout(); }
		},
		removeChild: (parent: HostNode, node: HostNode): void => {
			const p = parent as unknown as NativeNode;
			const n = node as unknown as NativeNode;
			const idx = childIndex(p, n);
			if (idx < 0) { throw "removeChild: the node is not a child of the parent"; }
			p.children.splice(idx, 1);
			if (n.zIndex !== 0) { p.zChildren -= 1; }
			removePaintChild(p, n);
			n.parent = null;
			if (isMounted(p)) { requestLayout(); }
			freeLayoutTree(n);
			releaseNativeTree(n);
			if (inLabel(p)) { refreshLabel(labelRoot(p)); }
		},
		nextSibling: (node: HostNode): HostNode | null => {
			const n = node as unknown as NativeNode;
			const p = n.parent;
			if (p === null) { return null; }
			const idx = childIndex(p, n);
			if (idx < 0 || idx + 1 >= (p.children.length as int32)) { return null; }
			return p.children[idx + 1] as unknown as HostNode;
		},
		firstChild: (node: HostNode): HostNode | null => {
			const n = node as unknown as NativeNode;
			if ((n.children.length as int32) === 0) { return null; }
			return n.children[0] as unknown as HostNode;
		},
		cloneNode: null,
		voidArea: null,
		overlayRoot: (node: HostNode): HostNode => root as unknown as HostNode,
		focus: (node: HostNode, focused: boolean): void => {
			const n = node as unknown as NativeNode;
			if (!n.isInput || n.view === null) { throw "native host: focus needs a mounted text input"; }
			niSetFocused(n.view, focused ? 1 : 0);
		},
		scrollTo: (node: HostNode, x: number, y: number, animated: boolean): void => {
			const n = node as unknown as NativeNode;
			if (!n.isScroll || n.view === null) { throw "native host: scrollTo needs a mounted scroll view"; }
			niScrollTo(n.view, x as float32, y as float32, animated ? 1 : 0);
		},
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
		rootNode: root as unknown as HostNode,
		relayout: (): void => { relayoutRoot(); },
	};
}

function writeProp(n: NativeNode, name: string, value: string): void {
	if (n.view === null) { return; }
	if (n.isScroll && name === "maintainVisibleContentPosition") {
		n.visibleContent = parseVisibleContent(value);
		return;
	}
	if (n.isScroll && name === "horizontal") { n.horizontal = value === "true"; }
	if (n.isScroll && !name.startsWith("accessib")) {
		niScrollSetOption(n.view, name, value);
		return;
	}
	niSetProp(n.view, name, value);
	if (name === "statusBarTranslucent") { requestLayout(); }
	if (n.isInput && (name === "value" || name === "defaultValue") && growInput(n) && isMounted(n)) { requestLayout(); }
	if (n.isText && name === "numberOfLines") {
		remeasureText(n);
		if (isMounted(n)) { requestLayout(); }
	}
}

function removePaintChild(p: NativeNode, n: NativeNode): void {
	const at = p.paintOrder.indexOf(n);
	if (at < 0) { return; }
	for (let i = at; i + 1 < p.paintOrder.length; i += 1) { p.paintOrder[i] = p.paintOrder[i + 1]; }
	p.paintOrder.pop();
}

function unlinkChild(n: NativeNode, nextParent: NativeNode): void {
	const old = n.parent;
	if (old === null) { return; }
	if (old !== nextParent && n.yg !== null) {
		const owner = YGNodeGetParent(n.yg);
		if (owner !== null) { YGNodeRemoveChild(owner, n.yg); }
	}
	const at = childIndex(old, n);
	if (at >= 0) { old.children.splice(at, 1); }
	if (n.zIndex !== 0) { old.zChildren -= 1; }
	removePaintChild(old, n);
	if (n.spanOwner !== null && old !== nextParent) {
		const root = n.spanOwner as NativeNode;
		if (!inLabel(nextParent)) { releaseSpan(n); }
		refreshLabel(root);
	}
	if (n.isString && old !== nextParent) {
		const owner = n.labelOwner;
		if (owner !== null && owner !== n && owner.view !== null) {
			refreshLabel(labelRoot(owner));
		}
		if (nextParent.isText && n.view !== null) {
			freeLayoutTree(n);
			niRemoveFromParent(n.view);
			niViewRelease(n.view);
			n.view = null;
			n.isText = false;
		}
		n.labelOwner = null;
	}
}

function restack(p: NativeNode): void {
	if (p.view === null) { return; }
	if (p.zChildren === 0) {
		for (const child of p.children) {
			if (child.view !== null && child.spanOwner === null) { niBringChildToFront(child.view); }
		}
		return;
	}
	let count: int32 = 0;
	for (const child of p.children) {
		if (child.view === null || child.spanOwner !== null) { continue; }
		if (count < p.paintOrder.length) { p.paintOrder[count] = child; }
		else { p.paintOrder.push(child); }
		let at = count;
		while (at > 0 && p.paintOrder[at - 1].zIndex > child.zIndex) {
			p.paintOrder[at] = p.paintOrder[at - 1];
			at -= 1;
		}
		p.paintOrder[at] = child;
		count += 1;
	}
	while (p.paintOrder.length > count) { p.paintOrder.pop(); }
	for (const child of p.paintOrder) {
		if (child.view !== null) { niBringChildToFront(child.view); }
	}
}

let batchDepth = 0;
let layoutDirty = false;

function requestLayout(): void {
	if (batchDepth > 0) {
		layoutDirty = true;
		return;
	}
	relayoutRoot();
}

function batched(fn: () => void): void {
	batchDepth += 1;
	try {
		fn();
	} finally {
		batchDepth -= 1;
	}
	if (batchDepth === 0 && layoutDirty) { relayoutRoot(); }
}

function relayoutRoot(): void {
	layoutDirty = false;
	const plan = takeLayoutAnimation();
	if (plan !== null) { layoutPlan = plan; }
	layoutPassId += 1;
	const width = niScreenWidth();
	const height = niScreenHeight();
	batchDepth += 1;
	try {
		publishWindow(width, height);
		publishSafeArea(niSafeAreaInset(0), niSafeAreaInset(1), niSafeAreaInset(2), niSafeAreaInset(3));
	} finally {
		batchDepth -= 1;
	}
	layoutDirty = false;
	root.flex = { width, height };
	prepareVisibleContent();
	runLayoutPass(root, width, height);
	for (let pass = 0; pass < 3; pass += 1) {
		let changed = false;
		for (const t of textNodes) {
			if (!textNeedsRemeasure(t)) { continue; }
			measureTextWithin(t, availableTextWidth(t));
			changed = true;
		}
		for (const field of inputNodes) {
			if (!growsWithContent(field) || !isMounted(field) || Math.abs(field.w - field.measuredFor) < 0.5) { continue; }
			if (growInput(field)) { changed = true; }
		}
		if (!changed) { break; }
		runLayoutPass(root, width, height);
	}
	layoutPlan = null;
	writeContentSizes();
	adjustVisibleContent();
	batched(fireLayouts);
}

let mountedApp: (() => NeonNode) | null = null;
let mounted: Dispose | null = null;

function mountApp(): void {
	const native = createNativeHost();
	batched((): void => {
		mounted = render((mountedApp as () => NeonNode)(), native.host, native.rootNode);
	});
	native.relayout();
}

function teardownApp(): void {
	if (mounted !== null) {
		(mounted as Dispose)();
		mounted = null;
	}
	freeLayoutTree(root);
	for (const child of root.children) { releaseNativeTree(child); }
	root.children = [];
	root.paintOrder = [];
	root.zChildren = 0;
}

export function runApp(app: () => NeonNode): int32 {
	mountedApp = app;
	niRegisterApp(mountApp);
	niSetTeardownHandler(teardownApp);
	return niRunApp();
}
