import { createSignal } from "../../src/core/signal";
import { flush } from "../../src/core/runtime";
import { element } from "../../src/macros/ui/element";
import { HostNode, mockNode, mockHost, render } from "../../src/render/host";
import { Void } from "../../src/components/primitives";
import { Scene2D, Group, Rect, Mask } from "../../src/components/scene2d";
import {
	NodeRef, Local2D, localToGlobal, globalToLocal, isLive,
} from "../../../void/src/void2d/node";
import { hitTest } from "../../../void/src/void2d/render";
import { rgba, vec2 } from "../../../void/src/void2d/types";

function pose(x: float32, y: float32, scale: float32, angle: float32): Local2D {
	return {
		x: x, y: y, scaleX: scale, scaleY: scale, rotation: angle, pivotX: 0.0, pivotY: 0.0,
	};
}

test "raw JSX geometry queries follow reactive ancestors and visibility before a frame" {
	const nodes: NodeRef[] = [];
	const [x, setX] = createSignal<float32>(10.0);
	const [scale, setScale] = createSignal<float32>(1.0);
	const [width, setWidth] = createSignal<float32>(10.0);
	const [parentShown, setParentShown] = createSignal(true);
	const [shown, setShown] = createSignal(true);
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene2D>
		<Group local={pose(x(), 30.0, scale(), 0.0)}
			order={{ zIndex: 0, visible: parentShown(), name: "parent", noOverlap: false }}>
			<Rect local={pose(5.0, 5.0, 1.0, 0.0)} width={width()} height={10.0}
				color={rgba(1.0, 1.0, 1.0, 1.0)}
				order={{ zIndex: 0, visible: shown(), name: "target", noOverlap: false }}
				ref={(node: NodeRef): void => { nodes.push(node); }} />
		</Group>
	</Scene2D></Void>), mockHost(), root as unknown as HostNode);
	const node = nodes[0];
	const id = node.id;
	try {
		assert node.localToGlobal(vec2(0.0, 0.0)) === vec2(15.0, 35.0);
		assert node.globalToLocal(vec2(18.0, 39.0)) === vec2(3.0, 4.0);
		assert node.hitTest(vec2(16.0, 36.0)) && !node.hitTest(vec2(5.0, 5.0));
		setX(20.0);
		flush();
		assert node.localToGlobal(vec2(0.0, 0.0)) === vec2(25.0, 35.0);
		assert !node.hitTest(vec2(16.0, 36.0)) && node.hitTest(vec2(26.0, 36.0));
		setScale(0.0);
		flush();
		assert !node.hitTest(vec2(25.0, 35.0));
		setScale(1.0); setWidth(0.0);
		flush();
		assert !node.hitTest(vec2(25.0, 35.0));
		setWidth(8.0); setParentShown(false);
		flush();
		assert !node.hitTest(vec2(26.0, 36.0));
		setParentShown(true); setShown(false);
		flush();
		assert !node.hitTest(vec2(26.0, 36.0));
		setShown(true);
		flush();
		assert node.hitTest(vec2(26.0, 36.0)) && node.id === id && nodes.length === 1;
	} finally { dispose(); }
	setX(40.0); setWidth(3.0);
	flush();
	assert !node.isLive() && node.scene.closed;
}

test "raw mask queries honor scroll and every nested rotated clip after resizing" {
	const nodes: NodeRef[] = [];
	const [scroll, setScroll] = createSignal<float32>(0.0);
	const [outerHeight, setOuterHeight] = createSignal<float32>(25.0);
	const [innerWidth, setInnerWidth] = createSignal<float32>(20.0);
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene2D>
		<Mask local={pose(10.0, 20.0, 1.0, 0.0)} width={80.0} height={60.0}
			scrollY={scroll()}>
			<Rect local={pose(5.0, 5.0, 1.0, 0.0)} width={20.0} height={10.0}
				color={rgba(1.0, 1.0, 1.0, 1.0)}
				ref={(node: NodeRef): void => { nodes.push(node); }} />
		</Mask>
		<Mask local={pose(10.0, 20.0, 1.0, 0.0)} width={50.0} height={outerHeight()}>
			<Mask local={pose(30.0, 10.0, 1.0, 1.5707963)}
				width={innerWidth()} height={20.0}>
				<Rect local={pose(5.0, 5.0, 1.0, 0.0)} width={30.0} height={10.0}
					color={rgba(1.0, 1.0, 1.0, 1.0)}
					ref={(node: NodeRef): void => { nodes.push(node); }} />
			</Mask>
		</Mask>
	</Scene2D></Void>), mockHost(), root as unknown as HostNode);
	try {
		assert nodes[0].hitTest(vec2(20.0, 30.0));
		setScroll(10.0);
		flush();
		assert nodes[0].localToGlobal(vec2(0.0, 0.0)) === vec2(15.0, 15.0);
		assert nodes[0].globalToLocal(vec2(20.0, 23.0)) === vec2(5.0, 8.0);
		assert nodes[0].hitTest(vec2(20.0, 23.0));
		assert !nodes[0].hitTest(vec2(20.0, 17.0));
		assert !nodes[0].hitTest(vec2(20.0, 30.0));
		assert nodes[1].hitTest(vec2(30.0, 40.0));
		assert !nodes[1].hitTest(vec2(30.0, 48.0));
		setOuterHeight(50.0);
		flush();
		assert nodes[1].hitTest(vec2(30.0, 48.0));
		assert !nodes[1].hitTest(vec2(30.0, 55.0));
		setInnerWidth(30.0);
		flush();
		assert nodes[1].hitTest(vec2(30.0, 55.0));
		assert nodes.length === 2;
	} finally { dispose(); }
	setScroll(0.0); setOuterHeight(10.0); setInnerWidth(10.0);
	flush();
	for (const node of nodes) { assert !node.isLive() && node.scene.closed; }
}
