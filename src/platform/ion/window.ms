// An Ion window whose content is one full-window <Void>: the window is the outer
// host, it accepts only the `void` tag, and its voidArea parents a visual holding
// the swapchain of a Void view under the window's root (void/docs/EMBED.md).

import {
	createWindow, defaultOptions, runLoop, windowRoot, windowDevice, commit, setImeRect,
	setFramePolicy, requestFrame, FrameOnDemand, pixelWidth, pixelHeight, show,
	onPointer, onKey, onText, onImePreedit, onFocus, onResize, onFrame,
	PointerEvent, PointerKind, KeyEvent, KeyAction, Window, keyName,
} from "../../../../ion/src/index";
import { embedRegister, viewCreate, viewResize, viewReady, viewFrame, viewDestroy, viewSwapChain, currentView, gfxSetup, ViewId, ViewInvalid } from "../../../../void/src/sokol/gpu";
import { setup2d } from "../../../../void/src/void2d/draw";
import { commit as commitFrame } from "../../../../void/src/gpu/door";
import { addFont, registerFace, setFaceResolver, FontId, FontStyle as FaceStyle, DEFAULT_FONT } from "../../../../void/src/void2d/font";
import { systemFace } from "./systemFace";
import { Scene2D } from "../../../../void/src/void2d/node";
import { isDirty } from "../../../../void/src/void2d/scene";
import { exit } from "std/process";
import { Host, HostNode, NeonNode, render } from "../../render/host";
import { flush } from "../../core/runtime";
import {
	VoidAreaHandle, AreaKeyEvent, AreaKeyAction, AreaKeyMod, AreaPointerEvent, AreaPointerKind,
} from "../../render/voidAreaHandle";
import { DOM_DELTA_PIXEL, DOM_DELTA_LINE } from "../../render/event";
import { installCaptureServices } from "../../api/captureServices";
import { installAppServices } from "../../api/services";
import { installFrameDriver } from "../../animation/frame";
import { ionCaptureServices } from "./audio";
import { ionAppServices } from "./appServices";
when (hcr) {
	import { pollReload, RELOAD_POLL_MS } from "../reloadPoll";
}
import { VoidHost, familyFont } from "../void/host";
import {
	WindowArea,
	windowHost,
	drawArea,
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
when (macos) {
	@compile("./voidVisual.m", "-fobjc-arc");
}
when (voidProfiler) {
	import { frameStats, profilerCollect } from "../../../../void/src/void2d/frameMarks";
	import { DurationRing, ringCount, ringPercentile } from "../../../../void/src/void2d/profiler";
	import { voidProfileInput } from "../../../../void/src/void2d/frameClock.h";
}
@include("./voidVisual.h");

extern function voidVisualAttach(device: Ptr<void>, root: Ptr<void>, swapChain: int64): Ptr<void>;
extern function voidVisualDetach(root: Ptr<void>, visual: Ptr<void>): void;

export interface DesktopOptions {
	title: string;
	width: number;
	height: number;
	font: string;
	fontFamily: string | null;
}

export function desktopOptions(title: string, width: number, height: number): DesktopOptions {
	return { title, width, height, font: "assets/font.ttf", fontFamily: null };
}

interface Area {
	win: Window;
	view: ViewId;
	visual: Ptr<void> | null;
	area: WindowArea;
	owed: boolean;
	shown: boolean;
}

// [frames the scene's dirty wake requested, frames drawn], since the process began.
let _requested = 0;
let _drawn = 0;

export function frameCounts(): number[] { return [_requested, _drawn]; }

const _areas: Area[] = [];
let _retiredViews: ViewId[] = [];
let _font: FontId = DEFAULT_FONT;
let _family: string | null = null;
let _wired = false;
let _frameFires: (() => void)[] = [];
let _firing = false;

function runFrameFires(): void {
	const due = _frameFires;
	_frameFires = [];
	_firing = true;
	for (const fire of due) { fire(); }
	_firing = false;
}

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
	owner.owed = false;
	_drawn = _drawn + 1;
	if (!drawArea(area)) {
		commitFrame();
		return;
	}
	if (!owner.shown) {
		owner.shown = true;
		show(owner.win);
	}
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
		deltaMode: e.kind === PointerKind.Wheel ? DOM_DELTA_LINE : DOM_DELTA_PIXEL,
		mods: (e.mods as uint16) as BitSet<AreaKeyMod>,
	};
}

function resized(window: int32, width: int32, height: int32, scale: float64): void {
	const a = areaOfWindow(window);
	if (a === null || width <= (0 as int32) || height <= (0 as int32)) { return; }
	const owner = a as Area;
	deliverResize(owner.area, width, height, scale);
	if (owner.view === ViewInvalid) {
		attachView(owner, width, height);
	} else {
		viewResize(owner.view, width, height, owner.area.scale);
	}
	owner.owed = true;
	requestFrame(owner.win);
}

function attachView(owner: Area, width: int32, height: int32): void {
	owner.view = viewCreate(0 as int64, width, height, owner.area.scale);
	const visual = voidVisualAttach(windowDevice(owner.win), windowRoot(owner.win), viewSwapChain(owner.view));
	if (visual === null) {
		console.log(`neon: window ${owner.win.id} refused the swapchain of view ${owner.view}`);
		exit(4);
	}
	owner.visual = visual;
	commit(owner.win);
}

function showWithFirstFrame(win: Window): void {
	const a = areaOfWindow(win.id);
	if (a === null) {
		show(win);
		return;
	}
	const owner = a as Area;
	if (owner.view !== ViewInvalid && !viewFrame(owner.view)) { requestFrame(owner.win); }
	if (!owner.shown) {
		owner.shown = true;
		show(win);
	}
}

function wireInput(): void {
	if (_wired) { return; }
	_wired = true;
	embedRegister(initGpu, drawCurrent);
	onResize(resized);
	onFrame((window: int32, timeMs: float64): void => {
		const a = areaOfWindow(window);
		if (a !== null) {
			const owner = a as Area;
			if (owner.view !== ViewInvalid && !viewReady(owner.view)) {
				requestFrame(owner.win);
				return;
			}
		}
		runFrameFires();
		flush();
		if (a !== null) {
			const owner = a as Area;
			if (owner.view !== ViewInvalid && (owner.owed || owner.area.vh.scene.isDirty()) && !viewFrame(owner.view)) { requestFrame(owner.win); }
		}
		const retired = _retiredViews;
		_retiredViews = [];
		for (const view of retired) { viewDestroy(view); }
	});
	onPointer((e: PointerEvent): void => {
		const a = areaOfWindow(e.window);
		if (a !== null) { deliverPointer((a as Area).area, areaPointer(e)); }
	});
	onKey((e: KeyEvent): void => {
		when (voidProfiler) { voidProfileInput(); }
		const a = areaOfWindow(e.window);
		if (a !== null) { deliverKey((a as Area).area, areaKey(e), keyName(e.key)); }
	});
	onText((window: int32, text: string): void => {
		when (voidProfiler) { voidProfileInput(); }
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

function owe(win: Window): void {
	const a = areaOfWindow(win.id);
	if (a !== null) { (a as Area).owed = true; }
}

function ionWindowHost(win: Window): Host {
	return windowHost({
		name: "Ion window",
		font: _font,
		family: _family,
		pixelWidth: (): int32 => pixelWidth(win),
		pixelHeight: (): int32 => pixelHeight(win),
		requestFrame: (): void => {
			owe(win);
			requestFrame(win);
		},
		dirty: (): void => {
			owe(win);
			if (_firing) { return; }
			_requested = _requested + 1;
			requestFrame(win);
		},
		setImeRect: (pixelX: int32, pixelY: int32, pixelW: int32, pixelH: int32): void => {
			setImeRect(win, pixelX, pixelY, pixelW, pixelH);
		},
		opened: (area: WindowArea): void => {
			setFramePolicy(win, FrameOnDemand);
			const owner: Area = { win, view: ViewInvalid, visual: null, area, owed: true, shown: false };
			_areas.push(owner);
			if (pixelWidth(win) > (0 as int32) && pixelHeight(win) > (0 as int32)) {
				attachView(owner, pixelWidth(win), pixelHeight(win));
			}
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
				if (owner.view === ViewInvalid) { return; }
				if (currentView() === owner.view) {
					_retiredViews.push(owner.view);
				} else {
					viewDestroy(owner.view);
				}
				return;
			}
		},
	});
}

export function runWindow(opts: DesktopOptions, app: () => NeonNode): int32 {
	const win = createWindow("main", { ...defaultOptions(opts.title, opts.width as int32, opts.height as int32), visible: false });
	if (win === null) { return 1; }
	const frameWin: Window = win;
	setFaceResolver(systemFace);
	registerFace(opts.font, opts.font, 400, FaceStyle.Normal);
	const family = opts.fontFamily !== null ? opts.fontFamily as string : opts.font;
	const font = opts.fontFamily !== null ? familyFont(family, 400, false) : addFont(opts.font);
	if (!font.ok) {
		console.log(`neon: cannot load the font ${family}: ${font.error.toString()}`);
		return 3;
	}
	_font = font.value;
	_family = family;
	wireInput();
	installCaptureServices(ionCaptureServices);
	installAppServices(ionAppServices);
	installFrameDriver({
		now: (): number => performance.now(),
		schedule: (fire: () => void): void => {
			_frameFires.push(fire);
			requestFrame(frameWin);
		},
	});
	const host = ionWindowHost(win);
	const dispose = render((h: Host, p: HostNode, b: HostNode | null): void => { app()(h, p, b); }, host, windowNode("window"));
	showWithFirstFrame(win);
	when (hcr) {
		setInterval(pollReload, RELOAD_POLL_MS);
	}
	runLoop();
	reportProfile();
	dispose();
	return 0;
}

function reportProfile(): void {
	when (voidProfiler) {
		profilerCollect();
		console.log(`neon.window.profileFrames ${frameStats.frames}`);
		reportRing("Draw", frameStats.draws);
		reportRing("DirtyToPresent", frameStats.dirtyToPresent);
		reportRing("InputLatency", frameStats.inputLatency);
	}
}

when (voidProfiler) {
	function milliseconds(ns: int64): float64 { return (ns as float64) / 1000000.0; }

	function reportRing(name: string, ring: DurationRing): void {
		if (ring.ringCount() == 0) { return; }
		console.log(`neon.window.profile${name}P50.ms ${milliseconds(ring.ringPercentile(50))}`);
		console.log(`neon.window.profile${name}P99.ms ${milliseconds(ring.ringPercentile(99))}`);
	}
}
