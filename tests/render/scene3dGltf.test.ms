import { createSignal, accessor } from "../../src/core/signal";
import { onCleanup } from "../../src/core/cleanup";
import { element } from "../../src/macros/ui/element";
import { Show } from "../../src/macros/ui/flow";
import { HostNode, mockNode, mockHost, render } from "../../src/render/host";
import { Void } from "../../src/components/primitives";
import { Scene3D, Scene3DHandle, Gltf, Group } from "../../src/components/scene3d";
import {
	GltfData, GltfAlphaMode, IDENTITY_TEXTURE_TRANSFORM, NO_TEXTURE_INDEX,
} from "../../../void/src/void3d/gltf";
import {
	GltfMaterialSetup, GltfSceneError, addGltfAssets, closeGltfAssets,
} from "../../../void/src/void3d/gltfScene";
import { DrawContext, closeContext } from "../../../void/src/void3d/draw";
import { MATERIAL_UNIFORM_LENGTH } from "../../../void/src/void3d/gpu3d";
import { ForwardRenderer, create, closeForward } from "../../../void/src/void3d/forwardRenderer";
import { liveRanges, freeRanges } from "../../../void/src/void3d/uniformPool";
import { Transform3D, NodeId3D, findByName } from "../../../void/src/void3d/scene";
import { vec3 } from "../../../void/src/math/math3d";
import { RenderState } from "../../../void/src/gpu/state";

function model(name: string, bad: boolean): GltfData {
	return { meshes: [], meshMaterials: [], materials: [], textures: [],
		nodes: [{ name: name, mesh: -1,
			local: { position: vec3(2.0, 3.0, 4.0),
				rotation: Transform3D.identity().rotation, scale: vec3(2.0, 3.0, 4.0) },
			children: [] }], sceneRoots: [bad ? 9 : 0] };
}

function setup(bad: boolean): GltfMaterialSetup {
	return { pass: RenderState.defaults(), block: bad ? [0.0, 0.0, 0.0] : [0.0, 0.0, 0.0, 0.0] };
}

test "Gltf keeps its wrapper and authored children while imported graphs replace atomically" {
	let handle: Scene3DHandle = null as unknown as Scene3DHandle;
	const wrappers: NodeId3D[] = [];
	const [name, setName] = createSignal("old");
	const [badGraph, setBadGraph] = createSignal(false);
	const [badSetup, setBadSetup] = createSignal(false);
	const [x, setX] = createSignal<float32>(10.0);
	const cleanup = render(element(<Void><Scene3D
		ref={(value: Scene3DHandle): void => { handle = value; }}>
		<Gltf data={model(name(), badGraph())} setup={setup(badSetup())}
			position={vec3(x(), 0.0, 0.0)} name={"wrapper"}
			ref={(node: NodeId3D): void => { wrappers.push(node); }}>
			<Group name={"authored"} />
		</Gltf>
	</Scene3D></Void>), mockHost(), mockNode("root") as unknown as HostNode);
	try {
		const wrapper = wrappers[0];
		const old = handle.scene.findByName(wrapper, "old");
		const authored = handle.scene.findByName(wrapper, "authored");
		assert old.ok && authored.ok;
		if (!old.ok || !authored.ok) { return; }
		const oldId = old.value;
		const authoredId = authored.value;
		assert handle.scene.nodes[wrapper.index].local.position.x === 10.0;
		assert handle.scene.nodes[oldId.index].local.position === vec3(2.0, 3.0, 4.0);
		assert handle.scene.nodes[oldId.index].local.scale === vec3(2.0, 3.0, 4.0);
		let message = "";
		try { setBadGraph(true); } catch (error) { message = error.message; }
		assert message === "Gltf: addGltfNodes failed: InvalidData";
		assert handle.scene.isLive(oldId) && handle.scene.isLive(authoredId);
		assert handle.scene.nodes[wrapper.index].children.length === 2;
		assert handle.scene.nodes[wrapper.index].children[1] === authoredId.index;
		setBadGraph(false);
		const beforeSetupFailure = handle.scene.findByName(wrapper, "old");
		assert beforeSetupFailure.ok;
		if (!beforeSetupFailure.ok) { return; }
		message = "";
		try { setBadSetup(true); } catch (error) { message = error.message; }
		assert message === "Gltf: addGltfAssets failed: BadSetup";
		assert handle.scene.isLive(beforeSetupFailure.value);
		setBadSetup(false);
		const beforeReplacement = handle.scene.findByName(wrapper, "old");
		assert beforeReplacement.ok;
		if (!beforeReplacement.ok) { return; }
		setName("new"); setX(20.0);
		const changed = handle.scene.findByName(wrapper, "new");
		assert changed.ok && !handle.scene.isLive(beforeReplacement.value);
		assert handle.scene.isLive(authoredId) && wrappers.length === 1;
		assert handle.scene.nodes[wrapper.index].children.length === 2;
		assert handle.scene.nodes[wrapper.index].children[1] === authoredId.index;
		assert handle.scene.nodes[wrapper.index].local.position.x === 20.0;
	} finally { cleanup(); }
	assert handle.scene.closed && !handle.scene.isLive(wrappers[0]);
	setName("after-close"); setX(30.0);
	assert wrappers.length === 1;
}

test "Gltf remount owns a fresh wrapper and does not revive removed imported nodes" {
	let handle: Scene3DHandle = null as unknown as Scene3DHandle;
	const wrappers: NodeId3D[] = [];
	const [shown, setShown] = createSignal(true);
	const [name, setName] = createSignal("first");
	const cleanup = render(element(<Void><Scene3D
		ref={(value: Scene3DHandle): void => { handle = value; }}>
		{Show({ when: accessor(() => shown()), children: element(
			<Gltf data={model(name(), false)} setup={setup(false)}
				ref={(node: NodeId3D): void => { wrappers.push(node); }} />
		) })}
	</Scene3D></Void>), mockHost(), mockNode("root") as unknown as HostNode);
	try {
		const imported = handle.scene.findByName(wrappers[0], "first");
		assert imported.ok;
		if (!imported.ok) { return; }
		setShown(false);
		assert !handle.scene.isLive(wrappers[0]) && !handle.scene.isLive(imported.value);
		setName("second"); setShown(true);
		assert wrappers.length === 2 && handle.scene.isLive(wrappers[1]);
		assert !handle.scene.isLive(wrappers[0]);
		assert handle.scene.findByName(wrappers[1], "second").ok;
	} finally { cleanup(); }
	assert handle.scene.closed && !handle.scene.isLive(wrappers[1]);
}

test "Gltf rejects a missing Scene3D scope with its own tag name" {
	let message = "";
	try {
		const cleanup = render(element(<Gltf data={model("root", false)} setup={setup(false)} />),
			mockHost(), mockNode("root") as unknown as HostNode);
		cleanup();
	} catch (error) { message = error.message; }
	assert message === "Gltf: mount inside Scene3D within Void";
}

function materialModel(name: string, badGraph: boolean, count: int32): GltfData {
	let data = model(name, badGraph);
	for (let i = 0; i < count; i++) {
		data.materials.push({
			texture: NO_TEXTURE_INDEX, doubleSided: false, alphaMode: GltfAlphaMode.Opaque, alphaKill: 0.0,
			emissiveTexture: NO_TEXTURE_INDEX, emissive: vec3(0.0, 0.0, 0.0), emissiveStrength: 1.0,
			normalTexture: NO_TEXTURE_INDEX, uvTransform: IDENTITY_TEXTURE_TRANSFORM,
		});
	}
	return data;
}

test "Gltf initial graph/setup failures and terminal disposal close renderer once before context" {
	for (let scenario = 0; scenario < 3; scenario++) {
		const badGraph = scenario === 0;
		const badSetup = scenario === 1;
		const handles: Scene3DHandle[] = [];
		const renderers: ForwardRenderer[] = [];
		let closes: int32 = 0;
		let message = "";
		try {
			const cleanup = render(element(<Void><Scene3D
				ref={(value: Scene3DHandle): void => {
					handles.push(value);
					const made = ForwardRenderer.create(value.context, { x: 0.0, y: 0.0, z: 0.0, w: 1.0 });
					assert made.ok;
					if (!made.ok) { throw new Error("test: ForwardRenderer.create failed"); }
					renderers.push(made.value);
					onCleanup((): void => {
						assert !value.context.closed && !value.scene.closed;
						closeForward(renderers[0]);
						closes += 1;
					});
				}}>
				<Gltf data={materialModel("root", badGraph, 2)} setup={setup(badSetup)} />
			</Scene3D></Void>), mockHost(), mockNode("root") as unknown as HostNode);
			cleanup();
		} catch (error) { message = error.message; }
		const expected = badSetup ? "Gltf: addGltfAssets failed: BadSetup"
			: badGraph ? "Gltf: addGltfNodes failed: InvalidData" : "";
		assert message === expected;
		assert handles.length === 1 && renderers.length === 1 && closes === 1;
		assert renderers[0].closed && renderers[0].core.closed;
		assert handles[0].scene.closed && handles[0].context.closed;
		assert handles[0].context.liveMeshes() === 0 && handles[0].context.liveMaterials() === 0;
		assert handles[0].context.liveTextures() === 0 && handles[0].context.uniforms.liveRanges() === 0;
	}
}

test "Gltf partial factory failure releases real material holds and reuses uniform ranges" {
	const context = DrawContext.withUniformCapacity(2 * MATERIAL_UNIFORM_LENGTH);
	try {
		const refused = addGltfAssets(context, materialModel("root", false, 3), setup(false));
		if (refused.ok) { closeGltfAssets(refused.value); assert false; return; }
		assert refused.error === GltfSceneError.UniformsFull;
		assert context.materialHolders.length === 2;
		assert context.materialHolders[0] === 0 && context.materialHolders[1] === 0;
		assert context.liveMaterials() === 0 && context.liveMeshes() === 0 && context.liveTextures() === 0;
		assert context.uniforms.used === 2 * MATERIAL_UNIFORM_LENGTH;
		assert context.uniforms.liveRanges() === 0 && context.uniforms.freeRanges() === 2;
		const recovered = addGltfAssets(context, materialModel("root", false, 2), setup(false));
		assert recovered.ok;
		if (!recovered.ok) { return; }
		try {
			assert context.liveMaterials() === 2 && context.uniforms.liveRanges() === 2;
			assert context.uniforms.used === 2 * MATERIAL_UNIFORM_LENGTH;
			for (const id of recovered.value.materials) {
				assert context.hasMaterial(id) && context.materialHolders[id.index] === 1;
				assert id.generation === 2;
			}
		} finally { closeGltfAssets(recovered.value); }
		assert context.liveMaterials() === 0 && context.uniforms.liveRanges() === 0;
	} finally { closeContext(context); }
	assert context.closed;
}
