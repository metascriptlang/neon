import { accessor, createSignal } from "../../src/core/signal";
import { flush } from "../../src/core/runtime";
import { sleepAsync } from "std/core/promise";
import { element } from "../../src/macros/ui/element";
import { Show } from "../../src/macros/ui/flow";
import { HostNode, MockNode, mockNode, mockHost, render, mockAreaHub } from "../../src/render/host";
import { NeonEvent, neonEvent, stopPropagation } from "../../src/render/event";
import { AreaLayer, AreaPointerKind } from "../../src/render/voidAreaHandle";
import { Void } from "../../src/components/primitives";
import { Scene3D, Scene3DHandle, Gltf, Pointer3DEvent } from "../../src/components/scene3d";
import { NodeId3D, NodeFlag, Transform3D, addGroup, syncWorld, setLocal } from "../../../void/src/void3d/scene";
import { MeshId, addMaterial } from "../../../void/src/void3d/draw";
import { Material, Phase } from "../../../void/src/void3d/material";
import { Program } from "../../../void/src/void3d/gpu3d";
import { GltfData, GltfAlphaMode, IDENTITY_TEXTURE_TRANSFORM, NO_TEXTURE_INDEX } from "../../../void/src/void3d/gltf";
import { GltfAssets } from "../../../void/src/void3d/gltfScene";
import { RenderState } from "../../../void/src/gpu/state";
import { MeshData, Rgba, addVertex, addTriangle } from "../../../void/src/void3d/meshData";
import { added, litShape } from "../../../void/src/test/drawHelpers";
import { Vec3, vec3 } from "../../../void/src/math/math3d";

type Handler3D = (e: Pointer3DEvent) => void;

const WHITE: Rgba = { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 };
const CENTER: float32 = 100.0;
const OFF: float32 = 10.0;

// A 2x2 square in the z = 0 plane, counter-clockwise seen from the default camera at +z.
function square(): MeshData {
	let data: MeshData = MeshData.empty();
	const facing: Vec3 = vec3(0.0, 0.0, 1.0);
	const a: int32 = try addVertex(data, vec3(-1.0, -1.0, 0.0), facing, WHITE) catch 0;
	const b: int32 = try addVertex(data, vec3(1.0, -1.0, 0.0), facing, WHITE) catch 0;
	const c: int32 = try addVertex(data, vec3(1.0, 1.0, 0.0), facing, WHITE) catch 0;
	const d: int32 = try addVertex(data, vec3(-1.0, 1.0, 0.0), facing, WHITE) catch 0;
	const _t1: int32 = try addTriangle(data, a, b, c) catch 0;
	const _t2: int32 = try addTriangle(data, a, c, d) catch 0;
	return data;
}

// A drawless mesh whose pick data is the square, so picking runs headless.
function squareMesh(handle: Scene3DHandle): MeshId {
	const mesh = added(handle.context, litShape());
	handle.context.meshData[mesh.index] = square();
	return mesh;
}

function pointer(type: string, pressed: boolean, x: float32, y: float32): NeonEvent {
	const e = neonEvent(type);
	e.x = x;
	e.y = y;
	e.button = 1;
	e.pressed = pressed;
	return e;
}

function layerOf(root: MockNode): AreaLayer {
	const hub = mockAreaHub(root.children[0]);
	hub.resize({ pixelWidth: 200, pixelHeight: 200, scale: 1.0 });
	const layers = hub.layers();
	if (layers.length !== 1) { throw new Error("fixture: expected one Scene3D layer, got " + layers.length.toString()); }
	return layers[0];
}

function hits(layer: AreaLayer, x: float32, y: float32, kind: AreaPointerKind, e: NeonEvent): boolean {
	const hit = layer.hit;
	if (hit === null) { throw new Error("the Scene3D layer has no hit hook"); }
	return (hit as (x: float32, y: float32, kind: AreaPointerKind, e: NeonEvent) => boolean)(x, y, kind, e);
}

function down(layer: AreaLayer, x: float32, y: float32): boolean {
	return hits(layer, x, y, AreaPointerKind.Button, pointer("pointerdown", true, x, y));
}

function up(layer: AreaLayer, x: float32, y: float32): boolean {
	return hits(layer, x, y, AreaPointerKind.Button, pointer("pointerup", false, x, y));
}

function hover(layer: AreaLayer, x: float32, y: float32): boolean {
	return hits(layer, x, y, AreaPointerKind.Motion, pointer("pointermove", false, x, y));
}

function tap(layer: AreaLayer, x: float32, y: float32): boolean {
	const took = down(layer, x, y);
	up(layer, x, y);
	return took;
}

function note(log: string[], what: string): Handler3D {
	return (e: Pointer3DEvent): void => { log.push(what); };
}

function sameNode(a: NodeId3D, b: NodeId3D): boolean {
	return a.index == b.index && a.generation == b.generation;
}

function near(a: float32, b: float32): boolean {
	return Math.abs(a - b) < 0.01;
}

function handleOf(refs: Scene3DHandle[]): Scene3DHandle {
	if (refs.length === 0) { throw new Error("fixture: handle ref did not mount"); }
	return refs[0];
}

function model(): GltfData {
	return { meshes: [MeshData.empty()], meshMaterials: [0],
		materials: [{
			texture: NO_TEXTURE_INDEX, doubleSided: false, alphaMode: GltfAlphaMode.Opaque, alphaKill: 0.0,
			emissiveTexture: NO_TEXTURE_INDEX, emissive: vec3(0.0, 0.0, 0.0), emissiveStrength: 1.0,
			normalTexture: NO_TEXTURE_INDEX, uvTransform: IDENTITY_TEXTURE_TRANSFORM,
		}],
		textures: [],
		nodes: [{ name: "plane", mesh: 0, local: { position: vec3(0.0, 0.0, 0.0),
			rotation: Transform3D.identity().rotation, scale: vec3(1.0, 1.0, 1.0) }, children: [] }],
		sceneRoots: [0] };
}

function callerAssets(handle: Scene3DHandle): GltfAssets {
	const mesh = squareMesh(handle);
	const material = addMaterial(handle.context, Material.plain(Program.Lit, RenderState.defaults(), Phase.Opaque));
	if (!material.ok) { throw new Error("fixture: addMaterial failed"); }
	return { context: handle.context, bindings: [{ skinMesh: null, skinMaterial: null, mesh: mesh, material: material.value }],
		meshes: [mesh], materials: [material.value], textures: [], closed: false };
}

test "a press on a glTF mesh reaches the Gltf's onPress with the hit mesh" {
	const refs: Scene3DHandle[] = [];
	const wrappers: NodeId3D[] = [];
	const got: Pointer3DEvent[] = [];
	let assets: GltfAssets = null as unknown as GltfAssets;
	const root = mockNode("root");
	render(element(<Void>
		<Scene3D ref={(value: Scene3DHandle): void => { refs.push(value); assets = callerAssets(value); }}>
			<Gltf data={model()} assets={assets} ref={(node: NodeId3D): void => { wrappers.push(node); }}
				onPress={(e: Pointer3DEvent): void => { got.push(e); }} />
		</Scene3D>
	</Void>), mockHost(), root as unknown as HostNode);
	const handle = handleOf(refs);
	const layer = layerOf(root);
	assert handle.scene.nodes[wrappers[0].index].flags.has(NodeFlag.Pickable), "the wrapper is pickable";
	assert tap(layer, CENTER, CENTER), "the glTF mesh takes the press";
	assert got.length === 1, "one press: " + got.length.toString();
	assert got[0].type === "press" && !sameNode(got[0].node, wrappers[0]), "the event names the hit mesh node, not the wrapper";
	assert near(got[0].point.x, 0.0) && near(got[0].point.y, 0.0), "the world point";
	assert !tap(layer, OFF, OFF), "empty space is not taken";
	assert got.length === 1, "a miss presses nothing";
}
