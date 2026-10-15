import { accessor, createSignal } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { Show } from "../../src/macros/ui/flow";
import { HostNode, mockNode, mockHost, render } from "../../src/render/host";
import { Void } from "../../src/components/primitives";
import { Scene2D, Graphics } from "../../src/components/scene2d";
import { GraphicsOp } from "../../src/render/graphics";
import { Scene2D as VoidScene2D, NodeRef, isLive } from "../../../void/src/void2d/node";
import { prepare, drawScreen } from "../../../void/src/void2d/scene";
import { rgba, vec2 } from "../../../void/src/void2d/types";
import { GradientSpace } from "../../../void/src/void2d/gradient";
import { GRAPHICS_OP_FLOATS, GFX_OP_MIDDLE, GFX_OP_SPACE, GFX_OP_PARAMS } from "../../../void/src/void2d/graphics";
import { setup2d, drawCallCount, vertexBufferBytes } from "../../../void/src/void2d/draw";
import { gfxSetup, fbWidth, fbHeight, dpiScale } from "../../../void/src/sokol/gpu";
import { beginScreenPass } from "../../../void/src/gpu/target";
import { endPass, commit } from "../../../void/src/gpu/door";

@include("../../../void/src/sokol/bridge.h");
extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;

let scene: VoidScene2D | null = null;
let cleanup: (() => void) | null = null;
let frames: int32 = 0;
const nodes: NodeRef[] = [];
const [changed, setChanged] = createSignal(false);
const [shown, setShown] = createSignal(true);

function operations(): GraphicsOp[] {
	const update = changed();
	const red = rgba(1.0, 0.0, 0.0, 1.0);
	const green = rgba(0.0, 1.0, 0.0, 1.0);
	const blue = rgba(0.0, 0.0, 1.0, 1.0);
	return [
		{ kind: "fillGradientRectStops", x: 20.0, y: 20.0, w: 20.0, h: 20.0,
			c0: red, cMiddle: green, c1: blue, middle: update ? 0.75 : 0.25,
			angle: 0.5, space: update ? GradientSpace.Oklab : GradientSpace.Srgb },
		{ kind: "fillGradientPolygonOklab", points: [vec2(60.0, 20.0), vec2(80.0, 20.0), vec2(60.0, 40.0)],
			c0: green, c1: blue, angle: 0.7 },
		{ kind: "fillRadialGradientOklab", cx: 120.0, cy: 32.0, r: update ? 20.0 : 12.0,
			cInner: red, cOuter: blue },
		{ kind: "fillSlashRect", x: 20.0, y: 70.0, w: 40.0, h: 20.0,
			background: blue, stripe: green, spacing: update ? 11.0 : 7.0, width: 2.0 },
		{ kind: "fillCheckerRect", x: 80.0, y: 70.0, w: 40.0, h: 20.0,
			a: red, b: blue, cell: update ? 8.0 : 4.0 },
	];
}

function init(): void {
	gfxSetup(); setup2d();
	cleanup = render(element(<Void><Scene2D ref={(value: VoidScene2D): void => { scene = value; }}>
		{Show({ when: accessor(() => shown()), children: element(
			<Graphics operations={operations()} ref={(node: NodeRef): void => { nodes.push(node); }} />
		) })}
	</Scene2D></Void>), mockHost(), mockNode("root") as unknown as HostNode);
}

function fail(message: string): void {
	console.log("FAIL Graphics paint device:", message);
	process.exit(1);
}

function frame(): void {
	if (scene === null) { fail("consumer did not mount"); return; }
	if (frames === 5) { setChanged(true); }
	if (frames === 7) { setShown(false); }
	if (frames === 9) { setShown(true); }
	const visible = frames < 7 || frames >= 9;
	if (visible) {
		const node = nodes[nodes.length - 1];
		const mesh = scene.meshes[scene.payloads[node.id.index]];
		if (mesh.records.length !== 5 * GRAPHICS_OP_FLOATS ||
			mesh.records[GFX_OP_MIDDLE] !== (frames < 5 ? 0.25 : 0.75) ||
			mesh.records[GFX_OP_SPACE] !== ((frames < 5 ? GradientSpace.Srgb : GradientSpace.Oklab) as int32) as float32 ||
			mesh.records[3 * GRAPHICS_OP_FLOATS + GFX_OP_PARAMS] !== (frames < 5 ? 7.0 : 11.0) ||
			mesh.records[4 * GRAPHICS_OP_FLOATS + GFX_OP_PARAMS] !== (frames < 5 ? 4.0 : 8.0)) {
			fail("reactive shader records"); return;
		}
		if (mesh.mesh.length !== (frames < 5 ? 504 : 600)) {
			fail("reactive radial geometry"); return;
		}
	}
	const dpi = dpiScale();
	scene.prepare((fbWidth() as float32) / dpi, (fbHeight() as float32) / dpi, dpi);
	beginScreenPass({ x: 0.0, y: 0.0, z: 0.1, w: 1.0 });
	scene.drawScreen(); endPass(); commit();
	if (drawCallCount() !== (visible ? 5 : 0) || (visible && vertexBufferBytes() <= 0)) {
		fail("gradient/pattern device draw ranges"); return;
	}
	frames += 1;
	if (frames === 12) {
		if (nodes.length !== 2 || nodes[0].isLive()) { fail("retained identity/remount"); return; }
		const dispose = cleanup;
		if (dispose !== null) { dispose(); }
		if (!scene.closed || nodes[1].isLive()) { fail("terminal close"); return; }
		console.log("PASS Graphics paint device: 12 frames, 5 shader ranges, reactive records/remount, closed scene");
		process.exit(0);
	}
}

voidRun(192, 128, init, frame);
