// An Ion window whose content is one full-window <Void>: the window is the outer
// host, it accepts only the `void` tag, and its voidArea opens an Ion render
// surface drawn by a Void view (void/docs/EMBED.md).

import {
	createWindow, defaultOptions, runLoop, webviewSetVisible,
	onInput, onKey, onText, onImePreedit, onSurfaceFocus, onSurfaceResize, onSurfaceFrame,
	renderSurfaceCreate, renderSurfaceAttachSwapChain, renderSurfaceSetImeRect,
	renderSurfaceSetFramePolicy, renderSurfaceRequestFrame, renderSurfaceRelease,
	SurfaceBelow, RenderSurfaceInvalid, FrameOnDemand,
	KeyEvent, KeyAction, KeyMod, keyName,
} from "../../../../ion/src/index";
import { embedRegister, viewCreate, viewResize, viewFrame, viewDestroy, viewSwapChain, currentView, gfxSetup, ViewId, ViewInvalid } from "../../../../void/src/sokol/gpu";
import { setup2d } from "../../../../void/src/void2d/draw";
import { addFont } from "../../../../void/src/void2d/font";
import { TextLayout, TextStyle } from "../../../../void/src/void2d/textLayout";
import { Scene, scene, add, present } from "../../../../void/src/void2d/scene";
import { Color } from "../../../../void/src/void2d/types";
import { Window } from "../../../../ion/src/windowManager";
import { exit } from "std/process";
import { Host, HostNode, NeonNode, VoidArea, render } from "../../render/host";
import { NeonEvent, neonEvent } from "../../render/event";
import { Style } from "../../render/style";
import { VoidHost, createVoidHostWith, asFlexStyle, parseColor } from "../void/host";

const PAGE = "data:text/html,<body style='margin:0;background:transparent'></body>";
const POINTER_BUTTON: int32 = 1 as int32;

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
	surface: int32;
	view: ViewId;
	vh: VoidHost;
	scene: Scene;
	width: int32;
	height: int32;
	scale: float32;
	composing: boolean;
}

const _areas: Area[] = [];
let _fontId: int32 = -1 as int32;
let _wired = false;

function areaOfSurface(surface: int32): Area | null {
	for (const a of _areas) {
		if (a.surface === surface) { return a; }
	}
	return null;
}

function areaOfView(view: ViewId): Area | null {
	for (const a of _areas) {
		if (a.view === view) { return a; }
	}
	return null;
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
	area.vh.layout(logicalWidth(area), logicalHeight(area));
	area.scene.present();
	const r = area.vh.imeRect();
	if (r !== null) {
		const s = area.scale;
		renderSurfaceSetImeRect(area.surface, (r.x * s) as int32, (r.y * s) as int32, (r.w * s) as int32, (r.h * s) as int32);
	}
}

function resized(surface: int32, width: int32, height: int32, scale: float64): void {
	const a = areaOfSurface(surface);
	if (a === null || width <= (0 as int32) || height <= (0 as int32)) { return; }
	const area = a as Area;
	area.width = width;
	area.height = height;
	area.scale = scale as float32;
	if (area.view === ViewInvalid) {
		area.view = viewCreate(0 as int64, width, height, area.scale);
		if (!renderSurfaceAttachSwapChain(surface, viewSwapChain(area.view))) {
			console.log(`neon: surface ${surface} refused the swapchain of view ${area.view}`);
			exit(4);
		}
	} else {
		viewResize(area.view, width, height, area.scale);
	}
	renderSurfaceRequestFrame(surface);
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
	if (printable(e.text)) { ev.key = e.text; }
	else if (e.unshifted >= (32 as int32) && e.unshifted !== (127 as int32) && ev.code.startsWith("Key")) { ev.key = String.fromCharCode(e.unshifted); }
	else { ev.key = ev.code; }
	return ev;
}

function wireInput(): void {
	if (_wired) { return; }
	_wired = true;
	embedRegister(initGpu, drawCurrent);
	onSurfaceResize(resized);
	onSurfaceFrame((surface: int32, timeMs: float64): void => {
		const a = areaOfSurface(surface);
		if (a !== null && (a as Area).view !== ViewInvalid) { viewFrame((a as Area).view); }
	});
	onInput((type: int32, x: float64, y: float64, button: float64, pressed: float64): void => {
		if (type !== POINTER_BUTTON || pressed === 0.0 || _areas.length === 0) { return; }
		const a = _areas[0];
		a.vh.clickAt((x as float32) * logicalWidth(a), (y as float32) * logicalHeight(a));
	});
	onKey((e: KeyEvent): void => {
		const a = areaOfSurface(e.surface);
		if (a === null) { return; }
		const area = a as Area;
		const ev = keyEvent(e, area.composing);
		if (e.action === KeyAction.Release) {
			area.vh.keyUp(ev);
			return;
		}
		area.vh.keyDown(ev);
		if (printable(e.text) && !ev.ctrlKey && !ev.altKey && !ev.metaKey) { area.vh.commitText(e.text); }
	});
	onText((surface: int32, text: string): void => {
		const a = areaOfSurface(surface);
		if (a !== null) { (a as Area).vh.commitText(text); }
	});
	onImePreedit((surface: int32, text: string, cursor: int32): void => {
		const a = areaOfSurface(surface);
		if (a === null) { return; }
		(a as Area).composing = text.length > 0;
		(a as Area).vh.composeText(text, cursor);
	});
	onSurfaceFocus((surface: int32, focused: boolean): void => {
		const a = areaOfSurface(surface);
		if (a !== null) { (a as Area).vh.setWindowFocus(focused); }
	});
}

function advanceWidth(text: string, style: TextStyle): float32 {
	const l = TextLayout.layout(text, style);
	if (l.glyphs.length === 0) { return 0.0; }
	const last = l.glyphs[l.glyphs.length - 1];
	return last.x + last.advance;
}

function applyAreaStyle(area: Area, style: Style): void {
	area.vh.root.layoutStyle = asFlexStyle(style);
	if (style.backgroundColor !== null) {
		const c = parseColor(style.backgroundColor as string);
		if (c !== null) { area.scene.clear = c as Color; }
	}
	renderSurfaceRequestFrame(area.surface);
}

function windowHost(win: Window): Host {
	let current: Area | null = null;
	let pendingStyle: Style | null = null;

	const refuse = (what: string): void => {
		throw `Ion window host: ${what}; an Ion window holds exactly one <Void>`;
	};

	const openArea = (node: HostNode): VoidArea => {
		if (current !== null) { refuse("a second <Void> was mounted"); }
		const surface = renderSurfaceCreate(win, SurfaceBelow);
		if (surface === RenderSurfaceInvalid) { throw "Ion window host: renderSurfaceCreate failed"; }
		renderSurfaceSetFramePolicy(surface, FrameOnDemand);
		const vh = createVoidHostWith((size: float32, text: string): float32 => advanceWidth(text, {
			font: _fontId, size, letterSpacing: 0.0, lineSpacing: 0.0, maxWidth: 0.0, align: 0.0,
		}), _fontId);
		const sc = scene({ r: 0.0, g: 0.0, b: 0.0, a: 1.0 });
		sc.add(vh.root);
		const area: Area = { surface, view: ViewInvalid, vh, scene: sc, width: 0 as int32, height: 0 as int32, scale: 1.0, composing: false };
		_areas.push(area);
		current = area;
		if (pendingStyle !== null) { applyAreaStyle(area, pendingStyle as Style); }
		vh.onDirty((): void => { renderSurfaceRequestFrame(surface); });
		return {
			host: vh.host,
			root: vh.root as unknown as HostNode,
			release: (): void => {
				const i = _areas.indexOf(area);
				if (i >= 0) { _areas.splice(i, 1); }
				current = null;
				if (area.view !== ViewInvalid) { viewDestroy(area.view); }
				renderSurfaceRelease(surface);
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
	};
}

export function runWindow(opts: DesktopOptions, app: () => NeonNode): int32 {
	const win = createWindow("main", defaultOptions(opts.title, opts.width as int32, opts.height as int32, PAGE));
	if (win === null) { return 1; }
	webviewSetVisible(win, false);
	_fontId = addFont(opts.font);
	if (_fontId < (0 as int32)) {
		console.log(`neon: cannot load the font ${opts.font}`);
		return 3;
	}
	wireInput();
	const host = windowHost(win);
	const dispose = render((h: Host, p: HostNode, b: HostNode | null): void => { app()(h, p, b); }, host, windowNode("window"));
	runLoop();
	dispose();
	return 0;
}
