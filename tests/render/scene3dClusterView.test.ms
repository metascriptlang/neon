import { flush, resetErrorHalt } from "../../src/core/runtime";
import { element } from "../../src/macros/ui/element";
import { HostNode, MockNode, mockNode, mockHost, render, mockAreaHub } from "../../src/render/host";
import { Void } from "../../src/components/primitives";
import { Scene3D, Group, PointLight } from "../../src/components/scene3d";
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
