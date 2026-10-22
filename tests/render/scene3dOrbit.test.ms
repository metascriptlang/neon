import { flush } from "../../src/core/runtime";
import { element } from "../../src/macros/ui/element";
import { HostNode, MockNode, mockNode, mockHost, render, mockAreaHub } from "../../src/render/host";
import { NeonEvent, neonEvent } from "../../src/render/event";
import { AreaLayer, AreaPointerKind } from "../../src/render/voidAreaHandle";
import { Void } from "../../src/components/primitives";
import { Scene3D, Scene3DHandle, Camera3D, Mesh, OrbitControls, Pointer3DEvent } from "../../src/components/scene3d";
import { NodeId3D } from "../../../void/src/void3d/scene";
import { MeshId, NO_MESH } from "../../../void/src/void3d/draw";
import { MeshData, Rgba, addVertex, addTriangle } from "../../../void/src/void3d/meshData";
import { added, litShape } from "../../../void/src/test/drawHelpers";
import { Vec3, vec3 } from "../../../void/src/math/math3d";

const WHITE: Rgba = { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 };

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

function squareMesh(handle: Scene3DHandle): MeshId {
	const mesh = added(handle.context, litShape());
	handle.context.meshData[mesh.index] = square();
	return mesh;
}

function event(type: string, button: number, pressed: boolean, x: float32, y: float32): NeonEvent {
	const e = neonEvent(type);
	e.button = button;
	e.pressed = pressed;
	e.x = x;
	e.y = y;
	return e;
}

function layerOf(root: MockNode): AreaLayer {
	const hub = mockAreaHub(root.children[0]);
	hub.resize({ pixelWidth: 200, pixelHeight: 200, scale: 1.0 });
	return hub.layers()[0];
}

function hits(layer: AreaLayer, x: float32, y: float32, kind: AreaPointerKind, e: NeonEvent): boolean {
	const hit = layer.hit;
	if (hit === null) { throw new Error("the Scene3D layer has no hit hook"); }
	return (hit as (x: float32, y: float32, kind: AreaPointerKind, e: NeonEvent) => boolean)(x, y, kind, e);
}

function dragBy(layer: AreaLayer, button: number, fromX: float32, fromY: float32, toX: float32, toY: float32): boolean {
	const took = hits(layer, fromX, fromY, AreaPointerKind.Button, event("pointerdown", button, true, fromX, fromY));
	hits(layer, toX, toY, AreaPointerKind.Motion, event("pointermove", button, true, toX, toY));
	hits(layer, toX, toY, AreaPointerKind.Button, event("pointerup", button, false, toX, toY));
	return took;
}

function wheel(layer: AreaLayer, dy: float32): boolean {
	const e = event("wheel", 0, false, 100.0, 100.0);
	e.deltaY = dy;
	return hits(layer, 100.0, 100.0, AreaPointerKind.Wheel, e);
}

function near(a: float32, b: float32): boolean {
	return Math.abs(a - b) < 0.01;
}

interface Rig {
	handle: Scene3DHandle;
	camera: NodeId3D;
	layer: AreaLayer;
	log: string[];
}

function rig(): Rig {
	const refs: Scene3DHandle[] = [];
	const cameras: NodeId3D[] = [];
	const log: string[] = [];
	let mesh = NO_MESH;
	const root = mockNode("root");
	render(element(<Void>
		<Scene3D ref={(value: Scene3DHandle): void => { refs.push(value); mesh = squareMesh(value); }}
			onPressMissed={(e: NeonEvent): void => { log.push("missed"); }}>
			<Camera3D active={true} position={vec3(0.0, 0.0, 5.0)} ref={(value: NodeId3D): void => { cameras.push(value); }} />
			<Mesh mesh={mesh} position={vec3(1.5, 0.0, 0.0)} onPress={(e: Pointer3DEvent): void => { log.push("mesh"); }} />
			<OrbitControls onChange={(): void => { log.push("change"); }} />
		</Scene3D>
	</Void>), mockHost(), root as unknown as HostNode);
	flush();
	return { handle: refs[0], camera: cameras[0], layer: layerOf(root), log };
}

function positionOf(r: Rig): Vec3 {
	return r.handle.scene.nodes[r.camera.index].local.position;
}

test "a left drag on empty space orbits the camera around the target at its distance" {
	const r = rig();
	assert dragBy(r.layer, 1, 100.0, 100.0, 150.0, 100.0), "the controls take a drag no node takes";
	const p = positionOf(r);
	assert near(p.length(), 5.0), "the distance holds: " + p.length().toString();
	assert near(p.y, 0.0), "a horizontal drag keeps the height";
	assert p.x < -0.1, "dragging right swings the camera left around the target: " + p.x.toString();
	assert r.log.indexOf("change") >= 0, "onChange fires";
	assert r.log.indexOf("missed") < 0, "an orbit drag is not a missed press";
}

test "a vertical drag stops short of the pole" {
	const r = rig();
	dragBy(r.layer, 1, 100.0, 100.0, 100.0, 900.0);
	const p = positionOf(r);
	assert p.y > 4.99 && near(p.length(), 5.0), "the camera ends over the target, not past it: " + p.y.toString();
}

test "the wheel dollies toward the target and a right drag pans" {
	const r = rig();
	assert wheel(r.layer, 1.0), "the controls take the wheel";
	assert near(positionOf(r).length(), 4.75), "one step in is 0.95 of the distance: " + positionOf(r).length().toString();
	wheel(r.layer, -1.0);
	assert near(positionOf(r).length(), 5.0), "one step out undoes it";
	dragBy(r.layer, 2, 100.0, 100.0, 120.0, 100.0);
	const p = positionOf(r);
	assert p.x < -0.1 && near(p.z, 5.0), "panning moves the camera with the target: " + p.x.toString() + "," + p.z.toString();
}

test "a press on a mesh goes to the mesh, not the controls" {
	const r = rig();
	const before = positionOf(r);
	const meshX: float32 = 100.0 + 1.5 / (5.0 * 0.5773503) * 100.0;
	dragBy(r.layer, 1, meshX, 100.0, meshX, 100.0);
	assert r.log.join("|") === "mesh", "the mesh presses: " + r.log.join("|");
	assert positionOf(r) == before, "the camera did not move";
}

test "a click on empty space beside the controls is still a missed press" {
	const r = rig();
	const before = positionOf(r);
	dragBy(r.layer, 1, 100.0, 100.0, 100.0, 100.0);
	assert r.log.join("|") === "missed", "the click misses: " + r.log.join("|");
	assert positionOf(r) == before, "a click does not move the camera";
}
