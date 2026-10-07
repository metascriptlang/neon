import { createSignal } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { HostNode, mockNode, mockHost, render } from "../../src/render/host";
import { Void } from "../../src/components/primitives";
import { Scene2D, Label } from "../../src/components/scene2d";
import { NodeRef, textStyle } from "../../../void/src/void2d/node";
import { rgba } from "../../../void/src/void2d/types";
import { FontId, addFont, fontFace } from "../../../void/src/void2d/font";
import { TextStyle, TextLayout, Align, layout, xForIndex as layoutXForIndex } from "../../../void/src/void2d/textLayout";
import { textLayout, textWidth, textHeight, xForIndex, lineBoxAt, indexAt } from "../../../void/src/void2d/render";

function loadedFont(): FontId {
	const loaded = addFont("../void/assets/font.ttf");
	if (!loaded.ok) { throw new Error("font fixture: " + loaded.error.toString()); }
	return loaded.value;
}

function styled(font: FontId, size: float32, spacing: float32, width: float32): TextStyle {
	return { font: font, size: size, letterSpacing: spacing, lineSpacing: 0.0, maxWidth: width, align: Align.Left };
}

test "Label with a real font measures and queries the same glyph layout as Void" {
	const font = loadedFont();
	assert fontFace(font) >= 0;
	const nodes: NodeRef[] = [];
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene2D>
		<Label text={"ab\ncd"} size={13.0} color={rgba(1.0, 1.0, 1.0, 1.0)}
			textStyle={styled(font, 99.0, 0.0, 0.0)}
			ref={(node: NodeRef): void => { nodes.push(node); }} />
	</Scene2D></Void>), mockHost(), root as unknown as HostNode);
	const node = nodes[0];
	assert node.textStyle().font === font && node.textStyle().size === 13.0;
	const direct = TextLayout.layout("ab\ncd", styled(font, 13.0, 0.0, 0.0));
	const actual = node.textLayout();
	assert actual.width > 0.0 && actual.height > 0.0;
	assert actual.glyphs.length === 4 && actual.lines.length === 2;
	assert actual.glyphs[0].face === fontFace(font);
	assert node.textWidth() === direct.width && node.textHeight() === direct.height;
	assert node.xForIndex(1) === direct.glyphs[1].x;
	assert node.lineBoxAt(3).top === direct.lines[1].top;
	assert node.indexAt(0.0, direct.lines[1].top + 1.0) === 3;
	dispose(); assert !node.isLive() && node.scene.closed;
}

test "Label updates borrowed font style size and wrapping without stale measurements" {
	const firstFont = loadedFont();
	const secondFont = loadedFont();
	const nodes: NodeRef[] = [];
	const [style, setStyle] = createSignal<TextStyle>(styled(firstFont, 99.0, 0.0, 0.0));
	const [size, setSize] = createSignal<float32>(13.0);
	const [text, setText] = createSignal("aa bb cc dd");
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene2D>
		<Label text={text()} size={size()} color={rgba(1.0, 1.0, 1.0, 1.0)} textStyle={style()}
			ref={(node: NodeRef): void => { nodes.push(node); }} />
	</Scene2D></Void>), mockHost(), root as unknown as HostNode);
	const node = nodes[0]; const id = node.id;
	const initialWidth = node.textWidth();
	assert initialWidth > 0.0 && node.textLayout().lines.length === 1;
	setSize(26.0);
	assert node.textWidth() > initialWidth * 1.9;
	setStyle(styled(secondFont, 99.0, 1.0, 35.0));
	assert node.id === id && node.textStyle().font === secondFont && node.textStyle().size === 26.0;
	const direct = TextLayout.layout(text(), styled(secondFont, 26.0, 1.0, 35.0));
	assert node.textLayout().lines.length > 1;
	assert node.textWidth() === direct.width && node.textHeight() === direct.height;
	setText("a🙂b");
	const changed = TextLayout.layout(text(), styled(secondFont, 26.0, 1.0, 35.0));
	assert node.textWidth() === changed.width && node.textLayout().glyphs.length === changed.glyphs.length;
	assert node.textLayout().glyphs[2].charIndex === 2;
	assert node.textLayout().glyphs[2].index === 3;
	assert node.xForIndex(3) === layoutXForIndex(changed, 3);
	dispose(); setSize(12.0); setStyle(styled(firstFont, 10.0, 0.0, 0.0));
	assert !node.isLive() && node.scene.closed;
}
