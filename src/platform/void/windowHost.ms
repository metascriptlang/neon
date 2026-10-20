import { Host, HostNode, VoidArea } from "../../render/host";
import { NeonEvent, neonEvent } from "../../render/event";
import {
	AreaHub,
	AreaKeyAction,
	AreaKeyEvent,
	AreaPointerEvent,
	AreaPointerKind,
	createAreaHub,
	setEventMods,
} from "../../render/voidAreaHandle";
import { Style } from "../../render/style";
import { publishScale } from "../../api/dimensions";
import { publishWindow } from "../../render/environment";
import { FontId } from "../../../../void/src/void2d/font";
import { Scene2D } from "../../../../void/src/void2d/node";
import { create, close } from "../../../../void/src/void2d/scene";
import { Color, rgba } from "../../../../void/src/void2d/types";
import { VoidHost, VoidNode, createVoidHostWith, asFlexStyle, parseColor } from "./host";

export interface WindowArea {
	vh: VoidHost;
	hub: AreaHub;
	width: int32;
	height: int32;
	scale: float32;
	held: int32;
	composing: boolean;
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
		});
		const area: WindowArea = {
			vh,
			hub,
			width: 0 as int32,
			height: 0 as int32,
			scale: 1.0,
			held: 0 as int32,
			composing: false,
		};
		current = area;
		w.opened(area);
		if (pendingStyle !== null) {
			applyAreaStyle(vh, pendingStyle as Style);
			w.requestFrame();
		}
		vh.onDirty(w.dirty);
		return {
			host: vh.host,
			root: vh.root as unknown as HostNode,
			hub,
			release: (): void => {
				current = null;
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
	else if (e.unshifted >= (32 as int32) && e.unshifted !== (127 as int32) && code.startsWith("Key")) { ev.key = String.fromCharCode(e.unshifted); }
	else { ev.key = code; }
	return ev;
}

export function deliverKey(a: WindowArea, e: AreaKeyEvent, code: string): void {
	a.hub.key(e);
	const ev = areaKeyEvent(e, code, a.composing);
	if (e.action === AreaKeyAction.Release) {
		a.vh.keyUp(ev);
		return;
	}
	a.vh.keyDown(ev);
	if (printable(e.text) && !ev.ctrlKey && !ev.altKey && !ev.metaKey) { a.vh.commitText(e.text); }
}

export function deliverPointer(a: WindowArea, e: AreaPointerEvent): void {
	a.hub.pointer(e);
	const x = (e.pixelX as float32) / a.scale;
	const y = (e.pixelY as float32) / a.scale;
	const mods = (e.mods as uint16) as number;
	if (e.kind === AreaPointerKind.Motion) {
		a.vh.pointerMove(x, y, a.held, a.held > (0 as int32), mods);
	} else if (e.kind === AreaPointerKind.Wheel) {
		a.vh.wheel(x, y, e.dx as float32, e.dy as float32, mods);
	} else if (e.kind === AreaPointerKind.Button && e.pressed) {
		a.held = e.button;
		a.vh.pointerDown(x, y, e.button, mods);
		a.vh.clickAt(x, y);
	} else if (e.kind === AreaPointerKind.Button) {
		if (a.held === e.button) { a.held = 0 as int32; }
		a.vh.pointerUp(x, y, e.button, mods);
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

export function deliverFocus(a: WindowArea, focused: boolean): void {
	a.hub.focus(focused);
	a.vh.setWindowFocus(focused);
}
