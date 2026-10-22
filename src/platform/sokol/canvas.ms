import { gfxSetup, fbWidth, fbHeight, dpiScale } from "../../../../void/src/sokol/gpu";
import { setup2d } from "../../../../void/src/void2d/draw";
import { FontId } from "../../../../void/src/void2d/font";
import { AppEvent, onAppEvent, setTextInput, setImeRect, safeArea, keyboardHeight } from "../../../../void/src/sokol/window";
import { publishKeyboard, publishSafeArea } from "../../render/environment";
import { canvasFont } from "./canvasFont";
import { Host, HostNode, NeonNode, render } from "../../render/host";
import { flush } from "../../core/runtime";
import {
	WindowArea,
	windowHost,
	drawArea,
	windowNode,
	deliverResize,
	logicalWidth,
	logicalHeight,
	syncTextInput,
} from "../void/windowHost";
import { SokolInput, sokolInput, deliverAppEvent, flushKey } from "./input";
import { pollReload, RELOAD_POLL_MS } from "../reloadPoll";
import { androidLibrary } from "../../../../ion/src/android";

@include("../../../../void/src/sokol/bridge.h");

when (android) {
	@compile("../../../../void/src/sokol/androidAppEntry.c");
	@compile("../android/canvasApp.c");
	androidLibrary("../../../../void/src/sokol/android/app");
}

extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;
extern function msRunOnce(timeoutMs: int32): boolean;

when (emcc || (windows && !voidGlCore)) {
	function skippedFrameKeepsPicture(): boolean { return true; }
} else {
	function skippedFrameKeepsPicture(): boolean { return false; }
}

when (ios || android) {
	function startTextInput(): void {}
	function followTextFocus(area: WindowArea): void { syncTextInput(area, setTextInput); }
} else {
	function startTextInput(): void { setTextInput(true); }
	function followTextFocus(area: WindowArea): void {}
}

export interface CanvasOptions {
	width: number;
	height: number;
	font: string;
	fontFamily: string | null;
	fontBytes: uint8[] | null;
	defaultFontBytes: uint8[] | null;
}

export function canvasOptions(width: number, height: number): CanvasOptions {
	return { width, height, font: "assets/font.ttf", fontFamily: null, fontBytes: null, defaultFontBytes: null };
}

interface Canvas {
	app: () => NeonNode;
	font: FontId;
	family: string;
	area: WindowArea | null;
	input: SokolInput | null;
	owed: boolean;
	dispose: (() => void) | null;
}

let _canvas: Canvas | null = null;
let _ticks = 0;
let _requested = 0;
let _drawn = 0;

export function canvasFrameCounts(): number[] { return [_ticks, _requested, _drawn]; }

function running(): Canvas {
	if (_canvas === null) { throw new Error("canvas: sokol called back before runCanvas started it"); }
	return _canvas as Canvas;
}

function canvasHost(c: Canvas): Host {
	return windowHost({
		name: "sokol canvas",
		font: c.font,
		family: c.family,
		pixelWidth: (): int32 => fbWidth(),
		pixelHeight: (): int32 => fbHeight(),
		requestFrame: (): void => { c.owed = true; },
		dirty: (): void => {
			_requested = _requested + 1;
			c.owed = true;
		},
		setImeRect: (pixelX: int32, pixelY: int32, pixelW: int32, pixelH: int32): void => {
			setImeRect(pixelX, pixelY, pixelW, pixelH);
		},
		opened: (area: WindowArea): void => {
			c.area = area;
			c.input = sokolInput(area);
			c.owed = true;
		},
		released: (area: WindowArea): void => {
			if (c.input !== null) { (c.input as SokolInput).touch.stop(); }
			c.area = null;
			c.input = null;
		},
	});
}

function initCanvas(): void {
	const c = running();
	gfxSetup();
	setup2d();
	const app = c.app;
	c.dispose = render((h: Host, p: HostNode, b: HostNode | null): void => { app()(h, p, b); }, canvasHost(c), windowNode("window"));
	onAppEvent((e: AppEvent): void => {
		if (c.input !== null) { deliverAppEvent(c.input as SokolInput, e); }
	});
	startTextInput();
	when (hcr) {
		setInterval(pollReload, RELOAD_POLL_MS);
	}
}

function frameCanvas(): void {
	_ticks = _ticks + 1;
	msRunOnce(0 as int32);
	const c = running();
	if (c.input !== null) { flushKey(c.input as SokolInput); }
	flush();
	if (c.area === null) { return; }
	const area = c.area as WindowArea;
	followTextFocus(area);
	const width = fbWidth();
	const height = fbHeight();
	const scale = dpiScale();
	if (width !== area.width || height !== area.height || scale !== area.scale) {
		deliverResize(area, width, height, scale as float64);
		c.owed = true;
	}
	const inset = safeArea();
	publishSafeArea(inset.top / scale, inset.right / scale, inset.bottom / scale, inset.left / scale);
	publishKeyboard(keyboardHeight() / scale);
	if ((!c.owed && skippedFrameKeepsPicture()) || width <= (0 as int32) || height <= (0 as int32)) { return; }
	c.owed = false;
	_drawn = _drawn + 1;
	if (!drawArea(area)) { return; }
	const r = area.vh.imeRect();
	if (r !== null) {
		const s = area.scale;
		setImeRect((r.x * s) as int32, (r.y * s) as int32, (r.w * s) as int32, (r.h * s) as int32);
	}
}

export function runCanvas(opts: CanvasOptions, app: () => NeonNode): int32 {
	if (_canvas !== null) { throw new Error("runCanvas: this process already runs a canvas; sokol_app has one window"); }
	const font = canvasFont(opts.font, opts.fontFamily, opts.fontBytes, opts.defaultFontBytes);
	if (!font.ok) {
		console.log(`neon: ${font.error}`);
		return 3;
	}
	const family = opts.fontFamily !== null ? opts.fontFamily as string : opts.font;
	_canvas = { app, font: font.value, family, area: null, input: null, owed: true, dispose: null };
	voidRun(opts.width as int32, opts.height as int32, initCanvas, frameCanvas);
	const c = running();
	if (c.dispose !== null) { (c.dispose as () => void)(); }
	return 0;
}
