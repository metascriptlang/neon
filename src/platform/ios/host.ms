// iOS host — a NeonNode mounts into a UIKit view tree through the bridge
// (bridge.h/bridge.m), laid out by the shared yoga pass (yoga/src/sync.ms:
// this module owns the seven `layout*` extensions on IosNode).
//
// First cut of the ios-host arc (~/metascript/.wt/ios-host.md): view / text /
// pressable, colors + fontSize + fontWeight + cornerRadius + opacity, tap
// forwarding through tag routing. Text intrinsic size is an EAGER measure
// (UILabel sizeThatFits written into the FlexStyle as fixed w/h) because the
// yoga binding has no measure-func surface yet — recorded as debt in the card.
//
// Events: the bridge fires one () => void closure per touch phase; the tag +
// phase are read back through niLastTouchTag/Phase (msClosure carries no
// args). The registry maps tag -> IosNode -> handlers.

import { Host, HostNode } from "../../render/host";
import { NeonEvent } from "../../render/event";
import { FlexStyle, layoutPass as runLayoutPass } from "../../../../yoga/src/index";
import { Style } from "../../render/style";
import { IosElementKind, createIosEventRegistry, iosElementKind, iosFlexStyle } from "./contract";

@passC("-I./");

when (ios) {
	@compile("./bridge.m", "-fobjc-arc");
	@passL("-framework UIKit");
	@passL("-framework Foundation");
	@passL("-framework CoreGraphics");
}

import {
	niViewCreate, niTextCreate, niAddChild, niRemoveFromParent, niSetFrame,
	niSetBackgroundColor, niSetCornerRadius, niSetOpacity,
	niSetText, niSetTextColor, niSetFont, niMeasureText, niMeasuredW, niMeasuredH,
	niContainerView, niScreenWidth, niScreenHeight, niViewSetTag,
	niLastTouchTag, niLastTouchPhase,
} from "./bridge.h";

extern function niRegisterApp(mount: () => void): void;
extern function niRunApp(): int32;
extern function niSetTouchHandler(handler: () => void): void;


interface IosNode {
	view: Ptr<void> | null;      // the UIView/UILabel; null on merged string nodes
	isText: boolean;             // owns a UILabel
	isString: boolean;           // a text leaf created by createText
	labelOwner: IosNode | null;  // whose label displays a string node's text
	text: string;
	children: IosNode[];
	parent: IosNode | null;
	eventTag: int32;
	styleCache: Style | null;
	flex: FlexStyle | null;
	lastFlex: FlexStyle | null;
	yg: Ptr<void> | null;
	x: float32; y: float32; w: float32; h: float32;
}

function iosNode(view: Ptr<void> | null, isText: boolean, isString: boolean): IosNode {
	return {
		view, isText, isString, labelOwner: null, text: "",
		children: [], parent: null, eventTag: 0, styleCache: null,
		flex: null, lastFlex: null, yg: null,
		x: 0.0, y: 0.0, w: 0.0, h: 0.0,
	};
}

// ---- the yoga sync protocol (yoga/src/sync.ms) on IosNode ----

export function layoutGetChildren(this n: IosNode): IosNode[] { return n.children; }
export function layoutGetStyle(this n: IosNode): FlexStyle | null { return n.flex; }
export function layoutGetLastStyle(this n: IosNode): FlexStyle | null { return n.lastFlex; }
export function layoutSetLastStyle(this n: IosNode, s: FlexStyle | null): void { n.lastFlex = s; }
export function layoutGetYg(this n: IosNode): Ptr<void> | null { return n.yg; }
export function layoutSetYg(this n: IosNode, yg: Ptr<void> | null): void { n.yg = yg; }
export function layoutSetFrame(this n: IosNode, x: float32, y: float32, w: float32, h: float32): void {
	n.x = x; n.y = y; n.w = w; n.h = h;
	if (n.view !== null) {
		niSetFrame(n.view, x, y, w, h);
	}
}

// ---- style projection + paint ----


function hexNibble(c: string): int32 {
	if (c >= "0" && c <= "9") { return c.charCodeAt(0) - 48; }
	if (c >= "a" && c <= "f") { return c.charCodeAt(0) - 87; }
	if (c >= "A" && c <= "F") { return c.charCodeAt(0) - 55; }
	return -1;
}

interface Rgba { r: float32; g: float32; b: float32; }

function parseHex(css: string): Rgba | null {
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
	return { r: (r as float32) / s, g: (g as float32) / s, b: (b as float32) / s };
}


// The paint half of the projection (docs/STYLE.md §5), onto UIKit.
function applyPaint(n: IosNode, s: Style): void {
	if (n.view === null || !n.isText) {
		if (n.view !== null) {
			const bg = s.backgroundColor;
			if (bg !== null) {
				const c = parseHex(bg as string);
				if (c !== null) { niSetBackgroundColor(n.view, c.r, c.g, c.b, 1.0); }
			}
			if (s.borderRadius !== null) { niSetCornerRadius(n.view, s.borderRadius as number); }
			if (s.opacity !== null) { niSetOpacity(n.view, s.opacity as number); }
		}
	}
	if (n.isText && n.view !== null) {
		const fg = s.color;
		if (fg !== null) {
			const c = parseHex(fg as string);
			if (c !== null) { niSetTextColor(n.view, c.r, c.g, c.b, 1.0); }
		}
		const size = s.fontSize !== null ? (s.fontSize as number) : 17.0;
		const bold = s.fontWeight !== null && s.fontWeight !== "normal";
		niSetFont(n.view, size, bold ? 1 : 0);
	}
}


// Eager text measure: sizeThatFits becomes the node's fixed w/h so yoga lays
// out text without a measure func. Fresh FlexStyle object every time — the
function remeasureText(n: IosNode): void {
	if (!n.isText || n.view === null) { return; }
	niMeasureText(n.view, niScreenWidth());
	const w = niMeasuredW();
	const h = niMeasuredH();
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
	fresh.width = w;
	fresh.height = h;
	n.flex = fresh;
}
// ---- the host ----

let nextTag: int32 = 1;
const eventRegistry = createIosEventRegistry();
let root: IosNode;

function childIndex(parent: IosNode, node: IosNode): int32 {
	let i: int32 = 0;
	while (i < (parent.children.length as int32)) {
		if (parent.children[i] === node) { return i; }
		i += 1;
	}
	return -1;
}

// A string under a Text element merges onto the parent's label (the reference
// hosts' rule — no nested labels); under anything else it materialises its
// own label, inheriting the parent's text paint (RN color/fontSize cascade,
// first cut).
function materializeString(child: IosNode, parent: IosNode): void {
	if (parent.isText && parent.view !== null) {
		child.labelOwner = parent;
		niSetText(parent.view, child.text);
		remeasureText(parent);
		return;
	}
	child.view = niTextCreate();
	child.isText = true;
	child.labelOwner = child;
	niSetText(child.view, child.text);
	const ps = parent.styleCache;
	if (ps !== null && child.view !== null) {
		const fg = ps.color;
		if (fg !== null) {
			const c = parseHex(fg as string);
			if (c !== null) { niSetTextColor(child.view, c.r, c.g, c.b, 1.0); }
		}
		const size = ps.fontSize !== null ? (ps.fontSize as number) : 17.0;
		const bold = ps.fontWeight !== null && ps.fontWeight !== "normal";
		niSetFont(child.view, size, bold ? 1 : 0);
	}
	remeasureText(child);
}


function onTouch(): void {
	const tag = niLastTouchTag();
	const phase = niLastTouchPhase();
	eventRegistry.dispatch(tag, phase, 0, 0);
}

export interface IosHost {
	host: Host;
	rootNode: HostNode;
	relayout: () => void;
}

export function createIosHost(): IosHost {
	const container = niContainerView();
	root = iosNode(container, false, false);
	root.flex = { width: niScreenWidth(), height: niScreenHeight() };
	niSetTouchHandler(onTouch);

	const host: Host = {
		createElement: (tag: string): HostNode => {
			const kind = iosElementKind(tag);
			const n = kind === IosElementKind.Text
				? iosNode(niTextCreate(), true, false)
				: iosNode(niViewCreate(), false, false);
			// RN parity: containers lay out as columns (yoga's default is row).
			n.flex = iosFlexStyle({} as Style, n.isText);
			return n as unknown as HostNode;
		},
		createText: (s: string): HostNode => {
			const n = iosNode(null, false, true);
			n.text = s;
			return n as unknown as HostNode;
		},
		setText: (node: HostNode, s: string): void => {
			const n = node as unknown as IosNode;
			n.text = s;
			const owner = n.labelOwner !== null ? (n.labelOwner as IosNode) : n;
			if (owner.isText && owner.view !== null) {
				niSetText(owner.view, s);
				remeasureText(owner);
				relayoutRoot();
			}
		},
		setAttr: (node: HostNode, name: string, value: string): void => {
			// No non-style, non-event attrs in the first-cut vocabulary.
		},
		removeAttr: (node: HostNode, name: string): void => {},
		setStyle: (node: HostNode, style: Style): void => {
			const n = node as unknown as IosNode;
			n.styleCache = style;
			n.flex = iosFlexStyle(style, n.isText);
			applyPaint(n, style);
			if (n.isText) { remeasureText(n); }
		},
		setStyleProp: null,
		setStyleClass: null,
		addEvent: (node: HostNode, name: string, handler: (e: NeonEvent) => void): void => {
			const n = node as unknown as IosNode;
			if (n.eventTag === 0) {
				n.eventTag = nextTag;
				nextTag += 1;
				if (n.view !== null) { niViewSetTag(n.view, n.eventTag); }
			}
			eventRegistry.add(n.eventTag, name, handler);
		},
		append: (parent: HostNode, child: HostNode): void => {
			const p = parent as unknown as IosNode;
			const c = child as unknown as IosNode;
			if (c.parent !== null) {
				const old = c.parent;
				const idx = childIndex(old, c);
				if (idx >= 0) { old.children.splice(idx, 1); }
			}
			c.parent = p;
			p.children.push(c);
			if (c.isString) {
				materializeString(c, p);
				return;
			}
			if (p.view !== null && c.view !== null) { niAddChild(p.view, c.view); }
		},
		insertBefore: (parent: HostNode, node: HostNode, ref: HostNode | null): void => {
			const p = parent as unknown as IosNode;
			const n = node as unknown as IosNode;
			let idx: int32;
			if (ref === null) {
				idx = p.children.length as int32;
			} else {
				idx = childIndex(p, ref as unknown as IosNode);
				if (idx < 0) { throw "insertBefore: the reference node is not a child of the parent"; }
			}
			if (n.parent !== null) {
				const old = n.parent;
				const cur = childIndex(old, n);
				if (cur >= 0) { old.children.splice(cur, 1); }
			}
			n.parent = p;
			p.children.splice(idx, 0, n);
			if (n.isString) {
				materializeString(n, p);
				return;
			}
			if (p.view !== null && n.view !== null) {
				niAddChild(p.view, n.view);
				const refChild = ref as unknown as IosNode;
				if (refChild !== null && refChild.view !== null) {
					// UIKit stacking order follows addSubview order; the next
					// relayout re-asserts frames, z-order matches the array.
					sortLater(p);
				}
			}
		},
		removeChild: (parent: HostNode, node: HostNode): void => {
			const p = parent as unknown as IosNode;
			const n = node as unknown as IosNode;
			const idx = childIndex(p, n);
			if (idx < 0) { throw "removeChild: the node is not a child of the parent"; }
			p.children.splice(idx, 1);
			n.parent = null;
			if (n.view !== null) { niRemoveFromParent(n.view); }
		},
		nextSibling: (node: HostNode): HostNode | null => {
			const n = node as unknown as IosNode;
			const p = n.parent;
			if (p === null) { return null; }
			const idx = childIndex(p, n);
			if (idx < 0 || idx + 1 >= (p.children.length as int32)) { return null; }
			return p.children[idx + 1] as unknown as HostNode;
		},
		firstChild: (node: HostNode): HostNode | null => {
			const n = node as unknown as IosNode;
			if ((n.children.length as int32) === 0) { return null; }
			return n.children[0] as unknown as HostNode;
		},
		cloneNode: null,
	};

	return {
		host,
		rootNode: root as unknown as HostNode,
		relayout: (): void => { relayoutRoot(); },
	};
}

// UIKit stacking order must follow the children array; frames alone do not
// reorder views. First cut: re-add subviews in array order on insert.
function sortLater(p: IosNode): void {
	if (p.view === null) { return; }
	for (let i = 0; i < p.children.length; i += 1) {
		const c = p.children[i];
		if (p.view !== null && c.view !== null && !c.isString) { niAddChild(p.view, c.view); }
	}
}

function relayoutRoot(): void {
	if (root.flex === null) { return; }
	runLayoutPass(root, niScreenWidth(), niScreenHeight());
}

// ---- app entry (probe/iosApp/app.ms drives this) ----

export function registerAndRun(mount: () => void): int32 {
	niRegisterApp(mount);
	return niRunApp();
}

