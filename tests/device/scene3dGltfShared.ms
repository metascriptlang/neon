import { readFileBytes } from "std/fs";
import { createSignal, accessor } from "../../src/core/signal";
import { flush } from "../../src/core/runtime";
import { element } from "../../src/macros/ui/element";
import { Show } from "../../src/macros/ui/flow";
import { HostNode, mockNode, mockHost, render } from "../../src/render/host";
import { Void } from "../../src/components/primitives";
import { Scene3D, Scene3DHandle, Gltf, Group } from "../../src/components/scene3d";
import { GltfData, loadGlb } from "../../../void/src/void3d/gltf";
import { GltfAssets, GltfMaterialSetup, addGltfAssets, closeGltfAssets } from "../../../void/src/void3d/gltfScene";
import { DrawItem, liveMeshes, liveMaterials, hasMesh } from "../../../void/src/void3d/draw";
import { refresh } from "../../../void/src/void3d/scene";
import { RenderState } from "../../../void/src/gpu/state";
import { vec3 } from "../../../void/src/math/math3d";
import { gfxSetup } from "../../../void/src/host/gpu";
import { beginScreenPass } from "../../../void/src/gpu/target";
import { endPass, commit, liveBuffers } from "../../../void/src/gpu/door";

@include("../../../void/src/host/bridge.h");
extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;

let handle: Scene3DHandle = null as unknown as Scene3DHandle;
let assets: GltfAssets = null as unknown as GltfAssets;
let cleanup: (() => void) | null = null;
let frames: int32 = 0;
let baseMeshes: int32 = 0;
let baseMaterials: int32 = 0;
let baseBuffers: int32 = 0;
let uploadedBuffers: int32 = 0;
let items: Vec<DrawItem> = [];
const [shown, setShown] = createSignal(true);

function fail(message: string): void {
	console.log("FAIL Gltf shared device:", message);
	process.exit(1);
}

function decoded(): GltfData {
	const file = readFileBytes("../void/tests/fixtures/gltf/texturedScene.glb");
	if (!file.ok) { fail("fixture read"); unreachable; }
	const bytes: Vec<uint8> = [...file.value];
	const loaded = loadGlb(bytes);
	if (!loaded.ok) { fail("fixture decode"); unreachable; }
	return loaded.value;
}

const fixture = decoded();
const setup: GltfMaterialSetup = { pass: RenderState.defaults(), block: [4.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0] };

function mounted(value: Scene3DHandle): void {
	handle = value;
	baseMeshes = value.context.liveMeshes();
	baseMaterials = value.context.liveMaterials();
	const added = addGltfAssets(value.context, fixture, setup);
	if (!added.ok) { fail("addGltfAssets " + added.error.toString()); unreachable; }
	assets = added.value;
	uploadedBuffers = liveBuffers();
}

function init(): void {
	gfxSetup();
	baseBuffers = liveBuffers();
	cleanup = render(element(<Void><Scene3D ref={mounted}>
		{Show({ when: accessor(() => shown()), children: element(<Group>
			<Gltf data={fixture} assets={assets} />
			<Gltf data={fixture} assets={assets} position={vec3(2.0, 0.0, 0.0)} />
			<Gltf data={fixture} assets={assets} position={vec3(-2.0, 0.0, 0.0)} />
		</Group>) })}
	</Scene3D></Void>), mockHost(), mockNode("root") as unknown as HostNode);
}

function frame(): void {
	const context = handle.context;
	const uploads = assets.meshes.length as int32;
	if (frames === 0) {
		if (uploads !== 5 || context.liveMeshes() !== baseMeshes + uploads
			|| context.liveMaterials() !== baseMaterials + (assets.materials.length as int32)
			|| liveBuffers() !== uploadedBuffers || uploadedBuffers <= baseBuffers) {
			fail("three borrowing Gltf mounts uploaded again"); return;
		}
		if (refresh(handle.scene, items) !== 3 * uploads) { fail("three imported graphs"); return; }
	}
	if (frames === 2) {
		setShown(false);
		flush();
		if (!context.hasMesh(assets.meshes[0]) || context.liveMeshes() !== baseMeshes + uploads) {
			fail("Neon cleanup released borrowed assets"); return;
		}
		closeGltfAssets(assets);
		if (context.liveMeshes() !== baseMeshes || context.liveMaterials() !== baseMaterials) {
			fail("caller close left borrowed holds"); return;
		}
	}
	beginScreenPass({ x: 0.02, y: 0.04, z: 0.1, w: 1.0 });
	endPass(); commit();
	frames += 1;
	if (frames === 4) {
		const dispose = cleanup;
		if (dispose !== null) { dispose(); }
		if (!context.closed || liveBuffers() !== baseBuffers) { fail("terminal GPU resource reclamation"); return; }
		console.log("PASS Gltf shared device: 3 mounts, 5 meshes uploaded once, borrowed holds closed by caller");
		process.exit(0);
	}
}

voidRun(320, 240, init, frame);
