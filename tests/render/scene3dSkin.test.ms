import { accessor } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { HostNode, mockNode, mockHost, render } from "../../src/render/host";
import { Host, NeonNode } from "../../src/render/hostTypes";
import { Void } from "../../src/components/primitives";
import { Scene3D, Scene3DHandle, Clip, GltfMount, GltfScope, gltfScope } from "../../src/components/scene3d";
import { useManualFrames, setFrameDriver, framePending } from "../../src/animation/frame";
import { GltfData, loadGltf } from "../../../void/src/void3d/gltf";
import { addGltfBoundNodes } from "../../../void/src/void3d/gltfScene";
import {
	DrawItem, MeshId, MaterialId, EXTERNAL_GENERATION, meshFor, addMaterial, releaseMesh, releaseMaterial,
} from "../../../void/src/void3d/draw";
import { Material, Phase } from "../../../void/src/void3d/material";
import { Program, ProgramKey, of, withSkin } from "../../../void/src/void3d/gpu3d";
import { RenderState } from "../../../void/src/gpu/state";
import { refreshChecked } from "../../../void/src/void3d/scene";
import { added } from "../../../void/src/test/drawHelpers";

function push32(ref bytes: Vec<uint8>, bits: uint32): void {
	for (let shift = 0; shift < 32; shift += 8) {
		bytes.push(((bits >> (shift as uint32)) & 255) as uint8);
	}
}

// void src/test/gltfSkinCheck.ms payload(false, true): one triangle skinned to joints 2 and 3,
// then a LINEAR clip that slides joint node 2 from x 1 to x 2 over one second.
function payload(): Vec<uint8> {
	let bytes: Vec<uint8> = [];
	for (const bits of [
		0 as uint32, 0 as uint32, 0 as uint32,
		0x3f800000 as uint32, 0 as uint32, 0 as uint32,
		0 as uint32, 0x3f800000 as uint32, 0 as uint32,
		0 as uint32, 0 as uint32, 0x3f800000 as uint32,
		0 as uint32, 0 as uint32, 0x3f800000 as uint32,
		0 as uint32, 0 as uint32, 0x3f800000 as uint32,
	]) { push32(bytes, bits); }
	for (const value of [0, 0, 1, 0, 2, 0, 0, 0]) { bytes.push(value as uint8); }
	for (const joint of [0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0]) { bytes.push(joint as uint8); }
	for (const bits of [
		0x3f800000 as uint32, 0 as uint32, 0 as uint32, 0 as uint32,
		0x3f800000 as uint32, 0 as uint32, 0 as uint32, 0 as uint32,
		0x3e800000 as uint32, 0x3f400000 as uint32, 0 as uint32, 0 as uint32,
	]) { push32(bytes, bits); }
	for (let joint = 0; joint < 2; joint++) {
		for (let cell = 0; cell < 16; cell++) {
			let bits: uint32 = cell % 5 == 0 ? 0x3f800000 as uint32 : 0 as uint32;
			if (cell == 12) { bits = 0xbf800000 as uint32; }
			if (joint == 1 && cell == 13) { bits = 0xc0000000 as uint32; }
			push32(bytes, bits);
		}
	}
	for (const bits of [
		0 as uint32, 0x3f800000 as uint32,
		0x3f800000 as uint32, 0 as uint32, 0 as uint32,
		0x40000000 as uint32, 0 as uint32, 0 as uint32,
	]) { push32(bytes, bits); }
	return move bytes;
}

function document(): string {
	return `{"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[0]}],`
		+ `"buffers":[{"byteLength":300}],"bufferViews":[`
		+ `{"buffer":0,"byteLength":36},`
		+ `{"buffer":0,"byteOffset":36,"byteLength":36},`
		+ `{"buffer":0,"byteOffset":72,"byteLength":6},`
		+ `{"buffer":0,"byteOffset":80,"byteLength":12},`
		+ `{"buffer":0,"byteOffset":92,"byteLength":48},`
		+ `{"buffer":0,"byteOffset":140,"byteLength":128},`
		+ `{"buffer":0,"byteOffset":268,"byteLength":8},`
		+ `{"buffer":0,"byteOffset":276,"byteLength":24}],"accessors":[`
		+ `{"bufferView":0,"componentType":5126,"count":3,"type":"VEC3",`
		+ `"min":[0,0,0],"max":[1,1,0]},`
		+ `{"bufferView":1,"componentType":5126,"count":3,"type":"VEC3"},`
		+ `{"bufferView":2,"componentType":5123,"count":3,"type":"SCALAR"},`
		+ `{"bufferView":3,"componentType":5121,"count":3,"type":"VEC4"},`
		+ `{"bufferView":4,"componentType":5126,"count":3,"type":"VEC4"},`
		+ `{"bufferView":5,"componentType":5126,"count":2,"type":"MAT4"},`
		+ `{"bufferView":6,"componentType":5126,"count":2,"type":"SCALAR","min":[0],"max":[1]},`
		+ `{"bufferView":7,"componentType":5126,"count":2,"type":"VEC3"}],`
		+ `"meshes":[{"primitives":[{"attributes":{`
		+ `"POSITION":0,"NORMAL":1,"JOINTS_0":3,"WEIGHTS_0":4},"indices":2}]}],`
		+ `"nodes":[{"translation":[3,0,0],"children":[1,2]},`
		+ `{"mesh":0,"translation":[100,0,0],"skin":0},`
		+ `{"name":"shoulder","translation":[1,0,0],"children":[3]},{"translation":[0,2,0]}],`
		+ `"skins":[{"joints":[2,3],"skeleton":2,"inverseBindMatrices":5}],`
		+ `"animations":[{"name":"Reach","channels":[{"sampler":0,`
		+ `"target":{"node":2,"path":"translation"}}],`
		+ `"samplers":[{"input":6,"output":7,"interpolation":"LINEAR"}]}]}`;
}

interface Skinned {
	mesh: MeshId;
	material: MaterialId;
}

// Uploading needs a GPU; the bindings borrow an external mesh as gltfSkinCheck does, and the
// mount is provided exactly as Gltf provides it.
function skinnedActor(data: GltfData, handle: Scene3DHandle, held: Skinned[]): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		const source = data.skinMeshes[0];
		if (source === null) { throw new Error("fixture: no skin mesh"); }
		const context = handle.context;
		const mesh = added(context, source.mesh.meshFor(0, 1, EXTERNAL_GENERATION));
		context.meshData[mesh.index] = source.mesh;
		const made = addMaterial(context, Material.plain(Program.Lit, RenderState.defaults(), Phase.Opaque));
		if (!made.ok) { throw new Error("fixture: addMaterial"); }
		context.materials[made.value.index].program = ProgramKey.of(Program.Lit).withSkin();
		held.push({ mesh, material: made.value });
		const mapped = addGltfBoundNodes(handle.scene, handle.scene.rootId(), data, [
			{ mesh, material: made.value, skinMesh: mesh, skinMaterial: made.value },
		]);
		if (!mapped.ok) { throw new Error("fixture: addGltfBoundNodes " + mapped.error.toString()); }
		const instance: GltfMount = { data, root: handle.scene.rootId(), nodes: mapped.value.nodes };
		const provided: GltfScope = { mount: accessor((): GltfMount | null => instance) };
		gltfScope.provider({
			value: accessor(() => provided),
			children: element(<Clip name={"Reach"} loop={false} />),
		})(host, parent, before);
	};
}

test "a Clip drives the joints of a skinned glTF and the next refresh deforms its vertices" {
	const frames = useManualFrames();
	const loaded = loadGltf(document(), payload());
	assert loaded.ok;
	if (!loaded.ok) { return; }
	const data = loaded.value;
	let handle: Scene3DHandle = null as unknown as Scene3DHandle;
	const held: Skinned[] = [];
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene3D ref={(value: Scene3DHandle): void => { handle = value; }}>
		{(host: Host, parent: HostNode, before: HostNode | null): void => {
			skinnedActor(data, handle, held)(host, parent, before);
		}}
	</Scene3D></Void>), mockHost(), root as unknown as HostNode);
	let items: Vec<DrawItem> = [];
	try {
		const geometry = handle.scene.meshes[0].skinGeometry;
		assert geometry !== null;
		if (geometry === null) { return; }
		assert refreshChecked(handle.scene, items).ok;
		const first = geometry.pose.revision;
		assert Math.abs(geometry.mesh.vertices[0] - 3.0) < 0.005, "rest: " + geometry.mesh.vertices[0].toString();
		frames.advance(500);
		assert refreshChecked(handle.scene, items).ok;
		assert geometry.pose.revision > first, "the moved joint re-poses the skin";
		assert Math.abs(geometry.mesh.vertices[0] - 3.5) < 0.005, "half way: " + geometry.mesh.vertices[0].toString();
		frames.advance(600);
		assert refreshChecked(handle.scene, items).ok;
		assert Math.abs(geometry.mesh.vertices[0] - 4.0) < 0.005, "end: " + geometry.mesh.vertices[0].toString();
		assert !framePending(), "the finished one-shot sleeps";
	} finally {
		for (const skinned of held) {
			const mesh = releaseMesh(handle.context, skinned.mesh);
			const material = releaseMaterial(handle.context, skinned.material);
		}
		dispose();
		setFrameDriver(null);
	}
}
