import { accessor, createSignal } from "../../src/core/signal";
import { flush } from "../../src/core/runtime";
import { sleepAsync } from "std/core/promise";
import { element } from "../../src/macros/ui/element";
import { Show } from "../../src/macros/ui/flow";
import { HostNode, MockNode, mockNode, mockHost, render, mockAreaHub } from "../../src/render/host";
import { NeonEvent, neonEvent, stopPropagation } from "../../src/render/event";
import { AreaLayer, AreaPointerKind } from "../../src/render/voidAreaHandle";
import { Void } from "../../src/components/primitives";
import { Scene3D, Scene3DHandle, Group, Mesh, Node, Pointer3DEvent } from "../../src/components/scene3d";
import { NodeId3D, NodeFlag, Transform3D, addGroup, syncWorld, setLocal } from "../../../void/src/void3d/scene";
import { MeshId, NO_MESH } from "../../../void/src/void3d/draw";
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

function wheel(layer: AreaLayer, x: float32, y: float32, dy: number): boolean {
	const e = pointer("wheel", false, x, y);
	e.deltaY = dy;
	return hits(layer, x, y, AreaPointerKind.Wheel, e);
}

test "move reaches the hit mesh and bubbles to a Group, and stopPropagation ends the walk" {
	const refs: Scene3DHandle[] = [];
	const nodes: NodeId3D[] = [];
	const log: string[] = [];
	const got: Pointer3DEvent[] = [];
	let mesh = NO_MESH;
	const root = mockNode("root");
	render(element(<Void>
		<Scene3D ref={(value: Scene3DHandle): void => { refs.push(value); mesh = squareMesh(value); }}>
			<Group onPointerMove={note(log, "group")}>
				<Mesh mesh={mesh} ref={(value: NodeId3D): void => { nodes.push(value); }}
					onPointerMove={(e: Pointer3DEvent): void => { log.push("mesh"); got.push(e); }} />
			</Group>
		</Scene3D>
	</Void>), mockHost(), root as unknown as HostNode);
	const layer = layerOf(root);
	assert hover(layer, CENTER, CENTER), "a mesh with a move handler takes the motion";
	assert log.length === 2 && log[0] === "mesh" && log[1] === "group", "mesh then group: " + log.join(",");
	const e = got[0];
	assert e.type === "pointermove", "type " + e.type;
	assert sameNode(e.node, nodes[0]), "the hit node";
	assert near(e.point.x, 0.0) && near(e.point.y, 0.0), "the world point";
	assert e.distance > 4.0 && e.distance < 5.01, "distance " + e.distance.toString();
	hover(layer, OFF, OFF);
	assert log.length === 2, "a miss moves nothing";
}

test "stopPropagation on a move keeps it from the Group" {
	const refs: Scene3DHandle[] = [];
	const log: string[] = [];
	let mesh = NO_MESH;
	const root = mockNode("root");
	render(element(<Void>
		<Scene3D ref={(value: Scene3DHandle): void => { refs.push(value); mesh = squareMesh(value); }}>
			<Group onPointerMove={note(log, "group")}>
				<Mesh mesh={mesh} onPointerMove={(e: Pointer3DEvent): void => { log.push("mesh"); stopPropagation(e); }} />
			</Group>
		</Scene3D>
	</Void>), mockHost(), root as unknown as HostNode);
	hover(layerOf(root), CENTER, CENTER);
	assert log.length === 1 && log[0] === "mesh", "stopped: " + log.join(",");
}

test "no move handler anywhere means motion does not pick, and a handler turns picking on" {
	const refs: Scene3DHandle[] = [];
	const nodes: NodeId3D[] = [];
	const [listening, setListening] = createSignal(false);
	let mesh = NO_MESH;
	const root = mockNode("root");
	render(element(<Void>
		<Scene3D ref={(value: Scene3DHandle): void => { refs.push(value); mesh = squareMesh(value); }}>
			<Mesh mesh={mesh} ref={(value: NodeId3D): void => { nodes.push(value); }} />
			{Show({ when: accessor(() => listening()), children: element(
				<Mesh mesh={mesh} position={vec3(5.0, 0.0, 0.0)} onPointerMove={(e: Pointer3DEvent): void => {}} />
			) })}
		</Scene3D>
	</Void>), mockHost(), root as unknown as HostNode);
	const handle = handleOf(refs);
	const layer = layerOf(root);
	const moved = (): void => {
		let t = Transform3D.identity();
		t.position = vec3(0.0, 0.1, 0.0);
		setLocal(handle.scene, nodes[0], t);
	};
	syncWorld(handle.scene);
	moved();
	assert !hover(layer, CENTER, CENTER);
	assert syncWorld(handle.scene) > 0, "no handler: no pick, so the world was not synced";
	setListening(true);
	flush();
	syncWorld(handle.scene);
	moved();
	hover(layer, CENTER, CENTER);
	assert syncWorld(handle.scene) === 0, "a move handler makes motion pick";
	setListening(false);
	flush();
	syncWorld(handle.scene);
	moved();
	hover(layer, CENTER, CENTER);
	assert syncWorld(handle.scene) > 0, "the removed handler stops the picking";
}

test "a removed move handler stops delivery" {
	const refs: Scene3DHandle[] = [];
	const log: string[] = [];
	const [listening, setListening] = createSignal(true);
	let mesh = NO_MESH;
	const root = mockNode("root");
	render(element(<Void>
		<Scene3D ref={(value: Scene3DHandle): void => { refs.push(value); mesh = squareMesh(value); }}>
			<Mesh mesh={mesh} onPress={(e: Pointer3DEvent): void => {}} />
			{Show({ when: accessor(() => listening()), children: element(
				<Mesh mesh={mesh} position={vec3(0.0, 0.0, 0.5)} onPointerMove={note(log, "move")} />
			) })}
		</Scene3D>
	</Void>), mockHost(), root as unknown as HostNode);
	const layer = layerOf(root);
	hover(layer, CENTER, CENTER);
	assert log.length === 1, "delivered while mounted: " + log.length.toString();
	setListening(false);
	flush();
	hover(layer, CENTER, CENTER);
	assert log.length === 1, "nothing after unmount: " + log.length.toString();
}

test "wheel reaches the hit mesh with its delta, bubbles, and a miss is not taken" {
	const refs: Scene3DHandle[] = [];
	const log: string[] = [];
	const got: Pointer3DEvent[] = [];
	let mesh = NO_MESH;
	const root = mockNode("root");
	render(element(<Void>
		<Scene3D ref={(value: Scene3DHandle): void => { refs.push(value); mesh = squareMesh(value); }}>
			<Group onWheel={note(log, "group")}>
				<Mesh mesh={mesh} onWheel={(e: Pointer3DEvent): void => { log.push("mesh"); got.push(e); }} />
			</Group>
		</Scene3D>
	</Void>), mockHost(), root as unknown as HostNode);
	const layer = layerOf(root);
	assert wheel(layer, CENTER, CENTER, 3.0), "the mesh takes the wheel";
	assert log.length === 2 && log[0] === "mesh" && log[1] === "group", "mesh then group: " + log.join(",");
	assert got[0].type === "wheel" && got[0].deltaY === 3.0, "delta " + got[0].deltaY.toString();
	assert !wheel(layer, OFF, OFF, 3.0), "empty space is left to the layers below";
	assert log.length === 2, "a miss wheels nothing";
}
