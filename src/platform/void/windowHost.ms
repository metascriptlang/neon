import { Host, HostNode, VoidArea } from "../../render/host";
import { NeonEvent, neonEvent, DOM_DELTA_PIXEL, DOM_DELTA_LINE } from "../../render/event";
import {
	AreaHub,
	AreaLayer,
	AreaKeyAction,
	AreaKeyEvent,
	AreaKeyMod,
	AreaPointerEvent,
	AreaPointerKind,
	createAreaHub,
	setEventMods,
} from "../../render/voidAreaHandle";
import { Style } from "../../render/style";
import { publishScale } from "../../api/dimensions";
import { DESKTOP_BACK_BUTTON, dispatchHardwareBackPress } from "../../api/backHandler";
import { publishWindow } from "../../render/environment";
import { FontId } from "../../../../void/src/void2d/font";
import { Scene2D, NodeRef } from "../../../../void/src/void2d/node";
import { SPAN_HOST } from "../../render/spanHost";
import { create, close, present, prepare, drawScreen, drawScreenUntil, paintedSlots, isClosed } from "../../../../void/src/void2d/scene";
import { fbWidth, fbHeight, dpiScale } from "../../../../void/src/host/gpu";
import { beginScreenPassWith, endPass, commit } from "../../../../void/src/gpu/door";
import { Color, rgba } from "../../../../void/src/void2d/types";
import { VoidHost, VoidNode, createVoidHostWith, asFlexStyle, parseColor } from "./host";
when (hcr || testBuild) {
	import { DevNode, setDevDriver } from "../../devtools/driver";
}
import { accessor } from "../../core/signal";
import { AreaFace, getAreaFaceContext } from "./areaScope";

export interface WindowArea {
	vh: VoidHost;
	hub: AreaHub;
	width: int32;
	height: int32;
	scale: float32;
	held: int32;
	composing: boolean;
	textInput: boolean;
	painted: NodeRef[];
}

export interface AreaWindow {
	name: string;
	font: FontId;
	family: string | null;
	pixelWidth: () => int32;
	pixelHeight: () => int32;
	requestFrame: () => void;
	dirty: () => void;
	setImeRect: (pixelX: int32, pixelY: int32, pixelW: int32, pixelH: int32) => void;
	opened: (area: WindowArea) => void;
	released: (area: WindowArea) => void;
}

class WindowNode {
	tag: string;
	parent: WindowNode | null = null;
	children: WindowNode[] = [];

	constructor(tag: string) {
		this.tag = tag;
	}
}

export function windowNode(tag: string): HostNode {
	return new WindowNode(tag) as unknown as HostNode;
}

function asWindowNode(node: HostNode): WindowNode {
	return node as unknown as WindowNode;
}

function detach(n: WindowNode): void {
	if (n.parent === null) { return; }
	const siblings = (n.parent as WindowNode).children;
	const at = siblings.indexOf(n);
	if (at >= 0) { siblings.splice(at, 1); }
	n.parent = null;
}

function insertChild(parent: HostNode, node: HostNode, ref: HostNode | null): void {
	const p = asWindowNode(parent);
	const n = asWindowNode(node);
	detach(n);
	const at = ref === null ? -1 : p.children.indexOf(asWindowNode(ref as HostNode));
	if (at < 0) { p.children.push(n); } else { p.children.splice(at, 0, n); }
	n.parent = p;
}

function applyAreaStyle(vh: VoidHost, style: Style): void {
	(vh.root as VoidNode).flex = asFlexStyle(style);
	if (style.backgroundColor !== null) {
		const c = parseColor(style.backgroundColor as string);
		if (c !== null) { vh.scene.clear = c as Color; }
	}
}

export function windowHost(w: AreaWindow): Host {
	let current: WindowArea | null = null;
	let pendingStyle: Style | null = null;

	const refuse = (what: string): void => {
		throw new Error(`${w.name} host: ${what}; the window holds exactly one <Void>`);
	};

	const placeChild = (parent: HostNode, child: HostNode, ref: HostNode | null): void => {
		const tag = asWindowNode(child).tag;
		if (asWindowNode(parent).tag === "window" && tag !== "void" && tag !== "") { refuse(`<${tag}> cannot be a child of the window`); }
		insertChild(parent, child, ref);
	};

	const openArea = (node: HostNode): VoidArea => {
		if (current !== null) { refuse("a second <Void> was mounted"); }
		const vh = createVoidHostWith(Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0)), w.font, w.family);
		const hub = createAreaHub({
			initialPixelWidth: w.pixelWidth(),
			initialPixelHeight: w.pixelHeight(),
			requestFrame: w.requestFrame,
			setImeRect: w.setImeRect,
			enter: (mount: () => void): void => {
				const face: AreaFace = { font: w.font, family: w.family };
				getAreaFaceContext().provider({
					value: accessor((): AreaFace => face),
					children: (host: Host, parent: HostNode, before: HostNode | null): void => { mount(); },
				})(vh.host, vh.root, null);
			},
		});
		const area: WindowArea = {
			vh,
			hub,
			width: 0 as int32,
			height: 0 as int32,
			scale: 1.0,
			held: 0 as int32,
			composing: false,
			textInput: false,
			painted: [],
		};
		current = area;
		w.opened(area);
		when (hcr || testBuild) {
			setDevDriver({
				host: w.name,
				tree: (): DevNode => vh.snapshot(),
				pressAt: (x: float32, y: float32): void => {
					const px = (x * area.scale) as float64;
					const py = (y * area.scale) as float64;
					deliverPointer(area, { kind: AreaPointerKind.Button, pixelX: px, pixelY: py, button: 1 as int32, pressed: true, dx: 0.0, dy: 0.0 });
					deliverPointer(area, { kind: AreaPointerKind.Button, pixelX: px, pixelY: py, button: 1 as int32, pressed: false, dx: 0.0, dy: 0.0 });
					w.requestFrame();
				},
				type: (text: string): void => {
					deliverText(area, text);
					w.requestFrame();
				},
			});
		}
		if (pendingStyle !== null) {
			applyAreaStyle(vh, pendingStyle as Style);
			w.requestFrame();
		}
		vh.onDirty(w.dirty);
		vh.setLayers((): AreaLayer[] => {
			const order: AreaLayer[] = [];
			for (const d of layersInPaintOrder(vh, hub.layers(), area.painted)) { order.push(d.layer); }
			return order;
		});
		return {
			host: vh.host,
			root: vh.root as unknown as HostNode,
			hub,
			release: (): void => {
				current = null;
				when (hcr || testBuild) {
					setDevDriver(null);
				}
				vh.scene.close();
				w.released(area);
			},
		};
	};

	return {
		createElement: (tag: string): HostNode => windowNode(tag),
		createText: (s: string): HostNode => {
			if (s !== "") { refuse(`text "${s}" cannot be a child of the window`); }
			return windowNode("");
		},
		setText: (node: HostNode, s: string): void => {
			if (s !== "") { refuse(`text "${s}" cannot be set on the window`); }
		},
		setAttr: (node: HostNode, name: string, value: string): void => {},
		removeAttr: (node: HostNode, name: string): void => {},
		setStyle: (node: HostNode, style: Style): void => {
			pendingStyle = style;
			if (current !== null) {
				applyAreaStyle((current as WindowArea).vh, style);
				w.requestFrame();
			}
		},
		setStyleProp: null,
		setStyleClass: null,
		addEvent: (node: HostNode, name: string, handler: (e: NeonEvent) => void): void => {
			refuse(`${name} on the window element`);
		},
		append: (parent: HostNode, child: HostNode): void => { placeChild(parent, child, null); },
		insertBefore: placeChild,
		removeChild: (parent: HostNode, node: HostNode): void => { detach(asWindowNode(node)); },
		parentOf: (node: HostNode): HostNode | null => {
			const p = asWindowNode(node).parent;
			return p === null ? null : p as unknown as HostNode;
		},
		release: (node: HostNode): void => {},
		nextSibling: (node: HostNode): HostNode | null => {
			const n = asWindowNode(node);
			if (n.parent === null) { return null; }
			const siblings = (n.parent as WindowNode).children;
			const at = siblings.indexOf(n);
			return at + 1 < siblings.length ? siblings[at + 1] as unknown as HostNode : null;
		},
		firstChild: (node: HostNode): HostNode | null => {
			const n = asWindowNode(node);
			return n.children.length > 0 ? n.children[0] as unknown as HostNode : null;
		},
		cloneNode: null,
		voidArea: openArea,
		scrollTo: null,
		measureText: null,
	};
}

function printable(text: string): boolean {
	if (text.length === 0) { return false; }
	const c = text.charCodeAt(0);
	return c >= 32 && c !== 127;
}

export function areaKeyEvent(e: AreaKeyEvent, code: string, composing: boolean): NeonEvent {
	const ev = neonEvent(e.action === AreaKeyAction.Release ? "keyup" : "keydown");
	ev.code = code;
	setEventMods(ev, e.mods);
	ev.repeat = e.action === AreaKeyAction.Repeat;
	ev.isComposing = composing;
	ev.scancode = e.scancode;
	ev.consumedMods = (e.consumedMods as uint16) as number;
	ev.unshifted = e.unshifted;
	ev.text = e.text;
	if (printable(e.text)) { ev.key = e.text; }
	else if (e.unshifted >= (32 as int32) && e.unshifted !== (127 as int32)) { ev.key = String.fromCharCode(e.unshifted); }
	else { ev.key = code; }
	return ev;
}

function chordBack(e: AreaKeyEvent, code: string): boolean {
	const mods = e.mods;
	if (mods.has(AreaKeyMod.Ctrl) || mods.has(AreaKeyMod.Shift)) { return false; }
	when (macos) {
		return code === "BracketLeft" && mods.has(AreaKeyMod.Super) && !mods.has(AreaKeyMod.Alt);
	}
	return code === "ArrowLeft" && mods.has(AreaKeyMod.Alt) && !mods.has(AreaKeyMod.Super);
}

export function deliverKey(a: WindowArea, e: AreaKeyEvent, code: string): void {
	a.hub.key(e);
	const ev = areaKeyEvent(e, code, a.composing);
	if (e.action === AreaKeyAction.Release) {
		a.vh.keyUp(ev);
		return;
	}
	a.vh.keyDown(ev);
	if (e.action === AreaKeyAction.Press && !ev.propagationStopped && chordBack(e, code)) {
		dispatchHardwareBackPress();
		return;
	}
	if (printable(e.text) && !ev.ctrlKey && !ev.altKey && !ev.metaKey) { a.vh.commitText(e.text); }
}

export function deliverPointer(a: WindowArea, e: AreaPointerEvent): void {
	a.hub.pointer(e);
	if (e.kind === AreaPointerKind.Button && e.button === DESKTOP_BACK_BUTTON) {
		if (!e.pressed) { dispatchHardwareBackPress(); }
		return;
	}
	const x = (e.pixelX as float32) / a.scale;
	const y = (e.pixelY as float32) / a.scale;
	const mods = (e.mods as uint16) as number;
	if (e.kind === AreaPointerKind.Motion) {
		a.vh.pointerMove(x, y, a.held, a.held > (0 as int32), mods);
	} else if (e.kind === AreaPointerKind.Wheel) {
		if (e.deltaMode === DOM_DELTA_PIXEL) {
			a.vh.wheel(x, y, (e.dx as float32) / a.scale, (e.dy as float32) / a.scale, DOM_DELTA_PIXEL, mods);
		} else if (e.deltaMode === DOM_DELTA_LINE) {
			a.vh.wheel(x, y, e.dx as float32, e.dy as float32, DOM_DELTA_LINE, mods);
		} else {
			throw new Error(`a wheel event reached the area with deltaMode ${e.deltaMode}, which is neither pixels nor lines`);
		}
	} else if (e.kind === AreaPointerKind.Button && e.pressed) {
		a.held = e.button;
		a.vh.pointerDown(x, y, e.button, mods);
	} else if (e.kind === AreaPointerKind.Button) {
		if (a.held === e.button) { a.held = 0 as int32; }
		a.vh.pointerUp(x, y, e.button, mods);
	} else if (e.kind === AreaPointerKind.Leave) {
		a.vh.pointerLeave();
	}
}

export function deliverText(a: WindowArea, text: string): void {
	a.hub.text(text);
	a.vh.textInput(text);
}

export function deliverPreedit(a: WindowArea, text: string, cursor: int32): void {
	a.hub.preedit({ text, cursor });
	a.composing = text.length > 0;
	a.vh.composeText(text, cursor);
}

export function deliverResize(a: WindowArea, width: int32, height: int32, scale: float64): void {
	a.width = width;
	a.height = height;
	a.scale = scale as float32;
	publishScale(scale, 1);
	publishWindow(a.logicalWidth(), a.logicalHeight());
	a.hub.resize({ pixelWidth: width, pixelHeight: height, scale: a.scale });
}

export function logicalWidth(this a: WindowArea): float32 { return (a.width as float32) / a.scale; }
export function logicalHeight(this a: WindowArea): float32 { return (a.height as float32) / a.scale; }

export function syncTextInput(a: WindowArea, set: (on: boolean) => void): void {
	const wants = a.vh.imeRect() !== null;
	if (wants === a.textInput) { return; }
	a.textInput = wants;
	set(wants);
}

export function deliverFocus(a: WindowArea, focused: boolean): void {
	a.hub.focus(focused);
	a.vh.setWindowFocus(focused);
}

export struct DueLayer {
	layer: AreaLayer;
	slot: NodeRef;
	rank: int32;
}

function rankOf(painted: NodeRef[], slot: NodeRef): int32 {
	for (let i = 0; i < painted.length; i += 1) {
		const p = painted[i];
		if (p.id.index === slot.id.index && p.id.generation === slot.id.generation) { return i as int32; }
	}
	return -1 as int32;
}

function spanPath(node: HostNode): int32[] {
	const path: int32[] = [];
	let at: HostNode = node;
	let up = SPAN_HOST.parentOf(at);
	while (up !== null) {
		let i: int32 = 0;
		let c = SPAN_HOST.firstChild(up as HostNode);
		while (c !== null && c !== at) {
			i += 1;
			c = SPAN_HOST.nextSibling(c as HostNode);
		}
		path.push(i);
		at = up as HostNode;
		up = SPAN_HOST.parentOf(at);
	}
	path.reverse();
	return path;
}

function spanOrder(a: HostNode, b: HostNode): number {
	const x = spanPath(a);
	const y = spanPath(b);
	for (let i = 0; i < x.length && i < y.length; i += 1) {
		if (x[i] !== y[i]) { return x[i] - y[i]; }
	}
	return x.length - y.length;
}

export function layersInPaintOrder(vh: VoidHost, layers: AreaLayer[], painted: NodeRef[]): DueLayer[] {
	const due: DueLayer[] = [];
	for (const layer of layers) {
		const slot = vh.layerSlot(layer.anchor);
		if (slot === null) { continue; }
		const rank = rankOf(painted, slot as NodeRef);
		if (rank < 0) { continue; }
		due.push({ layer, slot: slot as NodeRef, rank });
	}
	due.sort((x: DueLayer, y: DueLayer): number => x.rank !== y.rank ? x.rank - y.rank : spanOrder(x.layer.anchor.node, y.layer.anchor.node));
	return due;
}

export function drawArea(a: WindowArea): boolean {
	a.vh.layout(a.logicalWidth(), a.logicalHeight(), a.scale);
	const scene = a.vh.scene;
	if (scene.isClosed()) { return false; }
	const layers = a.hub.layers();
	if (layers.length === 0) {
		scene.present();
		return true;
	}
	const width = fbWidth();
	const height = fbHeight();
	const dpi = dpiScale();
	a.hub.layoutLayers(width, height);
	if (scene.isClosed()) { return false; }
	for (const layer of a.hub.layers()) { a.vh.layerSlot(layer.anchor); }
	scene.prepare((width as float32) / dpi, (height as float32) / dpi, dpi);
	a.painted = scene.paintedSlots();
	const due = layersInPaintOrder(a.vh, a.hub.layers(), a.painted);
	const order: AreaLayer[] = [];
	for (const d of due) { order.push(d.layer); }
	a.hub.prepareLayers(order, width, height);
	if (scene.isClosed()) { return false; }
	beginScreenPassWith(scene.clear.r, scene.clear.g, scene.clear.b, scene.clear.a);
	a.hub.drawLayers((layer: AreaLayer): void => { scene.drawScreenUntil(due[order.indexOf(layer)].slot); });
	scene.drawScreen();
	endPass();
	commit();
	return true;
}
