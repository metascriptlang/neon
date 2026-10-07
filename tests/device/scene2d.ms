import { createSignal } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { HostNode, mockNode, mockHost, render } from "../../src/render/host";
import { Void } from "../../src/components/primitives";
import { Scene2D, Rect } from "../../src/components/scene2d";
import { Scene2D as VoidScene2D, NodeRef, local } from "../../../void/src/void2d/node";
import { prepare, drawScreen } from "../../../void/src/void2d/scene";
import { rgba } from "../../../void/src/void2d/types";
import { setup2d, drawCallCount } from "../../../void/src/void2d/draw";
import { gfxSetup, fbWidth, fbHeight, dpiScale } from "../../../void/src/sokol/gpu";
import { beginScreenPass } from "../../../void/src/gpu/target";
import { endPass, commit } from "../../../void/src/gpu/door";

@include("../../../void/src/sokol/bridge.h");
extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;

let subject: VoidScene2D | null = null;
let dispose: (() => void) | null = null;
let frames: int32 = 0;
const nodes: NodeRef[] = [];
const [x, setX] = createSignal<float32>(20.0);

function init(): void {
	gfxSetup(); setup2d();
	const root = mockNode("root");
	dispose = render(element(<Void><Scene2D
		ref={(scene: VoidScene2D): void => { subject = scene; }}>
		<Rect width={32.0} height={32.0} color={rgba(1.0, 0.0, 0.0, 1.0)}
			local={{ x: x(), y: 20.0, scaleX: 1.0, scaleY: 1.0,
				rotation: 0.0, pivotX: 0.0, pivotY: 0.0 }}
			ref={(node: NodeRef): void => { nodes.push(node); }} />
	</Scene2D></Void>), mockHost(), root as unknown as HostNode);
}

function fail(message: string): void {
	console.log("FAIL Scene2D device:", message);
	process.exit(1);
}

function frame(): void {
	const scene = subject;
	if (scene === null) { fail("consumer did not mount"); return; }
	if (frames === 5) { setX(80.0); }
	if (nodes.length !== 1 || nodes[0].local().x !== (frames < 5 ? 20.0 : 80.0)) {
		fail("consumer lost its reactive Rect"); return;
	}
	const dpi: float32 = dpiScale();
	scene.prepare((fbWidth() as float32) / dpi, (fbHeight() as float32) / dpi, dpi);
	beginScreenPass({ x: 0.0, y: 0.0, z: 0.2, w: 1.0 });
	scene.drawScreen(); endPass(); commit();
	if (drawCallCount() !== 1) { fail("Rect did not submit one draw"); return; }
	frames++;
	if (frames === 12) {
		const cleanup = dispose;
		if (cleanup !== null) { cleanup(); }
		if (!scene.closed) { fail("consumer did not close"); return; }
		console.log("PASS Scene2D device: 12 submitted frames, x20→80, one Rect, closed scene");
		process.exit(0);
	}
}

voidRun(192, 128, init, frame);
