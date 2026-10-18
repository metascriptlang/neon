import { element } from "../../src/macros/ui/element";
import { render } from "../../src/render/host";
import { View, ViewHandle, Text } from "../../src/components/primitives";
import { createVoidHostWith, familyFont, VoidHost, VoidNode } from "../../src/platform/void/host";
import { Scene2D, NodeRef, textStyle } from "../../../void/src/void2d/node";
import { TextRun, TextLayout, calcTextWidth } from "../../../void/src/void2d/textLayout";
import { create } from "../../../void/src/void2d/scene";
import { rgba } from "../../../void/src/void2d/types";
import { labelTexts } from "../../../void/src/void2d/labelText";
import { FontId, addFont, registerFace, resolveFont, faceForCodepoint, fontFace, FontStyle as FaceStyle, SizeAdjust } from "../../../void/src/void2d/font";

const FONT_PATH = "../void/assets/font.ttf";

function loadedFont(): FontId {
	const r = addFont(FONT_PATH);
	if (!r.ok) { throw new Error("the test font did not load from " + FONT_PATH + "; run from the Neon checkout root beside ../void"); }
	return r.value;
}

function host(): VoidHost {
	return createVoidHostWith(Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0)), loadedFont());
}

function top(vh: VoidHost): VoidNode {
	return (vh.root as VoidNode).children[0];
}

function paragraph(text: VoidNode): NodeRef {
	if (text.para === null) { throw new Error("this Text has no paragraph label"); }
	return text.para as NodeRef;
}

function runsOf(vh: VoidHost, label: NodeRef): Vec<TextRun> {
	return labelTexts[vh.scene.payloads[label.id.index]].runs;
}

const PROBE_FAMILY = "Neon Probe Sans";

function registerProbeFamilyWithoutItalicFaces(): void {
	registerFace(FONT_PATH, PROBE_FAMILY, 400, FaceStyle.Normal);
	registerFace(FONT_PATH, PROBE_FAMILY, 700, FaceStyle.Normal);
}

function probeFace(weight: int32, italic: boolean): FontId {
	const got = resolveFont({
		family: PROBE_FAMILY, weight, style: italic ? FaceStyle.Italic : FaceStyle.Normal, features: [], fallbacks: [], sizeAdjust: SizeAdjust.None,
	});
	if (!got.ok) { throw new Error("the probe family did not resolve: " + got.error.toString()); }
	return got.value;
}

test "a span's fontWeight and fontStyle pick its face in the Text's family, and a wavy underline reaches its run" {
	registerProbeFamilyWithoutItalicFaces();
	const vh = host();
	render(element(<View style={{ width: 300 }}><Text style={{ fontFamily: PROBE_FAMILY }} spans={[
		{ text: "r " },
		{ text: "b ", style: { fontWeight: "bold" } },
		{ text: "i ", style: { fontStyle: "italic" } },
		{ text: "bi ", style: { fontWeight: "700", fontStyle: "italic" } },
		{ text: "w", style: { textDecorationLine: "underline", textDecorationStyle: "wavy" } },
	]} /></View>), vh.host, vh.root);
	const label = paragraph(top(vh).children[0]);
	const runs = runsOf(vh, label);
	const regular = probeFace(400, false);
	assert label.textStyle().font === regular, "the paragraph takes the family's regular face";
	assert runs[0].font === regular && runs[4].font === regular, "unstyled weight stays regular";
	assert runs[1].font === probeFace(700, false) && runs[1].font !== regular, "bold picks the registered bold face";
	assert runs[2].font === probeFace(400, true) && runs[2].font !== regular, "italic is synthesised from the regular face";
	assert runs[3].font === probeFace(700, true) && runs[3].font !== runs[1].font && runs[3].font !== runs[2].font, "bold italic is its own face";
	assert runs[4].wavy && runs[4].underline.a > 0.0 && !runs[1].wavy, "only the wavy span has a wavy underline";
}

test "a plain Text's weight comes from the host's default family, and its underline draws as one run" {
	registerProbeFamilyWithoutItalicFaces();
	const vh = createVoidHostWith(Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0)), loadedFont(), PROBE_FAMILY);
	render(element(<View style={{ width: 300 }}><Text style={{ fontWeight: "bold" }}>heavy</Text><Text style={{ textDecorationLine: "underline", textDecorationStyle: "wavy" }}>curly</Text></View>), vh.host, vh.root);
	const view = top(vh);
	assert paragraph(view.children[0]).textStyle().font === probeFace(700, false), "bold from the default family";
	const runs = runsOf(vh, paragraph(view.children[1]));
	assert runs.length === 1 && runs[0].wavy && runs[0].underline.a > 0.0, "a decorated Text draws its underline as one run";
}

test "a face the host cannot find, or a line it cannot draw, is refused by name" {
	let message = "";
	const a = host();
	try {
		render(element(<Text style={{ fontFamily: "Nowhere Grotesk" }}>x</Text>), a.host, a.root);
	} catch (e) { message = e.message; }
	assert message.indexOf(`font family "Nowhere Grotesk" has no registered face`) >= 0, "unknown family: " + message;
	message = "";
	const b = host();
	try {
		render(element(<Text>a <Text style={{ fontWeight: "bold" }}>b</Text></Text>), b.host, b.root);
	} catch (e) { message = e.message; }
	assert message.indexOf("names no fontFamily, and this host has no default family") >= 0, "bold with no family: " + message;
	message = "";
	const c = host();
	try {
		render(element(<Text style={{ textDecorationLine: "underline", textDecorationStyle: "dotted" }}>x</Text>), c.host, c.root);
	} catch (e) { message = e.message; }
	assert message.indexOf(`textDecorationStyle "dotted" is not drawn on the Void host yet`) >= 0, "dotted: " + message;
}

test "a View's handle measures a line with the face and size its Text draws with" {
	registerProbeFamilyWithoutItalicFaces();
	const vh = host();
	let frame: ViewHandle | null = null;
	render(element(<View ref={(h: ViewHandle): void => { frame = h; }} style={{ width: 300 }}>
		<Text style={{ fontFamily: PROBE_FAMILY, fontSize: 14 }}>MMMM</Text>
		<Text style={{ fontFamily: PROBE_FAMILY, fontSize: 14, fontWeight: "bold" }}>MMMM</Text>
	</View>), vh.host, vh.root);
	const regular = (frame as ViewHandle).measureText("MMMM", { fontFamily: PROBE_FAMILY, fontSize: 14 });
	const bold = (frame as ViewHandle).measureText("MMMM", { fontFamily: PROBE_FAMILY, fontSize: 14, fontWeight: "bold" });
	const drawn = paragraph(top(vh).children[0]).textStyle();
	const drawnBold = paragraph(top(vh).children[1]).textStyle();
	const width = calcTextWidth("MMMM", drawn);
	const boldWidth = calcTextWidth("MMMM", drawnBold);
	assert width.ok && regular.width === width.value as number, `regular width ${regular.width} is the drawn label's`;
	assert boldWidth.ok && bold.width === boldWidth.value as number, `bold width ${bold.width} is the drawn bold label's`;
	const laid = TextLayout.layout("MMMM", drawn);
	assert laid.ok && regular.height === laid.value.lineHeight as number && regular.ascender === laid.value.ascent as number
		&& regular.descender === laid.value.descent as number, "height, ascender and descender are the drawn line's";
	const one = (frame as ViewHandle).measureText("M", { fontFamily: PROBE_FAMILY, fontSize: 14 });
	const twice = (frame as ViewHandle).measureText("M", { fontFamily: PROBE_FAMILY, fontSize: 28 });
	assert one.width > 0 && twice.width > one.width && twice.height > one.height, "a larger size measures larger";
}

test "measuring a family the host cannot find is refused by name" {
	const vh = host();
	let frame: ViewHandle | null = null;
	render(element(<View ref={(h: ViewHandle): void => { frame = h; }} />), vh.host, vh.root);
	let message = "";
	try {
		(frame as ViewHandle).measureText("x", { fontFamily: "Nowhere Grotesk" });
	} catch (e) { message = e.message; }
	assert message.indexOf(`font family "Nowhere Grotesk" has no registered face`) >= 0, "unknown family: " + message;
}

test "a span's textDecorationColor colours its underline and line-through, not its text" {
	const vh = host();
	render(element(<View style={{ width: 300 }}><Text style={{ color: "#ffffff" }} spans={[
		{ text: "spell ", style: { textDecorationLine: "underline", textDecorationStyle: "wavy", textDecorationColor: "#ff5050" } },
		{ text: "gone ", style: { textDecorationLine: "line-through", textDecorationColor: "#00ff00" } },
		{ text: "plain", style: { textDecorationLine: "underline" } },
	]} /></View>), vh.host, vh.root);
	const runs = runsOf(vh, paragraph(top(vh).children[0]));
	assert runs[0].wavy && runs[0].underline.r > 0.99 && runs[0].underline.g < 0.32 && runs[0].color.g > 0.99, "red wavy underline under white text";
	assert runs[1].strikethrough.g > 0.99 && runs[1].strikethrough.r < 0.01 && runs[1].underline.a === 0.0, "green line-through";
	assert runs[2].underline.r > 0.99 && runs[2].underline.g > 0.99, "no decoration colour keeps the text colour";
}

const CJK_FAMILY = "Probe CJK";
const HAN = 0x4E2D;

function registerCjk(): void {
	registerFace("../void/tests/fonts/NotoSansSC-subset.ttf", CJK_FAMILY, 400, FaceStyle.Normal);
}

function drawsFromFallback(text: VoidNode, codepoint: int32): boolean {
	const font = paragraph(text).textStyle().font;
	return faceForCodepoint(font, codepoint) !== fontFace(font);
}

test "a fontFamily list draws a character its first family lacks in the next family that has it" {
	registerProbeFamilyWithoutItalicFaces();
	registerCjk();
	const vh = host();
	render(element(<View style={{ width: 300 }}>
		<Text style={{ fontFamily: `${PROBE_FAMILY}, "${CJK_FAMILY}"` }}>a中</Text>
		<Text style={{ fontFamily: PROBE_FAMILY }}>a中</Text>
		<Text style={{ fontSize: 14 }} spans={[{ text: "b" }, { text: "中", style: { fontFamily: `${PROBE_FAMILY}, ${CJK_FAMILY}` } }]} />
	</View>), vh.host, vh.root);
	const view = top(vh);
	assert drawsFromFallback(view.children[0], HAN) && !drawsFromFallback(view.children[0], 0x61), "the hanzi comes from the CJK family, the latin from the first";
	assert !drawsFromFallback(view.children[1], HAN), "one family has no fallback to draw it from";
	const runs = runsOf(vh, paragraph(view.children[2]));
	assert faceForCodepoint(runs[1].font, HAN) !== fontFace(runs[1].font), "a span's family list falls back too";
}

test "the host's default family list reaches a Text that names none, in every weight" {
	registerProbeFamilyWithoutItalicFaces();
	registerCjk();
	const list = `${PROBE_FAMILY}, ${CJK_FAMILY}`;
	const plain = familyFont(list, 400, false);
	assert plain.ok, "the default list resolves";
	const vh = createVoidHostWith(Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0)), plain.value, list);
	render(element(<View style={{ width: 300 }}><Text>中</Text><Text style={{ fontWeight: "bold" }}>中</Text></View>), vh.host, vh.root);
	const view = top(vh);
	assert paragraph(view.children[0]).textStyle().font === plain.value && drawsFromFallback(view.children[0], HAN), "a plain Text takes the default list";
	assert paragraph(view.children[1]).textStyle().font !== probeFace(700, false), "bold resolves the list, not the first family alone";
	assert drawsFromFallback(view.children[1], HAN), "a bold Text falls back through the default list";
}

test "a fallback family the host cannot find, or a family list it cannot read, is refused by name" {
	registerProbeFamilyWithoutItalicFaces();
	let message = "";
	const a = host();
	try {
		render(element(<Text style={{ fontFamily: `${PROBE_FAMILY}, Nowhere Grotesk` }}>x</Text>), a.host, a.root);
	} catch (e) { message = e.message; }
	assert message.indexOf(`a fallback family in fontFamily "${PROBE_FAMILY}, Nowhere Grotesk" has no registered face`) >= 0, "missing fallback: " + message;
	message = "";
	const b = host();
	try {
		render(element(<Text style={{ fontFamily: `${PROBE_FAMILY}, "Probe CJK` }}>x</Text>), b.host, b.root);
	} catch (e) { message = e.message; }
	assert message.indexOf("has an unclosed quote") >= 0, "unclosed quote: " + message;
	message = "";
	const c = host();
	try {
		render(element(<Text style={{ fontFamily: `${PROBE_FAMILY},, ${CJK_FAMILY}` }}>x</Text>), c.host, c.root);
	} catch (e) { message = e.message; }
	assert message.indexOf("names an empty family") >= 0, "empty name: " + message;
}
