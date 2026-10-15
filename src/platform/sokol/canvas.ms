import { gfxSetup, fbWidth, fbHeight, dpiScale } from "../../../../void/src/sokol/gpu";
import { setup2d } from "../../../../void/src/void2d/draw";
import { addFont, registerFace, FontId, FontStyle as FaceStyle } from "../../../../void/src/void2d/font";
import { present } from "../../../../void/src/void2d/scene";
import { Host, HostNode, NeonNode, render } from "../../render/host";
import {
	WindowArea,
	windowHost,
	windowNode,
	deliverResize,
	logicalWidth,
	logicalHeight,
} from "../void/windowHost";

@include("../../../../void/src/sokol/bridge.h");

extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;
extern function msRunOnce(timeoutMs: int32): boolean;

when (emcc) {
	function skippedFrameKeepsPicture(): boolean { return true; }
} else {
	function skippedFrameKeepsPicture(): boolean { return false; }
}

export interface CanvasOptions {
	width: number;
	height: number;
	font: string;
}

export function canvasOptions(width: number, height: number): CanvasOptions {
	return { width, height, font: "assets/font.ttf" };
}

interface Canvas {
	app: () => NeonNode;
	font: FontId;
	family: string;
	area: WindowArea | null;
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
		setImeRect: (pixelX: int32, pixelY: int32, pixelW: int32, pixelH: int32): void => {},
		opened: (area: WindowArea): void => {
			c.area = area;
			c.owed = true;
		},
		released: (area: WindowArea): void => { c.area = null; },
	});
}

function initCanvas(): void {
	const c = running();
	gfxSetup();
	setup2d();
	const app = c.app;
	c.dispose = render((h: Host, p: HostNode, b: HostNode | null): void => { app()(h, p, b); }, canvasHost(c), windowNode("window"));
}

function frameCanvas(): void {
	_ticks = _ticks + 1;
	msRunOnce(0 as int32);
	const c = running();
	if (c.area === null) { return; }
	const area = c.area as WindowArea;
	const width = fbWidth();
	const height = fbHeight();
	const scale = dpiScale();
	if (width !== area.width || height !== area.height || scale !== area.scale) {
		deliverResize(area, width, height, scale as float64);
		c.owed = true;
	}
	if ((!c.owed && skippedFrameKeepsPicture()) || width <= (0 as int32) || height <= (0 as int32)) { return; }
	c.owed = false;
	_drawn = _drawn + 1;
	area.vh.layout(area.logicalWidth(), area.logicalHeight());
	area.vh.scene.present();
}

export function runCanvas(opts: CanvasOptions, app: () => NeonNode): int32 {
	if (_canvas !== null) { throw new Error("runCanvas: this process already runs a canvas; sokol_app has one window"); }
	const font = addFont(opts.font);
	if (!font.ok) {
		console.log(`neon: cannot load the font ${opts.font}: ${font.error.toString()}`);
		return 3;
	}
	registerFace(opts.font, opts.font, 400, FaceStyle.Normal);
	_canvas = { app, font: font.value, family: opts.font, area: null, owed: true, dispose: null };
	voidRun(opts.width as int32, opts.height as int32, initCanvas, frameCanvas);
	const c = running();
	if (c.dispose !== null) { (c.dispose as () => void)(); }
	return 0;
}
