import { element } from "../../src/macros/ui/element";
import { render } from "../../src/render/host";
import { View, Text } from "../../src/components/primitives";
import { createVoidHostWith, VoidHost, VoidNode } from "../../src/platform/void/host";
import { Scene2D, NodeRef, textStyle } from "../../../void/src/void2d/node";
import { TextRun } from "../../../void/src/void2d/textLayout";
import { create } from "../../../void/src/void2d/scene";
import { rgba } from "../../../void/src/void2d/types";
import { labelTexts } from "../../../void/src/void2d/labelText";
import { FontId, addFont, registerFace, resolveFont, FontStyle as FaceStyle, SizeAdjust } from "../../../void/src/void2d/font";

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
