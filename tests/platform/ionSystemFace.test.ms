import { element } from "../../src/macros/ui/element";
import { render } from "../../src/render/host";
import { Text } from "../../src/components/primitives";
import { createVoidHostWith, VoidNode } from "../../src/platform/void/host";
import { systemFace } from "../../src/platform/ion/systemFace";
import { Scene2D, NodeRef } from "../../../void/src/void2d/node";
import { create } from "../../../void/src/void2d/scene";
import { rgba } from "../../../void/src/void2d/types";
import { addFont, setFaceResolver, faceForCodepoint, fontFace, FontStyle, Presentation } from "../../../void/src/void2d/font";

const PLAY = 0x23F5;
const RECORD = 0x23FA;

function drawsFromFallback(text: VoidNode, codepoint: int32): boolean {
	if (text.para === null) { throw new Error("this Text has no paragraph label"); }
	const font = (text.para as NodeRef).textStyle().font;
	return faceForCodepoint(font, codepoint) !== fontFace(font);
}

test "Ion's system lookup answers Void with the face that draws the codepoint, in text or emoji presentation" {
	const text = systemFace({ codepoint: RECORD, presentation: Presentation.Text, weight: 400, style: FontStyle.Normal });
	assert text.length === 1 && text[0].path.endsWith("/STIXTwoMath.otf") && text[0].index === 0, `text presentation: ${text.length}`;
	const emoji = systemFace({ codepoint: RECORD, presentation: Presentation.Emoji, weight: 400, style: FontStyle.Normal });
	assert emoji.length === 1 && emoji[0].path.endsWith("/Apple Color Emoji.ttc"), `emoji presentation: ${emoji.length}`;
	const cjk = systemFace({ codepoint: 0x4F60, presentation: Presentation.Text, weight: 400, style: FontStyle.Normal });
	assert cjk.length === 1 && cjk[0].path.endsWith(".ttc") && !cjk[0].path.endsWith("/PingFangUI.ttc"), `cjk: ${cjk.length}`;
	assert systemFace({ codepoint: 0x0378, presentation: Presentation.Text, weight: 400, style: FontStyle.Normal }).length === 0, "an unassigned codepoint has no face";
}

test "a Text draws a codepoint its font lacks from the system face the resolver finds" {
	const font = addFont("../void/assets/font.ttf");
	if (!font.ok) { throw new Error("the test font did not load; run from the Neon checkout root beside ../void"); }
	setFaceResolver(null);
	const bare = createVoidHostWith(Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0)), font.value);
	render(element(<Text>{"⏵⏺"}</Text>), bare.host, bare.root);
	assert !drawsFromFallback((bare.root as VoidNode).children[0], PLAY), "with no resolver the glyph stays in the primary face";
	setFaceResolver(systemFace);
	const vh = createVoidHostWith(Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0)), font.value);
	render(element(<Text>{"⏵⏺"}</Text>), vh.host, vh.root);
	const text = (vh.root as VoidNode).children[0];
	assert drawsFromFallback(text, PLAY) && drawsFromFallback(text, RECORD), "both glyphs come from a system face";
	setFaceResolver(null);
}
