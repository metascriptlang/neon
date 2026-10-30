import { createSignal } from "../../src/core/signal";
import { flush } from "../../src/core/runtime";
import { element } from "../../src/macros/ui/element";
import { HostNode, mockNode, mockHost, render } from "../../src/render/host";
import { Void } from "../../src/components/primitives";
import { Scene2D, Graphics } from "../../src/components/scene2d";
import { GraphicsOp } from "../../src/render/graphics";
import { Scene2D as VoidScene2D, NodeRef, GraphicsMesh } from "../../../void/src/void2d/node";
import { create, prepare, drawScreen } from "../../../void/src/void2d/scene";
import { fillTriangle, fillRoundedRect } from "../../../void/src/void2d/graphics";
import { rgba, vec2 } from "../../../void/src/void2d/types";
import { setup2d, preparePipelines, drawCallCount, vertexBufferBytes } from "../../../void/src/void2d/draw";
import { BlendMode } from "../../../void/src/gpu/state";
import { gfxSetup, fbWidth, fbHeight, dpiScale } from "../../../void/src/host/gpu";
import { beginScreenPass } from "../../../void/src/gpu/target";
import { endPass, commit } from "../../../void/src/gpu/door";

@include("../../../void/src/host/bridge.h");
extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;

let subject: VoidScene2D | null = null;
let cleanup: (() => void) | null = null;
let frames: int32 = 0;
const nodes: NodeRef[] = [];
const [changed, setChanged] = createSignal(false);
const reference: VoidScene2D = VoidScene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
const triangle: GraphicsMesh = meshOf(reference.graphics().fillTriangle(vec2(20.0, 20.0),
	vec2(44.0, 20.0), vec2(20.0, 44.0), rgba(1.0, 0.0, 0.0, 1.0)));
const square: GraphicsMesh = meshOf(reference.graphics().fillRoundedRect(80.0, 20.0, 24.0, 24.0,
	0.0, rgba(0.0, 1.0, 0.0, 1.0)));

function meshOf(node: NodeRef): GraphicsMesh {
	return node.scene.meshes[node.scene.payloads[node.id.index]];
}

function sameMesh(actual: GraphicsMesh, expected: GraphicsMesh): boolean {
	if (actual.mesh.length !== expected.mesh.length) { return false; }
	for (let i: int32 = 0; i < (expected.mesh.length as int32); i++) {
		if (actual.mesh[i] !== expected.mesh[i]) { return false; }
	}
	return true;
}

function operations(): GraphicsOp[] {
	if (changed()) {
		return [{ kind: "fillRoundedRect", x: 80.0, y: 20.0, w: 24.0, h: 24.0,
			radius: 0.0, color: rgba(0.0, 1.0, 0.0, 1.0) }];
	}
	return [{ kind: "fillTriangle", a: vec2(20.0, 20.0), b: vec2(44.0, 20.0),
		c: vec2(20.0, 44.0), color: rgba(1.0, 0.0, 0.0, 1.0) }];
}

function init(): void {
	gfxSetup(); setup2d(); preparePipelines([BlendMode.Alpha]);
	cleanup = render(element(<Void><Scene2D
		ref={(scene: VoidScene2D): void => { subject = scene; }}>
		<Graphics operations={operations()}
			ref={(node: NodeRef): void => { nodes.push(node); }} />
	</Scene2D></Void>), mockHost(), mockNode("root") as unknown as HostNode);
}

function fail(message: string): void {
	console.log("FAIL Graphics device:", message);
	process.exit(1);
}

function frame(): void {
	const scene = subject;
	if (scene === null || nodes.length !== 1) { fail("mount or identity"); return; }
	if (frames === 5) { setChanged(true); }
	flush();
	const mesh = meshOf(nodes[0]);
	const expected = frames < 5 ? triangle : square;
	if (!sameMesh(mesh, expected)) {
		fail("reactive geometry replacement"); return;
	}
	const dpi = dpiScale();
	scene.prepare((fbWidth() as float32) / dpi, (fbHeight() as float32) / dpi, dpi);
	beginScreenPass({ x: 0.0, y: 0.0, z: 0.2, w: 1.0 });
	scene.drawScreen(); endPass(); commit();
	if (mesh.stale || mesh.vertexCount !== (expected.mesh.length as int32) / 8 ||
		drawCallCount() !== 1 || vertexBufferBytes() <= 0) {
		fail("prepared Graphics did not submit exactly one device draw"); return;
	}
	frames += 1;
	if (frames === 12) {
		const dispose = cleanup;
		if (dispose !== null) { dispose(); }
		if (!scene.closed) { fail("terminal scene close"); return; }
		console.log("PASS Graphics device: 12 frames, triangle to rect, one draw, closed scene");
		process.exit(0);
	}
}

voidRun(192, 128, init, frame);
