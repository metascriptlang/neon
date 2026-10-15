// An Ion window whose content is one full-window <Void>: the window is the outer
// host, it accepts only the `void` tag, and its voidArea parents a visual holding
// the swapchain of a Void view under the window's root (void/docs/EMBED.md).

import {
	createWindow, defaultOptions, runLoop, windowRoot, windowDevice, commit, setImeRect,
	setFramePolicy, requestFrame, FrameOnDemand, pixelWidth, pixelHeight,
	onPointer, onKey, onText, onImePreedit, onFocus, onResize, onFrame,
	PointerEvent, PointerKind, KeyEvent, KeyAction, KeyMod, Window, keyName,
} from "../../../../ion/src/index";
import { embedRegister, viewCreate, viewResize, viewFrame, viewDestroy, viewSwapChain, currentView, gfxSetup, ViewId, ViewInvalid } from "../../../../void/src/sokol/gpu";
import { setup2d } from "../../../../void/src/void2d/draw";
import { addFont, FontId, DEFAULT_FONT } from "../../../../void/src/void2d/font";
import { Scene2D } from "../../../../void/src/void2d/node";
import { create, close, present } from "../../../../void/src/void2d/scene";
import { Color, rgba } from "../../../../void/src/void2d/types";
import { exit } from "std/process";
import { Host, HostNode, NeonNode, VoidArea, render } from "../../render/host";
import { NeonEvent, neonEvent } from "../../render/event";
import {
	AreaHub, VoidAreaHandle, AreaKeyEvent, AreaKeyAction, AreaKeyMod, AreaPointerEvent, AreaPointerKind, createAreaHub,
} from "../../render/voidAreaHandle";
import { Style } from "../../render/style";
import { publishScale } from "../../api/dimensions";
import { VoidHost, VoidNode, createVoidHostWith, asFlexStyle, parseColor } from "../void/host";

when (windows) {
	@compile("./voidVisual.cpp");
}
@include("./voidVisual.h");

extern function voidVisualAttach(device: Ptr<void>, root: Ptr<void>, swapChain: int64): Ptr<void>;
extern function voidVisualDetach(root: Ptr<void>, visual: Ptr<void>): void;

export interface DesktopOptions {
	title: string;
	width: number;
	height: number;
	font: string;
}

export function desktopOptions(title: string, width: number, height: number): DesktopOptions {
	return { title, width, height, font: "assets/font.ttf" };
}

interface WindowNode {
	tag: string;
}

function windowNode(tag: string): HostNode {
	const n: WindowNode = { tag };
	return n as unknown as HostNode;
}

interface Area {
	win: Window;
	view: ViewId;
	visual: Ptr<void> | null;
	vh: VoidHost;
	width: int32;
	height: int32;
	scale: float32;
	composing: boolean;
	held: int32;
	hub: AreaHub;
}

// [frames the scene's dirty wake requested, frames drawn], since the process began.
let _requested = 0;
let _drawn = 0;

export function frameCounts(): number[] { return [_requested, _drawn]; }

const _areas: Area[] = [];
let _font: FontId = DEFAULT_FONT;
let _wired = false;

function areaOfWindow(window: int32): Area | null {
	for (const a of _areas) {
		if (a.win.id === window) { return a; }
	}
	return null;
}

function areaOfView(view: ViewId): Area | null {
	for (const a of _areas) {
		if (a.view === view) { return a; }
	}
	return null;
}

export function areaScene(handle: VoidAreaHandle): Scene2D {
	for (const a of _areas) {
		if (a.hub.handle === handle) { return a.vh.scene; }
	}
	throw "areaScene: this handle belongs to no open Void area of an Ion window";
}

export function voidHostOf(host: Host): VoidHost {
	for (const a of _areas) {
		if (a.vh.host === host) { return a.vh; }
	}
	throw "voidHostOf: this host is not the host of a Void area in an Ion window";
}

function logicalWidth(a: Area): float32 { return (a.width as float32) / a.scale; }
function logicalHeight(a: Area): float32 { return (a.height as float32) / a.scale; }

function initGpu(): void {
	gfxSetup();
	setup2d();
}

function drawCurrent(): void {
	const a = areaOfView(currentView());
	if (a === null) {
		console.log(`neon: Void asked to draw view ${currentView()}, which no area owns`);
		exit(3);
	}
	const area = a as Area;
	_drawn = _drawn + 1;
	area.vh.layout(logicalWidth(area), logicalHeight(area));
	area.vh.scene.present();
	const r = area.vh.imeRect();
	if (r !== null) {
		const s = area.scale;
		setImeRect(area.win, (r.x * s) as int32, (r.y * s) as int32, (r.w * s) as int32, (r.h * s) as int32);
	}
}

function areaKey(e: KeyEvent): AreaKeyEvent {
	return {
		action: match (e.action) {
			KeyAction.Release => AreaKeyAction.Release,
			KeyAction.Repeat => AreaKeyAction.Repeat,
			_ => AreaKeyAction.Press,
		},
		key: e.key,
		scancode: e.scancode,
		mods: (e.mods as uint16) as BitSet<AreaKeyMod>,
		consumedMods: (e.consumedMods as uint16) as BitSet<AreaKeyMod>,
		unshifted: e.unshifted,
		text: e.text,
	};
}

function areaPointer(e: PointerEvent): AreaPointerEvent {
	return {
		kind: match (e.kind) {
			PointerKind.Motion => AreaPointerKind.Motion,
			PointerKind.Wheel => AreaPointerKind.Wheel,
			PointerKind.Leave => AreaPointerKind.Leave,
			_ => AreaPointerKind.Button,
		},
		pixelX: e.x,
		pixelY: e.y,
		button: e.button,
		pressed: e.pressed,
		dx: e.dx,
		dy: e.dy,
	};
}

function resized(window: int32, width: int32, height: int32, scale: float64): void {
	const a = areaOfWindow(window);
	if (a === null || width <= (0 as int32) || height <= (0 as int32)) { return; }
	const area = a as Area;
	area.width = width;
	area.height = height;
	area.scale = scale as float32;
	publishScale(scale, 1);
	area.hub.resize({ pixelWidth: width, pixelHeight: height, scale: area.scale });
	if (area.view === ViewInvalid) {
		area.view = viewCreate(0 as int64, width, height, area.scale);
		const visual = voidVisualAttach(windowDevice(area.win), windowRoot(area.win), viewSwapChain(area.view));
		if (visual === null) {
			console.log(`neon: window ${window} refused the swapchain of view ${area.view}`);
			exit(4);
		}
		area.visual = visual;
		commit(area.win);
	} else {
		viewResize(area.view, width, height, area.scale);
	}
	requestFrame(area.win);
}

function printable(text: string): boolean {
	if (text.length === 0) { return false; }
	const c = text.charCodeAt(0);
	return c >= 32 && c !== 127;
}

function keyEvent(e: KeyEvent, composing: boolean): NeonEvent {
	const ev = neonEvent(e.action === KeyAction.Release ? "keyup" : "keydown");
	ev.code = keyName(e.key);
	ev.altKey = e.mods.has(KeyMod.Alt);
	ev.ctrlKey = e.mods.has(KeyMod.Ctrl);
	ev.metaKey = e.mods.has(KeyMod.Super);
	ev.shiftKey = e.mods.has(KeyMod.Shift);
	ev.repeat = e.action === KeyAction.Repeat;
	ev.isComposing = composing;
	ev.scancode = e.scancode;
	ev.mods = (e.mods as uint16) as number;
	ev.consumedMods = (e.consumedMods as uint16) as number;
	ev.unshifted = e.unshifted;
	ev.text = e.text;
	if (printable(e.text)) { ev.key = e.text; }
	else if (e.unshifted >= (32 as int32) && e.unshifted !== (127 as int32) && ev.code.startsWith("Key")) { ev.key = String.fromCharCode(e.unshifted); }
	else { ev.key = ev.code; }
	return ev;
}

function wireInput(): void {
	if (_wired) { return; }
	_wired = true;
	embedRegister(initGpu, drawCurrent);
	onResize(resized);
	onFrame((window: int32, timeMs: float64): void => {
		const a = areaOfWindow(window);
		if (a !== null && (a as Area).view !== ViewInvalid) { viewFrame((a as Area).view); }
	});
	onPointer((e: PointerEvent): void => {
		const a = areaOfWindow(e.window);
		if (a === null) { return; }
		const area = a as Area;
		area.hub.pointer(areaPointer(e));
		const x = (e.x as float32) / area.scale;
		const y = (e.y as float32) / area.scale;
		if (e.kind === PointerKind.Motion) {
			area.vh.pointerMove(x, y, area.held, area.held > (0 as int32));
		} else if (e.kind === PointerKind.Wheel) {
			area.vh.wheel(x, y, e.dx as float32, e.dy as float32);
		} else if (e.kind === PointerKind.Button && e.pressed) {
			area.held = e.button;
			area.vh.pointerDown(x, y, e.button);
			area.vh.clickAt(x, y);
		} else if (e.kind === PointerKind.Button) {
			if (area.held === e.button) { area.held = 0 as int32; }
			area.vh.pointerUp(x, y, e.button);
		}
	});
	onKey((e: KeyEvent): void => {
		const a = areaOfWindow(e.window);
		if (a === null) { return; }
		const area = a as Area;
		area.hub.key(areaKey(e));
		const ev = keyEvent(e, area.composing);
		if (e.action === KeyAction.Release) {
			area.vh.keyUp(ev);
			return;
		}
		area.vh.keyDown(ev);
		if (printable(e.text) && !ev.ctrlKey && !ev.altKey && !ev.metaKey) { area.vh.commitText(e.text); }
	});
	onText((window: int32, text: string): void => {
		const a = areaOfWindow(window);
		if (a === null) { return; }
		(a as Area).hub.text(text);
		(a as Area).vh.textInput(text);
	});
	onImePreedit((window: int32, text: string, cursor: int32): void => {
		const a = areaOfWindow(window);
		if (a === null) { return; }
		(a as Area).hub.preedit({ text, cursor });
		(a as Area).composing = text.length > 0;
		(a as Area).vh.composeText(text, cursor);
	});
	onFocus((window: int32, focused: boolean): void => {
		const a = areaOfWindow(window);
		if (a === null) { return; }
		(a as Area).hub.focus(focused);
		(a as Area).vh.setWindowFocus(focused);
	});
}

function applyAreaStyle(area: Area, style: Style): void {
	(area.vh.root as VoidNode).flex = asFlexStyle(style);
	if (style.backgroundColor !== null) {
		const c = parseColor(style.backgroundColor as string);
		if (c !== null) { area.vh.scene.clear = c as Color; }
	}
	requestFrame(area.win);
}

function windowHost(win: Window): Host {
	let current: Area | null = null;
	let pendingStyle: Style | null = null;

	const refuse = (what: string): void => {
		throw `Ion window host: ${what}; an Ion window holds exactly one <Void>`;
	};

	const openArea = (node: HostNode): VoidArea => {
		if (current !== null) { refuse("a second <Void> was mounted"); }
		setFramePolicy(win, FrameOnDemand);
		const vh = createVoidHostWith(Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0)), _font);
		const hub = createAreaHub({
			initialPixelWidth: pixelWidth(win),
			initialPixelHeight: pixelHeight(win),
			requestFrame: (): void => { requestFrame(win); },
			setImeRect: (pixelX: int32, pixelY: int32, pixelW: int32, pixelH: int32): void => { setImeRect(win, pixelX, pixelY, pixelW, pixelH); },
		});
		const area: Area = { win, view: ViewInvalid, visual: null, vh, width: 0 as int32, height: 0 as int32, scale: 1.0, composing: false, held: 0 as int32, hub };
		_areas.push(area);
		current = area;
		if (pendingStyle !== null) { applyAreaStyle(area, pendingStyle as Style); }
		vh.onDirty((): void => {
			_requested = _requested + 1;
			requestFrame(win);
		});
		return {
			host: vh.host,
			root: vh.root as unknown as HostNode,
			hub,
			release: (): void => {
				const i = _areas.indexOf(area);
				if (i >= 0) { _areas.splice(i, 1); }
				current = null;
				vh.scene.close();
				if (area.visual !== null) {
					voidVisualDetach(windowRoot(win), area.visual as Ptr<void>);
					area.visual = null;
					commit(win);
				}
				if (area.view !== ViewInvalid) { viewDestroy(area.view); }
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
			if (current !== null) { applyAreaStyle(current as Area, style); }
		},
		setStyleProp: null,
		setStyleClass: null,
		addEvent: (node: HostNode, name: string, handler: (e: NeonEvent) => void): void => {
			refuse(`${name} on the window element`);
		},
		append: (parent: HostNode, child: HostNode): void => {},
		insertBefore: (parent: HostNode, node: HostNode, ref: HostNode | null): void => {},
		removeChild: (parent: HostNode, node: HostNode): void => {},
		nextSibling: (node: HostNode): HostNode | null => null,
		firstChild: (node: HostNode): HostNode | null => null,
		cloneNode: null,
		voidArea: openArea,
		scrollTo: null,
	};
}

export function runWindow(opts: DesktopOptions, app: () => NeonNode): int32 {
	const win = createWindow("main", defaultOptions(opts.title, opts.width as int32, opts.height as int32));
	if (win === null) { return 1; }
	const font = addFont(opts.font);
	if (!font.ok) {
		console.log(`neon: cannot load the font ${opts.font}: ${font.error.toString()}`);
		return 3;
	}
	_font = font.value;
	wireInput();
	const host = windowHost(win);
	const dispose = render((h: Host, p: HostNode, b: HostNode | null): void => { app()(h, p, b); }, host, windowNode("window"));
	runLoop();
	dispose();
	return 0;
}
