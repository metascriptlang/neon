import {
	createWindow, defaultOptions, runLoop, windowRoot, setFramePolicy, requestFrame, FrameOnDemand,
	onResize, onFrame, Window,
} from "../../../../ion/src/index";
import "./library";
import { runApp } from "../native/host";
import { useAppServices, useCaptureServices, imageSize } from "../native/appServices";
import { ionCaptureServices } from "../ion/audio";
import { ionAppServices } from "../ion/appServices";
import { NeonNode } from "../../render/node";
import { nimAttach, nimFrame, nimResize, nimShutdown } from "./handoff.h";

extern function nimSetFrameRequester(requester: () => void): void;

export interface NativeWindowOptions {
	title: string;
	width: number;
	height: number;
	topmost: boolean;
	decorations: boolean;
}

export function nativeWindowOptions(title: string, width: number, height: number): NativeWindowOptions {
	return { title, width, height, topmost: false, decorations: true };
}

let attached = false;

export function runNativeWindow(opts: NativeWindowOptions, app: () => NeonNode, onMounted: ((win: Window) => void) | null): int32 {
	const options = defaultOptions(opts.title, opts.width as int32, opts.height as int32);
	options.alwaysOnTop = opts.topmost;
	options.decorations = opts.decorations;
	const created = createWindow("main", options);
	if (created === null) { return 1; }
	const win: Window = created;
	setFramePolicy(win, FrameOnDemand);
	useCaptureServices(ionCaptureServices);
	useAppServices({ ...ionAppServices, imageSize });
	nimSetFrameRequester((): void => { requestFrame(win); });

	onResize((window: int32, width: int32, height: int32, scale: float64): void => {
		if (window !== win.id || width <= (0 as int32) || height <= (0 as int32)) { return; }
		const logicalWidth = (width as float64 / scale) as float32;
		const logicalHeight = (height as float64 / scale) as float32;
		if (attached) {
			nimResize(scale as float32, logicalWidth, logicalHeight);
			return;
		}
		attached = true;
		nimAttach(windowRoot(win), scale as float32, logicalWidth, logicalHeight);
		runApp(app);
		if (onMounted !== null) { (onMounted as (win: Window) => void)(win); }
	});
	onFrame((window: int32, timeMs: float64): void => {
		if (window === win.id && attached) { nimFrame(); }
	});

	runLoop();
	if (attached) { nimShutdown(); }
	return 0;
}
