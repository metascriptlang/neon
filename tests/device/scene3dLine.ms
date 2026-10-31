// A Line mounts, writes its block each frame, rebinds its mesh and gives everything back on the GPU.
//   msc run tests/device/scene3dLine.ms
// Exits 0 once frames prepared and drew a polyline whose block held the camera's pixel size, near
// and far, new points swapped the mesh and released the old one, width and color reached the block,
// segments re-read the points as pairs, and unmount gave every GPU object back.

import { createSignal, accessor } from "../../src/core/signal";
import { flush } from "../../src/core/runtime";
import { useManualFrames } from "../../src/animation/frame";
import { element } from "../../src/macros/ui/element";
import { Show } from "../../src/macros/ui/flow";
import { Host, HostNode, NeonNode } from "../../src/render/hostTypes";
import { MockNode, mockNode, mockHost, render, mockAreaHub } from "../../src/render/host";
import { Void } from "../../src/components/primitives";
import { Scene3D, Scene3DHandle, Camera3D, Line, viewCamera } from "../../src/components/scene3d";
import { NodeId3D } from "../../../void/src/void3d/scene";
import { vertexCount } from "../../../void/src/void3d/meshData";
import { Program, LINE_WIDTH, LINE_LENGTH_SCALE, LINE_PIXEL_SIZE, LINE_NEAR, LINE_FAR, LINE_COLOR } from "../../../void/src/void3d/gpu3d";
import { MeshId, MaterialId } from "../../../void/src/void3d/draw";
import { Color, rgba } from "../../../void/src/void2d/types";
import { Vec3, vec3 } from "../../../void/src/math/math3d";
import { gfxSetup, fbWidth, fbHeight } from "../../../void/src/host/gpu";
import { beginScreenPass } from "../../../void/src/gpu/target";
import { endPass, commit, liveImages, liveViews } from "../../../void/src/gpu/door";

@include("../../../void/src/host/bridge.h");
extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;

const clock = useManualFrames();
let handle: Scene3DHandle = null as unknown as Scene3DHandle;
let root: MockNode = mockNode("root");
let cleanup: (() => void) | null = null;
let frames: int32 = 0;
let baseImages: int32 = 0;
let baseViews: int32 = 0;
let node: NodeId3D | null = null;
let material: MaterialId | null = null;
let mesh: MeshId | null = null;

function ahead(count: int32): Vec3[] {
	const points: Vec3[] = [];
	for (let i = 0; i < count; i++) { points.push(vec3((i as float32) - 2.0, 0.0, 0.0)); }
	return points;
}

const [points, setPoints] = createSignal<Vec3[]>(ahead(2));
const [width, setWidth] = createSignal<float32>(2.0);
const [color, setColor] = createSignal<Color>(rgba(0.5, 0.25, 0.75, 1.0));
const [pairs, setPairs] = createSignal<boolean>(false);
const [on, setOn] = createSignal<boolean>(true);

function fail(message: string): void {
	console.log("FAIL Scene3D line device:", message);
	process.exit(1);
}

function near(a: float32, b: float32): boolean {
	return Math.abs(a - b) < 0.00001;
}

function value(offset: int32): float32 {
	return handle.context.uniforms.values[handle.context.materials[(material as MaterialId).index].uniforms.offset + offset];
}

function shownMesh(): MeshId {
	return handle.scene.meshes[handle.scene.nodes[(node as NodeId3D).index].payload].mesh;
}

function quads(): int32 {
	return (handle.context.meshData[shownMesh().index].vertexCount() / 4) as int32;
}

const painted: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
	Line({
		points: accessor((): Vec3[] => points()),
		lineWidth: accessor((): float32 => width()),
		color: accessor((): Color => color()),
		segments: accessor((): boolean => pairs()),
		ref: (id: NodeId3D): void => { node = id; },
	})(host, parent, before);
};

function init(): void {
	gfxSetup();
	baseImages = liveImages(); baseViews = liveViews();
	cleanup = render(element(<Void><Scene3D ref={(scene: Scene3DHandle): void => { handle = scene; }}>
		<Camera3D active={true} position={vec3(0.0, 0.0, 5.0)} />
		{Show({ when: accessor(() => on()), children: painted })}
	</Scene3D></Void>), mockHost(), root as unknown as HostNode);
}

function frame(): void {
	clock.advance(16.0);
	const layers = mockAreaHub(root.children[0]).layers();
	if (layers.length !== 1) { fail("one Scene3D layer"); return; }
	layers[0].prepare(fbWidth(), fbHeight());
	beginScreenPass({ x: 0.1, y: 0.1, z: 0.1, w: 1.0 });
	layers[0].draw();
	endPass(); commit();
	const context = handle.context;
	if (frames === 0) {
		const first = handle.scene.meshes[handle.scene.nodes[(node as NodeId3D).index].payload].material;
		material = first;
		mesh = shownMesh();
		if (context.materials[first.index].program.program !== Program.Line) { fail("the line program"); return; }
		const camera = viewCamera(handle);
		if (!camera.ok) { fail("camera"); return; }
		if (quads() !== 1) { fail("one quad for two points"); return; }
		if (!near(value(LINE_WIDTH), 2.0) || !near(value(LINE_LENGTH_SCALE), 1.0)) { fail("width block"); return; }
		if (!near(value(LINE_PIXEL_SIZE), 2.0 / (fbWidth() as float32)) || !near(value(LINE_PIXEL_SIZE + 1), 2.0 / (fbHeight() as float32))) { fail("pixel size block"); return; }
		if (!near(value(LINE_NEAR), camera.value.nearPlane) || !near(value(LINE_FAR), camera.value.farPlane)) { fail("near and far block"); return; }
		if (!near(value(LINE_COLOR), 0.5) || !near(value(LINE_COLOR + 1), 0.25) || !near(value(LINE_COLOR + 2), 0.75) || !near(value(LINE_COLOR + 3), 1.0)) { fail("color block"); return; }
		setPoints(ahead(5)); flush();
	} else if (frames === 1) {
		if (shownMesh() === mesh || context.hasMesh(mesh as MeshId)) { fail("new points swap the mesh and release the old one"); return; }
		if (quads() !== 4) { fail("four quads for five points"); return; }
		mesh = shownMesh();
		setWidth(8.0); setColor(rgba(0.0, 1.0, 0.0, 1.0)); flush();
	} else if (frames === 2) {
		if (!near(value(LINE_WIDTH), 8.0) || !near(value(LINE_COLOR + 1), 1.0) || !near(value(LINE_COLOR), 0.0)) { fail("width and color reach the block"); return; }
		if (shownMesh() !== mesh) { fail("width and color keep the mesh"); return; }
		setPoints(ahead(6)); setPairs(true); flush();
	} else if (frames === 3) {
		if (quads() !== 3) { fail("segments pairs six points into three quads"); return; }
		if (!near(value(LINE_WIDTH), 8.0)) { fail("a new mesh keeps the width"); return; }
		mesh = shownMesh();
		setOn(false); flush();
	} else {
		if (handle.scene.isLive(node as NodeId3D) || context.hasMaterial(material as MaterialId) || context.hasMesh(mesh as MeshId)) {
			fail("unmount removes the node, the material and the mesh"); return;
		}
		const renderer = handle.renderer;
		const dispose = cleanup;
		if (dispose !== null) { dispose(); }
		if (!renderer.closed || !context.closed || liveImages() !== baseImages || liveViews() !== baseViews) {
			fail("GPU objects outlive the Scene3D"); return;
		}
		console.log("PASS Scene3D line device: 5 frames, block values, mesh swaps, segments, unmount, closed GPU resources");
		process.exit(0);
	}
	frames += 1;
}

voidRun(320, 240, init, frame);
