import { readFile } from "std/fs";
import { createSignal, accessor } from "../../src/core/signal";
import { onCleanup } from "../../src/core/cleanup";
import { resetErrorHalt, flush } from "../../src/core/runtime";
import { element } from "../../src/macros/ui/element";
import { Show } from "../../src/macros/ui/flow";
import { HostNode, mockNode, mockHost, render } from "../../src/render/host";
import { Void } from "../../src/components/primitives";
import { Scene3D, Scene3DHandle, Gltf, Camera3D } from "../../src/components/scene3d";
import { GltfData, loadGlb } from "../../../void/src/void3d/gltf";
import { GltfMaterialSetup } from "../../../void/src/void3d/gltfScene";
import { NodeId3D, refresh, collectLights, cameraOf } from "../../../void/src/void3d/scene";
import { DrawItem, MeshId, MaterialId, buryDoomed } from "../../../void/src/void3d/draw";
import { TextureId } from "../../../void/src/void3d/texture";
import { resolve, writeCameraBlock } from "../../../void/src/void3d/camera";
import { VERTEX_UNIFORM_LENGTH, LIGHT_UNIFORM_LENGTH } from "../../../void/src/void3d/gpu3d";
import { ForwardRenderer, create, prepareFrame, drawToScreen, closeForward } from "../../../void/src/void3d/forwardRenderer";
import { RenderState } from "../../../void/src/gpu/state";
import { vec3 } from "../../../void/src/math/math3d";
import { gfxSetup, fbWidth, fbHeight } from "../../../void/src/sokol/gpu";
import { beginScreenPass } from "../../../void/src/gpu/target";
import { endPass, commit, contextGeneration, liveBuffers, liveImages, liveViews } from "../../../void/src/gpu/door";

@include("../../../void/src/sokol/bridge.h");
extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;

let handle: Scene3DHandle = null as unknown as Scene3DHandle;
let forward: ForwardRenderer = null as unknown as ForwardRenderer;
let cleanup: (() => void) | null = null;
let frames: int32 = 0;
let baseMeshes: int32 = 0;
let baseMaterials: int32 = 0;
let baseBuffers: int32 = 0;
let baseImages: int32 = 0;
let baseViews: int32 = 0;
const wrappers: NodeId3D[] = [];
let items: Vec<DrawItem> = [];
let cameraBlock: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
let lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
const [replacement, setReplacement] = createSignal(false);
const [bad, setBad] = createSignal(false);
const [shown, setShown] = createSignal(true);
let oldMesh: MeshId = { store: 0, index: 0, generation: 0 };
let oldMaterial: MaterialId = { store: 0, index: 0, generation: 0 };
let oldTexture: TextureId = { store: 0, index: 0, generation: 0 };

function fail(message: string): void {
	console.log("FAIL Gltf device:", message);
	process.exit(1);
}

function decoded(): GltfData {
	const file = readFile("../void/tests/fixtures/gltf/texturedScene.glb");
	if (!file.ok) { fail("fixture read"); unreachable; }
	const bytes: Vec<uint8> = [...file.value.asBytes()];
	const loaded = loadGlb(bytes);
	if (!loaded.ok) { fail("fixture decode"); unreachable; }
	return loaded.value;
}

const fixture = decoded();
function data(): GltfData {
	let value = replacement() ? decoded() : fixture;
	if (bad()) { value.sceneRoots = [999]; }
	return value;
}

function setup(): GltfMaterialSetup {
	return { pass: RenderState.defaults(), block: [4.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0] };
}

function mounted(value: Scene3DHandle): void {
	handle = value;
	const made = ForwardRenderer.create(value.context, { x: 0.02, y: 0.04, z: 0.1, w: 1.0 });
	if (!made.ok) { fail("forward renderer creation"); unreachable; }
	forward = made.value;
	onCleanup((): void => { closeForward(forward); });
	baseMeshes = value.context.liveMeshes();
	baseMaterials = value.context.liveMaterials();
}

function init(): void {
	gfxSetup();
	baseBuffers = liveBuffers(); baseImages = liveImages(); baseViews = liveViews();
	cleanup = render(element(<Void><Scene3D ambient={vec3(1.0, 1.0, 1.0)} ref={mounted}>
		<Camera3D active={true} position={vec3(0.2, 0.0, 7.0)} />
		{Show({ when: accessor(() => shown()), children: element(
			<Gltf data={data()} setup={setup()}
				ref={(node: NodeId3D): void => { wrappers.push(node); }} />
		) })}
	</Scene3D></Void>), mockHost(), mockNode("root") as unknown as HostNode);
}

function frame(): void {
	const context = handle.context;
	if (frames === 4) {
		oldMesh = items[0].mesh; oldMaterial = items[0].material;
		oldTexture = context.materials[oldMaterial.index].texture;
		let message = "";
		try { setBad(true); flush(); } catch (error) { message = error.message; }
		finally { resetErrorHalt(); }
		if (message !== "Gltf: addGltfBoundNodes failed: InvalidData (BadNode)" || !context.hasMesh(oldMesh)) {
			fail("failed import lost prior model"); return;
		}
		setBad(false);
		flush();
	}
	if (frames === 5) {
		oldMesh = items[0].mesh; oldMaterial = items[0].material;
		oldTexture = context.materials[oldMaterial.index].texture;
		setReplacement(true);
		flush();
		if (context.hasMesh(oldMesh) || context.hasMaterial(oldMaterial) || context.hasTexture(oldTexture)) {
			fail("replacement kept retired factory resources live"); return;
		}
	}
	if (frames === 7) { setShown(false); flush(); }
	if (frames === 9) { setShown(true); flush(); }
	const expected: int32 = frames >= 7 && frames < 9 ? 0 : 5;
	if (context.liveMeshes() !== baseMeshes + expected ||
		context.liveMaterials() !== baseMaterials + expected ||
		context.liveTextures() !== (expected === 0 ? 0 : 1)) {
		fail("factory holds or node resource ownership"); return;
	}
	if (refresh(handle.scene, items) !== expected) { fail("scene mesh count"); return; }
	const collected = collectLights(handle.scene, lights);
	if (!collected.ok) { fail("light block"); return; }
	const localCamera = handle.camera;
	if (localCamera === null) { fail("camera mount"); return; }
	const worldCamera = cameraOf(handle.scene, localCamera);
	if (!worldCamera.ok) { fail("camera world pose"); return; }
	const view = worldCamera.value.resolve(fbWidth(), fbHeight());
	if (!view.ok) { fail("camera resolve"); return; }
	view.value.writeCameraBlock(cameraBlock);
	const buried = buryDoomed(context, contextGeneration());
	const prepared = prepareFrame(forward, items, cameraBlock, lights, fbWidth(), fbHeight());
	if (!prepared.ok || prepared.value !== expected) { fail("forward frame"); return; }
	beginScreenPass({ x: 0.02, y: 0.04, z: 0.1, w: 1.0 });
	drawToScreen(forward); endPass(); commit();
	if (expected !== 0 && (liveBuffers() <= baseBuffers || liveImages() <= baseImages)) {
		fail("no live uploaded resources"); return;
	}
	frames += 1;
	if (frames === 12) {
		if (wrappers.length !== 2 || handle.scene.isLive(wrappers[0])) {
			fail("wrapper replacement or remount identity"); return;
		}
		const dispose = cleanup;
		if (dispose !== null) { dispose(); }
		if (!forward.closed || !handle.scene.closed || !context.closed || liveBuffers() !== baseBuffers ||
			liveImages() !== baseImages || liveViews() !== baseViews) {
			fail("terminal GPU resource reclamation"); return;
		}
		console.log("PASS Gltf device: 12 frames, 5 meshes, failure/replacement/remount, closed GPU resources");
		process.exit(0);
	}
}

voidRun(320, 240, init, frame);
