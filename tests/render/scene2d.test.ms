import { accessor, createSignal } from "../../src/core/signal";
import { createRoot } from "../../src/core/owner";
import { resetErrorHalt, flush } from "../../src/core/runtime";
import { element } from "../../src/macros/ui/element";
import { Show } from "../../src/macros/ui/flow";
import {
	HostNode, MockNode, mockNode, mockHost, render, mockToString,
} from "../../src/render/host";
import { NeonNode } from "../../src/render/node";
import { VoidNode } from "../../src/platform/void/host";
import { Void, View, Text, ViewHandle, ElementHandle } from "../../src/components/primitives";
import {
	Scene2D, Group, Rect, Sprite, Mask, Label, TileGroup, ScaleGrid, Underline, Selection,
} from "../../src/components/scene2d";
import { Scene3D } from "../../src/components/scene3d";
import { getVoidScopeContext, VoidSpace } from "../../src/render/voidScope";
import {
	Scene2D as VoidScene2D, NodeRef, NodeId2D, DrawKind, Local2D, nodeCount, kind, local,
	content, text, textStyle, paint, order, filter, colorMatrix, numChildren, parent, isLive,
	TileCell, ALL_TILES,
} from "../../../void/src/void2d/node";
import {
	rgba, whiteTile, camera, glowFilter, Smooth, ScaleMode, Bounds2D, Tile,
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

const Scope = getVoidScopeContext();

function translated(x: float32, y: float32): Local2D {
	return { x: x, y: y, scaleX: 1.0, scaleY: 1.0, rotation: 0.0, pivotX: 0.0, pivotY: 0.0 };
}

function cell(x: float32): TileCell {
	return {
		x: x, y: 0.0, tile: whiteTile(8.0, 8.0), color: rgba(1.0, 1.0, 1.0, 1.0),
		scaleX: 1.0, scaleY: 1.0, rotation: 0.0,
	};
}

function mountError(node: NeonNode): string {
	let message = "";
	createRoot((dispose: () => void): void => {
		try {
			const root = mockNode("root");
			node(mockHost(), root as unknown as HostNode, null);
		} catch (error) { message = error.toString(); } finally { dispose(); resetErrorHalt(); }
	});
	return message;
}

test "Scene2D scale modes and design size react independently and stop at disposal" {
	const firstRefs: VoidScene2D[] = [];
	const secondRefs: VoidScene2D[] = [];
	const [width, setWidth] = createSignal<float32>(200.0);
	const [height, setHeight] = createSignal<float32>(100.0);
	const [mode, setMode] = createSignal<ScaleMode>(ScaleMode.LetterBox);
	const root = mockNode("root");
	const dispose = render(element(<Void>
		<Scene2D scaleMode={mode()} designW={width()} designH={height()}
			ref={(value: VoidScene2D): void => { firstRefs.push(value); }} />
		<Scene2D scaleMode={ScaleMode.Stretch} designW={100.0} designH={100.0}
			ref={(value: VoidScene2D): void => { secondRefs.push(value); }} />
	</Void>), mockHost(), root as unknown as HostNode);
	const first: VoidScene2D | null = firstRefs.length === 0 ? null : firstRefs[0];
	const second: VoidScene2D | null = secondRefs.length === 0 ? null : secondRefs[0];
	if (first === null) { throw new Error("fixture: first ref did not mount"); }
	const letterBox = sceneViewMatrix(first, 800.0, 600.0);
	if (second === null) { throw new Error("fixture: second ref did not mount"); }
	const stretch = sceneViewMatrix(second, 800.0, 600.0);
	assert letterBox.a === 4.0 && letterBox.d === 4.0;
	assert letterBox.tx === 0.0 && letterBox.ty === 100.0;
	assert stretch.a === 8.0 && stretch.d === 6.0;
	setWidth(400.0); setHeight(300.0); setMode(ScaleMode.Stretch);
	flush();
	const changed = sceneViewMatrix(first, 800.0, 600.0);
	assert first.designW === 400.0 && first.designH === 300.0;
	assert changed.a === 2.0 && changed.d === 2.0;
	assert second.designW === 100.0 && second.designH === 100.0;
	assert second.scaleMode === ScaleMode.Stretch;
	setMode(ScaleMode.Resize);
	flush();
	const resized = sceneViewMatrix(first, 800.0, 600.0);
	assert resized.a === 1.0 && resized.d === 1.0;
	dispose();
	setWidth(900.0); setHeight(700.0); setMode(ScaleMode.Fixed);
	flush();
	assert first.closed && second.closed;
	assert first.designW === 400.0 && first.designH === 300.0;
	assert first.scaleMode === ScaleMode.Resize;
}

test "Scene2D Fixed Zoom AutoZoom and omitted design values keep Void semantics" {
	const refs: VoidScene2D[] = [];
	const noDesignRefs: VoidScene2D[] = [];
	const onlyWidthRefs: VoidScene2D[] = [];
	const [mode, setMode] = createSignal<ScaleMode>(ScaleMode.Fixed);
	const root = mockNode("root");
	const dispose = render(element(<Void>
		<Scene2D scaleMode={mode()} designW={400.0} designH={300.0}
			ref={(value: VoidScene2D): void => { refs.push(value); }} />
		<Scene2D scaleMode={ScaleMode.LetterBox}
			ref={(value: VoidScene2D): void => { noDesignRefs.push(value); }} />
		<Scene2D designW={100.0}
			ref={(value: VoidScene2D): void => { onlyWidthRefs.push(value); }} />
	</Void>), mockHost(), root as unknown as HostNode);
	const scene: VoidScene2D | null = refs.length === 0 ? null : refs[0];
	const noDesign: VoidScene2D | null = noDesignRefs.length === 0 ? null : noDesignRefs[0];
	const onlyWidth: VoidScene2D | null = onlyWidthRefs.length === 0 ? null : onlyWidthRefs[0];
	if (scene === null) { throw new Error("fixture: scene ref did not mount"); }
	const fixed = sceneViewMatrix(scene, 900.0, 600.0);
	assert fixed.a === 1.0 && fixed.d === 1.0;
	assert fixed.tx === 250.0 && fixed.ty === 150.0;
	setMode(ScaleMode.Zoom);
	flush();
	const zoom = sceneViewMatrix(scene, 900.0, 600.0);
	assert zoom.a === 2.25 && zoom.d === 2.25;
	assert zoom.tx === 0.0 && zoom.ty === -37.5;
	setMode(ScaleMode.AutoZoom);
	flush();
	const autoZoom = sceneViewMatrix(scene, 900.0, 600.0);
	assert autoZoom.a === 2.0 && autoZoom.d === 2.0;
	assert autoZoom.tx === 50.0 && autoZoom.ty === 0.0;
	if (noDesign === null) { throw new Error("fixture: noDesign ref did not mount"); }
	assert noDesign.designW === 0.0 && noDesign.designH === 0.0;
	if (onlyWidth === null) { throw new Error("fixture: onlyWidth ref did not mount"); }
	assert onlyWidth.scaleMode === ScaleMode.Resize && onlyWidth.designH === 0.0;
	const identity = sceneViewMatrix(noDesign, 900.0, 600.0);
	assert identity.a === 1.0 && identity.d === 1.0;
	dispose();
	setMode(ScaleMode.Fixed);
	flush();
	assert scene.closed && scene.scaleMode === ScaleMode.AutoZoom;
}

test "Rect boxStyle updates its owned payload and reuses it after removal" {
	const refs: VoidScene2D[] = [];
	const nodes: NodeRef[] = [];
	const [radius, setRadius] = createSignal<float32>(4.0);
	const [shown, setShown] = createSignal(true);
	const root = mockNode("root");
	const dispose = render(element(<Void>
		<Scene2D ref={(value: VoidScene2D): void => { refs.push(value); }}>
			{Show({ when: accessor(() => shown()), children: element(
				<Rect width={50.0} height={30.0} color={rgba(1.0, 0.0, 0.0, 1.0)}
					boxStyle={BoxStyle.create(
						uniformRadii(radius()), uniformBorders(2.0), rgba(0.0, 0.0, 1.0, 1.0),
					).dashed().castShadow(rgba(0.0, 0.0, 0.0, 0.5), 3.0, 1.0, 2.0)}
					ref={(value: NodeRef): void => { nodes.push(value); }} />
			) })}
		</Scene2D>
	</Void>), mockHost(), root as unknown as HostNode);
	const scene: VoidScene2D | null = refs.length === 0 ? null : refs[0];
	if (scene === null) { throw new Error("fixture: scene ref did not mount"); }
	const row = scene.payloads[nodes[0].id.index];
	assert row >= 0 && boxStyles[row].radii.topLeft === 4.0;
	assert boxStyles[row].borders.right === 2.0 && boxStyles[row].shadows.length === 1 &&
		boxStyles[row].shadows[0].blur === 3.0;
	setRadius(9.0);
	flush();
	assert scene.payloads[nodes[0].id.index] === row && boxStyles[row].radii.topRight === 9.0;
	setShown(false);
	flush();
	assert !nodes[0].isLive();
	setRadius(2.0); setShown(true);
	flush();
	assert scene.payloads[nodes[1].id.index] === row;
	assert boxStyles[row].radii.bottomLeft === 2.0;
	dispose();
	setRadius(20.0);
	flush();
	assert scene.closed && !nodes[1].isLive();
}

test "Sprite imageStyle and independent fitted size react without replacing its payload" {
	const refs: VoidScene2D[] = [];
	const nodes: NodeRef[] = [];
	const [width, setWidth] = createSignal<float32>(80.0);
	const [tileWidth, setTileWidth] = createSignal<float32>(64.0);
	const [gray, setGray] = createSignal(false);
	const [shown, setShown] = createSignal(true);
	const root = mockNode("root");
	const dispose = render(element(<Void>
		<Scene2D ref={(value: VoidScene2D): void => { refs.push(value); }}>
			{Show({ when: accessor(() => shown()), children: element(
				<Sprite tile={whiteTile(tileWidth(), 32.0)} width={width()} height={80.0}
					imageStyle={imageStyle(uniformRadii(3.0), gray(), ObjectFit.Contain)}
					ref={(value: NodeRef): void => { nodes.push(value); }} />
			) })}
		</Scene2D>
	</Void>), mockHost(), root as unknown as HostNode);
	const scene: VoidScene2D | null = refs.length === 0 ? null : refs[0];
	if (scene === null) { throw new Error("fixture: scene ref did not mount"); }
	const row = scene.payloads[nodes[0].id.index];
	const initial = fitImage(nodes[0].content().tile, 80.0, 80.0, imageStyles[row].fit);
	assert initial.w === 80.0 && initial.h === 40.0 && initial.y === 20.0;
	setWidth(120.0); setGray(true);
	flush();
	assert scene.payloads[nodes[0].id.index] === row && imageStyles[row].grayscale;
	assert nodes[0].content().w === 120.0 && nodes[0].content().h === 80.0;
	setTileWidth(32.0);
	flush();
	assert nodes[0].content().tile.w === 32.0 && nodes[0].content().w === 120.0;
	const fitted = fitImage(nodes[0].content().tile, 120.0, 80.0, imageStyles[row].fit);
	assert fitted.w === 80.0 && fitted.h === 80.0 && fitted.x === 20.0;
	setShown(false);
	flush();
	setWidth(60.0); setGray(false); setShown(true);
	flush();
	assert !nodes[0].isLive() && scene.payloads[nodes[1].id.index] === row;
	assert nodes[1].content().w === 60.0 && !imageStyles[row].grayscale;
	dispose();
	setWidth(200.0); setGray(true); setTileWidth(100.0);
	flush();
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
	flush();
	const filled = fitImage(nodes[0].content().tile, 80.0, 80.0, imageStyles[row].fit);
	assert filled.w === 80.0 && filled.h === 80.0 && filled.u0 === 0.0;
	setFit(ObjectFit.ScaleDown);
	flush();
	const small = fitImage(nodes[0].content().tile, 80.0, 80.0, imageStyles[row].fit);
	assert small.w === 64.0 && small.h === 32.0 && small.x === 8.0 && small.y === 24.0;
	setFit(ObjectFit.None);
	flush();
	const unchanged = fitImage(nodes[0].content().tile, 80.0, 80.0, imageStyles[row].fit);
	assert unchanged.x === 0.0 && unchanged.y === 0.0;
	assert unchanged.w === 64.0 && unchanged.h === 32.0;
	assert nodes[1].content().w === 30.0 && nodes[1].content().h === 12.0;
	setTileHeight(20.0);
	flush();
	assert nodes[1].content().w === 30.0 && nodes[1].content().h === 20.0;
	dispose();
	setFit(ObjectFit.Contain); setTileHeight(40.0);
	flush();
	assert !nodes[0].isLive() && !nodes[1].isLive();
}

test "Mask scroll bounds clamp requested offsets on resize and clear without stale state" {
	const refs: VoidScene2D[] = [];
	const masks: NodeRef[] = [];
	const [width, setWidth] = createSignal<float32>(50.0);
	const [x, setX] = createSignal<float32>(180.0);
	const [y, setY] = createSignal<float32>(120.0);
	const initial: Bounds2D = { xMin: 0.0, yMin: 0.0, xMax: 200.0, yMax: 150.0 };
	const [bounds, setBounds] = createSignal<Bounds2D | null>(initial);
	const [shown, setShown] = createSignal(true);
	const root = mockNode("root");
	const dispose = render(element(<Void>
		<Scene2D ref={(value: VoidScene2D): void => { refs.push(value); }}>
			{Show({ when: accessor(() => shown()), children: element(
				<Mask width={width()} height={40.0} scrollX={x()} scrollY={y()}
					scrollBounds={bounds()}
					ref={(value: NodeRef): void => { masks.push(value); }}>
					<Rect width={200.0} height={150.0} color={rgba(1.0, 1.0, 1.0, 1.0)} />
				</Mask>
			) })}
			<Mask width={10.0} height={10.0} />
		</Scene2D>
	</Void>), mockHost(), root as unknown as HostNode);
	const scene: VoidScene2D | null = refs.length === 0 ? null : refs[0];
	if (scene === null) { throw new Error("fixture: scene ref did not mount"); }
	const row = scene.payloads[masks[0].id.index];
	assert scene.scrolls.length === 1;
	assert masks[0].scroll().bounded;
	assert masks[0].scroll().x === 150.0 && masks[0].scroll().y === 110.0;
	setWidth(100.0);
	flush();
	assert masks[0].scroll().x === 100.0 && masks[0].scroll().y === 110.0;
	setBounds({ xMin: 10.0, yMin: 20.0, xMax: 250.0, yMax: 200.0 });
	flush();
	assert masks[0].scroll().x === 150.0 && masks[0].scroll().y === 120.0;
	setBounds(null);
	flush();
	assert !masks[0].scroll().bounded;
	assert masks[0].scroll().x === 180.0 && masks[0].scroll().y === 120.0;
	setShown(false);
	flush();
	setX(7.0); setY(8.0); setShown(true);
	flush();
	assert !masks[0].isLive() && scene.payloads[masks[1].id.index] === row;
	assert masks[1].scroll().x === 7.0 && masks[1].scroll().y === 8.0;
	dispose();
	setX(9.0); setY(10.0); setWidth(200.0); setBounds(initial);
	flush();
	assert scene.closed && !masks[1].isLive();
}

test "Mask omitted scroll axes retain Void defaults and resized bounds restore requested offsets" {
	const nodes: NodeRef[] = [];
	const [height, setHeight] = createSignal<float32>(20.0);
	const limits: Bounds2D = { xMin: 0.0, yMin: 0.0, xMax: 100.0, yMax: 100.0 };
	const positive: Bounds2D = { xMin: 5.0, yMin: 6.0, xMax: 100.0, yMax: 100.0 };
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene2D>
		<Mask width={10.0} height={height()} scrollY={50.0} scrollBounds={limits}
			ref={(value: NodeRef): void => { nodes.push(value); }} />
		<Mask width={10.0} height={10.0} scrollX={-5.0}
			ref={(value: NodeRef): void => { nodes.push(value); }} />
		<Mask width={10.0} height={10.0} scrollBounds={positive}
			ref={(value: NodeRef): void => { nodes.push(value); }} />
	</Scene2D></Void>), mockHost(), root as unknown as HostNode);
	assert nodes[0].scroll().x === 0.0 && nodes[0].scroll().y === 50.0;
	assert nodes[1].scroll().x === -5.0 && nodes[1].scroll().y === 0.0;
	assert !nodes[1].scroll().bounded;
	assert nodes[2].scroll().x === 5.0 && nodes[2].scroll().y === 6.0;
	setHeight(80.0);
	flush();
	assert nodes[0].scroll().y === 20.0;
	setHeight(10.0);
	flush();
	assert nodes[0].scroll().y === 50.0;
	dispose(); setHeight(90.0);
	flush();
	assert !nodes[0].isLive() && !nodes[1].isLive() && !nodes[2].isLive();
}

test "TileGroup replaces cells and visible range and reuses its owned payload" {
	const refs: VoidScene2D[] = [];
	const nodes: NodeRef[] = [];
	const [cells, setCells] = createSignal<TileCell[]>([cell(0.0), cell(8.0)]);
	const [first, setFirst] = createSignal<int32>(0);
	const [count, setCount] = createSignal<int32>(ALL_TILES);
	const [shown, setShown] = createSignal(true);
	const root = mockNode("root");
	const dispose = render(element(<Void>
		<Scene2D ref={(value: VoidScene2D): void => { refs.push(value); }}>
			<Group local={translated(3.0, 4.0)}>
				{Show({ when: accessor(() => shown()), children: element(
					<TileGroup cells={cells()} first={first()} count={count()}
						ref={(value: NodeRef): void => { nodes.push(value); }} />
				) })}
			</Group>
		</Scene2D>
	</Void>), mockHost(), root as unknown as HostNode);
	const scene: VoidScene2D | null = refs.length === 0 ? null : refs[0];
	if (scene === null) { throw new Error("fixture: scene ref did not mount"); }
	const row = scene.payloads[nodes[0].id.index];
	assert nodes[0].kind() === DrawKind.TileGroup;
	assert scene.tileCells[row].length === 2 && scene.tileGroups[row].count === ALL_TILES;
	setCells([cell(2.0), cell(10.0), cell(18.0)]); setFirst(1); setCount(1);
	flush();
	assert scene.payloads[nodes[0].id.index] === row;
	assert scene.tileCells[row].length === 3 && scene.tileCells[row][1].x === 10.0;
	assert scene.tileGroups[row].first === 1 && scene.tileGroups[row].count === 1;
	setCells([]); setCount(0);
	flush();
	assert scene.tileCells[row].length === 0 && scene.tileGroups[row].count === 0;
	setShown(false);
	flush();
	setCells([cell(7.0)]); setShown(true);
	flush();
	assert !nodes[0].isLive() && scene.payloads[nodes[1].id.index] === row;
	assert scene.tileCells[row].length === 1 && scene.tileCells[row][0].x === 7.0;
	dispose(); setCells([cell(9.0)]); setFirst(0); setCount(ALL_TILES);
	flush();
	assert scene.closed && !nodes[1].isLive();
}

test "TileGroup rejects negative ranges with named errors and cleans failed mounts" {
	const firstRefs: VoidScene2D[] = [];
	const countRefs: VoidScene2D[] = [];
	const badFirst = mountError(element(<Void>
		<Scene2D ref={(value: VoidScene2D): void => { firstRefs.push(value); }}>
			<TileGroup cells={[]} first={-1} />
		</Scene2D>
	</Void>));
	const badCount = mountError(element(<Void>
		<Scene2D ref={(value: VoidScene2D): void => { countRefs.push(value); }}>
			<TileGroup cells={[]} count={-1} />
		</Scene2D>
	</Void>));
	assert badFirst.includes("TileGroup: first/count must be nonnegative");
	assert badCount.includes("TileGroup: first/count must be nonnegative");
	const firstScene: VoidScene2D | null = firstRefs.length === 0 ? null : firstRefs[0];
	const countScene: VoidScene2D | null = countRefs.length === 0 ? null : countRefs[0];
	if (firstScene === null) { throw new Error("fixture: firstScene ref did not mount"); }
	if (countScene === null) { throw new Error("fixture: countScene ref did not mount"); }
	assert firstScene.closed && countScene.closed;
	assert firstScene.nodeCount() === 0 && countScene.nodeCount() === 0;
}

test "TileGroup defaults copy caller cells and preserve the ordinary scene parent guard" {
	const refs: NodeRef[] = [];
	let authored: TileCell[] = [cell(1.0)];
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene2D>
		<TileGroup cells={authored} local={translated(3.0, 4.0)}
			ref={(value: NodeRef): void => { refs.push(value); }} />
	</Scene2D></Void>), mockHost(), root as unknown as HostNode);
	const node: NodeRef | null = refs.length === 0 ? null : refs[0];
	if (node === null) { throw new Error("fixture: node ref did not mount"); }
	const row = node.scene.payloads[node.id.index];
	assert node.scene.tileGroups[row].first === 0;
	assert node.scene.tileGroups[row].count === ALL_TILES;
	assert node.local().x === 3.0 && node.local().y === 4.0;
	authored[0] = cell(99.0);
	assert node.scene.tileCells[row][0].x === 1.0;
	dispose();
	assert !node.isLive();
	const invalid = mountError(element(<TileGroup cells={[]} />));
	assert invalid.includes("TileGroup: mount inside Scene2D within Void");
}

test "ScaleGrid preserves its tile and borders through reactive independent dimensions" {
	const nodes: NodeRef[] = [];
	const [tile, setTile] = createSignal<Tile>(whiteTile(32.0, 16.0));
	const [width, setWidth] = createSignal<float32>(64.0);
	const [border, setBorder] = createSignal<float32>(4.0);
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene2D><Group>
		<ScaleGrid tile={tile()} width={width()}
			borderL={border()} borderT={2.0} borderR={6.0} borderB={3.0}
			ref={(value: NodeRef): void => { nodes.push(value); }} />
		<ScaleGrid tile={tile()} borderL={1.0} borderT={1.0} borderR={1.0} borderB={1.0}
			ref={(value: NodeRef): void => { nodes.push(value); }} />
	</Group></Scene2D></Void>), mockHost(), root as unknown as HostNode);
	assert nodes[0].kind() === DrawKind.ScaleGrid;
	assert nodes[0].content().w === 64.0 && nodes[0].content().h === 16.0;
	assert nodes[0].content().borderL === 4.0 && nodes[0].content().borderR === 6.0;
	assert nodes[0].content().borderT === 2.0 && nodes[0].content().borderB === 3.0;
	setWidth(80.0); setBorder(9.0); setTile(whiteTile(48.0, 24.0));
	flush();
	assert nodes[0].content().w === 80.0 && nodes[0].content().h === 24.0;
	assert nodes[0].content().tile.w === 48.0 && nodes[0].content().tile.h === 24.0;
	assert nodes[0].content().borderL === 9.0 && nodes[0].content().borderR === 6.0;
	assert nodes[1].content().w === 48.0 && nodes[1].content().h === 24.0;
	const firstParent = nodes[0].parent();
	const secondParent = nodes[1].parent();
	assert firstParent !== null && secondParent !== null &&
		firstParent.id.index === secondParent.id.index;
	dispose(); setWidth(20.0); setBorder(1.0); setTile(whiteTile(10.0, 10.0));
	flush();
	assert !nodes[0].isLive() && !nodes[1].isLive();
}

test "ScaleGrid structural remount reads current values and refuses a foreign parent" {
	const nodes: NodeRef[] = [];
	const [shown, setShown] = createSignal(true);
	const [height, setHeight] = createSignal<float32>(40.0);
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene2D>
		{Show({ when: accessor(() => shown()), children: element(
			<ScaleGrid tile={whiteTile(20.0, 10.0)} height={height()}
				borderL={2.0} borderT={1.0} borderR={2.0} borderB={1.0}
				ref={(value: NodeRef): void => { nodes.push(value); }} />
		) })}
	</Scene2D></Void>), mockHost(), root as unknown as HostNode);
	setShown(false);
	flush();
	setHeight(60.0); setShown(true);
	flush();
	assert !nodes[0].isLive() && nodes[1].content().h === 60.0;
	assert nodes[1].content().w === 20.0;
	dispose(); setHeight(80.0);
	flush();
	assert !nodes[1].isLive();
	const invalid = mountError(element(
		<ScaleGrid tile={whiteTile(1.0, 1.0)}
			borderL={0.0} borderT={0.0} borderR={0.0} borderB={0.0} />
	));
	assert invalid.includes("ScaleGrid: mount inside Scene2D within Void");
}

test "Underline maps straight and wavy geometry and reactive color without replacing the node" {
	const refs: NodeRef[] = [];
	const [width, setWidth] = createSignal<float32>(40.0);
	const [thickness, setThickness] = createSignal<float32>(2.0);
	const [wavy, setWavy] = createSignal(true);
	const [red, setRed] = createSignal<float32>(1.0);
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene2D>
		<Underline width={width()} thickness={thickness()} wavy={wavy()}
			color={rgba(red(), 0.0, 0.0, 1.0)}
			ref={(value: NodeRef): void => { refs.push(value); }} />
	</Scene2D></Void>), mockHost(), root as unknown as HostNode);
	const node: NodeRef | null = refs.length === 0 ? null : refs[0];
	if (node === null) { throw new Error("fixture: node ref did not mount"); }
	assert node.kind() === DrawKind.Underline;
	assert node.content().w === 40.0 && node.content().h === 6.0;
	assert node.content().borderL === 2.0 && node.content().borderT === 1.0;
	setWidth(20.0); setThickness(3.0); setWavy(false); setRed(0.5);
	flush();
	assert node.content().w === 20.0 && node.content().h === 3.0;
	assert node.content().borderL === 3.0 && node.content().borderT === 0.0;
	assert node.paint().color.r === 0.5;
	dispose(); setWavy(true); setThickness(8.0); setRed(0.1);
	flush();
	assert !node.isLive();
}

test "Selection maps all neighbor geometry and remount reads current reactive values" {
	const nodes: NodeRef[] = [];
	const [width, setWidth] = createSignal<float32>(40.0);
	const [offset, setOffset] = createSignal<float32>(5.0);
	const [shown, setShown] = createSignal(true);
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene2D><Group>
		{Show({ when: accessor(() => shown()), children: element(
			<Selection width={width()} height={12.0} color={rgba(0.0, 0.0, 1.0, 0.5)}
				prevOffsetX={offset()} prevWidth={30.0}
				nextOffsetX={offset() + 2.0} nextWidth={width() * 0.5}
				ref={(value: NodeRef): void => { nodes.push(value); }} />
		) })}
	</Group></Scene2D></Void>), mockHost(), root as unknown as HostNode);
	assert nodes[0].kind() === DrawKind.Selection;
	assert nodes[0].content().borderL === 5.0 && nodes[0].content().borderT === 30.0;
	assert nodes[0].content().borderR === 7.0 && nodes[0].content().borderB === 20.0;
	setWidth(60.0); setOffset(8.0);
	flush();
	assert nodes[0].content().w === 60.0 && nodes[0].content().h === 12.0;
	assert nodes[0].content().borderL === 8.0 && nodes[0].content().borderR === 10.0;
	assert nodes[0].content().borderB === 30.0;
	setShown(false);
	flush();
	setWidth(80.0); setShown(true);
	flush();
	assert !nodes[0].isLive() && nodes[1].content().w === 80.0;
	assert nodes[1].content().borderB === 40.0;
	dispose(); setWidth(100.0); setOffset(20.0);
	flush();
	assert !nodes[1].isLive();
	assert mountError(element(
		<Underline width={1.0} thickness={1.0} wavy={false} color={rgba(1.0, 1.0, 1.0, 1.0)} />
	)).includes("Underline: mount inside Scene2D within Void");
	assert mountError(element(
		<Selection width={1.0} height={1.0} color={rgba(1.0, 1.0, 1.0, 1.0)}
			prevOffsetX={0.0} prevWidth={0.0} nextOffsetX={0.0} nextWidth={0.0} />
	)).includes("Selection: mount inside Scene2D within Void");
}

test "Scene2D mounts real render nodes without leaking host elements into HUD" {
	const refs: VoidScene2D[] = [];
	const nodes: NodeRef[] = [];
	const root: MockNode = mockNode("root");
	const dispose = render(element(<Void>
		<Scene2D ref={(value: VoidScene2D): void => { refs.push(value); }}>
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
	const scene: VoidScene2D | null = refs.length === 0 ? null : refs[0];
	if (scene === null) { throw new Error("fixture: scene ref did not mount"); }
	assert scene.nodeCount() === 7;
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
	const outer = root.children[0];
	assert root.children.length === 1 && outer.tag === "void" && outer.children.length === 1, "Void is the only host element";
	assert outer.attrs.length > 0, "the scene asks its area for a frame";
	for (const attr of outer.attrs) { assert attr.name === "frameRequested" && attr.value === "true"; }
	assert mockToString(outer.children[0]) === "<voidroot></voidroot>", "Scene2D creates no host elements in the HUD";
	dispose();
	assert scene.closed && scene.nodeCount() === 0;
	assert !nodes[0].isLive() && !nodes[4].isLive();
}

test "Scene2D camera and raw node geometry follow signals and stop on disposal" {
	const refs: VoidScene2D[] = [];
	const nodes: NodeRef[] = [];
	const [x, setX] = createSignal<float32>(2.0);
	const [width, setWidth] = createSignal<float32>(10.0);
	const [zoom, setZoom] = createSignal<float32>(1.0);
	const [label, setLabel] = createSignal("first");
	const root = mockNode("root");
	const dispose = render(element(<Void>
		<Scene2D camera={{ ...camera(), zoom: zoom() }}
			ref={(value: VoidScene2D): void => { refs.push(value); }}>
			<Group local={translated(x(), 3.0)}>
				<Rect width={width()} height={5.0} color={rgba(0.0, 1.0, 0.0, 1.0)}
					ref={(value: NodeRef): void => { nodes.push(value); }} />
				<Label text={label()} size={12.0} color={rgba(1.0, 1.0, 1.0, 1.0)}
					ref={(value: NodeRef): void => { nodes.push(value); }} />
			</Group>
		</Scene2D>
	</Void>), mockHost(), root as unknown as HostNode);
	setX(8.0); setWidth(25.0); setZoom(2.0); setLabel("second");
	flush();
	const group = nodes[0].parent();
	assert group !== null;
	if (group !== null) { assert group.local().x === 8.0 && group.local().y === 3.0; }
	assert nodes[0].content().w === 25.0;
	assert nodes[1].text() === "second";
	const scene: VoidScene2D | null = refs.length === 0 ? null : refs[0];
	if (scene === null) { throw new Error("fixture: scene ref did not mount"); }
	assert scene.cam.zoom === 2.0;
	dispose();
	setX(9.0); setWidth(99.0); setZoom(3.0); setLabel("disposed");
	flush();
	assert scene.closed && scene.nodeCount() === 0;
}

test "Sprite retile and structural removal keep the scene and sibling alive" {
	const refs: VoidScene2D[] = [];
	const nodes: NodeRef[] = [];
	const [size, setSize] = createSignal<float32>(4.0);
	const [shown, setShown] = createSignal(true);
	const root = mockNode("root");
	const dispose = render(element(<Void>
		<Scene2D ref={(value: VoidScene2D): void => { refs.push(value); }}>
			{Show({ when: accessor(() => shown()), children: element(
				<Group ref={(value: NodeRef): void => { nodes.push(value); }}>
					<Sprite tile={whiteTile(size(), size())}
						ref={(value: NodeRef): void => { nodes.push(value); }} />
				</Group>
			) })}
			<Rect width={1.0} height={1.0} color={rgba(1.0, 1.0, 1.0, 1.0)}
				ref={(value: NodeRef): void => { nodes.push(value); }} />
		</Scene2D>
	</Void>), mockHost(), root as unknown as HostNode);
	const scene: VoidScene2D | null = refs.length === 0 ? null : refs[0];
	if (scene === null) { throw new Error("fixture: scene ref did not mount"); }
	assert scene.nodeCount() === 6;
	setSize(11.0);
	flush();
	assert nodes[1].content().tile.w === 11.0 && nodes[1].content().w === 11.0;
	setShown(false);
	flush();
	assert !scene.closed && scene.nodeCount() === 4;
	assert !nodes[0].isLive() && !nodes[1].isLive();
	assert nodes[2].isLive();
	setSize(15.0);
	setShown(true);
	flush();
	const regionHolder = 1;
	assert scene.nodeCount() === 6 + regionHolder && nodes[4].content().w === 15.0;
	dispose();
	assert scene.closed;
}

function nestedShows(outer: () => boolean, inner: () => boolean, refs: VoidScene2D[]): NeonNode {
	return element(<Void>
		<Scene2D ref={(value: VoidScene2D): void => { refs.push(value); }}>
			{Show({ when: accessor(() => outer()), children: element(
				<Group>
					{Show({ when: accessor(() => inner()), children: element(
						<Group><Rect width={1.0} height={1.0} color={rgba(1.0, 1.0, 1.0, 1.0)} /></Group>
					) })}
				</Group>
			) })}
			<Rect width={1.0} height={1.0} color={rgba(1.0, 1.0, 1.0, 1.0)} />
		</Scene2D>
	</Void>);
}

test "a remounted Show keeps one holder node in the scene until its region is disposed" {
	const controlRefs: VoidScene2D[] = [];
	const disposeControl = render(nestedShows((): boolean => false, (): boolean => true, controlRefs), mockHost(), mockNode("root") as unknown as HostNode);
	const withoutOuter = controlRefs[0].nodeCount();
	disposeControl();
	const refs: VoidScene2D[] = [];
	const [outer, setOuter] = createSignal(true);
	const [inner, setInner] = createSignal(true);
	const dispose = render(nestedShows(outer, inner, refs), mockHost(), mockNode("root") as unknown as HostNode);
	const scene = refs[0];
	const mounted = scene.nodeCount();
	setInner(false);
	flush();
	assert scene.nodeCount() === mounted - 2, "hiding frees the inner Group and Rect";
	setInner(true);
	flush();
	assert scene.nodeCount() === mounted + 1, "the later pass built into one holder: " + scene.nodeCount().toString();
	setInner(false);
	flush();
	setInner(true);
	flush();
	assert scene.nodeCount() === mounted + 1, "a second remount reuses that holder: " + scene.nodeCount().toString();
	setOuter(false);
	flush();
	assert scene.nodeCount() === withoutOuter, "disposing the region frees its holder: " + scene.nodeCount().toString();
	dispose();
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
	flush();
	assert nodes[0].order().name === "label" && !nodes[0].order().visible;
	assert nodes[0].filter().radius === 5.0 && nodes[0].textStyle().size === 20.0;
	assert nodes[1].paint().alpha === 0.5;
	assert nodes[1].paint().color.r === 1.0 && nodes[1].paint().color.g === 0.0;
	dispose();
	setAlpha(0.8); setVisible(true); setRadius(9.0); setSize(30.0);
	flush();
	assert !nodes[0].isLive() && !nodes[1].isLive();
}

test "colorMatrix owns its row across paint changes clearing remount and disposal" {
	const refs: VoidScene2D[] = [];
	const nodes: NodeRef[] = [];
	const [amount, setAmount] = createSignal<float32>(1.0);
	const [alpha, setAlpha] = createSignal<float32>(1.0);
	const [shown, setShown] = createSignal(true);
	const root = mockNode("root");
	const dispose = render(element(<Void>
		<Scene2D ref={(value: VoidScene2D): void => { refs.push(value); }}>
			{Show({ when: accessor(() => shown()), children: element(
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
	const scene: VoidScene2D | null = refs.length === 0 ? null : refs[0];
	if (scene === null) { throw new Error("fixture: scene ref did not mount"); }
	assert row >= 0 && scene.colorMatrices.length === 1;
	setAlpha(0.5); setAmount(0.5);
	flush();
	assert nodes[0].paint().colorMatrixRow === row && nodes[0].paint().alpha === 0.5;
	assert nodes[0].colorMatrix() === colorMatrixGrayscale(0.5);
	assert scene.colorMatrices.length === 1;
	setAmount(0.0);
	flush();
	assert nodes[0].colorMatrix() === NO_COLOR_MATRIX;
	assert nodes[0].paint().colorMatrixRow === -1 && scene.freeColorMatrices.length === 1;
	setAlpha(0.8); setAmount(1.0);
	flush();
	assert nodes[0].paint().colorMatrixRow === row && scene.freeColorMatrices.length === 0;
	setShown(false);
	flush();
	assert !nodes[0].isLive() && scene.freeColorMatrices.length === 1;
	setAlpha(0.3); setAmount(0.5); setShown(true);
	flush();
	assert nodes[1].paint().colorMatrixRow === row && nodes[1].paint().alpha === 0.3;
	assert scene.colorMatrices.length === 1;
	dispose();
	setAmount(1.0); setAlpha(0.9);
	flush();
	assert scene.closed && !nodes[1].isLive();
}

test "paint rejects selecting another matrix row and cleans up failed mount" {
	const refs: VoidScene2D[] = [];
	const error = mountError(element(<Void>
		<Scene2D ref={(value: VoidScene2D): void => { refs.push(value); }}>
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
	const scene: VoidScene2D | null = refs.length === 0 ? null : refs[0];
	if (scene === null) { throw new Error("fixture: scene ref did not mount"); }
	assert scene.closed && scene.nodeCount() === 0;
}

test "Scene2D scene values react and a failed child mount closes the scene" {
	const refs: VoidScene2D[] = [];
	const [red, setRed] = createSignal<float32>(0.2);
	const [smooth, setSmooth] = createSignal(true);
	const root = mockNode("root");
	const dispose = render(element(<Void>
		<Scene2D clear={rgba(red(), 0.0, 0.0, 1.0)} smooth={smooth()}
			ref={(value: VoidScene2D): void => { refs.push(value); }} />
	</Void>), mockHost(), root as unknown as HostNode);
	setRed(0.7); setSmooth(false);
	flush();
	let scene: VoidScene2D | null = refs.length === 0 ? null : refs[0];
	if (scene === null) { throw new Error("fixture: scene ref did not mount"); }
	assert scene.clear.r === 0.7 && !scene.defaultSmooth;
	dispose();
	setRed(0.9); setSmooth(true);
	flush();
	assert scene.closed && scene.clear.r === 0.7 && !scene.defaultSmooth;
	const failedChild: NeonNode = (): void => { throw new Error("Scene2D child failure"); };
	const failed = mountError(element(<Void>
		<Scene2D ref={(value: VoidScene2D): void => { refs.push(value); }}>
			<View />{failedChild}
		</Scene2D>
	</Void>));
	scene = refs.length === 0 ? null : refs[refs.length - 1];
	if (scene === null) { throw new Error("fixture: failed scene ref did not mount"); }
	assert failed.includes("Scene2D child failure") && scene.closed && scene.nodeCount() === 0;
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
	flush();
}

test "a foreign scene scope cannot capture the outer raw 2D parent" {
	const error = mountError(element(<Void><Scene2D>
		<Scope.provider value={VoidSpace.Scene3D}><Group /></Scope.provider>
	</Scene2D></Void>));
	assert error.includes("Group") && error.includes("Scene2D");
}

test "unmapped nested Void cannot bypass the Scene2D host boundary" {
	const error = mountError(element(<Void><Scene2D><Void><Scene3D>
		<Group />
	</Scene3D></Void></Scene2D></Void>));
	assert error.includes("void") && error.includes("Scene2D");
}

test "View and Text under Scene2D share its native scene without leaking into HUD" {
	const scenes: VoidScene2D[] = [];
	const ui: VoidNode[] = [];
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene2D
		ref={(scene: VoidScene2D): void => { scenes.push(scene); }}>
		<View ref={(handle: ViewHandle): void => { ui.push(handle.node as VoidNode); }}>
			<Text ref={(handle: ElementHandle): void => { ui.push(handle.node as VoidNode); }}>UI</Text>
		</View>
	</Scene2D></Void>), mockHost(), root);
	assert ui.length === 2 && ui[0].parent === ui[1];
	assert ui[0].ref.scene === scenes[0] && ui[1].ref.scene === scenes[0];
	const outer = root.children[0];
	assert root.children.length === 1 && outer.tag === "void" && outer.children.length === 1, "Void is the only host element";
	assert outer.attrs.length > 0, "the scene asks its area for a frame";
	for (const attr of outer.attrs) { assert attr.name === "frameRequested" && attr.value === "true"; }
	assert mockToString(outer.children[0]) === "<voidroot></voidroot>", "Scene2D creates no host elements in the HUD";
	dispose();
	assert ui[0].disposed && ui[1].disposed && scenes[0].closed;
}
