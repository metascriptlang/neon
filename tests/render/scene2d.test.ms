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
import {
	rgba, whiteTile, camera, glowFilter, Smooth, ScaleMode,
} from "../../../void/src/void2d/types";
import { sceneViewMatrix } from "../../../void/src/void2d/scene";
import { BlendMode } from "../../../void/src/gpu/state";
import { colorMatrixGrayscale, NO_COLOR_MATRIX } from "../../../void/src/void2d/effect";
import {
	BoxStyle, create, uniformRadii, uniformBorders, dashed, castShadow, boxStyles,
} from "../../../void/src/void2d/boxStyle";
import {
	imageStyle, imageStyles, ObjectFit, fitImage,
} from "../../../void/src/void2d/imageStyle";

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

test "Scene2D scale modes and design size react independently and stop at disposal" {
	let first: VoidScene2D = null as unknown as VoidScene2D;
	let second: VoidScene2D = null as unknown as VoidScene2D;
	const [width, setWidth] = createSignal<float32>(200.0);
	const [height, setHeight] = createSignal<float32>(100.0);
	const [mode, setMode] = createSignal<ScaleMode>(ScaleMode.LetterBox);
	const root = mockNode("root");
	const dispose = render(element(<Void>
		<Scene2D scaleMode={mode()} designW={width()} designH={height()}
			ref={(value: VoidScene2D): void => { first = value; }} />
		<Scene2D scaleMode={ScaleMode.Stretch} designW={100.0} designH={100.0}
			ref={(value: VoidScene2D): void => { second = value; }} />
	</Void>), mockHost(), root as unknown as HostNode);
	const letterBox = sceneViewMatrix(first, 800.0, 600.0);
	const stretch = sceneViewMatrix(second, 800.0, 600.0);
	assert letterBox.a === 4.0 && letterBox.d === 4.0;
	assert letterBox.tx === 0.0 && letterBox.ty === 100.0;
	assert stretch.a === 8.0 && stretch.d === 6.0;
	setWidth(400.0); setHeight(300.0); setMode(ScaleMode.Stretch);
	const changed = sceneViewMatrix(first, 800.0, 600.0);
	assert first.designW === 400.0 && first.designH === 300.0;
	assert changed.a === 2.0 && changed.d === 2.0;
	assert second.designW === 100.0 && second.designH === 100.0;
	assert second.scaleMode === ScaleMode.Stretch;
	setMode(ScaleMode.Resize);
	const resized = sceneViewMatrix(first, 800.0, 600.0);
	assert resized.a === 1.0 && resized.d === 1.0;
	dispose();
	setWidth(900.0); setHeight(700.0); setMode(ScaleMode.Fixed);
	assert first.closed && second.closed;
	assert first.designW === 400.0 && first.designH === 300.0;
	assert first.scaleMode === ScaleMode.Resize;
}

test "Scene2D Fixed Zoom AutoZoom and omitted design values keep Void semantics" {
	let scene: VoidScene2D = null as unknown as VoidScene2D;
	let noDesign: VoidScene2D = null as unknown as VoidScene2D;
	let onlyWidth: VoidScene2D = null as unknown as VoidScene2D;
	const [mode, setMode] = createSignal<ScaleMode>(ScaleMode.Fixed);
	const root = mockNode("root");
	const dispose = render(element(<Void>
		<Scene2D scaleMode={mode()} designW={400.0} designH={300.0}
			ref={(value: VoidScene2D): void => { scene = value; }} />
		<Scene2D scaleMode={ScaleMode.LetterBox}
			ref={(value: VoidScene2D): void => { noDesign = value; }} />
		<Scene2D designW={100.0}
			ref={(value: VoidScene2D): void => { onlyWidth = value; }} />
	</Void>), mockHost(), root as unknown as HostNode);
	const fixed = sceneViewMatrix(scene, 900.0, 600.0);
	assert fixed.a === 1.0 && fixed.d === 1.0;
	assert fixed.tx === 250.0 && fixed.ty === 150.0;
	setMode(ScaleMode.Zoom);
	const zoom = sceneViewMatrix(scene, 900.0, 600.0);
	assert zoom.a === 2.25 && zoom.d === 2.25;
	assert zoom.tx === 0.0 && zoom.ty === -37.5;
	setMode(ScaleMode.AutoZoom);
	const autoZoom = sceneViewMatrix(scene, 900.0, 600.0);
	assert autoZoom.a === 2.0 && autoZoom.d === 2.0;
	assert autoZoom.tx === 50.0 && autoZoom.ty === 0.0;
	assert noDesign.designW === 0.0 && noDesign.designH === 0.0;
	assert onlyWidth.scaleMode === ScaleMode.Resize && onlyWidth.designH === 0.0;
	const identity = sceneViewMatrix(noDesign, 900.0, 600.0);
	assert identity.a === 1.0 && identity.d === 1.0;
	dispose();
	setMode(ScaleMode.Fixed);
	assert scene.closed && scene.scaleMode === ScaleMode.AutoZoom;
}

test "Rect boxStyle updates its owned payload and reuses it after removal" {
	let scene: VoidScene2D = null as unknown as VoidScene2D;
	const nodes: NodeRef[] = [];
	const [radius, setRadius] = createSignal<float32>(4.0);
	const [shown, setShown] = createSignal(true);
	const root = mockNode("root");
	const dispose = render(element(<Void>
		<Scene2D ref={(value: VoidScene2D): void => { scene = value; }}>
			{Show({ when: () => shown(), children: element(
				<Rect width={50.0} height={30.0} color={rgba(1.0, 0.0, 0.0, 1.0)}
					boxStyle={BoxStyle.create(
						uniformRadii(radius()), uniformBorders(2.0), rgba(0.0, 0.0, 1.0, 1.0),
					).dashed().castShadow(rgba(0.0, 0.0, 0.0, 0.5), 3.0, 1.0, 2.0)}
					ref={(value: NodeRef): void => { nodes.push(value); }} />
			) })}
		</Scene2D>
	</Void>), mockHost(), root as unknown as HostNode);
	const row = scene.payloads[nodes[0].id.index];
	assert row >= 0 && boxStyles[row].radii.topLeft === 4.0;
	assert boxStyles[row].borders.right === 2.0 && boxStyles[row].shadowBlur === 3.0;
	setRadius(9.0);
	assert scene.payloads[nodes[0].id.index] === row && boxStyles[row].radii.topRight === 9.0;
	setShown(false);
	assert !nodes[0].isLive();
	setRadius(2.0); setShown(true);
	assert scene.payloads[nodes[1].id.index] === row;
	assert boxStyles[row].radii.bottomLeft === 2.0;
	dispose();
	setRadius(20.0);
	assert scene.closed && !nodes[1].isLive();
}

test "Sprite imageStyle and independent fitted size react without replacing its payload" {
	let scene: VoidScene2D = null as unknown as VoidScene2D;
	const nodes: NodeRef[] = [];
	const [width, setWidth] = createSignal<float32>(80.0);
	const [tileWidth, setTileWidth] = createSignal<float32>(64.0);
	const [gray, setGray] = createSignal(false);
	const [shown, setShown] = createSignal(true);
	const root = mockNode("root");
	const dispose = render(element(<Void>
		<Scene2D ref={(value: VoidScene2D): void => { scene = value; }}>
			{Show({ when: () => shown(), children: element(
				<Sprite tile={whiteTile(tileWidth(), 32.0)} width={width()} height={80.0}
					imageStyle={imageStyle(uniformRadii(3.0), gray(), ObjectFit.Contain)}
					ref={(value: NodeRef): void => { nodes.push(value); }} />
			) })}
		</Scene2D>
	</Void>), mockHost(), root as unknown as HostNode);
	const row = scene.payloads[nodes[0].id.index];
	const initial = fitImage(nodes[0].content().tile, 80.0, 80.0, imageStyles[row].fit);
	assert initial.w === 80.0 && initial.h === 40.0 && initial.y === 20.0;
	setWidth(120.0); setGray(true);
	assert scene.payloads[nodes[0].id.index] === row && imageStyles[row].grayscale;
	assert nodes[0].content().w === 120.0 && nodes[0].content().h === 80.0;
	setTileWidth(32.0);
	assert nodes[0].content().tile.w === 32.0 && nodes[0].content().w === 120.0;
	const fitted = fitImage(nodes[0].content().tile, 120.0, 80.0, imageStyles[row].fit);
	assert fitted.w === 80.0 && fitted.h === 80.0 && fitted.x === 20.0;
	setShown(false); setWidth(60.0); setGray(false); setShown(true);
	assert !nodes[0].isLive() && scene.payloads[nodes[1].id.index] === row;
	assert nodes[1].content().w === 60.0 && !imageStyles[row].grayscale;
	dispose();
	setWidth(200.0); setGray(true); setTileWidth(100.0);
	assert scene.closed && !nodes[1].isLive();
}

test "Sprite exposes remaining ObjectFit values and partial dimensions follow retile" {
	const nodes: NodeRef[] = [];
	const [fit, setFit] = createSignal<ObjectFit>(ObjectFit.Cover);
	const [tileHeight, setTileHeight] = createSignal<float32>(12.0);
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene2D>
		<Sprite tile={whiteTile(64.0, 32.0)} width={80.0} height={80.0}
			imageStyle={imageStyle(uniformRadii(0.0), false, fit())}
			ref={(value: NodeRef): void => { nodes.push(value); }} />
		<Sprite tile={whiteTile(10.0, tileHeight())} width={30.0}
			ref={(value: NodeRef): void => { nodes.push(value); }} />
	</Scene2D></Void>), mockHost(), root as unknown as HostNode);
	const row = nodes[0].scene.payloads[nodes[0].id.index];
	const covered = fitImage(nodes[0].content().tile, 80.0, 80.0, imageStyles[row].fit);
	assert covered.w === 80.0 && covered.h === 80.0;
	assert covered.u0 === 0.25 && covered.u1 === 0.75;
	setFit(ObjectFit.Fill);
	const filled = fitImage(nodes[0].content().tile, 80.0, 80.0, imageStyles[row].fit);
	assert filled.w === 80.0 && filled.h === 80.0 && filled.u0 === 0.0;
	setFit(ObjectFit.ScaleDown);
	const small = fitImage(nodes[0].content().tile, 80.0, 80.0, imageStyles[row].fit);
	assert small.w === 64.0 && small.h === 32.0 && small.x === 8.0 && small.y === 24.0;
	setFit(ObjectFit.None);
	const unchanged = fitImage(nodes[0].content().tile, 80.0, 80.0, imageStyles[row].fit);
	assert unchanged.x === 0.0 && unchanged.y === 0.0;
	assert unchanged.w === 64.0 && unchanged.h === 32.0;
	assert nodes[1].content().w === 30.0 && nodes[1].content().h === 12.0;
	setTileHeight(20.0);
	assert nodes[1].content().w === 30.0 && nodes[1].content().h === 20.0;
	dispose();
	setFit(ObjectFit.Contain); setTileHeight(40.0);
	assert !nodes[0].isLive() && !nodes[1].isLive();
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
