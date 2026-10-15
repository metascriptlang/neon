import {
	createWindow, defaultOptions, runLoop, windowRoot, windowDevice, setFramePolicy, requestFrame, FrameOnDemand,
	onPointer, onFocus, onResize, onFrame, PointerEvent, PointerKind, Window,
} from "../../../../ion/src/index";
import "./library";
import { runApp } from "../native/host";
import { NeonNode } from "../../render/node";
import { niwAttach, niwFrame, niwResize, niwPointer, niwShutdown } from "./handoff.h";

extern function niwSetFrameRequester(requester: () => void): void;

const POINTER_DOWN: int32 = 0;
const POINTER_UP: int32 = 1;
const POINTER_MOVE: int32 = 2;
const POINTER_CANCEL: int32 = 3;
const LEFT_BUTTON: int32 = 1;

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

export function runNativeWindow(opts: NativeWindowOptions, app: () => NeonNode, onMounted: (() => void) | null): int32 {
	const options = defaultOptions(opts.title, opts.width as int32, opts.height as int32);
	options.alwaysOnTop = opts.topmost;
	options.decorations = opts.decorations;
	const created = createWindow("main", options);
	if (created === null) { return 1; }
	const win: Window = created;
	setFramePolicy(win, FrameOnDemand);
	niwSetFrameRequester((): void => { requestFrame(win); });

	onResize((window: int32, width: int32, height: int32, scale: float64): void => {
		if (window !== win.id || width <= (0 as int32) || height <= (0 as int32)) { return; }
		const dpi = (scale * 96.0) as float32;
		const logicalWidth = (width as float64 / scale) as float32;
		const logicalHeight = (height as float64 / scale) as float32;
		if (attached) {
			niwResize(dpi, logicalWidth, logicalHeight);
			return;
		}
		attached = true;
		niwAttach(windowDevice(win), windowRoot(win), dpi, logicalWidth, logicalHeight);
		runApp(app);
		if (onMounted !== null) { (onMounted as () => void)(); }
	});
	onFrame((window: int32, timeMs: float64): void => {
		if (window === win.id && attached) { niwFrame(); }
	});
	onPointer((e: PointerEvent): void => {
		if (e.window !== win.id || !attached) { return; }
		const x = e.x as float32;
		const y = e.y as float32;
		if (e.kind === PointerKind.Button) {
			if (e.button !== LEFT_BUTTON) { return; }
			niwPointer(e.pressed ? POINTER_DOWN : POINTER_UP, x, y);
		} else if (e.kind === PointerKind.Motion) {
			niwPointer(POINTER_MOVE, x, y);
		} else if (e.kind === PointerKind.Leave) {
			niwPointer(POINTER_CANCEL, x, y);
		}
	});
	onFocus((window: int32, focused: boolean): void => {
		if (window === win.id && attached && !focused) { niwPointer(POINTER_CANCEL, 0.0, 0.0); }
	});

	runLoop();
	if (attached) { niwShutdown(); }
	return 0;
}
