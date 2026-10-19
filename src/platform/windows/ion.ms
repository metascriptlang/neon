import {
	createWindow, defaultOptions, runLoop, windowRoot, windowDevice, setFramePolicy, requestFrame, FrameOnDemand,
	setImeRect, setCursor, onPointer, onKey, onText, onImePreedit, onFocus, onResize, onFrame,
	PointerEvent, PointerKind, KeyEvent, KeyAction, KeyMod, Window,
} from "../../../../ion/src/index";
import "./library";
import { runApp } from "../native/host";
import { useAppServices, useCaptureServices } from "../native/appServices";
import { ionCaptureServices } from "../ion/audio";
import { ionAppServices } from "../ion/appServices";
import { NeonNode } from "../../render/node";
import { flush } from "../../core/runtime";
import {
	niwAttach, niwFrame, niwResize, niwPointer, niwWheel, niwShutdown, niwKey, niwText, niwPreedit, niwFocus, niwIonCursor,
	niwFocusedCaret, niwCaretPixelX, niwCaretPixelY, niwCaretPixelW, niwCaretPixelH,
} from "./handoff.h";

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
let cursor: int32 = 0;

function placeIme(win: Window): void {
	if (niwFocusedCaret() !== 0) { setImeRect(win, niwCaretPixelX(), niwCaretPixelY(), niwCaretPixelW(), niwCaretPixelH()); }
}

function keyAction(action: KeyAction): int32 {
	return match (action) {
		KeyAction.Release => 0,
		KeyAction.Repeat => 2,
		_ => 1,
	};
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
	useAppServices(ionAppServices);
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
		if (onMounted !== null) { (onMounted as (win: Window) => void)(win); }
	});
	onFrame((window: int32, timeMs: float64): void => {
		if (window !== win.id || !attached) { return; }
		flush();
		niwFrame();
		placeIme(win);
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
			const over = niwIonCursor();
			if (over !== cursor) {
				cursor = over;
				setCursor(win, over);
			}
		} else if (e.kind === PointerKind.Leave) {
			niwPointer(POINTER_CANCEL, x, y);
		} else if (e.kind === PointerKind.Wheel) {
			niwWheel(x, y, e.dx as float32, e.dy as float32);
		}
	});
	onFocus((window: int32, focused: boolean): void => {
		if (window !== win.id || !attached) { return; }
		if (!focused) { niwPointer(POINTER_CANCEL, 0.0, 0.0); }
		niwFocus(focused ? 1 : 0);
	});
	onKey((e: KeyEvent): void => {
		if (e.window !== win.id || !attached) { return; }
		niwKey(keyAction(e.action), e.scancode, e.mods.has(KeyMod.Ctrl) ? 1 : 0, e.text);
	});
	onText((window: int32, text: string): void => {
		if (window === win.id && attached) { niwText(text); }
	});
	onImePreedit((window: int32, text: string, caret: int32): void => {
		if (window === win.id && attached) { niwPreedit(text, caret); }
	});

	runLoop();
	if (attached) { niwShutdown(); }
	return 0;
}
