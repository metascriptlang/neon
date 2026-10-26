import { createSignal } from "../../src/core/signal";
import { flush } from "../../src/core/runtime";
import { element } from "../../src/macros/ui/element";
import { Host, HostNode, NeonNode } from "../../src/render/hostTypes";
import { useContext } from "../../src/render/context";
import { mockNode, mockHost, render } from "../../src/render/host";
import { Void } from "../../src/components/primitives";
import { Scene3D, Scene3DHandle, Mesh, Center } from "../../src/components/scene3d";
import { SceneState, sceneScope, runBeforeRefresh } from "../../src/components/scene3d/core";
import { NodeId3D } from "../../../void/src/void3d/scene";
import { center } from "../../../void/src/void3d/bounds";
import { MeshData, addBox, copy } from "../../../void/src/void3d/meshData";
import { MeshId, NO_MESH } from "../../../void/src/void3d/draw";
import { added, litShape } from "../../../void/src/test/drawHelpers";
import { Vec3, vec3 } from "../../../void/src/math/math3d";
import { approx } from "../../../void/src/test/helpers";

function Capture(states: SceneState[]): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		const scope = useContext(sceneScope);
		if (scope !== null) { states.push(scope.state); }
	};
}

function box(width: float32, height: float32, depth: float32): MeshData {
	let data = MeshData.empty();
	const made = addBox(data, { base: vec3(0.0, 0.0, 0.0), size: vec3(width, height, depth), yaw: 0.0, tilt: 0.0,
		color: { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 } });
	if (!made.ok) { throw new Error("fixture: addBox"); }
	return data;
}

function seeded(value: Scene3DHandle, shape: MeshData): MeshId {
	const mesh = added(value.context, litShape());
	value.context.meshData[mesh.index] = shape.copy();
	return mesh;
}

function innerPosition(state: SceneState, container: NodeId3D): Vec3 {
	const scene = state.handle.scene;
	return scene.nodes[scene.nodes[container.index].children[0]].local.position;
}

test "Center offsets its content by the centre of its bounds, like drei Center" {
	const states: SceneState[] = [];
	const containers: NodeId3D[] = [];
	const shape = box(2.0, 4.0, 6.0);
	const at = shape.bounds.center();
	let mesh = NO_MESH;
	render(element(<Void>
		<Scene3D ref={(value: Scene3DHandle): void => { mesh = seeded(value, shape); }}>
			{Capture(states)}
			<Center position={vec3(10.0, 0.0, 0.0)} ref={(id: NodeId3D): void => { containers.push(id); }}>
				<Mesh mesh={mesh} position={vec3(5.0, 6.0, 7.0)} />
			</Center>
		</Scene3D>
	</Void>), mockHost(), mockNode("root") as unknown as HostNode);
	runBeforeRefresh(states[0], 320, 240);
	const offset = innerPosition(states[0], containers[0]);
	assert approx(offset.x, -(5.0 + at.x) as float32) && approx(offset.y, -(6.0 + at.y) as float32) && approx(offset.z, -(7.0 + at.z) as float32),
		"content centred on the container, whatever the container's own pose: " + offset.x.toString() + "," + offset.y.toString() + "," + offset.z.toString();
}

test "Center aligns to a face and leaves a disabled axis alone" {
	const states: SceneState[] = [];
	const containers: NodeId3D[] = [];
	const shape = box(2.0, 4.0, 6.0);
	const at = shape.bounds.center();
	let mesh = NO_MESH;
	const [key, setKey] = createSignal<int32>(0);
	render(element(<Void>
		<Scene3D ref={(value: Scene3DHandle): void => { mesh = seeded(value, shape); }}>
			{Capture(states)}
			<Center top={true} disableZ={true} cacheKey={key()} ref={(id: NodeId3D): void => { containers.push(id); }}>
				<Mesh mesh={mesh} />
			</Center>
		</Scene3D>
	</Void>), mockHost(), mockNode("root") as unknown as HostNode);
	runBeforeRefresh(states[0], 320, 240);
	const offset = innerPosition(states[0], containers[0]);
	assert approx(offset.x, (-at.x) as float32), "x centred";
	assert approx(offset.y, (-at.y + 2.0) as float32), "top puts the top face on the origin plane: " + offset.y.toString();
	assert offset.z === 0.0, "disableZ keeps z";
}

test "Center measures again only when its props or cacheKey change" {
	const states: SceneState[] = [];
	const containers: NodeId3D[] = [];
	let mesh = NO_MESH;
	const [x, setX] = createSignal<float32>(4.0);
	const [key, setKey] = createSignal<int32>(0);
	render(element(<Void>
		<Scene3D ref={(value: Scene3DHandle): void => { mesh = seeded(value, box(2.0, 2.0, 2.0)); }}>
			{Capture(states)}
			<Center cacheKey={key()} ref={(id: NodeId3D): void => { containers.push(id); }}>
				<Mesh mesh={mesh} position={vec3(x(), 0.0, 0.0)} />
			</Center>
		</Scene3D>
	</Void>), mockHost(), mockNode("root") as unknown as HostNode);
	runBeforeRefresh(states[0], 320, 240);
	const first = innerPosition(states[0], containers[0]).x;
	setX(9.0);
	flush();
	runBeforeRefresh(states[0], 320, 240);
	assert innerPosition(states[0], containers[0]).x === first, "moved content alone does not re-measure";
	setKey(1);
	flush();
	runBeforeRefresh(states[0], 320, 240);
	assert approx(innerPosition(states[0], containers[0]).x, (first - 5.0) as float32), "a new cacheKey re-measures: " + innerPosition(states[0], containers[0]).x.toString();
}
