import { createVoidHostWith, VoidHost, VoidNode } from "../../src/platform/void/host";
import { Scene2D, content } from "../../../void/src/void2d/node";
import { create } from "../../../void/src/void2d/scene";
import { rgba } from "../../../void/src/void2d/types";
import { FontId, addFont } from "../../../void/src/void2d/font";
import { TextLayout, Align } from "../../../void/src/void2d/textLayout";
import { createSignal } from "../../src/core/signal";
import { flush } from "../../src/core/runtime";
import { element } from "../../src/macros/ui/element";
import { render } from "../../src/render/host";
import { NeonNode } from "../../src/render/hostTypes";
import { Pressable, Text, View } from "../../src/components/primitives";

function testFont(): FontId {
	const font = addFont("../void/assets/font.ttf");
	if (!font.ok) { throw new Error("the test font ../void/assets/font.ttf did not load"); }
	return font.value;
}

const FONT = testFont();
const LONG = "a sentence long enough to wrap in a narrow column";

function mounted(app: NeonNode, w: float32): VoidHost {
	const vh = createVoidHostWith(Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0)), FONT);
	render(app, vh.host, vh.root);
	vh.layout(w, 400.0);
	return vh;
}

function child(vh: VoidHost, n: VoidNode, i: int32): VoidNode { return vh.tree.childrenOf(n)[i]; }

function oneLine(s: string): float32 {
	const laid = TextLayout.layout(s, { font: FONT, size: 14.0, letterSpacing: 0.0, lineSpacing: 0.0, maxWidth: 0.0, align: Align.Left });
	if (!laid.ok || !(laid.value.height > 0.0)) { throw new Error("the reference layout of one line has no height"); }
	return Math.ceil(laid.value.height) as float32;
}

test "a Text in a column takes the height of its one line" {
	const vh = mounted(element(<View style={{ flexDirection: "column" }}><Text style={{ fontSize: 14 }}>Hello</Text></View>), 480.0);
	const t = child(vh, child(vh, vh.root as VoidNode, 0), 0);
	assert t.ref.content().h === oneLine("Hello"), `one line high, got ${t.ref.content().h}`;
	assert t.ref.content().w === 480.0, `stretched across the column, got ${t.ref.content().w}`;
}

test "a Text in a narrow column wraps and grows a line per wrap" {
	const vh = mounted(element(<View style={{ width: 80 }}><Text style={{ fontSize: 14 }}>{LONG}</Text></View>), 480.0);
	const t = child(vh, child(vh, vh.root as VoidNode, 0), 0);
	assert t.ref.content().h >= 2.0 * oneLine(LONG), `wrapped onto several lines, got ${t.ref.content().h}`;
}

test "a flex-start Pressable wraps its Text instead of shrinking to its padding" {
	const vh = mounted(element(
		<View style={{ flexDirection: "column" }}>
			<Pressable style={{ alignSelf: "flex-start", padding: 14 }}><Text style={{ fontSize: 14 }}>Press me</Text></Pressable>
		</View>
	), 480.0);
	const p = child(vh, child(vh, vh.root as VoidNode, 0), 0);
	const t = child(vh, p, 0);
	assert t.ref.content().w > 0.0 && t.ref.content().w < 480.0, `the Text is as wide as its words, got ${t.ref.content().w}`;
	assert p.ref.content().h === 28.0 + t.ref.content().h, `the Pressable is its Text plus padding, got ${p.ref.content().h}`;
}

test "a Text whose content changes is measured again" {
	const [word, setWord] = createSignal("one");
	const vh = mounted(element(<View style={{ width: 80 }}><Text style={{ fontSize: 14 }}>{word()}</Text></View>), 480.0);
	const t = child(vh, child(vh, vh.root as VoidNode, 0), 0);
	const before = t.ref.content().h;
	setWord(LONG);
	flush();
	vh.layout(480.0, 400.0);
	assert t.ref.content().h > before, `the longer text grows the Text, ${before} then ${t.ref.content().h}`;
}
