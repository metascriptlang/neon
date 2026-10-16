// An Ion window whose content is one full-window <Void>: the window is the outer
// host, it accepts only the `void` tag, and its voidArea parents a visual holding
// the swapchain of a Void view under the window's root (void/docs/EMBED.md).

import {
	createWindow, defaultOptions, runLoop, windowRoot, windowDevice, commit, setImeRect,
	setFramePolicy, requestFrame, FrameOnDemand, pixelWidth, pixelHeight,
	onPointer, onKey, onText, onImePreedit, onFocus, onResize, onFrame,
	PointerEvent, PointerKind, KeyEvent, KeyAction, Window, keyName,
} from "../../../../ion/src/index";
import { embedRegister, viewCreate, viewResize, viewFrame, viewDestroy, viewSwapChain, currentView, gfxSetup, ViewId, ViewInvalid } from "../../../../void/src/sokol/gpu";
import { setup2d } from "../../../../void/src/void2d/draw";
import { addFont, registerFace, FontId, FontStyle as FaceStyle, DEFAULT_FONT } from "../../../../void/src/void2d/font";
import { Scene2D } from "../../../../void/src/void2d/node";
import { present } from "../../../../void/src/void2d/scene";
import { exit } from "std/process";
import { Host, HostNode, NeonNode, render } from "../../render/host";
import {
	VoidAreaHandle, AreaKeyEvent, AreaKeyAction, AreaKeyMod, AreaPointerEvent, AreaPointerKind,
} from "../../render/voidAreaHandle";
import { installCaptureServices } from "../../api/captureServices";
import { installAppServices } from "../../api/services";
import { ionCaptureServices } from "./audio";
import { ionAppServices } from "./appServices";
import { VoidHost } from "../void/host";
import {
	WindowArea,
	windowHost,
	windowNode,
	deliverKey,
	deliverPointer,
	deliverText,
	deliverPreedit,
	deliverFocus,
	deliverResize,
	logicalWidth,
	logicalHeight,
} from "../void/windowHost";

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

interface Area {
	win: Window;
	view: ViewId;
	visual: Ptr<void> | null;
	area: WindowArea;
}

// [frames the scene's dirty wake requested, frames drawn], since the process began.
let _requested = 0;
let _drawn = 0;

export function frameCounts(): number[] { return [_requested, _drawn]; }

const _areas: Area[] = [];
let _font: FontId = DEFAULT_FONT;
let _family: string | null = null;
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
		if (a.area.hub.handle === handle) { return a.area.vh.scene; }
	}
	throw "areaScene: this handle belongs to no open Void area of an Ion window";
}

export function voidHostOf(host: Host): VoidHost {
	for (const a of _areas) {
		if (a.area.vh.host === host) { return a.area.vh; }
	}
	throw "voidHostOf: this host is not the host of a Void area in an Ion window";
}

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
	const owner = a as Area;
	const area = owner.area;
	_drawn = _drawn + 1;
	area.vh.layout(area.logicalWidth(), area.logicalHeight());
	area.vh.scene.present();
	const r = area.vh.imeRect();
	if (r !== null) {
		const s = area.scale;
		setImeRect(owner.win, (r.x * s) as int32, (r.y * s) as int32, (r.w * s) as int32, (r.h * s) as int32);
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
		mods: ionPointerCarriesNoMods(e),
	};
}

function ionPointerCarriesNoMods(e: PointerEvent): BitSet<AreaKeyMod> {
	return (0 as uint16) as BitSet<AreaKeyMod>;
}

function resized(window: int32, width: int32, height: int32, scale: float64): void {
	const a = areaOfWindow(window);
	if (a === null || width <= (0 as int32) || height <= (0 as int32)) { return; }
	const owner = a as Area;
	deliverResize(owner.area, width, height, scale);
	if (owner.view === ViewInvalid) {
		owner.view = viewCreate(0 as int64, width, height, owner.area.scale);
		const visual = voidVisualAttach(windowDevice(owner.win), windowRoot(owner.win), viewSwapChain(owner.view));
		if (visual === null) {
			console.log(`neon: window ${window} refused the swapchain of view ${owner.view}`);
			exit(4);
		}
		owner.visual = visual;
		commit(owner.win);
	} else {
		viewResize(owner.view, width, height, owner.area.scale);
	}
	requestFrame(owner.win);
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
		if (a !== null) { deliverPointer((a as Area).area, areaPointer(e)); }
	});
	onKey((e: KeyEvent): void => {
		const a = areaOfWindow(e.window);
		if (a !== null) { deliverKey((a as Area).area, areaKey(e), keyName(e.key)); }
	});
	onText((window: int32, text: string): void => {
		const a = areaOfWindow(window);
		if (a !== null) { deliverText((a as Area).area, text); }
	});
	onImePreedit((window: int32, text: string, cursor: int32): void => {
		const a = areaOfWindow(window);
		if (a !== null) { deliverPreedit((a as Area).area, text, cursor); }
	});
	onFocus((window: int32, focused: boolean): void => {
		const a = areaOfWindow(window);
		if (a !== null) { deliverFocus((a as Area).area, focused); }
	});
}

function ionWindowHost(win: Window): Host {
	return windowHost({
		name: "Ion window",
		font: _font,
		family: _family,
		pixelWidth: (): int32 => pixelWidth(win),
		pixelHeight: (): int32 => pixelHeight(win),
		requestFrame: (): void => { requestFrame(win); },
		dirty: (): void => {
			_requested = _requested + 1;
			requestFrame(win);
		},
		setImeRect: (pixelX: int32, pixelY: int32, pixelW: int32, pixelH: int32): void => {
			setImeRect(win, pixelX, pixelY, pixelW, pixelH);
		},
		opened: (area: WindowArea): void => {
			setFramePolicy(win, FrameOnDemand);
			_areas.push({ win, view: ViewInvalid, visual: null, area });
		},
		released: (area: WindowArea): void => {
			for (let i = 0; i < _areas.length; i += 1) {
				const owner = _areas[i];
				if (owner.area !== area) { continue; }
				_areas.splice(i, 1);
				if (owner.visual !== null) {
					voidVisualDetach(windowRoot(win), owner.visual as Ptr<void>);
					owner.visual = null;
					commit(win);
				}
				if (owner.view !== ViewInvalid) { viewDestroy(owner.view); }
				return;
			}
		},
	});
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
	registerFace(opts.font, opts.font, 400, FaceStyle.Normal);
	_family = opts.font;
	wireInput();
	installCaptureServices(ionCaptureServices);
	installAppServices(ionAppServices);
	const host = ionWindowHost(win);
	const dispose = render((h: Host, p: HostNode, b: HostNode | null): void => { app()(h, p, b); }, host, windowNode("window"));
	runLoop();
	dispose();
	return 0;
}
