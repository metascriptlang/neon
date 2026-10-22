// A Scene3D layer with hdr, bloom and a directional shadow submits frames on the GPU.
//   msc run tests/device/scene3dLook.ms
// Exits 0 once the layer drew with one caster and bloom mips, dropped the shadow map when
// castShadow turned off, and gave every GPU object back on unmount. Pixels are not checked.

import { createSignal } from "../../src/core/signal";
import { flush } from "../../src/core/runtime";
import { element } from "../../src/macros/ui/element";
import { HostNode, MockNode, mockNode, mockHost, render, mockAreaHub } from "../../src/render/host";
import { Void } from "../../src/components/primitives";
import { Scene3D, Scene3DHandle, Light, Mesh, Camera3D } from "../../src/components/scene3d";
import { LightKind } from "../../../void/src/void3d/scene";
import { MeshData, Rgba, empty, addQuad } from "../../../void/src/void3d/meshData";
import { BloomSettings, natural } from "../../../void/src/void3d/bloom";
import { vec3, quatBetween } from "../../../void/src/math/math3d";
import { gfxSetup, fbWidth, fbHeight } from "../../../void/src/sokol/gpu";
import { beginScreenPass } from "../../../void/src/gpu/target";
import { endPass, commit, liveImages, liveViews } from "../../../void/src/gpu/door";

@include("../../../void/src/sokol/bridge.h");
extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;

let handle: Scene3DHandle = null as unknown as Scene3DHandle;
let root: MockNode = mockNode("root");
let cleanup: (() => void) | null = null;
let frames: int32 = 0;
let baseImages: int32 = 0;
let baseViews: int32 = 0;
const [cast, setCast] = createSignal(true);

function fail(message: string): void {
	console.log("FAIL Scene3D look device:", message);
	process.exit(1);
}

function quad(half: float32, y: float32): MeshData {
	let data = MeshData.empty();
	const white: Rgba = { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 };
	const added = addQuad(data,
		vec3(-half, y, half), vec3(half, y, half), vec3(half, y, -half), vec3(-half, y, -half),
		vec3(0.0, 1.0, 0.0), white);
	if (!added.ok) { fail("quad"); }
	return data;
}

const floor = quad(3.0, 0.0);
const caster = quad(0.8, 1.0);

function init(): void {
	gfxSetup();
	baseImages = liveImages(); baseViews = liveViews();
	cleanup = render(element(<Void><Scene3D hdr={true} bloom={BloomSettings.natural()} exposure={1.5}
		ambient={vec3(0.2, 0.2, 0.2)} ref={(value: Scene3DHandle): void => { handle = value; }}>
		<Camera3D active={true} position={vec3(0.0, 4.0, 6.0)} />
		<Light kind={LightKind.Directional} castShadow={cast()} shadowMapSize={1024}
			rotation={quatBetween(vec3(0.0, 0.0, 1.0), vec3(0.0, -1.0, 0.0))} />
		<Mesh geometry={floor} receiveShadow={true} />
		<Mesh geometry={caster} castShadow={true} />
	</Scene3D></Void>), mockHost(), root as unknown as HostNode);
}

function frame(): void {
	const layers = mockAreaHub(root.children[0]).layers();
	if (layers.length !== 1) { fail("one Scene3D layer"); return; }
	layers[0].prepare(fbWidth(), fbHeight());
	beginScreenPass({ x: 0.1, y: 0.1, z: 0.1, w: 1.0 });
	layers[0].draw();
	endPass(); commit();
	const renderer = handle.renderer;
	const toneMap = renderer.toneMap;
	if (toneMap === null || toneMap.bloom.mips.length === 0) { fail("hdr bloom mips"); return; }
	if (frames < 4) {
		const shadow = renderer.core.shadow;
		if (shadow === null || shadow.casterCount !== 1) { fail("one shadow caster"); return; }
	}
	if (frames === 4) { setCast(false); flush(); }
	if (frames > 4 && renderer.core.shadow !== null) { fail("castShadow off keeps the map"); return; }
	frames += 1;
	if (frames === 8) {
		const dispose = cleanup;
		if (dispose !== null) { dispose(); }
		if (!renderer.closed || !handle.context.closed || liveImages() !== baseImages || liveViews() !== baseViews) {
			fail("GPU objects outlive the Scene3D"); return;
		}
		console.log("PASS Scene3D look device: 8 frames, hdr + bloom, 1 shadow caster, shadow off, closed GPU resources");
		process.exit(0);
	}
}

voidRun(320, 240, init, frame);
