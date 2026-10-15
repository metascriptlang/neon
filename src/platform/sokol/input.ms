import {
	AreaKeyAction,
	AreaKeyEvent,
	AreaKeyMod,
	AreaPointerKind,
} from "../../render/voidAreaHandle";
import {
	WindowArea,
	deliverKey,
	deliverPointer,
	deliverText,
	deliverFocus,
} from "../void/windowHost";

// The ordinals of sokol_app.h's sapp_event_type: keep the order.
export enum AppEventType {
	Invalid,
	KeyDown,
	KeyUp,
	Char,
	MouseDown,
	MouseUp,
	MouseScroll,
	MouseMove,
	MouseEnter,
	MouseLeave,
	TouchesBegan,
	TouchesMoved,
	TouchesEnded,
	TouchesCancelled,
	Resized,
	Iconified,
	Restored,
	Focused,
	Unfocused,
	Suspended,
	Resumed,
	QuitRequested,
	ClipboardPasted,
	FilesDropped,
}

export struct AppEvent {
	type: AppEventType;
	keyCode: int32;
	charCode: uint32;
	keyRepeat: boolean;
	modifiers: uint32;
	mouseButton: int32;
	mouseX: float32;
	mouseY: float32;
	mouseDx: float32;
	mouseDy: float32;
	scrollX: float32;
	scrollY: float32;
}

export struct KeyName {
	key: int32;
	code: string;
}

export function sokolKeyName(keyCode: int32): KeyName {
	return match (keyCode) {
		32 => ({ key: 63, code: "Space" }),
		39 => ({ key: 48, code: "Quote" }),
		44 => ({ key: 5, code: "Comma" }),
		45 => ({ key: 46, code: "Minus" }),
		46 => ({ key: 47, code: "Period" }),
		47 => ({ key: 50, code: "Slash" }),
		48 => ({ key: 6, code: "Digit0" }),
		49 => ({ key: 7, code: "Digit1" }),
		50 => ({ key: 8, code: "Digit2" }),
		51 => ({ key: 9, code: "Digit3" }),
		52 => ({ key: 10, code: "Digit4" }),
		53 => ({ key: 11, code: "Digit5" }),
		54 => ({ key: 12, code: "Digit6" }),
		55 => ({ key: 13, code: "Digit7" }),
		56 => ({ key: 14, code: "Digit8" }),
		57 => ({ key: 15, code: "Digit9" }),
		59 => ({ key: 49, code: "Semicolon" }),
		61 => ({ key: 16, code: "Equal" }),
		65 => ({ key: 20, code: "KeyA" }),
		66 => ({ key: 21, code: "KeyB" }),
		67 => ({ key: 22, code: "KeyC" }),
		68 => ({ key: 23, code: "KeyD" }),
		69 => ({ key: 24, code: "KeyE" }),
		70 => ({ key: 25, code: "KeyF" }),
		71 => ({ key: 26, code: "KeyG" }),
		72 => ({ key: 27, code: "KeyH" }),
		73 => ({ key: 28, code: "KeyI" }),
		74 => ({ key: 29, code: "KeyJ" }),
		75 => ({ key: 30, code: "KeyK" }),
		76 => ({ key: 31, code: "KeyL" }),
		77 => ({ key: 32, code: "KeyM" }),
		78 => ({ key: 33, code: "KeyN" }),
		79 => ({ key: 34, code: "KeyO" }),
		80 => ({ key: 35, code: "KeyP" }),
		81 => ({ key: 36, code: "KeyQ" }),
		82 => ({ key: 37, code: "KeyR" }),
		83 => ({ key: 38, code: "KeyS" }),
		84 => ({ key: 39, code: "KeyT" }),
		85 => ({ key: 40, code: "KeyU" }),
		86 => ({ key: 41, code: "KeyV" }),
		87 => ({ key: 42, code: "KeyW" }),
		88 => ({ key: 43, code: "KeyX" }),
		89 => ({ key: 44, code: "KeyY" }),
		90 => ({ key: 45, code: "KeyZ" }),
		91 => ({ key: 3, code: "BracketLeft" }),
		92 => ({ key: 2, code: "Backslash" }),
		93 => ({ key: 4, code: "BracketRight" }),
		96 => ({ key: 1, code: "Backquote" }),
		161 => ({ key: 17, code: "IntlBackslash" }),
		162 => ({ key: 17, code: "IntlBackslash" }),
		256 => ({ key: 125, code: "Escape" }),
		257 => ({ key: 58, code: "Enter" }),
		258 => ({ key: 64, code: "Tab" }),
		259 => ({ key: 53, code: "Backspace" }),
		260 => ({ key: 77, code: "Insert" }),
		261 => ({ key: 73, code: "Delete" }),
		262 => ({ key: 82, code: "ArrowRight" }),
		263 => ({ key: 81, code: "ArrowLeft" }),
		264 => ({ key: 80, code: "ArrowDown" }),
		265 => ({ key: 83, code: "ArrowUp" }),
		266 => ({ key: 79, code: "PageUp" }),
		267 => ({ key: 78, code: "PageDown" }),
		268 => ({ key: 76, code: "Home" }),
		269 => ({ key: 74, code: "End" }),
		280 => ({ key: 54, code: "CapsLock" }),
		281 => ({ key: 154, code: "ScrollLock" }),
		282 => ({ key: 84, code: "NumLock" }),
		283 => ({ key: 153, code: "PrintScreen" }),
		284 => ({ key: 155, code: "Pause" }),
		290 => ({ key: 126, code: "F1" }),
		291 => ({ key: 127, code: "F2" }),
		292 => ({ key: 128, code: "F3" }),
		293 => ({ key: 129, code: "F4" }),
		294 => ({ key: 130, code: "F5" }),
		295 => ({ key: 131, code: "F6" }),
		296 => ({ key: 132, code: "F7" }),
		297 => ({ key: 133, code: "F8" }),
		298 => ({ key: 134, code: "F9" }),
		299 => ({ key: 135, code: "F10" }),
		300 => ({ key: 136, code: "F11" }),
		301 => ({ key: 137, code: "F12" }),
		302 => ({ key: 138, code: "F13" }),
		303 => ({ key: 139, code: "F14" }),
		304 => ({ key: 140, code: "F15" }),
		305 => ({ key: 141, code: "F16" }),
		306 => ({ key: 142, code: "F17" }),
		307 => ({ key: 143, code: "F18" }),
		308 => ({ key: 144, code: "F19" }),
		309 => ({ key: 145, code: "F20" }),
		310 => ({ key: 146, code: "F21" }),
		311 => ({ key: 147, code: "F22" }),
		312 => ({ key: 148, code: "F23" }),
		313 => ({ key: 149, code: "F24" }),
		314 => ({ key: 150, code: "F25" }),
		320 => ({ key: 85, code: "Numpad0" }),
		321 => ({ key: 86, code: "Numpad1" }),
		322 => ({ key: 87, code: "Numpad2" }),
		323 => ({ key: 88, code: "Numpad3" }),
		324 => ({ key: 89, code: "Numpad4" }),
		325 => ({ key: 90, code: "Numpad5" }),
		326 => ({ key: 91, code: "Numpad6" }),
		327 => ({ key: 92, code: "Numpad7" }),
		328 => ({ key: 93, code: "Numpad8" }),
		329 => ({ key: 94, code: "Numpad9" }),
		330 => ({ key: 100, code: "NumpadDecimal" }),
		331 => ({ key: 101, code: "NumpadDivide" }),
		332 => ({ key: 109, code: "NumpadMultiply" }),
		333 => ({ key: 112, code: "NumpadSubtract" }),
		334 => ({ key: 95, code: "NumpadAdd" }),
		335 => ({ key: 102, code: "NumpadEnter" }),
		336 => ({ key: 103, code: "NumpadEqual" }),
		340 => ({ key: 61, code: "ShiftLeft" }),
		341 => ({ key: 56, code: "ControlLeft" }),
		342 => ({ key: 51, code: "AltLeft" }),
		343 => ({ key: 59, code: "MetaLeft" }),
		344 => ({ key: 62, code: "ShiftRight" }),
		345 => ({ key: 57, code: "ControlRight" }),
		346 => ({ key: 52, code: "AltRight" }),
		347 => ({ key: 60, code: "MetaRight" }),
		348 => ({ key: 55, code: "ContextMenu" }),
		_ => ({ key: 0, code: "Unidentified" }),
	};
}

function unshiftedOf(keyCode: int32): int32 {
	if (keyCode >= 65 && keyCode <= 90) { return keyCode + 32; }
	if (keyCode >= 32 && keyCode <= 96) { return keyCode; }
	return 0;
}

function mayType(keyCode: int32): boolean {
	return keyCode < 256 || (keyCode >= 320 && keyCode <= 336);
}

function modsOf(e: AppEvent): BitSet<AreaKeyMod> {
	return ((e.modifiers & (15 as uint32)) as uint16) as BitSet<AreaKeyMod>;
}

function buttonOf(button: int32): int32 {
	if (button < 0 || button > 2) { throw new Error(`sokol input: mouse button ${button} has no area button`); }
	return button + 1;
}

export interface SokolInput {
	area: WindowArea;
	pending: AppEvent | null;
}

export function sokolInput(area: WindowArea): SokolInput {
	return { area, pending: null };
}

function sendKey(s: SokolInput, e: AppEvent, action: AreaKeyAction, text: string): void {
	const mods = modsOf(e);
	const consumed = text.length > 0 && mods.has(AreaKeyMod.Shift)
		? (0 as BitSet<AreaKeyMod>).incl(AreaKeyMod.Shift)
		: 0 as BitSet<AreaKeyMod>;
	const name = sokolKeyName(e.keyCode);
	const key: AreaKeyEvent = {
		action,
		key: name.key,
		scancode: 0 as int32,
		mods,
		consumedMods: consumed,
		unshifted: unshiftedOf(e.keyCode),
		text,
	};
	deliverKey(s.area, key, name.code);
}

function press(e: AppEvent): AreaKeyAction {
	return e.keyRepeat ? AreaKeyAction.Repeat : AreaKeyAction.Press;
}

export function flushKey(s: SokolInput): void {
	if (s.pending === null) { return; }
	const e = s.pending as AppEvent;
	s.pending = null;
	sendKey(s, e, press(e), "");
}

function pointer(s: SokolInput, e: AppEvent, kind: AreaPointerKind, button: int32, pressed: boolean): void {
	const motion = kind === AreaPointerKind.Motion;
	const wheel = kind === AreaPointerKind.Wheel;
	deliverPointer(s.area, {
		kind,
		pixelX: e.mouseX as float64,
		pixelY: e.mouseY as float64,
		button,
		pressed,
		dx: motion ? e.mouseDx as float64 : wheel ? -(e.scrollX as float64) : 0.0,
		dy: motion ? e.mouseDy as float64 : wheel ? e.scrollY as float64 : 0.0,
	});
}

export function deliverAppEvent(s: SokolInput, e: AppEvent): void {
	if (e.type !== AppEventType.Char) { flushKey(s); }
	match (e.type) {
		AppEventType.KeyDown => {
			if (mayType(e.keyCode)) { s.pending = e; }
			else { sendKey(s, e, press(e), ""); }
		},
		AppEventType.KeyUp => { sendKey(s, e, AreaKeyAction.Release, ""); },
		AppEventType.Char => {
			const text = fromCodePoint(e.charCode as number);
			if (s.pending === null) {
				deliverText(s.area, text);
				return;
			}
			const typed = s.pending as AppEvent;
			s.pending = null;
			sendKey(s, typed, press(typed), text);
		},
		AppEventType.MouseDown => { pointer(s, e, AreaPointerKind.Button, buttonOf(e.mouseButton), true); },
		AppEventType.MouseUp => { pointer(s, e, AreaPointerKind.Button, buttonOf(e.mouseButton), false); },
		AppEventType.MouseMove => { pointer(s, e, AreaPointerKind.Motion, 0 as int32, false); },
		AppEventType.MouseScroll => { pointer(s, e, AreaPointerKind.Wheel, 0 as int32, false); },
		AppEventType.MouseLeave => { pointer(s, e, AreaPointerKind.Leave, 0 as int32, false); },
		AppEventType.Focused => { deliverFocus(s.area, true); },
		AppEventType.Unfocused => { deliverFocus(s.area, false); },
		AppEventType.MouseEnter | AppEventType.Resized | AppEventType.Iconified | AppEventType.Restored |
			AppEventType.Suspended | AppEventType.Resumed | AppEventType.QuitRequested |
			AppEventType.ClipboardPasted | AppEventType.FilesDropped => {},
		AppEventType.TouchesBegan | AppEventType.TouchesMoved | AppEventType.TouchesEnded |
			AppEventType.TouchesCancelled => {},
		AppEventType.Invalid => { throw new Error("sokol input: an event of type INVALID reached the canvas"); },
	}
}
