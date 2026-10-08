import { createSignal } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { HostNode, mockNode, mockHost, render } from "../../src/render/host";
import { Void } from "../../src/components/primitives";
import { Scene2D, Graphics } from "../../src/components/scene2d";
import { GraphicsOp } from "../../src/render/graphics";
import { Scene2D as VoidScene2D, NodeRef } from "../../../void/src/void2d/node";
import { prepare, drawScreen } from "../../../void/src/void2d/scene";
import { rgba, vec2 } from "../../../void/src/void2d/types";
import { setup2d, drawCallCount, vertexBufferBytes } from "../../../void/src/void2d/draw";
import { gfxSetup, fbWidth, fbHeight, dpiScale } from "../../../void/src/sokol/gpu";
import { beginScreenPass } from "../../../void/src/gpu/target";
import { endPass, commit } from "../../../void/src/gpu/door";

@include("../../../void/src/sokol/bridge.h");
extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;

let subject: VoidScene2D | null = null;
let cleanup: (() => void) | null = null;
let frames: int32 = 0;
const nodes: NodeRef[] = [];
const [changed, setChanged] = createSignal(false);

function operations(): GraphicsOp[] {
	if (changed()) {
		return [{ kind: "fillRoundedRect", x: 80.0, y: 20.0, w: 24.0, h: 24.0,
			radius: 0.0, color: rgba(0.0, 1.0, 0.0, 1.0) }];
	}
	return [{ kind: "fillTriangle", a: vec2(20.0, 20.0), b: vec2(44.0, 20.0),
		c: vec2(20.0, 44.0), color: rgba(1.0, 0.0, 0.0, 1.0) }];
}

function init(): void {
	gfxSetup(); setup2d();
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
	const mesh = scene.meshes[scene.payloads[nodes[0].id.index]];
	if (mesh.mesh.length !== (frames < 5 ? 24 : 48) ||
		mesh.mesh[0] !== (frames < 5 ? 20.0 : 80.0)) {
		fail("reactive geometry replacement"); return;
	}
	const dpi = dpiScale();
	scene.prepare((fbWidth() as float32) / dpi, (fbHeight() as float32) / dpi, dpi);
	beginScreenPass({ x: 0.0, y: 0.0, z: 0.2, w: 1.0 });
	scene.drawScreen(); endPass(); commit();
	if (mesh.stale || mesh.vertexCount !== (frames < 5 ? 3 : 6) ||
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
