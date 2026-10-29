import { flush, resetErrorHalt } from "../../src/core/runtime";
import { element } from "../../src/macros/ui/element";
import { HostNode, MockNode, mockNode, mockHost, render, mockAreaHub } from "../../src/render/host";
import { Void } from "../../src/components/primitives";
import { createSignal, accessor } from "../../src/core/signal";
import { NeonNode, Host } from "../../src/render/hostTypes";
import { Scene3D, Scene3DHandle, Group, PointLight, Mesh, Camera3D, createMaterial } from "../../src/components/scene3d";
import { MaterialId } from "../../../void/src/void3d/draw";
import { added, litShape } from "../../../void/src/test/drawHelpers";
import { vec3 } from "../../../void/src/math/math3d";

function prepareOnce(root: MockNode, width: int32, height: int32): string {
	const hub = mockAreaHub(root.children[0]);
	let message = "";
	try { hub.prepareLayers(hub.layers().slice(0), width, height); }
	catch (error) { message = error.toString(); }
	finally { resetErrorHalt(); }
	return message;
}

test "a Scene3D with a PointLight prepares its frame with the camera view set" {
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene3D>
		<PointLight position={vec3(0.0, 1.0, 0.0)} radius={6.0} />
	</Scene3D></Void>), mockHost(), root as unknown as HostNode);
	try {
		assert prepareOnce(root, 64, 48) === "";
		flush();
		assert prepareOnce(root, 96, 64) === "", "a resized frame resolves its own view";
	} finally { dispose(); resetErrorHalt(); }
}

test "two PointLights, one under a nested Group, prepare a frame" {
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene3D>
		<PointLight position={vec3(-2.0, 1.0, 0.0)} radius={5.0} />
		<Group position={vec3(3.0, 0.0, 0.0)}>
			<PointLight position={vec3(0.0, 2.0, 0.0)} radius={4.0} />
		</Group>
	</Scene3D></Void>), mockHost(), root as unknown as HostNode);
	try {
		assert prepareOnce(root, 64, 48) === "";
	} finally { dispose(); resetErrorHalt(); }
}

function pbrMesh(handle: Scene3DHandle): NeonNode {
	const mesh = added(handle.context, litShape());
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		const material = createMaterial({ roughness: accessor((): float32 => 0.5) });
		element(<Mesh mesh={mesh} material={material()} />)(host, parent, before);
	};
}

test "a Scene3D with a pbr Mesh material prepares a frame that has the camera's eye" {
	const refs: Scene3DHandle[] = [];
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene3D ref={(handle: Scene3DHandle): void => { refs.push(handle); }}>
		<Camera3D active={true} position={vec3(0.0, 1.0, 5.0)} />
		{(host: Host, parent: HostNode, before: HostNode | null): void => { pbrMesh(refs[0])(host, parent, before); }}
	</Scene3D></Void>), mockHost(), root as unknown as HostNode);
	try {
		assert prepareOnce(root, 64, 48) === "";
		assert refs[0].renderer.core.cameraPosition === vec3(0.0, 1.0, 5.0);
	} finally { dispose(); resetErrorHalt(); }
}

test "a pbr frame follows a camera moved by props between two prepares" {
	const refs: Scene3DHandle[] = [];
	const [eye, setEye] = createSignal(vec3(0.0, 1.0, 5.0));
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene3D ref={(handle: Scene3DHandle): void => { refs.push(handle); }}>
		<Camera3D active={true} position={eye()} />
		{(host: Host, parent: HostNode, before: HostNode | null): void => { pbrMesh(refs[0])(host, parent, before); }}
	</Scene3D></Void>), mockHost(), root as unknown as HostNode);
	try {
		assert prepareOnce(root, 64, 48) === "";
		setEye(vec3(3.0, 2.0, 7.0)); flush();
		assert prepareOnce(root, 64, 48) === "";
		assert refs[0].renderer.core.cameraPosition === vec3(3.0, 2.0, 7.0);
	} finally { dispose(); resetErrorHalt(); }
}
