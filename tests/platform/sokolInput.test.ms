import { element } from "../../src/macros/ui/element";
import { render } from "../../src/render/host";
import { NeonEvent } from "../../src/render/event";
import { VoidAreaHandle, AreaKeyEvent, AreaPointerEvent, AreaPointerKind } from "../../src/render/voidAreaHandle";
import { Void, View } from "../../src/components/primitives";
import { NeonNode } from "../../src/render/node";
import { WindowArea, windowHost, windowNode, deliverResize, logicalWidth, logicalHeight, syncTextInput } from "../../src/platform/void/windowHost";
import {
	SokolInput,
	sokolInput,
	deliverAppEvent,
	deliverTouches,
	flushKey,
	sokolKeyName,
} from "../../src/platform/sokol/input";
import { TouchPoint } from "../../src/platform/sokol/touch";
import { useManualFrames, setFrameDriver, framePending } from "../../src/animation/frame";
import { FontId, addFont } from "../../../void/src/void2d/font";
import { AppEvent, AppEventType } from "../../../void/src/sokol/window";

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
		framebufferWidth: 0 as int32,
		framebufferHeight: 0 as int32,
		text: "",
		cursor: 0 as int32,
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

function openCanvas(app: NeonNode): SokolInput {
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
	render(app, host, windowNode("window"));
	if (opened === null) { throw new Error("the canvas opened no area"); }
	const area = opened as WindowArea;
	deliverResize(area, 400 as int32, 200 as int32, 2.0);
	area.vh.layout(area.logicalWidth(), area.logicalHeight());
	return sokolInput(area);
}

function canvas(log: string[]): SokolInput {
	return openCanvas(element(
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
				onPreedit={(e: NeonEvent): void => { log.push(`preedit ${e.text}@${e.cursor}`); }}
				onPointerDown={(e: NeonEvent): void => { log.push(`down ${e.x},${e.y} b${e.button}${e.shiftKey ? " shift" : ""}${e.ctrlKey ? " ctrl" : ""}`); }}
				onPointerUp={(e: NeonEvent): void => { log.push(`up ${e.x},${e.y} b${e.button}`); }}
				onPointerMove={(e: NeonEvent): void => { log.push(`move ${e.x},${e.y}`); }}
				onWheel={(e: NeonEvent): void => { log.push(`wheel ${e.deltaX},${e.deltaY}`); }}
				onFocus={(): void => { log.push("focus"); }}
				onBlur={(): void => { log.push("blur"); }} />
		</Void>
	));
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
		"keydown   Space \"\" mods=0 consumed=0 unshifted=32 repeat=true",
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

test "a mouse event's modifiers reach the pointer handler" {
	const log: string[] = [];
	const s = canvas(log);
	deliverAppEvent(s, { ...mouse(AppEventType.MouseDown, 20.0, 40.0), modifiers: 3 as uint32 });
	deliverAppEvent(s, mouse(AppEventType.MouseUp, 20.0, 40.0));
	deliverAppEvent(s, { ...mouse(AppEventType.MouseDown, 20.0, 40.0), modifiers: 2 as uint32 });
	const all = log.join("|");
	assert all.indexOf("down 10,20 b1 shift ctrl|") >= 0 && all.indexOf("down 10,20 b1 ctrl") >= 0 && all.indexOf("down 10,20 b1|") < 0, all;
}

test "an IME composition reaches the area as preedit, and its result as committed text" {
	const log: string[] = [];
	const s = canvas(log);
	deliverAppEvent(s, mouse(AppEventType.MouseDown, 20.0, 20.0));
	const mark = log.length;
	deliverAppEvent(s, { ...event(AppEventType.Preedit), text: "tie", cursor: 3 as int32 });
	deliverAppEvent(s, { ...event(AppEventType.Preedit), text: "tiê", cursor: 3 as int32 });
	assert s.area.composing, "the area is composing";
	deliverAppEvent(s, { ...event(AppEventType.Preedit), text: "", cursor: 0 as int32 });
	deliverAppEvent(s, { ...event(AppEventType.TextInput), text: "tiếng" });
	assert !s.area.composing, "an empty preedit ends the composition";
	assert log.slice(mark).join("|") === [
		"preedit tie@3",
		"preedit tiê@3",
		"preedit @0",
		"hub text tiếng",
		"textinput tiếng",
	].join("|"), log.slice(mark).join("|");
}

function point(id: int32, x: float32, y: float32): TouchPoint {
	return { identifier: id as uint64, posX: x, posY: y, changed: true };
}

function touch(s: SokolInput, type: AppEventType, id: int32, x: float32, y: float32): void {
	deliverTouches(s, event(type), [point(id, x, y)]);
}

function wheelsOf(log: string[]): number[] {
	const dys: number[] = [];
	for (const line of log) {
		if (!line.startsWith("wheel ")) { throw new Error(`a touch pan delivered "${line}"`); }
		dys.push(parseFloat(line.split(",")[1]));
	}
	return dys;
}

test "a tap is a press and a release where the finger touched and lifted" {
	const clock = useManualFrames();
	const log: string[] = [];
	const s = canvas(log);
	touch(s, AppEventType.TouchesBegan, 1 as int32, 40.0, 60.0);
	clock.advance(100);
	touch(s, AppEventType.TouchesEnded, 1 as int32, 42.0, 60.0);
	clock.step(40 as int32);
	assert log.join("|") === "down 20,30 b1|focus|up 21,30 b1", log.join("|");
	assert s.area.held === (0 as int32), "the tap released its button";
	setFrameDriver(null);
}

test "a hold past the long-press timeout presses, and the drag that follows moves with the button held" {
	const clock = useManualFrames();
	const log: string[] = [];
	const s = canvas(log);
	touch(s, AppEventType.TouchesBegan, 1 as int32, 40.0, 60.0);
	clock.step(30 as int32);
	assert log.length === 0, "480 ms is not a long press yet: " + log.join("|");
	clock.step(2 as int32);
	touch(s, AppEventType.TouchesMoved, 1 as int32, 80.0, 60.0);
	assert s.area.held === (1 as int32), "the button is held while the finger drags";
	touch(s, AppEventType.TouchesEnded, 1 as int32, 80.0, 60.0);
	assert log.join("|") === "down 20,30 b1|focus|move 40,30|up 40,30 b1", log.join("|");
	assert s.area.held === (0 as int32), "the lift released the button";
	setFrameDriver(null);
}

test "a drag past the pan slop without a hold scrolls the area under its start and presses nothing" {
	const clock = useManualFrames();
	const log: string[] = [];
	const s = canvas(log);
	touch(s, AppEventType.TouchesBegan, 1 as int32, 40.0, 100.0);
	touch(s, AppEventType.TouchesMoved, 1 as int32, 40.0, 140.0);
	assert log.length === 0, "20 points is inside the pan slop: " + log.join("|");
	touch(s, AppEventType.TouchesMoved, 1 as int32, 40.0, 180.0);
	assert log.length === 0, "the move that crosses the slop starts the pan and scrolls nothing: " + log.join("|");
	touch(s, AppEventType.TouchesMoved, 1 as int32, 40.0, 190.0);
	touch(s, AppEventType.TouchesMoved, 1 as int32, 20.0, 170.0);
	clock.advance(50);
	touch(s, AppEventType.TouchesEnded, 1 as int32, 20.0, 170.0);
	clock.step(40 as int32);
	assert log.join("|") === "wheel 0,0.5|wheel 1,-1", log.join("|");
	assert !framePending(), "a finger that stopped before it lifted leaves no momentum";
	setFrameDriver(null);
}

test "a pan released with speed keeps scrolling with deltas that decay to a stop" {
	const clock = useManualFrames();
	const log: string[] = [];
	const s = canvas(log);
	touch(s, AppEventType.TouchesBegan, 1 as int32, 40.0, 20.0);
	for (let i = 1; i <= 6; i += 1) {
		clock.advance(16);
		touch(s, AppEventType.TouchesMoved, 1 as int32, 40.0, (20 + 20 * i) as float32);
	}
	assert log.join("|") === "wheel 0,1|wheel 0,1", log.join("|");
	touch(s, AppEventType.TouchesEnded, 1 as int32, 40.0, 140.0);
	const mark = log.length;
	clock.step(1 as int32);
	assert log.length === mark, "the first momentum frame only starts the clock";
	const frames = clock.runAll();
	const dys = wheelsOf(log.slice(mark));
	let total = 0.0;
	for (let i = 0; i < dys.length; i += 1) {
		assert dys[i] > 0.0, `momentum keeps the drag's direction: ${dys[i]}`;
		if (i > 0) { assert dys[i] < dys[i - 1], `momentum decays: ${dys[i - 1]} then ${dys[i]}`; }
		total += dys[i];
	}
	assert dys.length > 100 && dys.length < 160, `momentum runs about two seconds of frames: ${dys.length}`;
	assert total > 29.5 && total < 31.5, `625 points/s under iOS friction travels about 307 points: ${total} notches`;
	assert frames === dys.length && !framePending(), "momentum stops once it is slower than the tolerance";
	setFrameDriver(null);
}

function pixelCanvas(pixels: string[]): SokolInput {
	return openCanvas(element(
		<Void ref={(h: VoidAreaHandle): void => {
			h.onPointer((e: AreaPointerEvent): void => {
				if (e.kind === AreaPointerKind.Wheel) { pixels.push(`${e.pixelDx},${e.pixelDy}`); }
			});
		}}>
			<View style={{ width: 200, height: 100 }} />
		</Void>
	));
}

test "a touch pan and its momentum scroll by the finger's pixels, a mouse wheel by notches alone" {
	const clock = useManualFrames();
	const pixels: string[] = [];
	const s = pixelCanvas(pixels);
	deliverAppEvent(s, { ...mouse(AppEventType.MouseScroll, 30.0, 40.0), scrollX: 1.0, scrollY: 2.0 });
	assert pixels.join("|") === "0,0", pixels.join("|");
	touch(s, AppEventType.TouchesBegan, 1 as int32, 40.0, 100.0);
	touch(s, AppEventType.TouchesMoved, 1 as int32, 40.0, 140.0);
	touch(s, AppEventType.TouchesMoved, 1 as int32, 40.0, 180.0);
	touch(s, AppEventType.TouchesMoved, 1 as int32, 40.0, 190.0);
	touch(s, AppEventType.TouchesMoved, 1 as int32, 20.0, 170.0);
	assert pixels.join("|") === "0,0|0,10|20,-20", pixels.join("|");
	const mark = pixels.length;
	for (let i = 1; i <= 6; i += 1) {
		clock.advance(16);
		touch(s, AppEventType.TouchesMoved, 1 as int32, 20.0, (170 + 20 * i) as float32);
	}
	touch(s, AppEventType.TouchesEnded, 1 as int32, 20.0, 290.0);
	clock.runAll();
	let total = 0.0;
	for (const p of pixels.slice(mark + 6)) {
		const dx = parseFloat(p.split(",")[0]);
		assert dx === 0.0, `a vertical fling scrolls no x: ${p}`;
		total += parseFloat(p.split(",")[1]);
	}
	assert total > 590.0 && total < 630.0, `625 points/s under iOS friction travels about 307 points, 614 pixels at scale 2: ${total}`;
	setFrameDriver(null);
}

test "a touch during momentum stops it and is not a tap" {
	const clock = useManualFrames();
	const log: string[] = [];
	const s = canvas(log);
	touch(s, AppEventType.TouchesBegan, 1 as int32, 40.0, 20.0);
	for (let i = 1; i <= 6; i += 1) {
		clock.advance(16);
		touch(s, AppEventType.TouchesMoved, 1 as int32, 40.0, (20 + 20 * i) as float32);
	}
	touch(s, AppEventType.TouchesEnded, 1 as int32, 40.0, 140.0);
	clock.step(5 as int32);
	touch(s, AppEventType.TouchesBegan, 2 as int32, 40.0, 60.0);
	const mark = log.length;
	clock.step(5 as int32);
	touch(s, AppEventType.TouchesEnded, 2 as int32, 40.0, 60.0);
	clock.step(40 as int32);
	assert log.length === mark, "the touch stopped the momentum and pressed nothing: " + log.slice(mark).join("|");
	assert !framePending(), "nothing keeps running";
	setFrameDriver(null);
}

test "two fingers scroll by their average and never press, even when only one of them moves" {
	const clock = useManualFrames();
	const log: string[] = [];
	const s = canvas(log);
	deliverTouches(s, event(AppEventType.TouchesBegan), [point(1 as int32, 40.0, 100.0), point(2 as int32, 100.0, 100.0)]);
	for (let i = 1; i <= 3; i += 1) {
		const y = (100 + 20 * i) as float32;
		deliverTouches(s, event(AppEventType.TouchesMoved), [point(1 as int32, 40.0, y), point(2 as int32, 100.0, y)]);
	}
	clock.advance(50);
	deliverTouches(s, event(AppEventType.TouchesEnded), [point(1 as int32, 40.0, 160.0), point(2 as int32, 100.0, 160.0)]);
	assert log.join("|") === "wheel 0,1", log.join("|");
	deliverTouches(s, event(AppEventType.TouchesBegan), [point(3 as int32, 40.0, 100.0), point(4 as int32, 100.0, 180.0)]);
	for (let i = 1; i <= 5; i += 1) {
		touch(s, AppEventType.TouchesMoved, 4 as int32, 100.0, (180 - 20 * i) as float32);
	}
	clock.advance(50);
	touch(s, AppEventType.TouchesEnded, 3 as int32, 40.0, 100.0);
	touch(s, AppEventType.TouchesEnded, 4 as int32, 100.0, 80.0);
	clock.step(40 as int32);
	assert log.join("|") === "wheel 0,1|wheel 0,-0.5", log.join("|");
	setFrameDriver(null);
}

test "a cancelled touch presses nothing, and a cancelled press-drag releases its button" {
	const clock = useManualFrames();
	const log: string[] = [];
	const s = canvas(log);
	touch(s, AppEventType.TouchesBegan, 1 as int32, 40.0, 60.0);
	touch(s, AppEventType.TouchesCancelled, 1 as int32, 40.0, 60.0);
	clock.step(40 as int32);
	assert log.length === 0, "a cancel before the timeout is no tap and no long press: " + log.join("|");
	touch(s, AppEventType.TouchesBegan, 2 as int32, 40.0, 60.0);
	clock.step(32 as int32);
	touch(s, AppEventType.TouchesCancelled, 2 as int32, 40.0, 60.0);
	assert log.join("|") === "down 20,30 b1|focus|up 20,30 b1", log.join("|");
	assert s.area.held === (0 as int32), "no press leaks past the cancel";
	setFrameDriver(null);
}

test "a touch that moves without having begun is refused by name" {
	const clock = useManualFrames();
	const s = canvas([]);
	let message = "";
	try {
		touch(s, AppEventType.TouchesMoved, 7 as int32, 40.0, 60.0);
	} catch (e) {
		message = (e as Error).message;
	}
	assert message === "sokol touch: touch 7 moved but never began", message;
	setFrameDriver(null);
}

test "the window's text input is on while a node that places the IME holds focus, and off after" {
	const clock = useManualFrames();
	const s = openCanvas(element(
		<Void>
			<View style={{ width: 200, height: 50 }} focusable imeRect={{ x: 0, y: 0, width: 2, height: 16 }} />
			<View style={{ width: 200, height: 50 }} focusable />
		</Void>
	));
	const calls: string[] = [];
	const set = (on: boolean): void => { calls.push(on ? "on" : "off"); };
	syncTextInput(s.area, set);
	touch(s, AppEventType.TouchesBegan, 1 as int32, 40.0, 40.0);
	touch(s, AppEventType.TouchesEnded, 1 as int32, 40.0, 40.0);
	syncTextInput(s.area, set);
	syncTextInput(s.area, set);
	touch(s, AppEventType.TouchesBegan, 2 as int32, 40.0, 160.0);
	touch(s, AppEventType.TouchesEnded, 2 as int32, 40.0, 160.0);
	syncTextInput(s.area, set);
	assert calls.join("|") === "on|off", calls.join("|");
	setFrameDriver(null);
}

test "a released area stops its momentum and a pending long press" {
	const clock = useManualFrames();
	const log: string[] = [];
	const flinging = canvas(log);
	touch(flinging, AppEventType.TouchesBegan, 1 as int32, 40.0, 20.0);
	for (let i = 1; i <= 6; i += 1) {
		clock.advance(16);
		touch(flinging, AppEventType.TouchesMoved, 1 as int32, 40.0, (20 + 20 * i) as float32);
	}
	touch(flinging, AppEventType.TouchesEnded, 1 as int32, 40.0, 140.0);
	clock.step(5 as int32);
	flinging.touch.stop();
	let mark = log.length;
	clock.step(60 as int32);
	assert log.length === mark, "no momentum reaches the released area: " + log.slice(mark).join("|");
	assert !framePending(), "no momentum frame stays requested";
	const holding = canvas(log);
	touch(holding, AppEventType.TouchesBegan, 2 as int32, 80.0, 60.0);
	holding.touch.stop();
	mark = log.length;
	clock.step(60 as int32);
	assert log.length === mark, "no long press reaches the released area: " + log.slice(mark).join("|");
	assert !framePending(), "no long-press frame stays requested";
	setFrameDriver(null);
}
