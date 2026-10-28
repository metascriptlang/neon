import { createSignal, accessor } from "../../src/core/signal";
import { createAsyncMemo } from "../../src/core/memo";
import { Gate, gated, release } from "../core/asyncClock";
import { onCleanup } from "../../src/core/cleanup";
import { resetErrorHalt, flush } from "../../src/core/runtime";
import { element } from "../../src/macros/ui/element";
import { Show, Loading } from "../../src/macros/ui/flow";
import { HostNode, mockNode, mockHost, render } from "../../src/render/host";
import { Host } from "../../src/render/hostTypes";
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

function setup(): GltfMaterialSetup {
	return { pass: RenderState.defaults(), block: [0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0] };
}

test "a Gltf whose data is pending shows the fallback, mounts the model once it settles, and frees it on unmount" {
	let handle: Scene3DHandle = null as unknown as Scene3DHandle;
	const gate = new Gate();
	const runs = [0];
	const root = mockNode("root");
	const cleanup = render(element(<Void><Scene3D
		ref={(value: Scene3DHandle): void => { handle = value; }}>
		{Loading({ fallback: element(<Group name={"fallback"} />), children: (h: Host, p: HostNode, b: HostNode | null): void => {
			const data = createAsyncMemo((prev: GltfData | null): Promise<GltfData> => gated(gate, model("late", false)));
			runs[0] = runs[0] + 1;
			element(<Gltf data={data()} setup={setup()} name={"wrapper"} />)(h, p, b);
		} })}
	</Scene3D></Void>), mockHost(), root as unknown as HostNode);
	flush();
	const top = handle.scene.root;
	assert handle.scene.findByName(handle.scene.nodeIdAt(top), "fallback").ok, "the fallback shows while pending";
	assert !handle.scene.findByName(handle.scene.nodeIdAt(top), "wrapper").ok, "no model while pending";
	await release(gate);
	flush();
	const wrapper = handle.scene.findByName(handle.scene.nodeIdAt(top), "wrapper");
	assert wrapper.ok, "the model mounts once the promise settles";
	if (!wrapper.ok) { return; }
	assert handle.scene.findByName(wrapper.value, "late").ok, "the imported node is under the wrapper";
	assert !handle.scene.findByName(handle.scene.nodeIdAt(top), "fallback").ok, "the fallback is gone";
	assert runs[0] === 1, "the content ran once: " + runs[0].toString();
	cleanup();
	assert !handle.scene.isLive(wrapper.value), "unmount frees the wrapper";
}
