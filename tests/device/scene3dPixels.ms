// A Scene3D mounted through JSX paints its lit mesh and its background, read back from the Metal window.
//   msc run tests/device/scene3dPixels.ms
// Exits 0 once the corner pixel is the blue clear, the centre pixel is the lit red box, and the centre
// returns to the clear after the box moves off screen and again after it is hidden.

import { createSignal } from "../../src/core/signal";
import { flush } from "../../src/core/runtime";
import { element } from "../../src/macros/ui/element";
import { HostNode, MockNode, mockNode, mockHost, render, mockAreaHub } from "../../src/render/host";
import { Void } from "../../src/components/primitives";
import { Scene3D, Light, Mesh, Camera3D } from "../../src/components/scene3d";
import { LightKind } from "../../../void/src/void3d/scene";
import { MeshData, addBox } from "../../../void/src/void3d/meshData";
import { vec3, quatBetween } from "../../../void/src/math/math3d";
import { gfxSetup, fbWidth, fbHeight } from "../../../void/src/sokol/gpu";
import { beginScreenPass } from "../../../void/src/gpu/target";
import { endPass, commit } from "../../../void/src/gpu/door";
import { voidCaptureBackend, voidCaptureGrab, voidCapturePixel, voidCaptureExit } from "../../../void/tests/capture/capture.h";

@include("../../../void/src/sokol/bridge.h");
extern function voidRunConfigured(
	w: int32, h: int32, sampleCount: int32, highDpi: int32,
	init: () => void, frame: () => void,
): void;

const WIDTH: int32 = 320;
const HEIGHT: int32 = 240;
const METAL_WINDOW_BACKEND: int32 = 5;
const CLEAR_RED: int64 = 26;
const CLEAR_GREEN: int64 = 51;
const CLEAR_BLUE: int64 = 204;
const CLEAR_TOLERANCE: int64 = 3;
const LIT_RED_MIN: int64 = 64;
const HUE_MARGIN: int64 = 32;

let root: MockNode = mockNode("root");
let cleanup: (() => void) | null = null;
let frames: int32 = 0;
const [offsetX, setOffsetX] = createSignal<float32>(0.0);
const [shown, setShown] = createSignal(true);

function fail(message: string): void {
	console.log("FAIL Scene3D pixels device:", message);
	voidCaptureExit(1);
}

function redBox(): MeshData {
	let data = MeshData.empty();
	const made = addBox(data, { base: vec3(0.0, -0.5, 0.0), size: vec3(1.0, 1.0, 1.0), yaw: 0.0, tilt: 0.0,
		color: { red: 0.9, green: 0.1, blue: 0.1, alpha: 1.0 } });
	if (!made.ok) { fail("addBox"); unreachable; }
	return data;
}

const box = redBox();

function channel(pixel: int64, lane: int32): int64 {
	return (pixel >> ((24 - lane * 8) as int64)) & 255;
}

function off(value: int64, want: int64): boolean {
	return value < want - CLEAR_TOLERANCE || value > want + CLEAR_TOLERANCE;
}

function pixelAt(x: int32, y: int32): int64 {
	const pixel = voidCapturePixel(0, x, y);
	if (pixel < 0) { fail(`pixel ${x},${y} outside the capture`); }
	return pixel;
}

function describe(pixel: int64): string {
	return `rgb(${channel(pixel, 0)}, ${channel(pixel, 1)}, ${channel(pixel, 2)})`;
}

function expectClear(x: int32, y: int32, label: string): void {
	const pixel = pixelAt(x, y);
	if (off(channel(pixel, 0), CLEAR_RED) || off(channel(pixel, 1), CLEAR_GREEN) || off(channel(pixel, 2), CLEAR_BLUE)) {
		fail(`${label}: ${describe(pixel)} at ${x},${y}, expected the clear rgb(${CLEAR_RED}, ${CLEAR_GREEN}, ${CLEAR_BLUE})`);
	}
}

function expectLitRed(x: int32, y: int32, label: string): void {
	const pixel = pixelAt(x, y);
	const red = channel(pixel, 0);
	if (red < LIT_RED_MIN || red < channel(pixel, 1) + HUE_MARGIN || red < channel(pixel, 2) + HUE_MARGIN) {
		fail(`${label}: ${describe(pixel)} at ${x},${y}, expected the lit red box`);
	}
}

function init(): void {
	if (voidCaptureBackend() !== METAL_WINDOW_BACKEND) { fail(`readback backend ${voidCaptureBackend()}, expected the Metal window`); }
	gfxSetup();
	cleanup = render(element(<Void><Scene3D ambient={vec3(0.2, 0.2, 0.2)}>
		<Camera3D active={true} position={vec3(0.0, 0.0, 4.0)} />
		<Light kind={LightKind.Directional}
			rotation={quatBetween(vec3(0.0, 0.0, 1.0), vec3(-0.3, -0.4, -1.0).normalized())} />
		<Mesh geometry={box} position={vec3(offsetX(), 0.0, 0.0)} visible={shown()} />
	</Scene3D></Void>), mockHost(), root as unknown as HostNode);
}

function frame(): void {
	if (fbWidth() !== WIDTH || fbHeight() !== HEIGHT) { fail(`framebuffer ${fbWidth()}x${fbHeight()}, asked ${WIDTH}x${HEIGHT}`); }
	const layers = mockAreaHub(root.children[0]).layers();
	if (layers.length !== 1) { fail("one Scene3D layer"); return; }
	layers[0].prepare(WIDTH, HEIGHT);
	beginScreenPass({ x: 0.1, y: 0.2, z: 0.8, w: 1.0 });
	layers[0].draw();
	endPass(); commit();
	if (voidCaptureGrab(0) === 0) { fail(`readback of frame ${frames}`); }
	const cx = WIDTH / 2;
	const cy = HEIGHT / 2;
	if (frames === 1) {
		expectClear(8, 8, "background corner");
		expectLitRed(cx, cy, "box centre");
		setOffsetX(10.0);
		flush();
	}
	if (frames === 2) {
		expectClear(cx, cy, "centre after the box moved off screen");
		setOffsetX(0.0);
		setShown(false);
		flush();
	}
	if (frames === 3) {
		expectClear(cx, cy, "centre after the box was hidden");
		setShown(true);
		flush();
	}
	if (frames === 4) {
		expectLitRed(cx, cy, "box centre shown again");
		const dispose = cleanup;
		if (dispose !== null) { dispose(); }
		console.log("PASS Scene3D pixels device: clear corner, lit red centre, centre clears on move and on hide, red again on show");
		voidCaptureExit(0);
	}
	frames += 1;
}

voidRunConfigured(WIDTH, HEIGHT, 1, 0, init, frame);
