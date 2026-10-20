import { accessor, createSignal } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { Show } from "../../src/macros/ui/flow";
import { HostNode, mockNode, mockHost, render } from "../../src/render/host";
import { Void } from "../../src/components/primitives";
import { Scene3D, Scene3DHandle, Group, Camera3D } from "../../src/components/scene3d";
import { voidScope as Scope, VoidSpace } from "../../src/render/voidScope";
import { cameraOf, nodeCount } from "../../../void/src/void3d/scene";
import { Camera3D as VoidCamera3D, basisOf } from "../../../void/src/void3d/camera";
import { vec3, eulerQuat } from "../../../void/src/math/math3d";

function resolved(handle: Scene3DHandle): VoidCamera3D {
	const request = handle.camera;
	if (request === null) { throw new Error("fixture: no active camera"); }
	const result = cameraOf(handle.scene, request);
	if (!result.ok) { throw new Error(result.error.toString()); }
	return result.value;
}

test "Camera3D follows parent translation roll and scale through Void world binding" {
	const refs: Scene3DHandle[] = [];
	const [x, setX] = createSignal<float32>(1.0);
	const [roll, setRoll] = createSignal<float32>(0.0);
	const root = mockNode("root");
	const dispose = render(element(<Void>
		<Scene3D ref={(value: Scene3DHandle): void => { refs.push(value); }}>
			<Group position={vec3(x(), 2.0, 4.0)} rotation={eulerQuat(0.0, 0.0, roll())}
				scale={vec3(2.0, 4.0, 8.0)}>
				<Camera3D active={true} position={vec3(0.0, 0.0, 1.0)} />
			</Group>
		</Scene3D>
	</Void>), mockHost(), root as unknown as HostNode);
	const handle: Scene3DHandle | null = refs.length === 0 ? null : refs[0];
	if (handle === null) { throw new Error("fixture: handle ref did not mount"); }
	const initial = resolved(handle);
	assert initial.position === vec3(1.0, 2.0, 12.0);
	setX(3.0); setRoll(0.5);
	const moved = resolved(handle);
	assert moved.position === vec3(3.0, 2.0, 12.0);
	assert moved.basisOf().right.y > 0.4;
	assert Math.abs(moved.basisOf().right.lengthSquared() - 1.0) < 0.00001;
	dispose(); setX(10.0); setRoll(1.0);
	assert handle.camera === null && handle.scene.closed && handle.scene.nodeCount() === 0;
}

test "Camera3D retains local yaw pitch and restores a surviving world camera after subtree removal" {
	const refs: Scene3DHandle[] = [];
	const [yaw, setYaw] = createSignal<float32>(0.7);
	const [pitch, setPitch] = createSignal<float32>(-0.3);
	const [shown, setShown] = createSignal(true);
	const root = mockNode("root");
	const dispose = render(element(<Void>
		<Scene3D ref={(value: Scene3DHandle): void => { refs.push(value); }}>
			<Camera3D active={true} position={vec3(1.0, 2.0, 3.0)} yaw={yaw()} pitch={pitch()} />
			{Show({ when: accessor(() => shown()), children: element(
				<Group position={vec3(20.0, 0.0, 0.0)}><Camera3D active={true} /></Group>
			) })}
		</Scene3D>
	</Void>), mockHost(), root as unknown as HostNode);
	const handle: Scene3DHandle | null = refs.length === 0 ? null : refs[0];
	if (handle === null) { throw new Error("fixture: handle ref did not mount"); }
	assert resolved(handle).position.x === 20.0;
	setShown(false);
	const selected = handle.camera;
	assert selected !== null;
	if (selected !== null) {
		const expected = selected.basisOf();
		const actual = resolved(handle).basisOf();
		assert Math.abs(expected.forward.x - actual.forward.x) < 0.00001;
		assert Math.abs(expected.forward.y - actual.forward.y) < 0.00001;
		assert Math.abs(expected.forward.z - actual.forward.z) < 0.00001;
	}
	assert handle.scene.nodeCount() === 2;
	setYaw(0.2); setPitch(0.4);
	assert resolved(handle).basisOf().forward.y < -0.3;
	setShown(true);
	assert resolved(handle).position.x === 20.0;
	dispose(); setYaw(1.0); setShown(false);
	assert handle.camera === null && handle.scene.closed;
}

test "Camera3D rejects an inherited foreign scene scope and closes failed owners" {
	const refs: Scene3DHandle[] = [];
	const root = mockNode("root");
	let failure = "";
	try {
		const dispose = render(element(<Void>
			<Scene3D ref={(value: Scene3DHandle): void => { refs.push(value); }}>
				<Scope.provider value={VoidSpace.Scene2D}><Camera3D active={true} /></Scope.provider>
			</Scene3D>
		</Void>), mockHost(), root as unknown as HostNode);
		dispose();
	} catch (error) { failure = error.toString(); }
	assert failure.includes("Camera3D: mount inside Scene3D within Void");
	const handle: Scene3DHandle | null = refs.length === 0 ? null : refs[0];
	if (handle === null) { throw new Error("fixture: handle ref did not mount"); }
	assert handle.scene.closed && handle.context.closed && handle.scene.nodeCount() === 0;
}
