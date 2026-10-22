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

test "a press on a mesh reaches its onPress with the world hit, the ray and the node" {
	const refs: Scene3DHandle[] = [];
	const nodes: NodeId3D[] = [];
	const got: Pointer3DEvent[] = [];
	let mesh = NO_MESH;
	const root = mockNode("root");
	render(element(<Void>
		<Scene3D ref={(value: Scene3DHandle): void => { refs.push(value); mesh = squareMesh(value); }}>
			<Mesh mesh={mesh} ref={(value: NodeId3D): void => { nodes.push(value); }}
				onPress={(e: Pointer3DEvent): void => { got.push(e); }} />
		</Scene3D>
	</Void>), mockHost(), root as unknown as HostNode);
	const handle = handleOf(refs);
	const layer = layerOf(root);
	assert handle.scene.nodes[nodes[0].index].flags.has(NodeFlag.Pickable), "a node with a pointer handler is pickable";
	assert tap(layer, CENTER, CENTER), "the mesh takes the press";
	assert got.length === 1, "one press: " + got.length.toString();
	const e = got[0];
	assert e.type === "press", "type " + e.type;
	assert sameNode(e.node, nodes[0]), "the hit node";
	assert near(e.point.x, 0.0) && near(e.point.y, 0.0) && near(e.point.z, 0.0), "the world point";
	assert e.distance > 4.0 && e.distance < 5.01, "distance " + e.distance.toString();
	assert near(e.ray.direction.z, -1.0), "the ray looks down -z";
	assert e.x === CENTER && e.y === CENTER, "screen position";
	assert !tap(layer, OFF, OFF), "empty space is left to the layers below";
	assert got.length === 1, "a miss presses nothing";
}

test "only the innermost node with a press handler presses, as nested Pressables do" {
	const log: string[] = [];
	const refs: Scene3DHandle[] = [];
	let mesh = NO_MESH;
	const root = mockNode("root");
	render(element(<Void>
		<Scene3D ref={(value: Scene3DHandle): void => { refs.push(value); mesh = squareMesh(value); }}>
			<Group onPress={note(log, "group")}>
				<Mesh mesh={mesh} onPress={note(log, "mesh")} />
			</Group>
			<Mesh mesh={mesh} position={vec3(0.0, 0.0, -1.0)} onPress={note(log, "far")} />
		</Scene3D>
	</Void>), mockHost(), root as unknown as HostNode);
	tap(layerOf(root), CENTER, CENTER);
	assert log.join("|") === "mesh", "the mesh presses, its Group does not, the farther mesh does not: " + log.join("|");
}

test "a Group with onPress presses for a mesh under it that has none" {
	const log: string[] = [];
	const refs: Scene3DHandle[] = [];
	const nodes: NodeId3D[] = [];
	let mesh = NO_MESH;
	const root = mockNode("root");
	render(element(<Void>
		<Scene3D ref={(value: Scene3DHandle): void => { refs.push(value); mesh = squareMesh(value); }}>
			<Group onPress={(e: Pointer3DEvent): void => { log.push(sameNode(e.node, nodes[0]) ? "group" : "group, wrong hit"); }}>
				<Mesh mesh={mesh} ref={(value: NodeId3D): void => { nodes.push(value); }} />
			</Group>
		</Scene3D>
	</Void>), mockHost(), root as unknown as HostNode);
	assert tap(layerOf(root), CENTER, CENTER), "the Group's handler takes the press";
	assert log.join("|") === "group", "the nearest press handler on the hit's path receives, with the mesh as the hit: " + log.join("|");
}

test "nested press gestures: the innermost claims the press, and stopPropagation ends the pointerdown walk" {
	const log: string[] = [];
	const refs: Scene3DHandle[] = [];
	let mesh = NO_MESH;
	const root = mockNode("root");
	render(element(<Void>
		<Scene3D ref={(value: Scene3DHandle): void => { refs.push(value); mesh = squareMesh(value); }}>
			<Group onPressIn={note(log, "group in")}>
				<Mesh mesh={mesh} onPressIn={(e: Pointer3DEvent): void => {
					log.push("mesh in");
					stopPropagation(e);
				}} />
			</Group>
		</Scene3D>
	</Void>), mockHost(), root as unknown as HostNode);
	const layer = layerOf(root);
	down(layer, CENTER, CENTER);
	assert log.join("|") === "mesh in", "only the mesh starts a press: " + log.join("|");
	up(layer, CENTER, CENTER);
}

test "a gesture Group around a plain-press Mesh presses both, the same as the 2D nesting" {
	const log: string[] = [];
	const refs: Scene3DHandle[] = [];
	let mesh = NO_MESH;
	const root = mockNode("root");
	render(element(<Void>
		<Scene3D ref={(value: Scene3DHandle): void => { refs.push(value); mesh = squareMesh(value); }}>
			<Group onPressIn={note(log, "group in")} onPress={note(log, "group")}>
				<Mesh mesh={mesh} onPress={note(log, "mesh")} />
			</Group>
		</Scene3D>
	</Void>), mockHost(), root as unknown as HostNode);
	tap(layerOf(root), CENTER, CENTER);
	assert log.join("|") === "group in|group|mesh", "scene2dEvents pins the same order in 2D: " + log.join("|");
}

test "a release away from the pressed mesh does not press, and the pointer stays captured" {
	const log: string[] = [];
	const refs: Scene3DHandle[] = [];
	let mesh = NO_MESH;
	const root = mockNode("root");
	render(element(<Void>
		<Scene3D ref={(value: Scene3DHandle): void => { refs.push(value); mesh = squareMesh(value); }}
			onPressMissed={(e: NeonEvent): void => { log.push("missed"); }}>
			<Mesh mesh={mesh} onPress={note(log, "press")} />
		</Scene3D>
	</Void>), mockHost(), root as unknown as HostNode);
	const layer = layerOf(root);
	assert down(layer, CENTER, CENTER);
	assert up(layer, OFF, OFF), "the captured release still belongs to the layer";
	assert log.length === 0, "neither press nor miss: " + log.join("|");
	assert tap(layer, OFF, OFF), "with onPressMissed the layer takes a press on empty space";
	assert log.join("|") === "missed", "a click on nothing is a miss: " + log.join("|");
	log.length = 0;
	down(layer, OFF, OFF);
	up(layer, OFF + 20.0, OFF);
	assert log.length === 0, "a drag on empty space is not a miss: " + log.join("|");
}

test "hover enters and leaves per node, and a hovered node that unmounts leaves silently" {
	const log: string[] = [];
	const refs: Scene3DHandle[] = [];
	const [shown, setShown] = createSignal(true);
	let mesh = NO_MESH;
	const root = mockNode("root");
	render(element(<Void>
		<Scene3D ref={(value: Scene3DHandle): void => { refs.push(value); mesh = squareMesh(value); }}>
			<Group onHoverIn={note(log, "group in")} onHoverOut={note(log, "group out")}>
				{Show({ when: accessor(() => shown()), children: element(
					<Mesh mesh={mesh} onHoverIn={note(log, "mesh in")} onHoverOut={note(log, "mesh out")} />
				) })}
			</Group>
		</Scene3D>
	</Void>), mockHost(), root as unknown as HostNode);
	const layer = layerOf(root);
	assert hover(layer, CENTER, CENTER), "a hovered mesh keeps the layer";
	assert log.join("|") === "group in|mesh in", "outermost enters first: " + log.join("|");
	log.length = 0;
	hover(layer, CENTER + 1.0, CENTER);
	assert log.length === 0, "moving within the node is no change: " + log.join("|");
	assert !hover(layer, OFF, OFF);
	assert log.join("|") === "mesh out|group out", "deepest leaves first: " + log.join("|");
	log.length = 0;
	hover(layer, CENTER, CENTER);
	log.length = 0;
	setShown(false);
	flush();
	assert log.length === 0, "unmount sends no leave: " + log.join("|");
	hover(layer, OFF, OFF);
	assert log.join("|") === "group out", "only the node still mounted leaves: " + log.join("|");
}

test "the layer picks nothing until a node registers a handler, and motion picks only for hover" {
	const refs: Scene3DHandle[] = [];
	const nodes: NodeId3D[] = [];
	const [pressable, setPressable] = createSignal(false);
	let mesh = NO_MESH;
	const root = mockNode("root");
	render(element(<Void>
		<Scene3D ref={(value: Scene3DHandle): void => { refs.push(value); mesh = squareMesh(value); }}>
			<Mesh mesh={mesh} ref={(value: NodeId3D): void => { nodes.push(value); }} />
			{Show({ when: accessor(() => pressable()), children: element(
				<Mesh mesh={mesh} position={vec3(5.0, 0.0, 0.0)} onPress={(e: Pointer3DEvent): void => {}} />
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
	assert !tap(layer, CENTER, CENTER);
	assert syncWorld(handle.scene) > 0, "no handler: no pick, so the world was not synced";
	setPressable(true);
	flush();
	syncWorld(handle.scene);
	moved();
	assert !hover(layer, CENTER, CENTER);
	assert syncWorld(handle.scene) > 0, "no hover handler: motion does not pick";
	moved();
	down(layer, CENTER, CENTER);
	assert syncWorld(handle.scene) === 0, "a press picks once a handler exists";
	up(layer, CENTER, CENTER);
}

test "press in and out bracket the 3D gesture through the shared press machine" {
	const [log, setLog] = createSignal("");
	const say = (s: string): Handler3D => {
		return (e: Pointer3DEvent): void => { setLog(log() + s); };
	};
	const refs: Scene3DHandle[] = [];
	let mesh = NO_MESH;
	const root = mockNode("root");
	render(element(<Void>
		<Scene3D ref={(value: Scene3DHandle): void => { refs.push(value); mesh = squareMesh(value); }}>
			<Mesh mesh={mesh} onPressIn={say("in;")} onPressOut={say("out;")} onPress={say("press;")} />
		</Scene3D>
	</Void>), mockHost(), root as unknown as HostNode);
	const layer = layerOf(root);
	down(layer, CENTER, CENTER);
	flush();
	assert log() === "in;", "after down: " + log();
	up(layer, CENTER, CENTER);
	flush();
	assert log() === "in;press;", "after up: " + log();
	await sleepAsync(250);
	assert log() === "in;press;out;", "after the minimum hold: " + log();
}

test "a capture ends without an event when the pressed node unmounts" {
	const log: string[] = [];
	const refs: Scene3DHandle[] = [];
	const [shown, setShown] = createSignal(true);
	let mesh = NO_MESH;
	const root = mockNode("root");
	render(element(<Void>
		<Scene3D ref={(value: Scene3DHandle): void => { refs.push(value); mesh = squareMesh(value); }}>
			<Group onPress={note(log, "group")}>
				{Show({ when: accessor(() => shown()), children: element(
					<Mesh mesh={mesh} onPress={note(log, "mesh")} />
				) })}
			</Group>
			<Mesh mesh={mesh} position={vec3(0.0, 0.0, -1.0)} onPress={note(log, "back")} />
		</Scene3D>
	</Void>), mockHost(), root as unknown as HostNode);
	const layer = layerOf(root);
	down(layer, CENTER, CENTER);
	setShown(false);
	flush();
	assert up(layer, CENTER, CENTER), "the layer keeps the captured release";
	assert log.length === 0, "the unmounted mesh hears nothing, and the release left the group's subtree: " + log.join("|");
	log.length = 0;
	tap(layer, CENTER, CENTER);
	assert log.join("|") === "back", "the next press finds the mesh behind: " + log.join("|");
}

test "a placed Node takes pointer handlers and gives its pickability back on unmount" {
	const log: string[] = [];
	const refs: Scene3DHandle[] = [];
	const [shown, setShown] = createSignal(true);
	let mesh = NO_MESH;
	let borrowed: NodeId3D | null = null;
	const root = mockNode("root");
	render(element(<Void>
		<Scene3D ref={(value: Scene3DHandle): void => {
			refs.push(value);
			mesh = squareMesh(value);
			borrowed = addGroup(value.scene, null, Transform3D.identity());
		}}>
			{Show({ when: accessor(() => shown()), children: element(
				<Node id={borrowed as NodeId3D} onPress={note(log, "node")}>
					<Mesh mesh={mesh} />
				</Node>
			) })}
		</Scene3D>
	</Void>), mockHost(), root as unknown as HostNode);
	const handle = handleOf(refs);
	const layer = layerOf(root);
	assert tap(layer, CENTER, CENTER);
	assert log.join("|") === "node", "the Node presses through its child mesh: " + log.join("|");
	setShown(false);
	flush();
	const id = borrowed as NodeId3D;
	assert !handle.scene.nodes[id.index].flags.has(NodeFlag.Pickable), "the borrowed node is not left pickable";
}

test "a mesh on a layer the camera does not draw is not picked" {
	const log: string[] = [];
	const refs: Scene3DHandle[] = [];
	let mesh = NO_MESH;
	const root = mockNode("root");
	render(element(<Void>
		<Scene3D ref={(value: Scene3DHandle): void => { refs.push(value); mesh = squareMesh(value); }}>
			<Mesh mesh={mesh} layers={2 as uint32} onPress={note(log, "hidden")} />
			<Mesh mesh={mesh} position={vec3(0.0, 0.0, -1.0)} onPress={note(log, "seen")} />
		</Scene3D>
	</Void>), mockHost(), root as unknown as HostNode);
	const layer = layerOf(root);
	tap(layer, CENTER, CENTER);
	assert log.join("|") === "seen", "the press goes to what the camera shows: " + log.join("|");
}
