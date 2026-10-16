import { element } from "../../src/macros/ui/element";
import { render } from "../../src/render/host";
import { NeonEvent } from "../../src/render/event";
import { VoidAreaHandle, AreaKeyEvent } from "../../src/render/voidAreaHandle";
import { Void, View } from "../../src/components/primitives";
import { WindowArea, windowHost, windowNode, deliverResize, logicalWidth, logicalHeight } from "../../src/platform/void/windowHost";
import {
	AppEvent,
	AppEventType,
	SokolInput,
	sokolInput,
	deliverAppEvent,
	flushKey,
	sokolKeyName,
} from "../../src/platform/sokol/input";
import { FontId, addFont } from "../../../void/src/void2d/font";

const FONT_PATH = "../void/assets/font.ttf";

function loadedFont(): FontId {
	const r = addFont(FONT_PATH);
	if (!r.ok) { throw new Error("the test font did not load from " + FONT_PATH + "; run from the Neon checkout root beside ../void"); }
	return r.value;
}

function event(type: AppEventType): AppEvent {
	return {
		type,
		keyCode: 0 as int32,
		charCode: 0 as uint32,
		keyRepeat: false,
		modifiers: 0 as uint32,
		mouseButton: 0 as int32,
		mouseX: 0.0,
		mouseY: 0.0,
		mouseDx: 0.0,
		mouseDy: 0.0,
		scrollX: 0.0,
		scrollY: 0.0,
	};
}

function keyDown(keyCode: int32, modifiers: uint32): AppEvent {
	return { ...event(AppEventType.KeyDown), keyCode, modifiers };
}

function keyUp(keyCode: int32): AppEvent {
	return { ...event(AppEventType.KeyUp), keyCode };
}

function typed(charCode: uint32, modifiers: uint32): AppEvent {
	return { ...event(AppEventType.Char), charCode, modifiers };
}

function mouse(type: AppEventType, x: float32, y: float32): AppEvent {
	return { ...event(type), mouseX: x, mouseY: y };
}

function canvas(log: string[]): SokolInput {
	let opened: WindowArea | null = null;
	const host = windowHost({
		name: "test canvas",
		font: loadedFont(),
		pixelWidth: (): int32 => 400 as int32,
		pixelHeight: (): int32 => 200 as int32,
		requestFrame: (): void => {},
		dirty: (): void => {},
		setImeRect: (pixelX: int32, pixelY: int32, pixelW: int32, pixelH: int32): void => {},
		opened: (area: WindowArea): void => { opened = area; },
		released: (area: WindowArea): void => {},
	});
	render(element(
		<Void ref={(h: VoidAreaHandle): void => {
			h.onKey((e: AreaKeyEvent): void => { log.push(`hub key ${e.key} "${e.text}"`); });
			h.onText((t: string): void => { log.push(`hub text ${t}`); });
		}}>
			<View style={{ width: 200, height: 100 }} focusable
				onKeyDown={(e: NeonEvent): void => {
					log.push(`keydown ${e.key} ${e.code} "${e.text}" mods=${e.mods} consumed=${e.consumedMods} unshifted=${e.unshifted} repeat=${e.repeat}`);
				}}
				onKeyUp={(e: NeonEvent): void => { log.push(`keyup ${e.code}`); }}
				onTextInput={(e: NeonEvent): void => { log.push(`textinput ${e.text}`); }}
				onPointerDown={(e: NeonEvent): void => { log.push(`down ${e.x},${e.y} b${e.button}`); }}
				onPointerUp={(e: NeonEvent): void => { log.push(`up ${e.x},${e.y} b${e.button}`); }}
				onPointerMove={(e: NeonEvent): void => { log.push(`move ${e.x},${e.y}`); }}
				onWheel={(e: NeonEvent): void => { log.push(`wheel ${e.deltaX},${e.deltaY}`); }}
				onFocus={(): void => { log.push("focus"); }}
				onBlur={(): void => { log.push("blur"); }} />
		</Void>
	), host, windowNode("window"));
	if (opened === null) { throw new Error("the canvas opened no area"); }
	const area = opened as WindowArea;
	deliverResize(area, 400 as int32, 200 as int32, 2.0);
	area.vh.layout(area.logicalWidth(), area.logicalHeight());
	return sokolInput(area);
}

test "a key down and the char that follows it reach the area as one typed key" {
	const log: string[] = [];
	const s = canvas(log);
	deliverAppEvent(s, mouse(AppEventType.MouseDown, 20.0, 20.0));
	const mark = log.length;
	deliverAppEvent(s, keyDown(65 as int32, 1 as uint32));
	assert log.length === mark, "the key waits for the char it may type: " + log.join("|");
	deliverAppEvent(s, typed(65 as uint32, 1 as uint32));
	deliverAppEvent(s, keyUp(65 as int32));
	assert log.slice(mark).join("|") === [
		"hub key 20 \"A\"",
		"keydown A KeyA \"A\" mods=1 consumed=1 unshifted=97 repeat=false",
		"hub key 20 \"\"",
		"keyup KeyA",
	].join("|"), log.slice(mark).join("|");
}

test "a key that types nothing goes at once, a held key goes at the frame, and a lone char is committed text" {
	const log: string[] = [];
	const s = canvas(log);
	deliverAppEvent(s, mouse(AppEventType.MouseDown, 20.0, 20.0));
	const mark = log.length;
	deliverAppEvent(s, keyDown(263 as int32, 0 as uint32));
	deliverAppEvent(s, keyDown(67 as int32, 2 as uint32));
	deliverAppEvent(s, keyUp(67 as int32));
	deliverAppEvent(s, { ...keyDown(32 as int32, 0 as uint32), keyRepeat: true });
	flushKey(s);
	deliverAppEvent(s, typed(233 as uint32, 0 as uint32));
	assert log.slice(mark).join("|") === [
		"hub key 81 \"\"",
		"keydown ArrowLeft ArrowLeft \"\" mods=0 consumed=0 unshifted=0 repeat=false",
		"hub key 22 \"\"",
		"keydown c KeyC \"\" mods=2 consumed=0 unshifted=99 repeat=false",
		"hub key 22 \"\"",
		"keyup KeyC",
		"hub key 63 \"\"",
		"keydown Space Space \"\" mods=0 consumed=0 unshifted=32 repeat=true",
		"hub text é",
		"textinput é",
	].join("|"), log.slice(mark).join("|");
}

test "mouse, wheel and focus events reach the area in logical units with Ion's signs" {
	const log: string[] = [];
	const s = canvas(log);
	deliverAppEvent(s, mouse(AppEventType.MouseDown, 20.0, 40.0));
	deliverAppEvent(s, { ...mouse(AppEventType.MouseMove, 30.0, 40.0), mouseDx: 10.0 });
	deliverAppEvent(s, mouse(AppEventType.MouseUp, 30.0, 40.0));
	deliverAppEvent(s, { ...mouse(AppEventType.MouseScroll, 30.0, 40.0), scrollX: 1.0, scrollY: 2.0 });
	deliverAppEvent(s, event(AppEventType.Unfocused));
	deliverAppEvent(s, event(AppEventType.Focused));
	assert s.area.held === (0 as int32), "the button was released";
	assert log.join("|") === [
		"down 10,20 b1",
		"focus",
		"move 15,20",
		"up 15,20 b1",
		"wheel -1,2",
		"blur",
		"focus",
	].join("|"), log.join("|");
}

test "a sokol key code names the W3C code and Ion's key number, and an unknown one is Unidentified" {
	assert sokolKeyName(32 as int32).code === "Space" && sokolKeyName(32 as int32).key === (63 as int32), "Space";
	assert sokolKeyName(65 as int32).code === "KeyA" && sokolKeyName(65 as int32).key === (20 as int32), "KeyA";
	assert sokolKeyName(256 as int32).code === "Escape", "Escape";
	assert sokolKeyName(335 as int32).code === "NumpadEnter", "NumpadEnter";
	assert sokolKeyName(0 as int32).code === "Unidentified" && sokolKeyName(0 as int32).key === (0 as int32), "invalid";
}

test "an INVALID event is refused by name" {
	const s = canvas([]);
	let message = "";
	try {
		deliverAppEvent(s, event(AppEventType.Invalid));
	} catch (e) {
		message = (e as Error).message;
	}
	assert message === "sokol input: an event of type INVALID reached the canvas", message;
}
