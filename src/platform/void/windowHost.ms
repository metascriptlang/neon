import { Host, HostNode, VoidArea } from "../../render/host";
import { NeonEvent, neonEvent } from "../../render/event";
import {
	AreaHub,
	AreaKeyAction,
	AreaKeyEvent,
	AreaKeyMod,
	AreaPointerEvent,
	AreaPointerKind,
	createAreaHub,
} from "../../render/voidAreaHandle";
import { Style } from "../../render/style";
import { publishScale } from "../../api/dimensions";
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

interface WindowNode {
	tag: string;
}

export function windowNode(tag: string): HostNode {
	const n: WindowNode = { tag };
	return n as unknown as HostNode;
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
		createElement: (tag: string): HostNode => {
			if (tag !== "void") { refuse(`<${tag}> cannot be a child of the window`); }
			return windowNode(tag);
		},
		createText: (s: string): HostNode => {
			refuse(`text "${s}" cannot be a child of the window`);
			return windowNode("");
		},
		setText: (node: HostNode, s: string): void => { refuse("text cannot be set on the window"); },
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
		append: (parent: HostNode, child: HostNode): void => {},
		insertBefore: (parent: HostNode, node: HostNode, ref: HostNode | null): void => {},
		removeChild: (parent: HostNode, node: HostNode): void => {},
		parentOf: (node: HostNode): HostNode | null => null,
		release: (node: HostNode): void => {},
		nextSibling: (node: HostNode): HostNode | null => null,
		firstChild: (node: HostNode): HostNode | null => null,
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
	ev.altKey = e.mods.has(AreaKeyMod.Alt);
	ev.ctrlKey = e.mods.has(AreaKeyMod.Ctrl);
	ev.metaKey = e.mods.has(AreaKeyMod.Super);
	ev.shiftKey = e.mods.has(AreaKeyMod.Shift);
	ev.repeat = e.action === AreaKeyAction.Repeat;
	ev.isComposing = composing;
	ev.scancode = e.scancode;
	ev.mods = (e.mods as uint16) as number;
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
	if (e.kind === AreaPointerKind.Motion) {
		a.vh.pointerMove(x, y, a.held, a.held > (0 as int32));
	} else if (e.kind === AreaPointerKind.Wheel) {
		a.vh.wheel(x, y, e.dx as float32, e.dy as float32);
	} else if (e.kind === AreaPointerKind.Button && e.pressed) {
		a.held = e.button;
		a.vh.pointerDown(x, y, e.button);
		a.vh.clickAt(x, y);
	} else if (e.kind === AreaPointerKind.Button) {
		if (a.held === e.button) { a.held = 0 as int32; }
		a.vh.pointerUp(x, y, e.button);
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
	a.hub.resize({ pixelWidth: width, pixelHeight: height, scale: a.scale });
}

export function logicalWidth(this a: WindowArea): float32 { return (a.width as float32) / a.scale; }
export function logicalHeight(this a: WindowArea): float32 { return (a.height as float32) / a.scale; }

export function deliverFocus(a: WindowArea, focused: boolean): void {
	a.hub.focus(focused);
	a.vh.setWindowFocus(focused);
}
