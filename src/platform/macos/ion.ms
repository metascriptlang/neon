import {
	createWindow, defaultOptions, runLoop, windowRoot, setFramePolicy, requestFrame, FrameOnDemand,
	onResize, onFrame, onPointer, onWindowEvent, PointerEvent, PointerKind, Window, WindowEventDestroyed,
} from "../../../../ion/src/index";
import "./library";
import { runApp, mountNativeRoot, NativeRootHandle } from "../native/host";
import { useAppServices, useCaptureServices, imageSize } from "../native/appServices";
import { ionCaptureServices } from "../ion/audio";
import { ionAppServices } from "../ion/appServices";
import { useIonStorage } from "../ion/storage";
import { DESKTOP_BACK_BUTTON, dispatchHardwareBackPress } from "../../api/backHandler";
import { NeonNode } from "../../render/node";
import { Dispose } from "../../core/types";
import { nimAttach, nimDetach, nimFrame, nimResize, nimShutdown } from "./handoff.h";

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
const frameWindows: Window[] = [];
let lastFrameMs: float64 = -1.0;

function requestFrames(): void {
	for (const w of frameWindows) { requestFrame(w); }
}

function framesWindow(id: int32): boolean {
	return frameWindows.findIndex((w: Window): boolean => w.id === id) >= 0;
}

export function runNativeWindow(opts: NativeWindowOptions, app: () => NeonNode, onMounted: ((win: Window) => void) | null): int32 {
	const options = defaultOptions(opts.title, opts.width as int32, opts.height as int32);
	options.alwaysOnTop = opts.topmost;
	options.decorations = opts.decorations;
	const created = createWindow("main", options);
	if (created === null) { return 1; }
	const win: Window = created;
	setFramePolicy(win, FrameOnDemand);
	useCaptureServices(ionCaptureServices);
	useIonStorage(opts.title);
	useAppServices({ ...ionAppServices, imageSize });
	frameWindows.push(win);
	nimSetFrameRequester((): void => { requestFrames(); });
	let mainRoot: Ptr<void> | null = null;

	onResize((window: int32, width: int32, height: int32, scale: float64): void => {
		if (window !== win.id || width <= (0 as int32) || height <= (0 as int32)) { return; }
		const logicalWidth = (width as float64 / scale) as float32;
		const logicalHeight = (height as float64 / scale) as float32;
		if (mainRoot !== null) {
			nimResize(mainRoot, scale as float32, logicalWidth, logicalHeight);
			return;
		}
		attached = true;
		mainRoot = nimAttach(windowRoot(win), scale as float32, logicalWidth, logicalHeight);
		runApp(app);
		if (onMounted !== null) { (onMounted as (win: Window) => void)(win); }
	});
	onFrame((window: int32, timeMs: float64): void => {
		if (!attached || timeMs === lastFrameMs || !framesWindow(window)) { return; }
		lastFrameMs = timeMs;
		nimFrame();
	});

	onPointer((e: PointerEvent): void => {
		if (e.window === win.id && e.kind === PointerKind.Button && e.button === DESKTOP_BACK_BUTTON && !e.pressed) { dispatchHardwareBackPress(); }
	});

	runLoop();
	if (attached) { nimShutdown(); }
	return 0;
}

export function mountNativeWindow(win: Window, app: () => NeonNode): Dispose {
	setFramePolicy(win, FrameOnDemand);
	frameWindows.push(win);
	let live = true;
	let root: Ptr<void> | null = null;
	let handle: NativeRootHandle | null = null;
	const dispose = (): void => {
		if (!live) { return; }
		live = false;
		frameWindows.splice(frameWindows.findIndex((w: Window): boolean => w.id === win.id), 1);
		if (handle !== null && root !== null) {
			handle.dispose();
			nimDetach(root);
		}
	};
	onResize((window: int32, width: int32, height: int32, scale: float64): void => {
		if (!live || window !== win.id || width <= (0 as int32) || height <= (0 as int32)) { return; }
		const logicalWidth = (width as float64 / scale) as float32;
		const logicalHeight = (height as float64 / scale) as float32;
		if (handle !== null && root !== null) {
			nimResize(root, scale as float32, logicalWidth, logicalHeight);
			handle.resize(logicalWidth, logicalHeight);
			return;
		}
		if (!attached) { throw new Error("mountNativeWindow: runNativeWindow has not mounted its main window yet"); }
		root = nimAttach(windowRoot(win), scale as float32, logicalWidth, logicalHeight);
		handle = mountNativeRoot(root as Ptr<void>, logicalWidth, logicalHeight, app);
	});
	onWindowEvent((label: string, type: int32): void => {
		if (live && label === win.label && type === WindowEventDestroyed) { dispose(); }
	});
	return dispose;
}
