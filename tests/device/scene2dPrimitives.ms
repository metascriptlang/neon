import { createSignal } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { Show } from "../../src/macros/ui/flow";
import { HostNode, mockNode, mockHost, render } from "../../src/render/host";
import { Void } from "../../src/components/primitives";
import { Scene2D, ScaleGrid, TileGroup, Underline, Selection, Rect, Sprite, Group } from "../../src/components/scene2d";
import { Scene2D as VoidScene2D, NodeRef, TileCell, DrawKind, content, isLive, kind } from "../../../void/src/void2d/node";
import { prepare, drawScreen } from "../../../void/src/void2d/scene";
import { whiteTile, rgba } from "../../../void/src/void2d/types";
import { BoxStyle, create, dashed, castShadow, castInsetShadow, uniformRadii, uniformBorders, boxStyles } from "../../../void/src/void2d/boxStyle";
import { ImageStyle, ObjectFit, imageStyle, imageStyles } from "../../../void/src/void2d/imageStyle";
import { setup2d, drawCallCount, vertexBufferBytes } from "../../../void/src/void2d/draw";
import { gfxSetup, fbWidth, fbHeight, dpiScale } from "../../../void/src/sokol/gpu";
import { beginScreenPass } from "../../../void/src/gpu/target";
import { endPass, commit } from "../../../void/src/gpu/door";

@include("../../../void/src/sokol/bridge.h");
extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;

let scene: VoidScene2D = null as unknown as VoidScene2D;
let cleanup: (() => void) | null = null;
let frames: int32 = 0;
const nodes: NodeRef[] = [];
const [phase, setPhase] = createSignal<int32>(0);
const [changed, setChanged] = createSignal(false);

function capture(node: NodeRef): void { nodes.push(node); }
function cells(): TileCell[] {
	return [
		{ x: 24.0, y: 24.0, tile: whiteTile(12.0, 12.0), color: rgba(1.0, 0.0, 0.0, 1.0),
			scaleX: 1.0, scaleY: 1.0, rotation: 0.0 },
		{ x: 48.0, y: 24.0, tile: whiteTile(12.0, 12.0), color: rgba(0.0, 0.0, 1.0, 1.0),
			scaleX: changed() ? 2.0 : 1.0, scaleY: 1.0, rotation: 0.0 },
	];
}

function styledBox(): BoxStyle {
	const style = BoxStyle.create(uniformRadii(changed() ? 8.0 : 4.0),
		uniformBorders(changed() ? 3.0 : 1.0), rgba(1.0, 0.0, 0.0, 1.0));
	return changed() ? style.dashed().castInsetShadow(rgba(0.0, 0.0, 0.0, 0.8), 3.0) :
		style.castShadow(rgba(0.0, 0.0, 0.0, 0.5), 2.0, 4.0, 4.0);
}

function styledImage(): ImageStyle {
	return imageStyle(uniformRadii(changed() ? 8.0 : 4.0), changed(),
		changed() ? ObjectFit.Cover : ObjectFit.Contain);
}

function init(): void {
	gfxSetup(); setup2d();
	cleanup = render(element(<Void><Scene2D ref={(value: VoidScene2D): void => { scene = value; }}>
		{Show({ when: () => phase() === 0, children: element(
			<ScaleGrid tile={whiteTile(32.0, 32.0)} width={changed() ? 80.0 : 64.0} height={48.0}
				borderL={8.0} borderT={8.0} borderR={8.0} borderB={8.0} ref={capture} />
		) })}
		{Show({ when: () => phase() === 1, children: element(
			<TileGroup cells={cells()} count={changed() ? 2 : 1} ref={capture} />
		) })}
		{Show({ when: () => phase() === 2, children: element(
			<Underline width={changed() ? 48.0 : 32.0} thickness={2.0} wavy={changed()}
				color={rgba(0.0, 1.0, 0.0, 1.0)} ref={capture} />
		) })}
		{Show({ when: () => phase() === 3, children: element(
			<Selection width={changed() ? 48.0 : 32.0} height={14.0}
				color={rgba(0.0, 0.0, 1.0, 0.7)} prevOffsetX={changed() ? 4.0 : 0.0}
				prevWidth={16.0} nextOffsetX={8.0} nextWidth={10.0} ref={capture} />
		) })}
		{Show({ when: () => phase() === 4, children: element(
			<Rect width={64.0} height={48.0} color={rgba(0.0, 1.0, 0.0, 1.0)} boxStyle={styledBox()} ref={capture} />
		) })}
		{Show({ when: () => phase() === 5, children: element(
			<Sprite tile={whiteTile(24.0, 12.0)} width={64.0} height={48.0} imageStyle={styledImage()} ref={capture} />
		) })}
		{Show({ when: () => phase() === 6, children: element(
			<Group width={64.0} height={48.0} background={changed() ? rgba(0.0, 0.0, 1.0, 1.0) : null} ref={capture} />
		) })}
	</Scene2D></Void>), mockHost(), mockNode("root") as unknown as HostNode);
}

function fail(message: string): void {
	console.log("FAIL primitives device:", message);
	process.exit(1);
}

function frame(): void {
	if (frames > 0 && frames % 3 === 0) {
		setPhase(frames / 3); setChanged(false);
	}
	if (frames % 3 === 2) { setChanged(true); }
	if (nodes.length !== phase() + 1) { fail("mount identity"); return; }
	const node = nodes[nodes.length - 1];
	const value = node.content();
	match (phase()) {
		0 => {
			if (value.w !== (changed() ? 80.0 : 64.0) || value.h !== 48.0 || value.borderL !== 8.0) {
				fail("ScaleGrid dimensions/borders"); return;
			}
		}
		1 => {
			const payload = scene.payloads[node.id.index];
			if (scene.tileGroups[payload].count !== (changed() ? 2 : 1) ||
				scene.tileCells[payload].length !== 2 ||
				scene.tileCells[payload][1].scaleX !== (changed() ? 2.0 : 1.0)) {
				fail("TileGroup cells"); return;
			}
		}
		2 => {
			if (value.w !== (changed() ? 48.0 : 32.0) || value.h !== (changed() ? 6.0 : 2.0) ||
				value.borderT !== (changed() ? 1.0 : 0.0)) {
				fail("Underline wave geometry"); return;
			}
		}
		3 => {
			if (value.w !== (changed() ? 48.0 : 32.0) || value.borderL !== (changed() ? 4.0 : 0.0) ||
				value.borderT !== 16.0 || value.borderR !== 8.0 || value.borderB !== 10.0) {
				fail("Selection neighbor geometry"); return;
			}
		}
		4 => {
			const style = boxStyles[scene.payloads[node.id.index]];
			if (style.radii.topLeft !== (changed() ? 8.0 : 4.0) ||
				style.borders.left !== (changed() ? 3.0 : 1.0) || style.shadowInset !== changed()) {
				fail("BoxStyle border/radius/shadow"); return;
			}
		}
		5 => {
			const style = imageStyles[scene.payloads[node.id.index]];
			if (style.radii.topLeft !== (changed() ? 8.0 : 4.0) || style.grayscale !== changed() ||
				style.fit !== (changed() ? ObjectFit.Cover : ObjectFit.Contain)) {
				fail("ImageStyle fit/radius/grayscale"); return;
			}
		}
		6 => {
			if (node.kind() !== (changed() ? DrawKind.Rect : DrawKind.Group)) {
				fail("Group promotion"); return;
			}
		}
		_ => { fail("invalid primitive phase"); return; }
	}
	const dpi = dpiScale();
	scene.prepare((fbWidth() as float32) / dpi, (fbHeight() as float32) / dpi, dpi);
	beginScreenPass({ x: 0.0, y: 0.0, z: 0.1, w: 1.0 });
	scene.drawScreen(); endPass(); commit();
	if ((phase() === 6 && !changed()) ? drawCallCount() !== 0 :
		(drawCallCount() < 1 || vertexBufferBytes() <= 0)) {
		fail("isolated primitive submission"); return;
	}
	for (let i: int32 = 0; i < nodes.length - 1; i++) {
		if (nodes[i].isLive()) { fail("old primitive remains mounted"); return; }
	}
	frames += 1;
	if (frames === 21) {
		const dispose = cleanup;
		if (dispose !== null) { dispose(); }
		if (!scene.closed || node.isLive()) { fail("terminal close"); return; }
		console.log("PASS primitives device: 21 frames, isolated raw primitives/styles/group promotion, reactive, closed scene");
		process.exit(0);
	}
}

voidRun(192, 128, init, frame);
