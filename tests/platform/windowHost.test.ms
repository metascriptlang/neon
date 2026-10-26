import { createSignal } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { flush, resetErrorHalt } from "../../src/core/runtime";
import { Show } from "../../src/macros/ui/flow";
import { render } from "../../src/render/host";
import { NeonEvent, DOM_DELTA_PIXEL } from "../../src/render/event";
import { NeonNode } from "../../src/render/node";
import {
	VoidAreaHandle,
	AreaKeyAction,
	AreaKeyEvent,
	AreaKeyMod,
	AreaPointerKind,
	AreaResize,
} from "../../src/render/voidAreaHandle";
import { Void, View, Text, Pressable, TextInput } from "../../src/components/primitives";
import { Scene2D, Label } from "../../src/components/scene2d";
import { NodeRef, textStyle } from "../../../void/src/void2d/node";
import { rgba } from "../../../void/src/void2d/types";
import { VoidNode, parseColor } from "../../src/platform/void/host";
import {
	AreaWindow,
	WindowArea,
	windowHost,
	windowNode,
	deliverKey,
	deliverPointer,
	deliverText,
	deliverPreedit,
	deliverFocus,
	deliverResize,
	logicalWidth,
	logicalHeight,
	drawArea,
} from "../../src/platform/void/windowHost";
import { areaPointer, setWindowTitle } from "../../src/platform/ion/window";
import { PointerEvent, PointerKind, DeltaMode, KeyMod } from "../../../ion/src/index";
import { PixelRatio } from "../../src/api/pixelRatio";
import { useWindowDimensions } from "../../src/render/environment";
import { refreshBoundary0, refreshComponent0, refreshModule, refreshReset } from "../../src/render/refresh";
import { DrawKind, clearChanges } from "../../../void/src/void2d/node";
import { labelTexts } from "../../../void/src/void2d/labelText";
import { paint as paintScene } from "../../../void/src/void2d/scene";
import { frameEnd } from "../../../void/src/void2d/draw";
import { Color } from "../../../void/src/void2d/types";
import { FontId, addFont } from "../../../void/src/void2d/font";
import { devDriver } from "../../src/devtools/driver";
import { ControlSession, handleRequest } from "../../src/devtools/control";

const FONT_PATH = "../void/assets/font.ttf";

function loadedFont(): FontId {
	const r = addFont(FONT_PATH);
	if (!r.ok) { throw new Error("the test font did not load from " + FONT_PATH + "; run from the Neon checkout root beside ../void"); }
	return r.value;
}

interface Probe {
	window: AreaWindow;
	log: string[];
	areas: WindowArea[];
}

function probe(): Probe {
	const log: string[] = [];
	const areas: WindowArea[] = [];
	return {
		log,
		areas,
		window: {
			name: "test window",
			font: loadedFont(),
			pixelWidth: (): int32 => 640 as int32,
			pixelHeight: (): int32 => 360 as int32,
			requestFrame: (): void => { log.push("frame"); },
			dirty: (): void => { log.push("dirty"); },
			setImeRect: (pixelX: int32, pixelY: int32, pixelW: int32, pixelH: int32): void => {},
			opened: (area: WindowArea): void => {
				areas.push(area);
				log.push("opened");
			},
			released: (area: WindowArea): void => { log.push("released"); },
		},
	};
}

function thrown(run: () => void): string {
	try {
		run();
	} catch (e) {
		return (e as Error).message;
	}
	return "";
}

test "the window opens its one Void on the Void host, with the Void's style on the area" {
	const p = probe();
	render(element(
		<Void style={{ backgroundColor: "#102030", padding: 4 }}>
			<View><Text>hi</Text></View>
		</Void>
	), windowHost(p.window), windowNode("window"));
	assert p.areas.length === 1, "one area opened";
	const area = p.areas[0];
	const root = area.vh.root as VoidNode;
	assert root.children.length === 1, "the View is the area root's child";
	assert root.children[0].ref.kind() === DrawKind.Group, "the View is a Void group";
	assert area.vh.scene.clear == (parseColor("#102030") as Color), "the background clears the scene";
	assert area.hub.handle.pixelWidth() === (640 as int32), "the handle starts at the window's pixel width";
	assert p.log.indexOf("frame") > p.log.indexOf("opened"), "the style asked for a frame after the area opened: " + p.log.join(",");
}

test "a Scene2D in the window's Void draws its Label and Text in the window font" {
	const p = probe();
	const labels: NodeRef[] = [];
	const dispose = render(element(
		<Void><Scene2D>
			<Label text="world" size={12.0} color={rgba(1.0, 1.0, 1.0, 1.0)} ref={(node: NodeRef): void => { labels.push(node); }} />
			<View><Text>hud</Text></View>
		</Scene2D></Void>
	), windowHost(p.window), windowNode("window"));
	assert labels.length === 1 && labels[0].textStyle().font === p.window.font, "a Label without textStyle takes the window font";
	let fonts: string[] = [];
	for (const entry of labelTexts) {
		if (entry.text === "hud") { fonts.push((entry.style.font as int32).toString()); }
	}
	assert fonts.length === 1 && fonts[0] === (p.window.font as int32).toString(), "a Text in the Scene2D takes the window font: " + fonts.join(",");
	dispose();
}

test "a tree change inside the area wakes the window, and disposing the owner releases the area once" {
	const p = probe();
	const [n, setN] = createSignal(1);
	const dispose = render(element(
		<Void><Text>{n().toString()}</Text></Void>
	), windowHost(p.window), windowNode("window"));
	const area = p.areas[0];
	area.vh.scene.paintScene(400.0, 300.0, 1.0);
	frameEnd();
	area.vh.scene.clearChanges();
	const mark = p.log.length;
	setN(2);
	flush();
	assert p.log.slice(mark).join(",") === "dirty", "one wake: " + p.log.join(",");
	dispose();
	assert p.log.slice(mark).join(",") === "dirty,released", "released: " + p.log.join(",");
}

function windowOnly(child: NeonNode): () => void {
	const p = probe();
	return (): void => { render(child, windowHost(p.window), windowNode("window")); };
}

test "anything but one Void at the window is refused by name" {
	assert thrown(windowOnly(element(<View />))) === "test window host: <view> cannot be a child of the window; the window holds exactly one <Void>",
		thrown(windowOnly(element(<View />)));
	assert thrown(windowOnly(element(<><Void /><Void /></>))).indexOf("a second <Void> was mounted") >= 0,
		thrown(windowOnly(element(<><Void /><Void /></>)));
}

test "a refresh boundary at the window: its empty anchor is accepted, and a remount replaces the Void" {
	refreshReset();
	const p = probe();
	const file = "windowHost.test";
	const v1 = (): NeonNode => element(<Void><Text>v1</Text></Void>);
	const v2 = (): NeonNode => element(<Void><Text>v2</Text></Void>);
	const window = windowNode("window");
	render(refreshBoundary0(file, "App", v1, (): string => "v1"), windowHost(p.window), window);
	assert p.areas.length === 1, "one area opened";
	refreshComponent0(file, "App", v2, (): string => "v2");
	const summary = refreshModule(file);
	assert summary.remounted === 1, "the window-level component remounted";
	assert p.areas.length === 2 && p.log.filter((l: string): boolean => l === "released").length === 1, "the old area released, a new one opened: " + p.log.join(",");
	assert (p.areas[1].vh.root as VoidNode).children.length === 1, "the new area holds the new Text";
	assert thrown(windowOnly(element(<>{"hi"}<Void /></>))).indexOf("text \"hi\" cannot be a child of the window") >= 0, "text with characters is still refused";
}

test "a Show at the window swaps its Void for the fallback's through the region holder" {
	const p = probe();
	const [first, setFirst] = createSignal(true);
	render(element(
		<Show when={first()} fallback={<Void><Text>b</Text></Void>}><Void><Text>a</Text></Void></Show>
	), windowHost(p.window), windowNode("window"));
	assert p.areas.length === 1, "one area opened";
	setFirst(false);
	flush();
	assert p.areas.length === 2 && p.log.filter((l: string): boolean => l === "released").length === 1, "the fallback's Void replaced the first: " + p.log.join(",");
}

test "a later pass that brings a View to the window is refused when the View reaches the window" {
	const p = probe();
	const [shown, setShown] = createSignal(false);
	render(element(<Show when={shown()}><View /></Show>), windowHost(p.window), windowNode("window"));
	let failure = "";
	try {
		setShown(true);
		flush();
	} catch (e) {
		failure = (e as Error).message;
	} finally {
		resetErrorHalt();
	}
	assert failure === "test window host: <view> cannot be a child of the window; the window holds exactly one <Void>", failure;
}

function key(action: AreaKeyAction, text: string, mods: BitSet<AreaKeyMod>): AreaKeyEvent {
	return { action, key: 20, scancode: 30, mods, consumedMods: 0 as BitSet<AreaKeyMod>, unshifted: 97, text };
}

test "window input reaches the handle's subscribers and the focused node alike" {
	const p = probe();
	const log: string[] = [];
	let handle: VoidAreaHandle | null = null;
	render(element(
		<Void ref={(h: VoidAreaHandle): void => {
			handle = h;
			h.onKey((e: AreaKeyEvent): void => { log.push("hub key " + e.text); });
			h.onText((t: string): void => { log.push("hub text " + t); });
			h.onResize((e: AreaResize): void => { log.push(`hub resize ${e.pixelWidth}x${e.pixelHeight}@${e.scale}`); });
		}}>
			<View style={{ width: 200, height: 100 }} focusable
				onKeyDown={(e: NeonEvent): void => { log.push(`keydown ${e.key} ${e.code} ${e.mods} ${e.ctrlKey}`); }}
				onKeyUp={(e: NeonEvent): void => { log.push(`keyup ${e.code}`); }}
				onTextInput={(e: NeonEvent): void => { log.push("textinput " + e.text); }}
				onPreedit={(e: NeonEvent): void => { log.push(`preedit ${e.text}@${e.cursor}`); }}
				onPointerDown={(e: NeonEvent): void => { log.push(`down ${e.x},${e.y} b${e.button}`); }}
				onFocus={(): void => { log.push("focus"); }}
				onBlur={(): void => { log.push("blur"); }} />
		</Void>
	), windowHost(p.window), windowNode("window"));
	const area = p.areas[0];
	deliverResize(area, 800 as int32, 400 as int32, 2.0);
	assert area.logicalWidth() === 400.0 && area.logicalHeight() === 200.0, "logical size is pixels over scale";
	assert PixelRatio.get() === 2, "the scale is published";
	assert useWindowDimensions()().width === 400 && useWindowDimensions()().height === 200, "the logical window size is published";
	area.vh.layout(area.logicalWidth(), area.logicalHeight());
	deliverPointer(area, { kind: AreaPointerKind.Button, pixelX: 20.0, pixelY: 40.0, button: 1 as int32, pressed: true, dx: 0.0, dy: 0.0 });
	assert area.held === (1 as int32), "the pressed button is held";
	deliverKey(area, key(AreaKeyAction.Press, "a", 0 as BitSet<AreaKeyMod>), "KeyA");
	deliverKey(area, key(AreaKeyAction.Press, "", (0 as BitSet<AreaKeyMod>).incl(AreaKeyMod.Ctrl)), "KeyA");
	deliverKey(area, key(AreaKeyAction.Release, "", 0 as BitSet<AreaKeyMod>), "KeyA");
	deliverText(area, "é");
	deliverPreedit(area, "ni", 2 as int32);
	assert area.composing, "a preedit marks the area composing";
	deliverFocus(area, false);
	assert log.join("|") === [
		"hub resize 800x400@2",
		"down 10,20 b1",
		"focus",
		"hub key a",
		"keydown a KeyA 0 false",
		"hub key ",
		"keydown a KeyA 2 true",
		"hub key ",
		"keyup KeyA",
		"hub text é",
		"textinput é",
		"preedit ni@2",
		"blur",
	].join("|"), log.join("|");
}

test "an onLayout that releases the area ends the frame without drawing the closed scene" {
	const p = probe();
	let dispose: (() => void) | null = null;
	dispose = render(element(
		<Void><View style={{ width: 10, height: 10 }} onLayout={(e: NeonEvent): void => {
			p.log.push("layout");
			if (dispose !== null) { (dispose as () => void)(); }
		}} /></Void>
	), windowHost(p.window), windowNode("window"));
	const mark = p.log.length;
	assert !drawArea(p.areas[0]), "a released area reports the frame undrawn";
	assert p.log.slice(mark).join(",") === "layout,released", p.log.join(",");
}

test "a sibling onLayout after the release does not run, and the frame stays undrawn" {
	const p = probe();
	let dispose: (() => void) | null = null;
	dispose = render(element(
		<Void>
			<View style={{ width: 10, height: 10 }} onLayout={(e: NeonEvent): void => {
				p.log.push("first");
				if (dispose !== null) { (dispose as () => void)(); }
			}} />
			<View style={{ width: 20, height: 20 }} onLayout={(e: NeonEvent): void => { p.log.push("second"); }} />
		</Void>
	), windowHost(p.window), windowNode("window"));
	const mark = p.log.length;
	assert !drawArea(p.areas[0]), "a released area reports the frame undrawn";
	assert p.log.slice(mark).join(",") === "first,released", p.log.join(",");
}

test "the control channel drives a window: tree shows what is laid out, press and type take the real input path" {
	const p = probe();
	const log: string[] = [];
	const dispose = render(element(
		<Void>
			<View style={{ width: 300, height: 200 }}>
				<Pressable style={{ width: 120, height: 40 }} onPress={(): void => { log.push("pressed"); }}><Text>Add</Text></Pressable>
				<TextInput style={{ width: 200, height: 24 }} onChangeText={(t: string): void => { log.push("text " + t); }} />
			</View>
		</Void>
	), windowHost(p.window), windowNode("window"));
	flush();
	const area = p.areas[0];
	deliverResize(area, 600 as int32, 400 as int32, 2.0);
	area.vh.layout(area.logicalWidth(), area.logicalHeight());
	assert devDriver() !== null, "opening the area registers the driver";
	const lines: string[] = [];
	const s = new ControlSession((line: string): void => { lines.push(line); });
	handleRequest(s, `{"jsonrpc":"2.0","id":1,"method":"tree"}`);
	assert lines[0].includes(`"text":"Add"`) && lines[0].includes(`"pressable":true,"frame":[0,0,120,40]`), lines[0];
	handleRequest(s, `{"jsonrpc":"2.0","id":2,"method":"press","params":{"target":"text:Add"}}`);
	flush();
	assert lines[1].includes(`"result"`), lines[1];
	assert area.held === (0 as int32), "press releases the button it pressed";
	handleRequest(s, `{"jsonrpc":"2.0","id":3,"method":"press","params":{"target":"0.1"}}`);
	handleRequest(s, `{"jsonrpc":"2.0","id":4,"method":"type","params":{"text":"hi"}}`);
	flush();
	handleRequest(s, `{"jsonrpc":"2.0","id":5,"method":"tree"}`);
	assert lines[4].includes(`"value":"hi","focused":true`), lines[4];
	assert log.join("|") === "pressed|text hi", log.join("|");
	dispose();
	assert devDriver() === null, "releasing the area drops the driver";
}

function wheel(deltaMode: DeltaMode, dy: float64): PointerEvent {
	return { window: 0 as int32, kind: PointerKind.Wheel, x: 20.0, y: 40.0, button: 0 as int32, pressed: false, dx: 0.0, dy, deltaMode, mods: 0 as BitSet<KeyMod> };
}

test "an Ion trackpad wheel reaches onWheel in layout points and a notch as one line" {
	const p = probe();
	const log: string[] = [];
	render(element(
		<Void>
			<View style={{ width: 200, height: 100 }}
				onWheel={(e: NeonEvent): void => { log.push(`${e.deltaMode === DOM_DELTA_PIXEL ? "pixel" : "line"} ${e.deltaY}`); }} />
		</Void>
	), windowHost(p.window), windowNode("window"));
	const area = p.areas[0];
	deliverResize(area, 800 as int32, 400 as int32, 2.0);
	area.vh.layout(area.logicalWidth(), area.logicalHeight());
	deliverPointer(area, areaPointer(wheel(DeltaMode.Pixel, -40.0)));
	deliverPointer(area, areaPointer(wheel(DeltaMode.Line, 1.0)));
	assert log.join("|") === "pixel -20|line 1", log.join("|");
}

test "setWindowTitle before runWindow opened its window names the call" {
	assert thrown((): void => { setWindowTitle("vim"); }) === "setWindowTitle(\"vim\") ran before runWindow opened its window; the first title goes in desktopOptions", "a title with no window is refused";
}
