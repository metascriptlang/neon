import { createSignal } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { render, HostNode } from "../../src/render/host";
import { NeonEvent, neonEvent } from "../../src/render/event";
import { View, Text, TextInput } from "../../src/components/primitives";
import {
	createVoidHostWith, VoidHost, Node2D, TextEditingValue, editingValue, CaretRect,
} from "../../src/platform/void/host";

const ADVANCE: float32 = 8.0;

function fixedMeasure(size: float32, text: string): float32 {
	return (text.length as float32) * ADVANCE;
}

function key(k: string): NeonEvent {
	const e = neonEvent("keydown");
	e.key = k;
	e.code = k;
	return e;
}


function field(vh: VoidHost): Node2D {
	return vh.root.children[0].children[0];
}

test "a click focuses the text field and typed text reaches onChangeText" {
	const vh = createVoidHostWith(fixedMeasure, 0 as int32);
	const seen: string[] = [];
	render(element(
		<View style={{ width: 300, height: 100 }}>
			<TextInput style={{ width: 200, height: 24 }} onChangeText={(t: string): void => { seen.push(t); }} />
		</View>
	), vh.host, vh.root as unknown as HostNode);
	vh.layout(300.0, 100.0);
	vh.clickAt(10.0, 10.0);
	assert vh.focused() === field(vh), "the click focused the field";
	vh.commitText("h");
	vh.commitText("i");
	assert seen.join(",") === "h,hi", "each commit reported: " + seen.join(",");
	assert field(vh).children[0].text === "hi", "the label shows the value";
}

test "a Telex word shows its preedit and reports once, on commit" {
	const vh = createVoidHostWith(fixedMeasure, 0 as int32);
	const seen: string[] = [];
	render(element(<TextInput style={{ width: 200, height: 24 }} onChangeText={(t: string): void => { seen.push(t); }} />), vh.host, vh.root as unknown as HostNode);
	vh.layout(300.0, 100.0);
	vh.focus(vh.root.children[0]);
	for (const step of ["v", "vi", "vie", "viê", "viêt", "việt"]) {
		vh.composeText(step, step.length);
	}
	assert seen.length === 0, "no change while composing: " + seen.join(",");
	assert vh.root.children[0].children[0].text === "việt", "the preedit is drawn inline";
	vh.composeText("", 0);
	vh.commitText("việt");
	assert seen.join(",") === "việt", "one change on commit: " + seen.join(",");
}

test "Backspace, arrows and Enter edit the focused field" {
	const vh = createVoidHostWith(fixedMeasure, 0 as int32);
	const seen: string[] = [];
	let submitted = "";
	let pressed = "";
	render(element(<TextInput
		onChangeText={(t: string): void => { seen.push(t); }}
		onKeyPress={(e: NeonEvent): void => { pressed = pressed + e.key + " "; }}
		onSubmitEditing={(e: NeonEvent): void => { submitted = e.value; }} />), vh.host, vh.root as unknown as HostNode);
	vh.focus(vh.root.children[0]);
	vh.commitText("abc");
	vh.keyDown(key("ArrowLeft"));
	vh.keyDown(key("Backspace"));
	assert seen[seen.length - 1] === "ac", "backspace before the caret: " + seen.join(",");
	vh.keyDown(key("Enter"));
	assert submitted === "ac", "submit carries the text: " + submitted;
	assert pressed === "ArrowLeft Backspace Enter ", "onKeyPress saw each key: " + pressed;
}

test "a controlled value replaces the text without reporting a change" {
	const vh = createVoidHostWith(fixedMeasure, 0 as int32);
	const [value, setValue] = createSignal("one");
	let changes = 0;
	render(element(<TextInput value={value()} onChangeText={(t: string): void => { changes = changes + 1; }} />), vh.host, vh.root as unknown as HostNode);
	assert vh.root.children[0].children[0].text === "one", "initial value drawn";
	setValue("two");
	assert vh.root.children[0].children[0].text === "two", "new value drawn";
	assert changes === 0, "a value set by the app is not a change: " + changes.toString();
}

test "keys go to the focused node and bubble to its parents" {
	const vh = createVoidHostWith(fixedMeasure, 0 as int32);
	let order = "";
	let inner: Node2D | null = null;
	render(element(
		<View onKeyDown={(e: NeonEvent): void => { order = order + "outer:" + e.key + " "; }}>
			<View ref={(n: HostNode): void => { inner = n as unknown as Node2D; }} onKeyDown={(e: NeonEvent): void => { order = order + "inner:" + e.key + " "; }} />
		</View>
	), vh.host, vh.root as unknown as HostNode);
	vh.keyDown(key("a"));
	assert order === "", "nothing is focused, nothing receives keys: " + order;
	vh.focus(inner);
	vh.keyDown(key("a"));
	assert order === "inner:a outer:a ", "focused first, then its parent: " + order;
}

test "focus moves on click, fires onFocus and onBlur, and a click on empty space blurs" {
	const vh = createVoidHostWith(fixedMeasure, 0 as int32);
	let log = "";
	render(element(
		<View style={{ width: 300, height: 100, flexDirection: "row" }}>
			<TextInput style={{ width: 100, height: 24 }} onFocus={(): void => { log = log + "+a "; }} onBlur={(): void => { log = log + "-a "; }} />
			<TextInput style={{ width: 100, height: 24 }} onFocus={(): void => { log = log + "+b "; }} onBlur={(): void => { log = log + "-b "; }} />
		</View>
	), vh.host, vh.root as unknown as HostNode);
	vh.layout(300.0, 100.0);
	vh.clickAt(10.0, 10.0);
	vh.clickAt(110.0, 10.0);
	vh.clickAt(250.0, 90.0);
	assert log === "+a -a +b -b ", "focus sequence: " + log;
	assert vh.focused() === null, "empty space leaves nothing focused";
}

test "window focus blurs and refocuses the focused node" {
	const vh = createVoidHostWith(fixedMeasure, 0 as int32);
	let log = "";
	render(element(<TextInput onFocus={(): void => { log = log + "+ "; }} onBlur={(): void => { log = log + "- "; }} />), vh.host, vh.root as unknown as HostNode);
	vh.focus(vh.root.children[0]);
	vh.setWindowFocus(false);
	vh.setWindowFocus(true);
	assert log === "+ - + ", "window focus reached the node: " + log;
	assert vh.focused() === vh.root.children[0], "the node keeps focus across the window";
}

test "onLayout reports the frame once per change" {
	const vh = createVoidHostWith(fixedMeasure, 0 as int32);
	const frames: string[] = [];
	render(element(
		<View style={{ flexGrow: 1, padding: 10 }} onLayout={(e: NeonEvent): void => { frames.push(e.x.toString() + "," + e.y.toString() + "," + e.width.toString() + "x" + e.height.toString()); }} />
	), vh.host, vh.root as unknown as HostNode);
	vh.layout(400.0, 300.0);
	vh.layout(400.0, 300.0);
	vh.layout(500.0, 200.0);
	assert frames.join(" ") === "0,0,400x300 0,0,500x200", "frames: " + frames.join(" ");
}

test "the IME rect follows the caret of the focused field in window coordinates" {
	const vh = createVoidHostWith(fixedMeasure, 0 as int32);
	render(element(
		<View style={{ width: 300, height: 100, paddingLeft: 20, paddingTop: 30 }}>
			<TextInput style={{ width: 200, height: 24 }} />
		</View>
	), vh.host, vh.root as unknown as HostNode);
	vh.layout(300.0, 100.0);
	assert vh.imeRect() === null, "no focus, no rect";
	vh.clickAt(25.0, 35.0);
	vh.commitText("abc");
	const r = vh.imeRect() as CaretRect;
	assert r.x === 20.0 + 3.0 * ADVANCE && r.y === 30.0, `rect at ${r.x},${r.y}`;
	assert r.h > 0.0, "rect has the line height";
}

test "a hand-drawn node receives text as a Flutter-style text input client" {
	const vh = createVoidHostWith(fixedMeasure, 0 as int32);
	const node = vh.host.createElement("view") as unknown as Node2D;
	vh.host.append(vh.root as unknown as HostNode, node as unknown as HostNode);
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

test "any tree change marks the host dirty" {
	const vh = createVoidHostWith(fixedMeasure, 0 as int32);
	let dirty = 0;
	vh.onDirty((): void => { dirty = dirty + 1; });
	const [n, setN] = createSignal(0);
	render(element(<View><TextInput value={n().toString()} /></View>), vh.host, vh.root as unknown as HostNode);
	const before = dirty;
	assert before > 0, "mounting marked dirty";
	setN(1);
	assert dirty > before, "a signal write marked dirty";
}

test "every label the host makes draws in the host's font" {
	const vh = createVoidHostWith(fixedMeasure, 3 as int32);
	render(element(<View><Text>hi</Text><TextInput /></View>), vh.host, vh.root as unknown as HostNode);
	const view = vh.root.children[0];
	assert view.children[0].children[0].fontId === 3, "text label font";
	assert view.children[1].children[0].fontId === 3, "text field label font";
}

test "text pieces inside one element flow one after another on the line" {
	const vh = createVoidHostWith(fixedMeasure, 0 as int32);
	const [n, setN] = createSignal(7);
	render(element(<View style={{ width: 200, height: 20 }}><Text>Count: {n().toString()}</Text></View>), vh.host, vh.root as unknown as HostNode);
	vh.layout(200.0, 20.0);
	const text = vh.root.children[0].children[0];
	assert text.children[0].x === 0.0, "first piece at the start";
	assert text.children[1].x === 7.0 * ADVANCE, "second piece after 'Count: ': " + text.children[1].x.toString();
}

test "a text field keeps its text color when it has a background" {
	const vh = createVoidHostWith(fixedMeasure, 0 as int32);
	render(element(<TextInput style={{ backgroundColor: "#313244", color: "#ffffff" }} />), vh.host, vh.root as unknown as HostNode);
	const f = vh.root.children[0];
	assert Math.abs(f.color.r - 0x31 / 255.0) < 0.001 && Math.abs(f.color.b - 0x44 / 255.0) < 0.001, "the field paints the background";
	assert f.children[0].color.r === 1.0, "the label keeps the text color, got r=" + f.children[0].color.r.toString();
}
