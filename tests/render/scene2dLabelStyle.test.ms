import { createSignal } from "../../src/core/signal";
import { flush, resetErrorHalt } from "../../src/core/runtime";
import { createRoot } from "../../src/core/owner";
import { element } from "../../src/macros/ui/element";
import { NeonNode } from "../../src/render/node";
import { HostNode, mockHost, mockNode, render } from "../../src/render/host";
import { Void } from "../../src/components/primitives";
import { Scene2D, Label } from "../../src/components/scene2d";
import { NodeRef, Scene2D as VoidScene2D, isLive, textDirection, label, setTextStyle, setTextDirection } from "../../../void/src/void2d/node";
import { create, add, close } from "../../../void/src/void2d/scene";
import { addFont } from "../../../void/src/void2d/font";
import { TextStyle, Align, TextErrorKind } from "../../../void/src/void2d/textLayout";
import { textLayout, xForIndex } from "../../../void/src/void2d/render";
import { TextDirection } from "../../../void/src/void2d/textDirection";
import { Color, rgba } from "../../../void/src/void2d/types";
import { labelTexts } from "../../../void/src/void2d/labelText";

function refusal(child: NeonNode): string {
	let message = "";
	createRoot((dispose: () => void): void => {
		try {
			const root = mockNode("root");
			element(<Void><Scene2D>{child}</Scene2D></Void>)(mockHost(), root as unknown as HostNode, null);
		} catch (error) { message = error.toString(); }
		finally { dispose(); resetErrorHalt(); }
	});
	return message;
}

test "Label textDirection follows the Void binder without replacing its node or changing a sibling" {
	const [direction, setDirection] = createSignal<TextDirection>(TextDirection.Ltr);
	const nodes: NodeRef[] = [];
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene2D>
		<Label text="" size={12.0} color={rgba(1.0, 1.0, 1.0, 1.0)} textDirection={direction()}
			ref={(node: NodeRef): void => { nodes.push(node); }} />
		<Label text="" size={12.0} color={rgba(1.0, 1.0, 1.0, 1.0)}
			ref={(node: NodeRef): void => { nodes.push(node); }} />
	</Scene2D></Void>), mockHost(), root as unknown as HostNode);
	try {
		const node = nodes[0];
		assert node.textDirection() === TextDirection.Ltr && nodes[1].textDirection() === TextDirection.Auto;
		setDirection(TextDirection.Rtl); flush();
		assert nodes.length === 2 && nodes[0] === node && node.textDirection() === TextDirection.Rtl;
		assert nodes[1].textDirection() === TextDirection.Auto;
		setDirection(TextDirection.Auto); flush();
		assert node.textDirection() === TextDirection.Auto;
	} finally { dispose(); }
	assert !nodes[0].isLive() && !nodes[1].isLive();
}

test "Label direction reshapes real glyphs and caret queries like a direct Void label" {
	const loaded = addFont("../void/tests/fonts/notoSansHebrewSubset.ttf");
	if (!loaded.ok) { throw new Error("font fixture: " + loaded.error.toString()); }
	const style: TextStyle = { font: loaded.value, size: 13.0, letterSpacing: 0.0, lineSpacing: 0.0, maxWidth: 0.0, align: Align.Left };
	const text = "ab \u{5D0}\u{5D1}";
	const [direction, setDirection] = createSignal<TextDirection>(TextDirection.Ltr);
	const nodes: NodeRef[] = [];
	const root = mockNode("root");
	const directScene = VoidScene2D.create(rgba(0.0, 0.0, 0.0, 0.0));
	const direct = directScene.add(directScene.label(text, 13.0, rgba(1.0, 1.0, 1.0, 1.0)));
	direct.setTextStyle(style).setTextDirection(TextDirection.Ltr);
	const dispose = render(element(<Void><Scene2D>
		<Label text={text} size={13.0} color={rgba(1.0, 1.0, 1.0, 1.0)} textStyle={style} textDirection={direction()}
			ref={(node: NodeRef): void => { nodes.push(node); }} />
	</Scene2D></Void>), mockHost(), root as unknown as HostNode);
	try {
		const node = nodes[0];
		when (voidBidi) {
			const same = (): void => {
				const actual = node.textLayout();
				const expected = direct.textLayout();
				assert actual.glyphs.length > 0 && actual.glyphs.length === expected.glyphs.length;
				assert actual.width === expected.width && actual.height === expected.height;
				for (let i = 0; i < actual.glyphs.length; i += 1) {
					assert actual.glyphs[i].x === expected.glyphs[i].x && actual.glyphs[i].index === expected.glyphs[i].index;
				}
				for (let i = 0; i <= text.length; i += 1) { assert node.xForIndex(i) === direct.xForIndex(i); }
			};
			same();
			const firstCaret = node.xForIndex(0);
			setDirection(TextDirection.Rtl); flush(); direct.setTextDirection(TextDirection.Rtl);
			same();
			assert node.xForIndex(0) !== firstCaret;
			setDirection(TextDirection.Auto); flush(); direct.setTextDirection(TextDirection.Auto);
			same();
		} else {
			node.textLayout();
			const row = node.scene.payloads[node.id.index];
			assert labelTexts[row].textRefused;
			assert labelTexts[row].textRefusal.kind === TextErrorKind.RightToLeftNeedsBidi;
		}
	} finally { dispose(); directScene.close(); }
	assert !nodes[0].isLive();
}

test "Label outline width and color must be supplied together and width must be nonnegative" {
	const widthOnly = refusal(element(<Label text="" size={12.0} color={rgba(1.0, 1.0, 1.0, 1.0)} outlineWidth={1.0} />));
	assert widthOnly.includes("Label: provide outlineWidth and outlineColor together"), widthOnly;
	const colorOnly = refusal(element(<Label text="" size={12.0} color={rgba(1.0, 1.0, 1.0, 1.0)} outlineColor={rgba(0.0, 0.0, 0.0, 1.0)} />));
	assert colorOnly.includes("Label: provide outlineWidth and outlineColor together"), colorOnly;
	const negative = refusal(element(<Label text="" size={12.0} color={rgba(1.0, 1.0, 1.0, 1.0)}
		outlineWidth={-1.0} outlineColor={rgba(0.0, 0.0, 0.0, 1.0)} />));
	assert negative.includes("Label: outlineWidth must be nonnegative"), negative;
}

test "Label outline uses the enabled Void module and refuses positive width when it is disabled" {
	when (voidTextOutline) {
		const [width, setWidth] = createSignal<float32>(2.0);
		const [color, setColor] = createSignal<Color>(rgba(1.0, 0.0, 0.0, 1.0));
		const nodes: NodeRef[] = [];
		const root = mockNode("root");
		const dispose = render(element(<Void><Scene2D>
			<Label text="" size={12.0} color={rgba(1.0, 1.0, 1.0, 1.0)} outlineWidth={width()} outlineColor={color()}
				ref={(node: NodeRef): void => { nodes.push(node); }} />
			<Label text="" size={12.0} color={rgba(1.0, 1.0, 1.0, 1.0)}
				ref={(node: NodeRef): void => { nodes.push(node); }} />
		</Scene2D></Void>), mockHost(), root as unknown as HostNode);
		try {
			const node = nodes[0];
			const row = node.scene.payloads[node.id.index];
			const sibling = nodes[1].scene.payloads[nodes[1].id.index];
			assert labelTexts[row].outlineWidth === 2.0 && labelTexts[row].outlineColor.r === 1.0;
			setWidth(3.0); setColor(rgba(0.0, 1.0, 0.0, 1.0)); flush();
			assert nodes.length === 2 && nodes[0] === node;
			assert labelTexts[row].outlineWidth === 3.0 && labelTexts[row].outlineColor.g === 1.0;
			assert labelTexts[sibling].outlineWidth === 0.0;
			setWidth(0.0); flush();
			assert labelTexts[row].outlineWidth === 0.0;
		} finally { dispose(); }
		assert !nodes[0].isLive() && !nodes[1].isLive();
	} else {
		const message = refusal(element(<Label text="" size={12.0} color={rgba(1.0, 1.0, 1.0, 1.0)}
			outlineWidth={1.0} outlineColor={rgba(0.0, 0.0, 0.0, 1.0)} />));
		assert message.includes("Label: positive outlineWidth requires -d:voidTextOutline"), message;
		const cleared = refusal(element(<Label text="" size={12.0} color={rgba(1.0, 1.0, 1.0, 1.0)}
			outlineWidth={0.0} outlineColor={rgba(0.0, 0.0, 0.0, 1.0)} />));
		assert cleared === "", cleared;
	}
}
