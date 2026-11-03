import { accessor, createSignal } from "../../src/core/signal";
import { flush } from "../../src/core/runtime";
import { element } from "../../src/macros/ui/element";
import { Show } from "../../src/macros/ui/flow";
import { HostNode, mockNode, mockHost, render } from "../../src/render/host";
import { Void } from "../../src/components/primitives";
import { Scene3D, Scene3DHandle, Node } from "../../src/components/scene3d";
import { NodeId3D, NO_NODE_ID, Transform3D, addGroup } from "../../../void/src/void3d/scene";
import { Vec3, Quat, vec3, axisAngle } from "../../../void/src/math/math3d";

function same(a: Transform3D, b: Transform3D): boolean {
	return a.position.x == b.position.x && a.position.y == b.position.y && a.position.z == b.position.z
		&& a.rotation.x == b.rotation.x && a.rotation.y == b.rotation.y && a.rotation.z == b.rotation.z && a.rotation.w == b.rotation.w
		&& a.scale.x == b.scale.x && a.scale.y == b.scale.y && a.scale.z == b.scale.z;
}

test "Node with one transform prop writes only that part and gives the borrowed transform back" {
	const refs: Scene3DHandle[] = [];
	let kept = NO_NODE_ID;
	const spun: Quat = axisAngle(vec3(0, 1, 0), 1);
	const born: Transform3D = { position: vec3(1, 2, 3), rotation: spun, scale: vec3(2, 3, 4) };
	const [on, setOn] = createSignal(true);
	const [at, setAt] = createSignal<Vec3>(vec3(9, 8, 7));
	const root = mockNode("root");
	const dispose = render(element(<Void>
		<Scene3D ref={(value: Scene3DHandle): void => {
			refs.push(value);
			kept = addGroup(value.scene, value.scene.rootId(), born);
		}}>
			{Show({ when: accessor(() => on()), children: element(<Node id={kept} position={at()} />) })}
		</Scene3D>
	</Void>), mockHost(), root as unknown as HostNode);
	const scene = refs[0].scene;
	const now = (): Transform3D => scene.nodes[kept.index].local;
	assert now().position.x == 9 && now().position.y == 8 && now().position.z == 7, "position is the one part written";
	assert now().rotation.y == spun.y && now().rotation.w == spun.w, "rotation of the borrowed node is kept";
	assert now().scale.x == 2 && now().scale.y == 3 && now().scale.z == 4, "scale of the borrowed node is kept";
	setAt(vec3(5, 5, 5)); flush();
	assert now().position.x == 5 && now().rotation.w == spun.w && now().scale.z == 4, "an update keeps the other parts";
	setOn(false); flush();
	assert scene.isLive(kept) && same(now(), born), "unmount restores the transform the node came with";
	dispose();
}
