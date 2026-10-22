import { createSignal, accessor } from "../../src/core/signal";
import { createRoot } from "../../src/core/owner";
import { createRenderEffect } from "../../src/core/effect";
import { Cleanup } from "../../src/core/types";
import { onCleanup } from "../../src/core/cleanup";
import { resetErrorHalt, flush } from "../../src/core/runtime";
import { element } from "../../src/macros/ui/element";
import { Show } from "../../src/macros/ui/flow";
import { NeonNode } from "../../src/render/node";
import { HostNode, mockNode, mockHost, render } from "../../src/render/host";
import { Void } from "../../src/components/primitives";
import { Scene3D, Scene3DHandle, Gltf, GltfGraph, Group, gltfData } from "../../src/components/scene3d";
import {
	GltfData, GltfAlphaMode, IDENTITY_TEXTURE_TRANSFORM, NO_TEXTURE_INDEX, loadGltfDetailed, describe,
} from "../../../void/src/void3d/gltf";
import { GltfAssets, GltfMaterialSetup, closeGltfAssets } from "../../../void/src/void3d/gltfScene";
import { MeshData } from "../../../void/src/void3d/meshData";
import { Material, Phase } from "../../../void/src/void3d/material";
import { Program } from "../../../void/src/void3d/gpu3d";
import { added, litShape } from "../../../void/src/test/drawHelpers";
import { DrawContext, addMaterial, liveMeshes, liveMaterials, hasMesh, hasMaterial } from "../../../void/src/void3d/draw";
import { Transform3D, NodeId3D, findByName } from "../../../void/src/void3d/scene";
import { vec3 } from "../../../void/src/math/math3d";
import { RenderState } from "../../../void/src/gpu/state";

function model(name: string): GltfData {
	return { meshes: [MeshData.empty()], meshMaterials: [0],
		materials: [{
			texture: NO_TEXTURE_INDEX, doubleSided: false, alphaMode: GltfAlphaMode.Opaque, alphaKill: 0.0,
			emissiveTexture: NO_TEXTURE_INDEX, emissive: vec3(0.0, 0.0, 0.0), emissiveStrength: 1.0,
			normalTexture: NO_TEXTURE_INDEX, uvTransform: IDENTITY_TEXTURE_TRANSFORM,
		}],
		textures: [],
		nodes: [{ name: name, mesh: 0, local: { position: vec3(0.0, 0.0, 0.0),
			rotation: Transform3D.identity().rotation, scale: vec3(1.0, 1.0, 1.0) }, children: [] }],
		sceneRoots: [0] };
}

function groupModel(name: string): GltfData {
	return { meshes: [], meshMaterials: [], materials: [], textures: [],
		nodes: [{ name: name, mesh: -1, local: { position: vec3(0.0, 0.0, 0.0),
			rotation: Transform3D.identity().rotation, scale: vec3(1.0, 1.0, 1.0) }, children: [] }],
		sceneRoots: [0] };
}

// addGltfAssets uploads through sokol, absent from CPU tests, so the caller's assets hold a caller-built mesh.
function callerAssets(context: DrawContext): GltfAssets {
	const mesh = added(context, litShape());
	const material = addMaterial(context, Material.plain(Program.Lit, RenderState.defaults(), Phase.Opaque));
	if (!material.ok) { throw new Error("test: addMaterial failed"); }
	return { context: context, bindings: [{ skinMesh: null, skinMaterial: null, mesh: mesh, material: material.value }],
		meshes: [mesh], materials: [material.value], textures: [], closed: false };
}

function setup(): GltfMaterialSetup {
	return { pass: RenderState.defaults(), block: [0.0, 0.0, 0.0, 0.0] };
}

function mountError(node: NeonNode): string {
	let message = "";
	createRoot((dispose: () => void): void => {
		try {
			node(mockHost(), mockNode("root") as unknown as HostNode, null);
		} catch (error) { message = error.message; } finally { dispose(); resetErrorHalt(); }
	});
	return message;
}

test "three Gltf mounts borrowing one GltfAssets upload once and leave the assets to their owner" {
	let handle: Scene3DHandle = null as unknown as Scene3DHandle;
	let assets: GltfAssets = null as unknown as GltfAssets;
	let baseMeshes: int32 = 0;
	let baseMaterials: int32 = 0;
	const [shown, setShown] = createSignal(true);
	const cleanup = render(element(<Void><Scene3D ref={(value: Scene3DHandle): void => {
		handle = value;
		assets = callerAssets(value.context);
		baseMeshes = value.context.liveMeshes();
		baseMaterials = value.context.liveMaterials();
		onCleanup((): void => { if (!assets.closed) { closeGltfAssets(assets); } });
	}}>
		{Show({ when: accessor(() => shown()), children: element(<Group>
			<Gltf data={model("a")} assets={assets} />
			<Gltf data={model("b")} assets={assets} position={vec3(1.0, 0.0, 0.0)} />
			<Gltf data={model("c")} assets={assets} position={vec3(2.0, 0.0, 0.0)} />
		</Group>) })}
	</Scene3D></Void>), mockHost(), mockNode("root") as unknown as HostNode);
	try {
		const context = handle.context;
		const mesh = assets.meshes[0];
		const material = assets.materials[0];
		assert context.liveMeshes() === baseMeshes && context.liveMaterials() === baseMaterials;
		assert context.meshHolders[mesh.index] === 4 && context.materialHolders[material.index] === 4;
		const root = handle.scene.rootId();
		assert handle.scene.findByName(root, "a").ok && handle.scene.findByName(root, "c").ok;
		setShown(false);
		flush();
		assert context.hasMesh(mesh) && context.hasMaterial(material) && !assets.closed;
		assert context.meshHolders[mesh.index] === 1 && context.materialHolders[material.index] === 1;
		setShown(true);
		flush();
		assert context.liveMeshes() === baseMeshes && context.meshHolders[mesh.index] === 4;
		setShown(false);
		flush();
		assert context.meshHolders[mesh.index] === 1 && context.materialHolders[material.index] === 1;
		closeGltfAssets(assets);
		assert context.liveMeshes() === baseMeshes - 1 && context.liveMaterials() === baseMaterials - 1;
		assert !context.hasMesh(mesh) && !context.hasMaterial(material);
	} finally { cleanup(); }
	assert handle.context.closed;
}

test "Gltf without setup or assets uploads its own with the plain lit setup Mesh uses" {
	let handle: Scene3DHandle = null as unknown as Scene3DHandle;
	const cleanup = render(element(<Void><Scene3D ref={(value: Scene3DHandle): void => { handle = value; }}>
		<Gltf data={groupModel("plain")} />
	</Scene3D></Void>), mockHost(), mockNode("root") as unknown as HostNode);
	try {
		assert handle.scene.findByName(handle.scene.rootId(), "plain").ok;
	} finally { cleanup(); }
	assert handle.context.closed;
}

test "Gltf refuses setup and assets together before any upload" {
	let assets: GltfAssets = null as unknown as GltfAssets;
	let handle: Scene3DHandle = null as unknown as Scene3DHandle;
	const both = mountError(element(<Void><Scene3D ref={(value: Scene3DHandle): void => {
		handle = value;
		assets = callerAssets(value.context);
		onCleanup((): void => { closeGltfAssets(assets); });
	}}><Gltf data={model("a")} setup={setup()} assets={assets} /></Scene3D></Void>));
	assert both === "Gltf: provide setup (Gltf uploads its own assets) or assets (borrowed GltfAssets), not both";
	assert handle.context.closed;
}

test "Gltf graph names the current imported root and finds imported nodes across reloads" {
	const graphs: GltfGraph[] = [];
	const [name, setName] = createSignal("old");
	const cleanup = render(element(<Void><Scene3D>
		<Gltf data={groupModel(name())} setup={setup()} graph={(graph: GltfGraph): void => { graphs.push(graph); }}>
			<Group name={"authored"} />
		</Gltf>
	</Scene3D></Void>), mockHost(), mockNode("root") as unknown as HostNode);
	let roots: NodeId3D[] = [];
	let found: (NodeId3D | null)[] = [];
	const stop = createRoot((dispose: () => void): () => void => {
		createRenderEffect<NodeId3D | null>(
			(prev: NodeId3D | null): NodeId3D | null => graphs[0].find("new"),
			(value: NodeId3D | null, prev: NodeId3D | null): Cleanup | null => {
				roots.push(graphs[0].root());
				found.push(value);
				return null;
			},
		);
		return dispose;
	});
	try {
		assert graphs.length === 1;
		const graph = graphs[0];
		const old = graph.find("old");
		assert old !== null && graph.find("authored") === null && graph.find("missing") === null;
		assert found.length === 1 && found[0] === null;
		const oldRoot = graph.root();
		setName("new");
		flush();
		assert graphs.length === 1 && graph.find("old") === null;
		const fresh = graph.find("new");
		assert fresh !== null && graph.root() !== oldRoot;
		assert found.length === 2 && found[1] !== null && roots[1] === graph.root();
	} finally { stop(); cleanup(); }
	assert graphs[0].find("new") === null;
}

test "Gltf errors carry the decoder diagnostic and the graph check" {
	const loaded = loadGltfDetailed("{", [], "broken.gltf");
	assert !loaded.ok;
	if (loaded.ok) { return; }
	let message = "";
	try { const data = gltfData(loaded); } catch (error) { message = error.message; }
	assert message === "Gltf: " + loaded.error.describe();
	assert message.includes("broken.gltf") && message.includes("BadJson");
	let bad = groupModel("bad");
	bad.sceneRoots = [9];
	const invalid = mountError(element(<Void><Scene3D><Gltf data={bad} setup={setup()} /></Scene3D></Void>));
	assert invalid === "Gltf: addGltfBoundNodes failed: InvalidData (BadNode)";
}

test "Gltf refuses borrowed assets their owner already closed" {
	let assets: GltfAssets = null as unknown as GltfAssets;
	const closed = mountError(element(<Void><Scene3D ref={(value: Scene3DHandle): void => {
		assets = callerAssets(value.context);
		closeGltfAssets(assets);
	}}><Gltf data={model("a")} assets={assets} /></Scene3D></Void>));
	assert closed === "Gltf: borrowed assets were closed by their owner";
}
