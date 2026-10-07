import { createSignal } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { Show } from "../../src/macros/ui/flow";
import { HostNode, mockNode, mockHost, render } from "../../src/render/host";
import { Void } from "../../src/components/primitives";
import { Scene2D, Group, Rect } from "../../src/components/scene2d";
import { NodeRef, Paint2D, DrawKind, Changed, clearChanges, kind, content, paint, parent, local, setBoxStyle } from "../../../void/src/void2d/node";
import { Color, rgba, Smooth } from "../../../void/src/void2d/types";
import { BlendMode } from "../../../void/src/gpu/state";
import { BoxStyle, create, uniformRadii, uniformBorders, boxStyles } from "../../../void/src/void2d/boxStyle";
import { colorMatrixGrayscale } from "../../../void/src/void2d/effect";

function colored(color: Color): Paint2D {
	return { color: color, alpha: 0.4, colorAdd: rgba(0.0, 0.0, 0.0, 0.0),
		colorKey: rgba(0.0, 0.0, 0.0, 0.0), colorMatrixRow: -1,
		blend: BlendMode.Alpha, smooth: Smooth.Inherit, tileWrap: false };
}

test "Group background promotes and demotes in place without replacing its child or local" {
	const nodes: NodeRef[] = [];
	const [background, setBackground] = createSignal<Color | null>(null);
	const [width, setWidth] = createSignal<float32>(20.0);
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene2D>
		<Group width={width()} height={10.0} background={background()}
			local={{ x: 3.0, y: 4.0, scaleX: 1.0, scaleY: 1.0, rotation: 0.0, pivotX: 0.0, pivotY: 0.0 }}
			ref={(node: NodeRef): void => { nodes.push(node); }}>
			<Rect width={2.0} height={3.0} color={rgba(1.0, 1.0, 1.0, 1.0)}
				ref={(node: NodeRef): void => { nodes.push(node); }} />
		</Group>
	</Scene2D></Void>), mockHost(), root as unknown as HostNode);
	const group = nodes[0]; const child = nodes[1]; const id = group.id;
	assert group.kind() === DrawKind.Group;
	setBackground(rgba(0.2, 0.4, 0.8, 1.0));
	assert group.kind() === DrawKind.Rect && group.id === id && child.parent() === group;
	assert group.local().x === 3.0 && group.local().y === 4.0;
	assert group.content().w === 20.0 && group.content().h === 10.0;
	assert group.paint().color === rgba(0.2, 0.4, 0.8, 1.0);
	group.setBoxStyle(BoxStyle.create(uniformRadii(2.0), uniformBorders(1.0), rgba(1.0, 1.0, 1.0, 1.0)));
	const style = group.scene.payloads[group.id.index];
	const rows = boxStyles.length;
	setWidth(30.0); setBackground(null);
	assert group.kind() === DrawKind.Group && group.id === id && child.isLive();
	assert group.paint().color.a === 0.0 && group.content().w === 30.0;
	assert group.scene.payloads[group.id.index] === -1;
	setBackground(rgba(0.9, 0.1, 0.2, 1.0));
	assert group.kind() === DrawKind.Rect && child.parent() === group;
	group.setBoxStyle(BoxStyle.create(uniformRadii(4.0), uniformBorders(1.0), rgba(1.0, 1.0, 1.0, 1.0)));
	assert group.scene.payloads[group.id.index] === style && boxStyles.length === rows;
	dispose(); setBackground(null); setWidth(1.0);
	assert !group.isLive() && !child.isLive() && group.scene.closed;
}

test "Group omitted background stays structural and remount restores current fill with full Paint precedence" {
	const nodes: NodeRef[] = [];
	const [shown, setShown] = createSignal(true);
	const [background, setBackground] = createSignal<Color | null>(rgba(0.0, 0.0, 1.0, 1.0));
	const [full, setFull] = createSignal<Paint2D>(colored(rgba(1.0, 0.0, 0.0, 1.0)));
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene2D>
		<Group height={7.0} ref={(node: NodeRef): void => { nodes.push(node); }} />
		{Show({ when: () => shown(), children: element(
			<Group width={12.0} background={background()} paint={full()} colorMatrix={colorMatrixGrayscale(0.5)}
				ref={(node: NodeRef): void => { nodes.push(node); }} />
		) })}
	</Scene2D></Void>), mockHost(), root as unknown as HostNode);
	assert nodes[0].kind() === DrawKind.Group && nodes[0].content().w === 0.0 && nodes[0].content().h === 7.0;
	assert nodes[1].paint().color === full().color && nodes[1].paint().alpha === 0.4;
	const matrixRow = nodes[1].paint().colorMatrixRow;
	assert matrixRow >= 0;
	nodes[1].scene.clearChanges();
	setBackground(rgba(0.0, 1.0, 0.0, 1.0));
	assert nodes[1].paint().color === full().color;
	assert !nodes[1].scene.changed[nodes[1].id.index].has(Changed.Paint);
	setFull(colored(rgba(0.3, 0.4, 0.5, 1.0)));
	assert nodes[1].paint().color === full().color;
	assert nodes[1].paint().colorMatrixRow === matrixRow;
	setShown(false); setBackground(rgba(0.5, 0.6, 0.7, 1.0)); setShown(true);
	assert !nodes[1].isLive() && nodes[2].kind() === DrawKind.Rect;
	assert nodes[2].content().w === 12.0 && nodes[2].content().h === 0.0;
	assert nodes[2].paint().color === full().color && nodes[0].kind() === DrawKind.Group;
	assert nodes[2].paint().colorMatrixRow === matrixRow;
	dispose(); setShown(false); setFull(colored(rgba(0.0, 0.0, 0.0, 1.0)));
	assert !nodes[0].isLive() && !nodes[2].isLive();
}
