import { createSignal } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { render } from "../../src/render/host";
import { NeonEvent, neonEvent } from "../../src/render/event";
import { View, Text, TextInput } from "../../src/components/primitives";
import {
	createVoidHostWith, VoidHost, VoidNode, TextEditingValue, editingValue, CaretRect,
} from "../../src/platform/void/host";
import { Scene2D, NodeRef, text, paint, textStyle, local, getChildAt, clearChanges } from "../../../void/src/void2d/node";
import { create, paint as paintScene, isDirty } from "../../../void/src/void2d/scene";
import { frameEnd } from "../../../void/src/void2d/draw";
import { xForIndex, textWidth } from "../../../void/src/void2d/render";
import { rgba } from "../../../void/src/void2d/types";
import { FontId, DEFAULT_FONT, addFont } from "../../../void/src/void2d/font";

const FONT_PATH = "../void/assets/font.ttf";

function loadedFont(): FontId {
	const r = addFont(FONT_PATH);
	if (!r.ok) { throw new Error("the test font did not load from " + FONT_PATH + "; run from the Neon checkout root beside ../void"); }
	return r.value;
}

function host(): VoidHost {
	return createVoidHostWith(Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0)), loadedFont());
}

function settle(vh: VoidHost): void {
	vh.scene.paintScene(400.0, 300.0, 1.0);
	frameEnd();
	vh.scene.clearChanges();
}

function key(k: string): NeonEvent {
	const e = neonEvent("keydown");
	e.key = k;
	e.code = k;
	return e;
}

function top(vh: VoidHost): VoidNode {
	return (vh.root as VoidNode).children[0];
}

function field(vh: VoidHost): VoidNode {
	return top(vh).children[0];
}

function labelOf(n: VoidNode): NodeRef {
	return n.ref.getChildAt(0);
}

test "a click focuses the text field and typed text reaches onChangeText" {
	const vh = host();
	const seen: string[] = [];
	render(element(
		<View style={{ width: 300, height: 100 }}>
			<TextInput style={{ width: 200, height: 24 }} onChangeText={(t: string): void => { seen.push(t); }} />
		</View>
	), vh.host, vh.root);
	vh.layout(300.0, 100.0);
	vh.clickAt(10.0, 10.0);
	assert vh.focused() === field(vh), "the click focused the field";
	vh.commitText("h");
	vh.commitText("i");
	assert seen.join(",") === "h,hi", "each commit reported: " + seen.join(",");
	assert labelOf(field(vh)).text() === "hi", "the label shows the value";
}

test "a Telex word shows its preedit and reports once, on commit" {
	const vh = host();
	const seen: string[] = [];
	render(element(<TextInput style={{ width: 200, height: 24 }} onChangeText={(t: string): void => { seen.push(t); }} />), vh.host, vh.root);
	vh.layout(300.0, 100.0);
	vh.focus(top(vh));
	for (const step of ["v", "vi", "vie", "viê", "viêt", "việt"]) {
		vh.composeText(step, step.length);
	}
	assert seen.length === 0, "no change while composing: " + seen.join(",");
	assert labelOf(top(vh)).text() === "việt", "the preedit is drawn inline";
	vh.composeText("", 0);
	vh.commitText("việt");
	assert seen.join(",") === "việt", "one change on commit: " + seen.join(",");
}

test "Backspace, arrows and Enter edit the focused field" {
	const vh = host();
	const seen: string[] = [];
	let submitted = "";
	let pressed = "";
	render(element(<TextInput
		onChangeText={(t: string): void => { seen.push(t); }}
		onKeyPress={(e: NeonEvent): void => { pressed = pressed + e.key + " "; }}
		onSubmitEditing={(e: NeonEvent): void => { submitted = e.value; }} />), vh.host, vh.root);
	vh.focus(top(vh));
	vh.commitText("abc");
	vh.keyDown(key("ArrowLeft"));
	vh.keyDown(key("Backspace"));
	assert seen[seen.length - 1] === "ac", "backspace before the caret: " + seen.join(",");
	vh.keyDown(key("Enter"));
	assert submitted === "ac", "submit carries the text: " + submitted;
	assert pressed === "ArrowLeft Backspace Enter ", "onKeyPress saw each key: " + pressed;
}

test "a controlled value replaces the text without reporting a change" {
	const vh = host();
	const [value, setValue] = createSignal("one");
	let changes = 0;
	render(element(<TextInput value={value()} onChangeText={(t: string): void => { changes = changes + 1; }} />), vh.host, vh.root);
	assert labelOf(top(vh)).text() === "one", "initial value drawn";
	setValue("two");
	assert labelOf(top(vh)).text() === "two", "new value drawn";
	assert changes === 0, "a value set by the app is not a change: " + changes.toString();
}

test "keys go to the focused node and bubble to its parents" {
	const vh = host();
	let order = "";
	let inner: VoidNode | null = null;
	render(element(
		<View onKeyDown={(e: NeonEvent): void => { order = order + "outer:" + e.key + " "; }}>
			<View ref={(n: HostNode): void => { inner = n as VoidNode; }} onKeyDown={(e: NeonEvent): void => { order = order + "inner:" + e.key + " "; }} />
		</View>
	), vh.host, vh.root);
	vh.keyDown(key("a"));
	assert order === "", "nothing is focused, nothing receives keys: " + order;
	vh.focus(inner);
	vh.keyDown(key("a"));
	assert order === "inner:a outer:a ", "focused first, then its parent: " + order;
}

test "focus moves on click, fires onFocus and onBlur, and a click on empty space blurs" {
	const vh = host();
	let log = "";
	render(element(
		<View style={{ width: 300, height: 100, flexDirection: "row" }}>
			<TextInput style={{ width: 100, height: 24 }} onFocus={(): void => { log = log + "+a "; }} onBlur={(): void => { log = log + "-a "; }} />
			<TextInput style={{ width: 100, height: 24 }} onFocus={(): void => { log = log + "+b "; }} onBlur={(): void => { log = log + "-b "; }} />
		</View>
	), vh.host, vh.root);
	vh.layout(300.0, 100.0);
	vh.clickAt(10.0, 10.0);
	vh.clickAt(110.0, 10.0);
	vh.clickAt(250.0, 90.0);
	assert log === "+a -a +b -b ", "focus sequence: " + log;
	assert vh.focused() === null, "empty space leaves nothing focused";
}

test "window focus blurs and refocuses the focused node" {
	const vh = host();
	let log = "";
	render(element(<TextInput onFocus={(): void => { log = log + "+ "; }} onBlur={(): void => { log = log + "- "; }} />), vh.host, vh.root);
	vh.focus(top(vh));
	vh.setWindowFocus(false);
	vh.setWindowFocus(true);
	assert log === "+ - + ", "window focus reached the node: " + log;
	assert vh.focused() === top(vh), "the node keeps focus across the window";
}

test "onLayout reports the frame once per change" {
	const vh = host();
	const frames: string[] = [];
	render(element(
		<View style={{ flexGrow: 1, padding: 10 }} onLayout={(e: NeonEvent): void => { frames.push(e.x.toString() + "," + e.y.toString() + "," + e.width.toString() + "x" + e.height.toString()); }} />
	), vh.host, vh.root);
	vh.layout(400.0, 300.0);
	vh.layout(400.0, 300.0);
	vh.layout(500.0, 200.0);
	assert frames.join(" ") === "0,0,400x300 0,0,500x200", "frames: " + frames.join(" ");
}

test "the IME rect follows the caret of the focused field in window coordinates" {
	const vh = host();
	render(element(
		<View style={{ width: 300, height: 100, paddingLeft: 20, paddingTop: 30 }}>
			<TextInput style={{ width: 200, height: 24 }} />
		</View>
	), vh.host, vh.root);
	vh.layout(300.0, 100.0);
	assert vh.imeRect() === null, "no focus, no rect";
	vh.clickAt(25.0, 35.0);
	vh.commitText("abc");
	const r = vh.imeRect() as CaretRect;
	assert r.x === 20.0 + labelOf(field(vh)).xForIndex(3) && r.x > 20.0 && r.y === 30.0, `rect at ${r.x},${r.y}`;
	assert r.h > 0.0, "rect has the line height";
}

test "a hand-drawn node receives text as a Flutter-style text input client" {
	const vh = host();
	const node = vh.host.createElement("view") as VoidNode;
	vh.host.append(vh.root, node);
	const values: string[] = [];
	vh.attachTextInput(node, {
		updateEditingValue: (v: TextEditingValue): void => {
			values.push(`${v.text}[${v.composing.start},${v.composing.end}]`);
		},
		caretRect: (): CaretRect => { return { x: 5.0, y: 6.0, w: 1.0, h: 16.0 }; },
	}, editingValue(""));
	vh.focus(node);
	vh.composeText("a", 1);
	vh.commitText("á");
	vh.setEditingState(node, editingValue(""));
	vh.commitText("x");
	assert values.join(" ") === "a[0,1] á[-1,-1] [-1,-1] x[-1,-1]", "values: " + values.join(" ");
	const r = vh.imeRect() as CaretRect;
	assert r.x === 5.0 && r.y === 6.0, "the client's caret rect, offset by the node";
}

test "a tree change wakes the host once the scene is clean" {
	const vh = host();
	let woke = 0;
	vh.onDirty((): void => { woke = woke + 1; });
	const [n, setN] = createSignal(0);
	settle(vh);
	assert !vh.scene.isDirty(), "a painted scene with no writes is clean";
	render(element(<View><TextInput value={n().toString()} /></View>), vh.host, vh.root);
	assert woke === 1, "mounting woke the host once: " + woke.toString();
	settle(vh);
	setN(1);
	assert woke === 2, "a signal write woke it again: " + woke.toString();
}

test "every label the host makes draws in the host's font" {
	const second = loadedFont();
	assert second !== DEFAULT_FONT, "the test font is a second face";
	const vh = createVoidHostWith(Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0)), second);
	render(element(<View><Text>hi</Text><TextInput /></View>), vh.host, vh.root);
	const view = top(vh);
	assert view.children[0].children[0].ref.textStyle().font === second, "text label font";
	assert labelOf(view.children[1]).textStyle().font === second, "text field label font";
}

test "text pieces inside one element flow one after another on the line" {
	const vh = host();
	const [n, setN] = createSignal(7);
	render(element(<View style={{ width: 200, height: 20 }}><Text>Count: {n().toString()}</Text></View>), vh.host, vh.root);
	vh.layout(200.0, 20.0);
	const line = top(vh).children[0];
	assert line.children[0].ref.local().x === 0.0, "first piece at the start";
	const second = line.children[1].ref.local().x;
	assert second === line.children[0].ref.textWidth() && second > 0.0, "second piece after 'Count: ': " + second.toString();
}

test "a text field keeps its text color when it has a background" {
	const vh = host();
	render(element(<TextInput style={{ backgroundColor: "#313244", color: "#ffffff" }} />), vh.host, vh.root);
	const f = top(vh);
	assert Math.abs(f.ref.paint().color.r - 0x31 / 255.0) < 0.001 && Math.abs(f.ref.paint().color.b - 0x44 / 255.0) < 0.001, "the field paints the background";
	assert labelOf(f).paint().color.r === 1.0, "the label keeps the text color, got r=" + labelOf(f).paint().color.r.toString();
}
