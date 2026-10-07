import { createSignal } from "../../src/core/signal";
import { createRoot } from "../../src/core/owner";
import { element } from "../../src/macros/ui/element";
import { Show } from "../../src/macros/ui/flow";
import {
	HostNode, MockNode, mockNode, mockHost, render, mockToString,
} from "../../src/render/host";
import { NeonNode } from "../../src/render/node";
import { Void, View, Text } from "../../src/components/primitives";
import { Scene2D, Group, Rect, Sprite, Mask, Label } from "../../src/components/scene2d";
import { Scene3D } from "../../src/components/scene3d";
import { voidScope as Scope, VoidSpace } from "../../src/render/voidScope";
import {
	Scene2D as VoidScene2D, NodeRef, NodeId2D, DrawKind, Local2D, nodeCount, kind, local,
	content, text, textStyle, paint, order, filter, colorMatrix, numChildren, parent, isLive,
} from "../../../void/src/void2d/node";
import { rgba, whiteTile, camera, glowFilter, Smooth } from "../../../void/src/void2d/types";
import { BlendMode } from "../../../void/src/gpu/state";
import { colorMatrixGrayscale, NO_COLOR_MATRIX } from "../../../void/src/void2d/effect";

function translated(x: float32, y: float32): Local2D {
	return { x: x, y: y, scaleX: 1.0, scaleY: 1.0, rotation: 0.0, pivotX: 0.0, pivotY: 0.0 };
}

function mountError(node: NeonNode): string {
	let message = "";
	createRoot((dispose: () => void): void => {
		try {
			const root = mockNode("root");
			node(mockHost(), root as unknown as HostNode, null);
		} catch (error) { message = error.toString(); } finally { dispose(); }
	});
	return message;
}

test "Scene2D mounts real render nodes without creating host elements" {
	let scene: VoidScene2D = null as unknown as VoidScene2D;
	const nodes: NodeRef[] = [];
	const root: MockNode = mockNode("root");
	const dispose = render(element(<Void>
		<Scene2D ref={(value: VoidScene2D): void => { scene = value; }}>
			<Group ref={(value: NodeRef): void => { nodes.push(value); }}>
				<Rect width={20.0} height={30.0} color={rgba(1.0, 0.0, 0.0, 1.0)}
					ref={(value: NodeRef): void => { nodes.push(value); }} />
				<Sprite tile={whiteTile(7.0, 9.0)}
					ref={(value: NodeRef): void => { nodes.push(value); }} />
				<Mask width={40.0} height={50.0}
					ref={(value: NodeRef): void => { nodes.push(value); }}>
					<Label text="hello" size={16.0} color={rgba(1.0, 1.0, 1.0, 1.0)}
						ref={(value: NodeRef): void => { nodes.push(value); }} />
				</Mask>
			</Group>
		</Scene2D>
	</Void>), mockHost(), root as unknown as HostNode);
	assert scene.nodeCount() === 6;
	assert nodes[0].kind() === DrawKind.Group;
	assert nodes[1].kind() === DrawKind.Rect;
	assert nodes[2].kind() === DrawKind.Sprite;
	assert nodes[3].kind() === DrawKind.Mask;
	assert nodes[4].kind() === DrawKind.Label;
	assert nodes[0].numChildren() === 3;
	const rectParent = nodes[1].parent();
	const labelParent = nodes[4].parent();
	assert rectParent !== null && labelParent !== null;
	if (rectParent !== null) { assert rectParent.id === nodes[0].id; }
	if (labelParent !== null) { assert labelParent.id === nodes[3].id; }
	assert nodes[1].content().w === 20.0 && nodes[1].content().h === 30.0;
	assert nodes[2].content().w === 7.0 && nodes[2].content().h === 9.0;
	assert nodes[4].text() === "hello";
	assert mockToString(root) === "<root><void><voidroot></voidroot></void></root>";
	dispose();
	assert scene.closed && scene.nodeCount() === 0;
	assert !nodes[0].isLive() && !nodes[4].isLive();
}

test "Scene2D camera and raw node geometry follow signals and stop on disposal" {
	let scene: VoidScene2D = null as unknown as VoidScene2D;
	const nodes: NodeRef[] = [];
	const [x, setX] = createSignal<float32>(2.0);
	const [width, setWidth] = createSignal<float32>(10.0);
	const [zoom, setZoom] = createSignal<float32>(1.0);
	const [label, setLabel] = createSignal("first");
	const root = mockNode("root");
	const dispose = render(element(<Void>
		<Scene2D camera={{ ...camera(), zoom: zoom() }}
			ref={(value: VoidScene2D): void => { scene = value; }}>
			<Group local={translated(x(), 3.0)}>
				<Rect width={width()} height={5.0} color={rgba(0.0, 1.0, 0.0, 1.0)}
					ref={(value: NodeRef): void => { nodes.push(value); }} />
				<Label text={label()} size={12.0} color={rgba(1.0, 1.0, 1.0, 1.0)}
					ref={(value: NodeRef): void => { nodes.push(value); }} />
			</Group>
		</Scene2D>
	</Void>), mockHost(), root as unknown as HostNode);
	setX(8.0); setWidth(25.0); setZoom(2.0); setLabel("second");
	const group = nodes[0].parent();
	assert group !== null;
	if (group !== null) { assert group.local().x === 8.0 && group.local().y === 3.0; }
	assert nodes[0].content().w === 25.0;
	assert nodes[1].text() === "second";
	assert scene.cam.zoom === 2.0;
	dispose();
	setX(9.0); setWidth(99.0); setZoom(3.0); setLabel("disposed");
	assert scene.closed && scene.nodeCount() === 0;
}

test "Sprite retile and structural removal keep the scene and sibling alive" {
	let scene: VoidScene2D = null as unknown as VoidScene2D;
	const nodes: NodeRef[] = [];
	const [size, setSize] = createSignal<float32>(4.0);
	const [shown, setShown] = createSignal(true);
	const root = mockNode("root");
	const dispose = render(element(<Void>
		<Scene2D ref={(value: VoidScene2D): void => { scene = value; }}>
			{Show({ when: () => shown(), children: element(
				<Group ref={(value: NodeRef): void => { nodes.push(value); }}>
					<Sprite tile={whiteTile(size(), size())}
						ref={(value: NodeRef): void => { nodes.push(value); }} />
				</Group>
			) })}
			<Rect width={1.0} height={1.0} color={rgba(1.0, 1.0, 1.0, 1.0)}
				ref={(value: NodeRef): void => { nodes.push(value); }} />
		</Scene2D>
	</Void>), mockHost(), root as unknown as HostNode);
	assert scene.nodeCount() === 4;
	setSize(11.0);
	assert nodes[1].content().tile.w === 11.0 && nodes[1].content().w === 11.0;
	setShown(false);
	assert !scene.closed && scene.nodeCount() === 2;
	assert !nodes[0].isLive() && !nodes[1].isLive();
	assert nodes[2].isLive();
	setSize(15.0);
	setShown(true);
	assert scene.nodeCount() === 4 && nodes[4].content().w === 15.0;
	dispose();
	assert scene.closed;
}

test "raw 2D paint order filter and label size update through Void binders" {
	const nodes: NodeRef[] = [];
	const [alpha, setAlpha] = createSignal<float32>(1.0);
	const [visible, setVisible] = createSignal(true);
	const [radius, setRadius] = createSignal<float32>(2.0);
	const [size, setSize] = createSignal<float32>(12.0);
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene2D>
		<Label text="paint" size={size()} color={rgba(1.0, 1.0, 1.0, 1.0)}
			order={{ zIndex: 4, visible: visible(), name: "label", noOverlap: false }}
			filter={glowFilter(rgba(1.0, 0.0, 0.0, 1.0), radius(), 1.0)}
			ref={(value: NodeRef): void => { nodes.push(value); }} />
		<Rect width={3.0} height={4.0} color={rgba(0.0, 1.0, 0.0, 1.0)}
			paint={{
				color: rgba(1.0, 0.0, 0.0, 1.0), alpha: alpha(),
				colorAdd: rgba(0.0, 0.0, 0.0, 0.0), colorKey: rgba(0.0, 0.0, 0.0, 0.0),
				colorMatrixRow: -1, blend: BlendMode.Alpha,
				smooth: Smooth.Inherit, tileWrap: false,
			}}
			ref={(value: NodeRef): void => { nodes.push(value); }} />
	</Scene2D></Void>), mockHost(), root as unknown as HostNode);
	setAlpha(0.5); setVisible(false); setRadius(5.0); setSize(20.0);
	assert nodes[0].order().name === "label" && !nodes[0].order().visible;
	assert nodes[0].filter().radius === 5.0 && nodes[0].textStyle().size === 20.0;
	assert nodes[1].paint().alpha === 0.5;
	assert nodes[1].paint().color.r === 1.0 && nodes[1].paint().color.g === 0.0;
	dispose();
	setAlpha(0.8); setVisible(true); setRadius(9.0); setSize(30.0);
	assert !nodes[0].isLive() && !nodes[1].isLive();
}

test "colorMatrix owns its row across paint changes clearing remount and disposal" {
	let scene: VoidScene2D = null as unknown as VoidScene2D;
	const nodes: NodeRef[] = [];
	const [amount, setAmount] = createSignal<float32>(1.0);
	const [alpha, setAlpha] = createSignal<float32>(1.0);
	const [shown, setShown] = createSignal(true);
	const root = mockNode("root");
	const dispose = render(element(<Void>
		<Scene2D ref={(value: VoidScene2D): void => { scene = value; }}>
			{Show({ when: () => shown(), children: element(
				<Rect width={10.0} height={20.0} color={rgba(1.0, 1.0, 1.0, 1.0)}
					colorMatrix={colorMatrixGrayscale(amount())}
					paint={{
						color: rgba(1.0, 1.0, 1.0, 1.0), alpha: alpha(),
						colorAdd: rgba(0.0, 0.0, 0.0, 0.0),
						colorKey: rgba(0.0, 0.0, 0.0, 0.0),
						colorMatrixRow: -1, blend: BlendMode.Alpha,
						smooth: Smooth.Inherit, tileWrap: false,
					}}
					ref={(value: NodeRef): void => { nodes.push(value); }} />
			) })}
		</Scene2D>
	</Void>), mockHost(), root as unknown as HostNode);
	const row = nodes[0].paint().colorMatrixRow;
	assert row >= 0 && scene.colorMatrices.length === 1;
	setAlpha(0.5); setAmount(0.5);
	assert nodes[0].paint().colorMatrixRow === row && nodes[0].paint().alpha === 0.5;
	assert nodes[0].colorMatrix() === colorMatrixGrayscale(0.5);
	assert scene.colorMatrices.length === 1;
	setAmount(0.0);
	assert nodes[0].colorMatrix() === NO_COLOR_MATRIX;
	assert nodes[0].paint().colorMatrixRow === -1 && scene.freeColorMatrices.length === 1;
	setAlpha(0.8); setAmount(1.0);
	assert nodes[0].paint().colorMatrixRow === row && scene.freeColorMatrices.length === 0;
	setShown(false);
	assert !nodes[0].isLive() && scene.freeColorMatrices.length === 1;
	setAlpha(0.3); setAmount(0.5); setShown(true);
	assert nodes[1].paint().colorMatrixRow === row && nodes[1].paint().alpha === 0.3;
	assert scene.colorMatrices.length === 1;
	dispose();
	setAmount(1.0); setAlpha(0.9);
	assert scene.closed && !nodes[1].isLive();
}

test "paint rejects selecting another matrix row and cleans up failed mount" {
	let scene: VoidScene2D = null as unknown as VoidScene2D;
	const error = mountError(element(<Void>
		<Scene2D ref={(value: VoidScene2D): void => { scene = value; }}>
			<Rect width={10.0} height={20.0} color={rgba(1.0, 1.0, 1.0, 1.0)}
				paint={{
					color: rgba(1.0, 1.0, 1.0, 1.0), alpha: 1.0,
					colorAdd: rgba(0.0, 0.0, 0.0, 0.0), colorKey: rgba(0.0, 0.0, 0.0, 0.0),
					colorMatrixRow: 7, blend: BlendMode.Alpha,
					smooth: Smooth.Inherit, tileWrap: false,
				}} />
		</Scene2D>
	</Void>));
	assert error.includes("Rect") && error.includes("colorMatrixRow");
	assert scene.closed && scene.nodeCount() === 0;
}

test "Scene2D scene values react and a failed child mount closes the scene" {
	let scene: VoidScene2D = null as unknown as VoidScene2D;
	const [red, setRed] = createSignal<float32>(0.2);
	const [smooth, setSmooth] = createSignal(true);
	const root = mockNode("root");
	const dispose = render(element(<Void>
		<Scene2D clear={rgba(red(), 0.0, 0.0, 1.0)} smooth={smooth()}
			ref={(value: VoidScene2D): void => { scene = value; }} />
	</Void>), mockHost(), root as unknown as HostNode);
	setRed(0.7); setSmooth(false);
	assert scene.clear.r === 0.7 && !scene.defaultSmooth;
	dispose();
	setRed(0.9); setSmooth(true);
	assert scene.closed && scene.clear.r === 0.7 && !scene.defaultSmooth;
	const failed = mountError(element(<Void>
		<Scene2D ref={(value: VoidScene2D): void => { scene = value; }}><View /></Scene2D>
	</Void>));
	assert failed.includes("Scene2D") && scene.closed && scene.nodeCount() === 0;
}

test "raw 2D components reject missing or nested scene parents" {
	const outside = mountError(element(<Scene2D />));
	const group = mountError(element(<Void><Group /></Void>));
	const nested = mountError(element(<Void><Scene2D><Scene2D /></Scene2D></Void>));
	assert outside.includes("Scene2D") && outside.includes("Void");
	assert group.includes("Group") && group.includes("Scene2D");
	assert nested.includes("Scene2D") && nested.includes("Void");
}

test "raw text and intrinsic host tags cannot leak into HUD from Scene2D" {
	const text = mountError(element(<Void><Scene2D>not a Label</Scene2D></Void>));
	const tag = mountError(element(<Void><Scene2D><div /></Scene2D></Void>));
	const [value, setValue] = createSignal("dynamic raw text");
	const dynamic = mountError(element(<Void><Scene2D>{value()}</Scene2D></Void>));
	assert text.includes("Scene2D") && text.includes("Label");
	assert tag.includes("Scene2D") && tag.includes("div");
	assert dynamic.includes("Scene2D") && dynamic.includes("Label");
	setValue("disposed");
}

test "a foreign scene scope cannot capture the outer raw 2D parent" {
	const error = mountError(element(<Void><Scene2D>
		<Scope.Provider value={VoidSpace.Scene3D}><Group /></Scope.Provider>
	</Scene2D></Void>));
	assert error.includes("Group") && error.includes("Scene2D");
}

test "unmapped nested Void cannot bypass the Scene2D host boundary" {
	const error = mountError(element(<Void><Scene2D><Void><Scene3D>
		<Group />
	</Scene3D></Void></Scene2D></Void>));
	assert error.includes("void") && error.includes("Scene2D");
}

test "unmapped View and Text under Scene2D fail loud instead of mounting on the HUD host" {
	const view = mountError(element(<Void><Scene2D><View /></Scene2D></Void>));
	const text = mountError(element(<Void><Scene2D><Text>not HUD</Text></Scene2D></Void>));
	assert view.includes("View") && view.includes("Scene2D");
	assert text.includes("Text") && text.includes("Scene2D");
}
