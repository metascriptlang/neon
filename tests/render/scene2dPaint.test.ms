import { createSignal } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { HostNode, mockNode, mockHost, render } from "../../src/render/host";
import { Void } from "../../src/components/primitives";
import { Scene2D, Underline, Selection } from "../../src/components/scene2d";
import { NodeRef, Paint2D, paint, isLive } from "../../../void/src/void2d/node";
import { rgba, Smooth } from "../../../void/src/void2d/types";
import { BlendMode } from "../../../void/src/gpu/state";

test "Both text decorations honor full Paint2D over reactive constructor color" {
	const nodes: NodeRef[] = [];
	const [red, setRed] = createSignal<float32>(1.0);
	const initial: Paint2D = {
		color: rgba(0.0, 1.0, 0.0, 1.0), alpha: 0.5,
		colorAdd: rgba(0.0, 0.0, 0.0, 0.0), colorKey: rgba(0.0, 0.0, 0.0, 0.0),
		colorMatrixRow: -1, blend: BlendMode.Alpha, smooth: Smooth.Inherit, tileWrap: false,
	};
	const [paint, setPaint] = createSignal<Paint2D>(initial);
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene2D>
		<Underline width={10.0} thickness={1.0} wavy={false}
			color={rgba(red(), 0.0, 0.0, 1.0)} paint={paint()}
			ref={(value: NodeRef): void => { nodes.push(value); }} />
		<Selection width={10.0} height={10.0} color={rgba(red(), 0.0, 0.0, 1.0)}
			prevOffsetX={0.0} prevWidth={0.0} nextOffsetX={0.0} nextWidth={0.0} paint={paint()}
			ref={(value: NodeRef): void => { nodes.push(value); }} />
	</Scene2D></Void>), mockHost(), root as unknown as HostNode);
	setRed(0.25); setPaint({ ...initial, alpha: 0.75 });
	assert nodes[0].paint().color.g === 1.0 && nodes[1].paint().color.g === 1.0;
	assert nodes[0].paint().color.r === 0.0 && nodes[1].paint().color.r === 0.0;
	assert nodes[0].paint().alpha === 0.75 && nodes[1].paint().alpha === 0.75;
	dispose(); setRed(0.5); setPaint(initial);
	assert !nodes[0].isLive() && !nodes[1].isLive();
}
