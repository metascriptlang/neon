// Two PointLights and a pbr Mesh prepare and draw frames on the GPU, and the camera follows its props.
//   msc run tests/device/scene3dClusterView.ms
// Exits 0 once frames prepared and drew with two lights (one under a nested Group), the renderer's
// camera position followed a signal between frames, and unmount gave every GPU object back.

import { createSignal, accessor } from "../../src/core/signal";
import { flush } from "../../src/core/runtime";
import { useManualFrames } from "../../src/animation/frame";
import { element } from "../../src/macros/ui/element";
import { Host } from "../../src/render/hostTypes";
import { HostNode, MockNode, mockNode, mockHost, render, mockAreaHub } from "../../src/render/host";
import { Void } from "../../src/components/primitives";
import { Scene3D, Scene3DHandle, Group, PointLight, Mesh, Camera3D, createMaterial } from "../../src/components/scene3d";
import { MeshData, Rgba, empty, addQuad } from "../../../void/src/void3d/meshData";
import { Vec3, vec3 } from "../../../void/src/math/math3d";
import { gfxSetup, fbWidth, fbHeight } from "../../../void/src/sokol/gpu";
import { beginScreenPass } from "../../../void/src/gpu/target";
import { endPass, commit, liveImages, liveViews } from "../../../void/src/gpu/door";

@include("../../../void/src/sokol/bridge.h");
extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;

const clock = useManualFrames();
let handle: Scene3DHandle = null as unknown as Scene3DHandle;
let root: MockNode = mockNode("root");
let cleanup: (() => void) | null = null;
let frames: int32 = 0;
let baseImages: int32 = 0;
let baseViews: int32 = 0;
const [eye, setEye] = createSignal(vec3(0.0, 1.0, 5.0));

function fail(message: string): void {
	console.log("FAIL Scene3D cluster view device:", message);
	process.exit(1);
}

function floor(): MeshData {
	let data = MeshData.empty();
	const white: Rgba = { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 };
	const added = addQuad(data,
		vec3(-3.0, 0.0, 3.0), vec3(3.0, 0.0, 3.0), vec3(3.0, 0.0, -3.0), vec3(-3.0, 0.0, -3.0),
		vec3(0.0, 1.0, 0.0), white);
	if (!added.ok) { fail("floor"); }
	return data;
}

const ground = floor();

function mount(): void {
	gfxSetup();
	baseImages = liveImages(); baseViews = liveViews();
	const roughness = createMaterialHolder();
	cleanup = render(element(<Void><Scene3D ref={(value: Scene3DHandle): void => { handle = value; }}>
		<Camera3D active={true} position={eye()} />
		<PointLight position={vec3(-2.0, 1.0, 0.0)} radius={5.0} />
		<Group position={vec3(3.0, 0.0, 0.0)}>
			<PointLight position={vec3(0.0, 2.0, 0.0)} radius={4.0} />
		</Group>
		{roughness}
	</Scene3D></Void>), mockHost(), root as unknown as HostNode);
}

function createMaterialHolder(): (host: Host, parent: HostNode, before: HostNode | null) => void {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		const material = createMaterial({ roughness: accessor((): float32 => 0.5) });
		element(<Mesh geometry={ground} material={material()} />)(host, parent, before);
	};
}

function near(a: float32, b: float32): boolean {
	return Math.abs(a - b) < 0.0001;
}

function step(): void {
	clock.advance(16.0);
	const layers = mockAreaHub(root.children[0]).layers();
	if (layers.length !== 1) { fail("one Scene3D layer"); return; }
	layers[0].prepare(fbWidth(), fbHeight());
	beginScreenPass({ x: 0.1, y: 0.1, z: 0.1, w: 1.0 });
	layers[0].draw();
	endPass(); commit();
	const seen = handle.renderer.core.cameraPosition;
	if (seen === null) { fail("no camera position at frame " + frames.toString()); return; }
	const at = seen as Vec3;
	const want = frames < 3 ? vec3(0.0, 1.0, 5.0) : vec3(3.0, 2.0, 7.0);
	if (!near(at.x, want.x) || !near(at.y, want.y) || !near(at.z, want.z)) {
		fail("camera position " + at.x.toString() + "," + at.y.toString() + "," + at.z.toString() + " at frame " + frames.toString());
		return;
	}
	frames += 1;
	if (frames === 3) { setEye(vec3(3.0, 2.0, 7.0)); flush(); }
	if (frames === 6) {
		const renderer = handle.renderer;
		const dispose = cleanup;
		if (dispose !== null) { dispose(); }
		if (!renderer.closed || !handle.context.closed || liveImages() !== baseImages || liveViews() !== baseViews) {
			fail("GPU objects outlive the Scene3D"); return;
		}
		console.log("PASS Scene3D cluster view device: 6 frames, 2 point lights, pbr mesh, camera followed its props, closed GPU resources");
		process.exit(0);
	}
}

function init(): void {
	try { mount(); } catch (error) { fail("mount threw: " + error.message); }
}

function frame(): void {
	try { step(); } catch (error) { fail("frame " + frames.toString() + " threw: " + error.message); }
}

voidRun(320, 240, init, frame);
