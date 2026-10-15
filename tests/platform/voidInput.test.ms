import { createSignal, Accessor } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { render } from "../../src/render/host";
import { NeonEvent, neonEvent } from "../../src/render/event";
import { View, Text, TextInput, Pressable } from "../../src/components/primitives";
import { ForList } from "../../src/macros/ui/flow";
import { createList } from "../../src/core/list";
import { NeonNode } from "../../src/render/node";
import {
	createVoidHostWith, VoidHost, VoidNode, TextEditingValue, editingValue, CaretRect,
} from "../../src/platform/void/host";
import { Scene2D, NodeRef, DrawKind, Changed, text, paint, textStyle, local, getChildAt, clearChanges } from "../../../void/src/void2d/node";
import { create, paint as paintScene, isDirty } from "../../../void/src/void2d/scene";
import { frameEnd } from "../../../void/src/void2d/draw";
import { xForIndex, textWidth } from "../../../void/src/void2d/render";
import { rgba } from "../../../void/src/void2d/types";
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
	const first = line.children[0].ref;
	const second = line.children[1].ref.local().x;
	assert first.text() === "Count: ", "first piece keeps its trailing space: \"" + first.text() + "\"";
	assert second > first.textWidth(), "second piece after the space that ends 'Count: ': " + second.toString() + " against " + first.textWidth().toString();
}

test "a text field keeps its text color when it has a background" {
	const vh = host();
	render(element(<TextInput style={{ backgroundColor: "#313244", color: "#ffffff" }} />), vh.host, vh.root);
	const f = top(vh);
	assert Math.abs(f.ref.paint().color.r - 0x31 / 255.0) < 0.001 && Math.abs(f.ref.paint().color.b - 0x44 / 255.0) < 0.001, "the field paints the background";
	assert labelOf(f).paint().color.r === 1.0, "the label keeps the text color, got r=" + labelOf(f).paint().color.r.toString();
}

test "a Text's color and fontSize reach every text piece inside it, and follow a style change" {
	const vh = host();
	const [red, setRed] = createSignal(true);
	const [n, setN] = createSignal(7);
	render(element(<View><Text style={{ color: red() ? "#ff0000" : "#00ff00", fontSize: 20 }}>Count: {n().toString()}</Text></View>), vh.host, vh.root);
	const line = top(vh).children[0];
	for (const piece of line.children) {
		assert piece.ref.paint().color.r === 1.0 && piece.ref.paint().color.g === 0.0, "piece \"" + piece.ref.text() + "\" is red";
		assert piece.ref.textStyle().size === 20.0, "piece \"" + piece.ref.text() + "\" is 20, got " + piece.ref.textStyle().size.toString();
	}
	setRed(false);
	for (const piece of line.children) {
		assert piece.ref.paint().color.g === 1.0 && piece.ref.paint().color.r === 0.0, "piece \"" + piece.ref.text() + "\" turned green";
	}
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

test "pointer events go to the deepest node under the pointer, bubble, and carry local coordinates" {
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
	assert log.join("|") === "inner:pointerdown@10,15/30,35 b0 down d0,0|outer:pointerdown@30,35/30,35 b0 down d0,0", "down: " + log.join("|");
	log.length = 0;
	vh.pointerMove(31.0, 36.0, 0, true);
	vh.pointerUp(31.0, 36.0, 0);
	vh.wheel(31.0, 36.0, 0.0, -3.0);
	assert log.join("|") === "inner:pointermove@11,16/31,36 b0 down d0,0|outer:pointermove@31,36/31,36 b0 down d0,0"
		+ "|inner:pointerup@11,16/31,36 b0 up d0,0|outer:pointerup@31,36/31,36 b0 up d0,0"
		+ "|inner:wheel@11,16/31,36 b0 up d0,-3|outer:wheel@31,36/31,36 b0 up d0,-3", "move, up, wheel: " + log.join("|");
	log.length = 0;
	vh.pointerMove(200.0, 90.0, 0, false);
	assert log.join("|") === "outer:pointermove@200,90/200,90 b0 up d0,0", "outside the inner node only the outer hears: " + log.join("|");
	log.length = 0;
	vh.pointerMove(290.0, 190.0, 0, false);
	assert log.length === 0, "outside everything nothing is heard: " + log.join("|");
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
	if (n.ref.kind() === DrawKind.Label) { n.ref.textWidth(); }
	for (const c of n.children) { shapeAll(c); }
}

// Labels whose text or style changed since the last paint, or whose shaped layout is out of date.
function textTouched(vh: VoidHost, n: VoidNode): number {
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
