import { createSignal, Accessor } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { render } from "../../src/render/host";
import { NeonEvent, neonEvent } from "../../src/render/event";
import { View, Text, TextInput, Pressable } from "../../src/components/primitives";
import { ForList, Show } from "../../src/macros/ui/flow";
import { createList } from "../../src/core/list";
import { NeonNode } from "../../src/render/node";
import {
	createVoidHostWith, VoidHost, VoidNode, TextEditingValue, editingValue, CaretRect,
} from "../../src/platform/void/host";
import { Scene2D, NodeRef, DrawKind, Changed, text, paint, textStyle, local, getChildAt, clearChanges, numChildren, localToGlobal } from "../../../void/src/void2d/node";
import { create, paint as paintScene, isDirty } from "../../../void/src/void2d/scene";
import { frameEnd } from "../../../void/src/void2d/draw";
import { xForIndex, textWidth, lineBoxAt } from "../../../void/src/void2d/render";
import { TextRun } from "../../../void/src/void2d/textLayout";
import { TextSpan } from "../../src/render/hostTypes";
import { Style } from "../../src/render/style";
import { rgba, vec2, Vec2 } from "../../../void/src/void2d/types";
import { labelTexts } from "../../../void/src/void2d/labelText";
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

function paragraph(text: VoidNode): NodeRef {
	if (text.para === null) { throw new Error("this Text has no paragraph label"); }
	return text.para as NodeRef;
}

function runsOf(vh: VoidHost, label: NodeRef): Vec<TextRun> {
	return labelTexts[vh.scene.payloads[label.id.index]].runs;
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
	assert paragraph(view.children[0]).textStyle().font === second, "text label font";
	assert labelOf(view.children[1]).textStyle().font === second, "text field label font";
}

test "a Text's strings draw in order as one paragraph label, and a string change rewrites it" {
	const vh = host();
	const [n, setN] = createSignal(7);
	render(element(<View style={{ width: 200, height: 20 }}><Text>Count: {n().toString()}</Text></View>), vh.host, vh.root);
	vh.layout(200.0, 20.0);
	const text = top(vh).children[0];
	assert paragraph(text).text() === "Count: 7", "one label holds both strings: \"" + paragraph(text).text() + "\"";
	assert text.ref.numChildren() === 1, "the paragraph label is the Text's only scene child, got " + text.ref.numChildren().toString();
	assert text.children.length === 0, "the strings are spans, not host nodes";
	setN(8);
	assert paragraph(text).text() === "Count: 8", "the changed string reaches the paragraph: \"" + paragraph(text).text() + "\"";
	assert runsOf(vh, paragraph(text)).length === 0, "an unstyled paragraph draws without runs";
}

test "a text field keeps its text color when it has a background" {
	const vh = host();
	render(element(<TextInput style={{ backgroundColor: "#313244", color: "#ffffff" }} />), vh.host, vh.root);
	const f = top(vh);
	assert Math.abs(f.ref.paint().color.r - 0x31 / 255.0) < 0.001 && Math.abs(f.ref.paint().color.b - 0x44 / 255.0) < 0.001, "the field paints the background";
	assert labelOf(f).paint().color.r === 1.0, "the label keeps the text color, got r=" + labelOf(f).paint().color.r.toString();
}

test "a Text's color and fontSize reach its paragraph, and follow a style change" {
	const vh = host();
	const [red, setRed] = createSignal(true);
	const [n, setN] = createSignal(7);
	render(element(<View><Text style={{ color: red() ? "#ff0000" : "#00ff00", fontSize: 20 }}>Count: {n().toString()}</Text></View>), vh.host, vh.root);
	const label = paragraph(top(vh).children[0]);
	assert label.paint().color.r === 1.0 && label.paint().color.g === 0.0, "the paragraph is red";
	assert label.textStyle().size === 20.0, "the paragraph is 20, got " + label.textStyle().size.toString();
	setRed(false);
	assert label.paint().color.g === 1.0 && label.paint().color.r === 0.0, "the paragraph turned green";
}

test "a nested Text is a run of the outer Text's paragraph, which wraps at the Text's laid width" {
	const vh = host();
	render(element(<View style={{ width: 120 }}><Text>Hello there <Text style={{ color: "#ff0000" }}>big red words</Text> and a long tail that wraps</Text></View>), vh.host, vh.root);
	vh.layout(120.0, 300.0);
	const text = top(vh).children[0];
	const label = paragraph(text);
	assert label.text() === "Hello there big red words and a long tail that wraps", "one paragraph: \"" + label.text() + "\"";
	assert text.ref.numChildren() === 1, "no scene node for the nested Text, got " + text.ref.numChildren().toString();
	const runs = runsOf(vh, label);
	assert runs.length === 3 && runs[0].len === 12 && runs[1].len === 13 && runs[2].len === 27, "three runs over the pieces, got " + runs.length.toString();
	assert runs[0].color.g === 1.0 && runs[1].color.r === 1.0 && runs[1].color.g === 0.0 && runs[2].color.g === 1.0, "only the nested run is red";
	assert label.paint().color.g === 1.0, "a styled paragraph draws its runs untinted";
	assert label.textWidth() <= 120.0, "the paragraph wraps inside 120, got " + label.textWidth().toString();
	assert label.lineBoxAt(label.text().length as int32 - 1).top > 0.0, "the tail lands on a later line";
}

test "a nested Text's colour and content changes reach its run, and the runs go when the last styled span does" {
	const vh = host();
	const [hot, setHot] = createSignal(true);
	const [word, setWord] = createSignal("red");
	const [shown, setShown] = createSignal(true);
	render(element(<View style={{ width: 300 }}><Text>a <Show when={shown()}><Text style={{ color: hot() ? "#ff0000" : "#0000ff", textDecorationLine: "underline" }}>{word()}</Text></Show> b</Text></View>), vh.host, vh.root);
	const label = paragraph(top(vh).children[0]);
	assert label.text() === "a red b", "start: \"" + label.text() + "\"";
	assert runsOf(vh, label)[1].underline.r === 1.0, "the underline takes the run colour";
	setHot(false);
	assert runsOf(vh, label)[1].color.b === 1.0 && runsOf(vh, label)[1].color.r === 0.0, "the run turned blue";
	setWord("blue");
	assert label.text() === "a blue b" && runsOf(vh, label)[1].len === 4, "the run follows its string: \"" + label.text() + "\"";
	setShown(false);
	assert label.text() === "a  b", "the span left: \"" + label.text() + "\"";
	assert runsOf(vh, label).length === 0, "no styled span left, so no runs";
}

test "cellWidth puts every grapheme of the paragraph on a fixed cell, and follows a change" {
	const vh = host();
	const [cell, setCell] = createSignal(10);
	render(element(<View style={{ width: 300 }}><Text cellWidth={cell()}>ab<Text style={{ color: "#ff0000" }}>cd</Text></Text></View>), vh.host, vh.root);
	vh.layout(300.0, 100.0);
	const label = paragraph(top(vh).children[0]);
	label.textWidth();
	assert label.xForIndex(1) === 10.0 && label.xForIndex(3) === 30.0, "cells of 10: " + label.xForIndex(1).toString() + ", " + label.xForIndex(3).toString();
	setCell(7);
	label.textWidth();
	assert label.xForIndex(2) === 14.0, "cells of 7: " + label.xForIndex(2).toString();
}

test "spans draw as one paragraph label on the Void host, with no node per span" {
	const vh = host();
	const red: Style = { color: "#ff0000", textDecorationLine: "underline" };
	const [spans, setSpans] = createSignal<TextSpan[]>([{ text: "error", style: red }, { text: ": not found" }]);
	render(element(<View style={{ width: 300 }}><Text spans={spans()} /></View>), vh.host, vh.root);
	const text = top(vh).children[0];
	const label = paragraph(text);
	assert label.text() === "error: not found", "one paragraph: \"" + label.text() + "\"";
	assert text.children.length === 0 && text.ref.numChildren() === 1, "no host node per span";
	const runs = runsOf(vh, label);
	assert runs.length === 2 && runs[0].len === 5 && runs[1].len === 11, "a run per span";
	assert runs[0].color.r === 1.0 && runs[0].color.g === 0.0 && runs[0].underline.r === 1.0 && runs[1].color.g === 1.0, "only the first span is red and underlined";
	setSpans([{ text: "warning", style: { color: "#0000ff" } }, { text: ": slow" }]);
	assert label.text() === "warning: slow" && runsOf(vh, label)[0].len === 7 && runsOf(vh, label)[0].color.b === 1.0, "a new line of spans: \"" + label.text() + "\"";
	setSpans([{ text: "plain" }]);
	assert label.text() === "plain" && runsOf(vh, label).length === 0, "unstyled spans draw without runs";
}

test "a press over a nested Text's run fires that run's onPress, and the plain text around it does not" {
	const vh = host();
	let link = 0;
	let outer = 0;
	render(element(<View style={{ width: 400 }}><Text style={{ height: 30 }} onPress={(): void => { outer += 1; }}>plain <Text onPress={(): void => { link += 1; }}>link</Text> tail</Text></View>), vh.host, vh.root);
	vh.layout(400.0, 100.0);
	const label = paragraph(top(vh).children[0]);
	label.textWidth();
	const at = (index: int32): Vec2 => label.localToGlobal(vec2(label.xForIndex(index) + 1.0, label.lineBoxAt(index).top + 2.0));
	const inLink = at(7);
	vh.clickAt(inLink.x, inLink.y);
	assert link === 1 && outer === 0, "a press inside \"link\" is the run's: link=" + link.toString() + " outer=" + outer.toString();
	const inPlain = at(1);
	vh.clickAt(inPlain.x, inPlain.y);
	assert link === 1 && outer === 1, "a press on the plain text is the Text's: link=" + link.toString() + " outer=" + outer.toString();
	const pastEnd = label.localToGlobal(vec2(label.textWidth() + 40.0, label.lineBoxAt(0).top + 2.0));
	vh.clickAt(pastEnd.x, pastEnd.y);
	assert link === 1, "past the line's end there is no run";
}

test "what a Void paragraph cannot draw yet is refused by name" {
	let message = "";
	const a = host();
	try {
		render(element(<Text>a <View style={{ width: 4, height: 4 }} /></Text>), a.host, a.root);
	} catch (e) { message = e.message; }
	assert message.indexOf("inline view") >= 0, "a View inside a Text: " + message;
	message = "";
	const c = host();
	try {
		render(element(<Text style={{ fontSize: 14 }}>a <Text style={{ fontSize: 20 }}>b</Text></Text>), c.host, c.root);
	} catch (e) { message = e.message; }
	assert message.indexOf("one size") >= 0, "a nested fontSize: " + message;
	message = "";
	const d = host();
	try {
		render(element(<Text>a <Text cellWidth={8}>b</Text></Text>), d.host, d.root);
	} catch (e) { message = e.message; }
	assert message.indexOf("outermost Text") >= 0, "cellWidth on a nested Text: " + message;
	message = "";
	const e = host();
	try {
		render(element(<Text>a <Text spans={[{ text: "b" }]} /></Text>), e.host, e.root);
	} catch (err) { message = err.message; }
	assert message.indexOf("spans belong on the outermost Text") >= 0, "spans on a nested Text: " + message;
}

test "a key event carries the physical detail the window supplied, to the focused node and its parents" {
	const vh = host();
	let seen = "";
	let inner: VoidNode | null = null;
	render(element(
		<View onKeyDown={(e: NeonEvent): void => { seen = seen + "outer "; }}>
			<View ref={(n: HostNode): void => { inner = n as VoidNode; }}
				onKeyDown={(e: NeonEvent): void => { seen = seen + `${e.scancode} ${e.mods} ${e.consumedMods} ${e.unshifted} ${e.text} `; }} />
		</View>
	), vh.host, vh.root);
	vh.focus(inner);
	const e = key("A");
	e.scancode = 30;
	e.mods = 1;
	e.consumedMods = 1;
	e.unshifted = 97;
	e.text = "A";
	vh.keyDown(e);
	assert seen === "30 1 1 97 A outer ", "seen: " + seen;
}

test "a focused View hears committed and composing text, and a TextInput keeps its own path" {
	const vh = host();
	let log = "";
	let plain: VoidNode | null = null;
	render(element(
		<View style={{ width: 300, height: 100 }}
			onTextInput={(e: NeonEvent): void => { log = log + "outer:" + e.text + " "; }}>
			<View style={{ width: 100, height: 20 }}
				ref={(n: HostNode): void => { plain = n as VoidNode; }}
				onTextInput={(e: NeonEvent): void => { log = log + "text:" + e.text + " "; }}
				onPreedit={(e: NeonEvent): void => { log = log + "pre:" + e.text + "@" + e.cursor.toString() + " "; }} />
			<TextInput style={{ width: 100, height: 20 }} />
		</View>
	), vh.host, vh.root);
	vh.layout(300.0, 100.0);
	vh.focus(plain);
	vh.composeText("ni", 2);
	vh.textInput("你");
	vh.commitText("typed");
	assert log === "pre:ni@2 text:你 outer:你 ", "a typed key's text is not a second text event: " + log;
	vh.focus(top(vh).children[1]);
	vh.textInput("é");
	assert log === "pre:ni@2 text:你 outer:你 ", "the TextInput took the text, nothing bubbled: " + log;
	assert labelOf(top(vh).children[1]).text() === "é", "the field shows the commit";
}

function seen(who: string, sink: string[]): (e: NeonEvent) => void {
	return (e: NeonEvent): void => {
		sink.push(`${who}:${e.type}@${e.locationX},${e.locationY}/${e.x},${e.y} b${e.button} ${e.pressed ? "down" : "up"} d${e.deltaX},${e.deltaY}`);
	};
}

test "pointer events go to the deepest node under the pointer, bubble, and carry coordinates relative to that target" {
	const vh = host();
	const log: string[] = [];
	render(element(
		<View style={{ width: 300, height: 100, paddingLeft: 20, paddingTop: 20 }}
			onPointerDown={seen("outer", log)} onPointerMove={seen("outer", log)} onPointerUp={seen("outer", log)} onWheel={seen("outer", log)}>
			<View style={{ width: 100, height: 50 }}
				onPointerDown={seen("inner", log)} onPointerMove={seen("inner", log)} onPointerUp={seen("inner", log)} onWheel={seen("inner", log)} />
		</View>
	), vh.host, vh.root);
	vh.layout(300.0, 100.0);
	vh.pointerDown(30.0, 35.0, 0);
	assert log.join("|") === "inner:pointerdown@10,15/30,35 b0 down d0,0|outer:pointerdown@10,15/30,35 b0 down d0,0", "down: " + log.join("|");
	log.length = 0;
	vh.pointerMove(31.0, 36.0, 0, true);
	vh.pointerUp(31.0, 36.0, 0);
	vh.wheel(31.0, 36.0, 0.0, -3.0);
	assert log.join("|") === "inner:pointermove@11,16/31,36 b0 down d0,0|outer:pointermove@11,16/31,36 b0 down d0,0"
		+ "|inner:pointerup@11,16/31,36 b0 up d0,0|outer:pointerup@11,16/31,36 b0 up d0,0"
		+ "|inner:wheel@11,16/31,36 b0 up d0,-3|outer:wheel@11,16/31,36 b0 up d0,-3", "move, up, wheel: " + log.join("|");
	log.length = 0;
	vh.pointerMove(200.0, 90.0, 0, false);
	assert log.join("|") === "outer:pointermove@200,90/200,90 b0 up d0,0", "outside the inner node only the outer hears: " + log.join("|");
	log.length = 0;
	vh.pointerMove(290.0, 190.0, 0, false);
	assert log.length === 0, "outside everything nothing is heard: " + log.join("|");
}

function pressedWith(mode: string, x: float32, y: float32): string {
	const vh = host();
	const log: string[] = [];
	render(element(
		<View style={{ width: 200, height: 100, pointerEvents: mode }} onPointerDown={seen("outer", log)}>
			<View style={{ width: 100, height: 50 }} onPointerDown={seen("inner", log)} />
		</View>
	), vh.host, vh.root);
	vh.layout(200.0, 100.0);
	vh.pointerDown(x, y, 1);
	return log.join("|");
}

test "pointerEvents auto, none, box-none and box-only choose the target" {
	assert pressedWith("auto", 10.0, 10.0) === "inner:pointerdown@10,10/10,10 b1 down d0,0|outer:pointerdown@10,10/10,10 b1 down d0,0", "auto: " + pressedWith("auto", 10.0, 10.0);
	assert pressedWith("none", 10.0, 10.0) === "", "none hides the node and its subtree: " + pressedWith("none", 10.0, 10.0);
	assert pressedWith("box-none", 10.0, 10.0) === "inner:pointerdown@10,10/10,10 b1 down d0,0|outer:pointerdown@10,10/10,10 b1 down d0,0", "box-none: the child is the target, the event still bubbles: " + pressedWith("box-none", 10.0, 10.0);
	assert pressedWith("box-none", 150.0, 80.0) === "", "box-none: the box itself is no target: " + pressedWith("box-none", 150.0, 80.0);
	assert pressedWith("box-only", 10.0, 10.0) === "outer:pointerdown@10,10/10,10 b1 down d0,0", "box-only: the box is the target, its child inert: " + pressedWith("box-only", 10.0, 10.0);
	assert pressedWith("box-only", 150.0, 80.0) === "outer:pointerdown@150,80/150,80 b1 down d0,0", "box-only outside the child: " + pressedWith("box-only", 150.0, 80.0);
}

test "a box-only parent takes the focus from its focusable child" {
	const vh = host();
	render(element(
		<View style={{ width: 200, height: 100, pointerEvents: "box-only" }} focusable>
			<View style={{ width: 100, height: 50 }} focusable />
		</View>
	), vh.host, vh.root);
	vh.layout(200.0, 100.0);
	vh.clickAt(10.0, 10.0);
	assert vh.focused() === top(vh), "the box, not its child, took the press";
}

test "pressing a component with a pointer, wheel or text handler, or focusable, focuses it, and onPress still fires" {
	const vh = host();
	let pressed = 0;
	render(element(
		<View style={{ width: 400, height: 50, flexDirection: "row" }}>
			<View style={{ width: 100, height: 50 }} onPointerDown={(e: NeonEvent): void => {}} />
			<View style={{ width: 100, height: 50 }} onWheel={(e: NeonEvent): void => {}} />
			<View style={{ width: 100, height: 50 }} focusable />
			<Pressable style={{ width: 100, height: 50 }} onPress={(): void => { pressed = pressed + 1; }} />
		</View>
	), vh.host, vh.root);
	vh.layout(400.0, 50.0);
	const row = top(vh);
	vh.clickAt(10.0, 10.0);
	assert vh.focused() === row.children[0], "onPointerDown makes it focusable";
	vh.clickAt(110.0, 10.0);
	assert vh.focused() === row.children[1], "onWheel makes it focusable";
	vh.clickAt(210.0, 10.0);
	assert vh.focused() === row.children[2], "the focusable prop makes it focusable";
	vh.clickAt(310.0, 10.0);
	assert pressed === 1, "onPress fired once";
	assert vh.focused() === null, "a pressable with no key handler takes no focus";
}

test "a focused component places the IME rect with its imeRect prop, in its own coordinates" {
	const vh = host();
	const [at, setAt] = createSignal(3);
	let woke = 0;
	let node: VoidNode | null = null;
	render(element(
		<View style={{ width: 300, height: 100, paddingLeft: 20, paddingTop: 30 }}>
			<View style={{ width: 200, height: 24 }} ref={(n: HostNode): void => { node = n as VoidNode; }}
				imeRect={{ x: at(), y: 4, width: 8, height: 16 }} focusable />
		</View>
	), vh.host, vh.root);
	vh.layout(300.0, 100.0);
	assert vh.imeRect() === null, "no focus, no rect";
	settle(vh);
	vh.onDirty((): void => { woke = woke + 1; });
	vh.focus(node);
	let r = vh.imeRect() as CaretRect;
	assert r.x === 23.0 && r.y === 34.0 && r.w === 8.0 && r.h === 16.0, `rect ${r.x},${r.y} ${r.w}x${r.h}`;
	assert woke === 1, "focusing it asks for a frame so Ion hears the rect: " + woke.toString();
	setAt(10);
	r = vh.imeRect() as CaretRect;
	assert r.x === 30.0, "the rect follows the signal: " + r.x.toString();
	assert woke === 2, "moving it asks for a frame: " + woke.toString();
}

interface Line {
	id: number;
	text: string;
}

function lineRow(item: Accessor<Line>): NeonNode {
	return element(<Text>{item().text}</Text>);
}

function shapeAll(n: VoidNode): void {
	if (n.para !== null) {
		(n.para as NodeRef).textWidth();
		return;
	}
	if (n.ref.kind() === DrawKind.Label) { n.ref.textWidth(); }
	for (const c of n.children) { shapeAll(c); }
}

// Labels whose text or style changed since the last paint, or whose shaped layout is out of date.
function textTouched(vh: VoidHost, n: VoidNode): number {
	if (n.para !== null) {
		const row = (n.para as NodeRef).id.index;
		return labelTexts[vh.scene.payloads[row]].stale || vh.scene.changed[row].has(Changed.Text) ? 1 : 0;
	}
	let count: number = 0;
	if (n.ref.kind() === DrawKind.Label) {
		const row = n.ref.id.index;
		if (labelTexts[vh.scene.payloads[row]].stale || vh.scene.changed[row].has(Changed.Text)) { count = 1; }
	}
	for (const c of n.children) { count = count + textTouched(vh, c); }
	return count;
}

test "a ForList scroll moves 59 of 60 rows without reshaping or rebuilding them" {
	const vh = host();
	const items: Line[] = [];
	for (let i = 0; i < 60; i += 1) { items.push({ id: i, text: "row " + i.toString() }); }
	const rows = createList<Line>(items);
	render(element(<View style={{ width: 300, height: 1200 }}>{ForList<Line>({ each: rows, children: lineRow })}</View>), vh.host, vh.root);
	vh.layout(300.0, 1200.0);
	shapeAll(vh.root as VoidNode);
	settle(vh);
	const root = vh.root as VoidNode;
	const before = top(vh).children.slice(0);
	assert before.length === 61 && textTouched(vh, root) === 0, "60 rows and the region anchor, all shaped and painted: " + textTouched(vh, root).toString();
	rows.remove(0);
	rows.push({ id: 60, text: "row 60" });
	assert textTouched(vh, root) === 1, "after the ops only the pushed row's label is new: " + textTouched(vh, root).toString();
	vh.layout(300.0, 1200.0);
	const after = top(vh).children;
	assert after.length === 61 && after[60] === before[60], "still 60 rows before the same anchor";
	for (let i = 0; i < 59; i += 1) {
		assert after[i] === before[i + 1], "row " + (i + 1).toString() + " kept its node";
	}
	assert textTouched(vh, root) === 1, "a layout pass touched no kept row's text: " + textTouched(vh, root).toString();
	assert after[0].ref.local().y === 0.0, "the kept row 1 now sits at the top, y=" + after[0].ref.local().y.toString();
}
