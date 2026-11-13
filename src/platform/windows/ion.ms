import {
	createWindow, defaultOptions, runLoop, windowRoot, windowDevice, setFramePolicy, requestFrame, FrameOnDemand,
	onWake, setImeRect, setCursor, onPointer, onKey, onText, onImePreedit, onFocus, onResize, onFrame,
	PointerEvent, PointerKind, KeyEvent, KeyAction, KeyMod, Window, keyName,
} from "../../../../ion/src/index";
import "./library";
import { nativeLayerEngine, runApp } from "../native/host";
import { installLayerEngine } from "../native/layerEngine";
import { useAppServices, useCaptureServices, imageSize } from "../native/appServices";
import { ionCaptureServices } from "../ion/audio";
import { ionAppServices } from "../ion/appServices";
import { useIonStorage } from "../ion/storage";
import { DESKTOP_BACK_BUTTON, dispatchHardwareBackPress } from "../../api/backHandler";
import { NeonNode } from "../../render/node";
import { flush } from "../../core/runtime";
import { DesktopInput, DesktopPointer } from "../native/desktopInput";
import {
	niwAttach, niwFrame, niwResize, niwPointer, niwWheel, niwShutdown, niwKey, niwText, niwPreedit, niwFocus, niwIonCursor,
	niwDrainImages, niwFocusedCaret, niwCaretPixelX, niwCaretPixelY, niwCaretPixelW, niwCaretPixelH,
} from "./handoff.h";

extern function niwSetFrameRequester(requester: () => void): void;

const POINTER_DOWN: int32 = 0;
const POINTER_UP: int32 = 1;
const POINTER_MOVE: int32 = 2;
const POINTER_CANCEL: int32 = 3;
const LEFT_BUTTON: int32 = 1;

function chordBack(e: KeyEvent): boolean {
	const mods = e.mods;
	return keyName(e.key) === "ArrowLeft" && mods.has(KeyMod.Alt) && !mods.has(KeyMod.Ctrl) && !mods.has(KeyMod.Shift) && !mods.has(KeyMod.Super);
}

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

function deliverMove(win: Window, x: float32, y: float32): void {
	niwPointer(POINTER_MOVE, x, y);
	const over = niwIonCursor();
	if (over !== cursor) {
		cursor = over;
		setCursor(win, over);
	}
}

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
	const input = new DesktopInput((e: DesktopPointer): void => {
		if (!attached) { return; }
		if (e.kind === "wheel") { niwWheel(e.x, e.y, e.dx, e.dy); }
		else { deliverMove(win, e.x, e.y); }
	});
	setFramePolicy(win, FrameOnDemand);
	useCaptureServices(ionCaptureServices);
	useIonStorage(opts.title);
	useAppServices({ ...ionAppServices, imageSize });
	installLayerEngine(nativeLayerEngine());
	niwSetFrameRequester((): void => { requestFrame(win); });
	onWake((): void => { niwDrainImages(); });

	onResize((window: int32, width: int32, height: int32, scale: float64): void => {
		if (window !== win.id || width <= (0 as int32) || height <= (0 as int32)) { return; }
		const dpi = (scale * 96.0) as float32;
		const logicalWidth = (width as float64 / scale) as float32;
		const logicalHeight = (height as float64 / scale) as float32;
		if (attached) {
			input.drain();
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
		input.drain();
		niwFrame(timeMs);
		placeIme(win);
	});
	onPointer((e: PointerEvent): void => {
		if (e.window !== win.id || !attached) { return; }
		const x = e.x as float32;
		const y = e.y as float32;
		if (e.kind === PointerKind.Motion || e.kind === PointerKind.Wheel) {
			input.push({
				kind: e.kind === PointerKind.Motion ? "motion" : "wheel",
				x, y, dx: e.dx as float32, dy: e.dy as float32,
			});
			return;
		}
		input.drain();
		if (e.kind === PointerKind.Button) {
			if (e.button === DESKTOP_BACK_BUTTON) {
				if (!e.pressed) { dispatchHardwareBackPress(); }
				return;
			}
			if (e.button !== LEFT_BUTTON) { return; }
			niwPointer(e.pressed ? POINTER_DOWN : POINTER_UP, x, y);
		} else if (e.kind === PointerKind.Leave) {
			niwPointer(POINTER_CANCEL, x, y);
		}
	});
	onFocus((window: int32, focused: boolean): void => {
		if (window !== win.id || !attached) { return; }
		input.drain();
		if (!focused) { niwPointer(POINTER_CANCEL, 0.0, 0.0); }
		niwFocus(focused ? 1 : 0);
	});
	onKey((e: KeyEvent): void => {
		if (e.window !== win.id || !attached) { return; }
		input.drain();
		if (chordBack(e)) {
			if (e.action === KeyAction.Press) { dispatchHardwareBackPress(); }
			return;
		}
		niwKey(keyAction(e.action), e.scancode, e.mods.has(KeyMod.Ctrl) ? 1 : 0, e.text);
	});
	onText((window: int32, text: string): void => {
		if (window === win.id && attached) {
			input.drain();
			niwText(text);
		}
	});
	onImePreedit((window: int32, text: string, caret: int32): void => {
		if (window === win.id && attached) {
			input.drain();
			niwPreedit(text, caret);
		}
	});

	runLoop();
	input.stop();
	if (attached) { niwShutdown(); }
	return 0;
}
