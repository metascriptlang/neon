import { accessor, createSignal } from "../../src/core/signal";
import { flush } from "../../src/core/runtime";
import { element } from "../../src/macros/ui/element";
import { Show } from "../../src/macros/ui/flow";
import { HostNode, MockNode, mockNode, mockHost, render, mockAreaHub } from "../../src/render/host";
import { Void, View } from "../../src/components/primitives";
import { Scene3D, Scene3DHandle, Group, Camera3D, viewCamera } from "../../src/components/scene3d";
import { ProjectionKind } from "../../../void/src/void3d/camera";
import { Vec3, vec3 } from "../../../void/src/math/math3d";

function frameRequests(outer: MockNode): int32 {
	let n: int32 = 0;
	for (const a of outer.attrs) {
		if (a.name === "frameRequested") { n += 1; }
	}
	return n;
}

test "a Scene3D draws as a layer of its Void area until it unmounts" {
	const root: MockNode = mockNode("root");
	const [shown, setShown] = createSignal(true);
	const refs: Scene3DHandle[] = [];
	render(element(<Void>
		{Show({ when: accessor(() => shown()), children: element(
			<Scene3D ref={(value: Scene3DHandle): void => { refs.push(value); }}>
				<Camera3D active={true} position={vec3(0.0, 0.0, 5.0)} />
			</Scene3D>
		) })}
	</Void>), mockHost(), root as unknown as HostNode);
	const hub = mockAreaHub(root.children[0]);
	assert hub.layers().length === 1, "layers after mount: " + hub.layers().length.toString();
	setShown(false);
	flush();
	assert hub.layers().length === 0, "layers after unmount: " + hub.layers().length.toString();
	assert refs[0].scene.closed && refs[0].context.closed, "the scene and its context close with the layer";
	setShown(true);
	flush();
	assert hub.layers().length === 1 && refs.length === 2, "a remount registers one fresh layer";
}

test "a 2D-only Void has no 3D layer" {
	const root: MockNode = mockNode("root");
	render(element(<Void><View /></Void>), mockHost(), root as unknown as HostNode);
	assert mockAreaHub(root.children[0]).layers().length === 0;
}

test "a Scene3D change asks its area for a frame, and an idle scene asks for none" {
	const root: MockNode = mockNode("root");
	const [position, setPosition] = createSignal<Vec3>(vec3(0.0, 0.0, 0.0));
	const [eye, setEye] = createSignal<Vec3>(vec3(0.0, 0.0, 5.0));
	render(element(<Void>
		<Scene3D>
			<Camera3D active={true} position={eye()} />
			<Group position={position()} />
		</Scene3D>
	</Void>), mockHost(), root as unknown as HostNode);
	const outer = root.children[0];
	const mounted = frameRequests(outer);
	assert mounted > 0, "mounting asks for a frame";
	flush();
	assert frameRequests(outer) === mounted, "nothing changed, no frame: " + frameRequests(outer).toString();
	setPosition(vec3(1.0, 0.0, 0.0));
	flush();
	const moved = frameRequests(outer);
	assert moved > mounted, "a moved group asks for a frame";
	setEye(vec3(0.0, 1.0, 5.0));
	flush();
	assert frameRequests(outer) > moved, "a moved camera asks for a frame";
}

test "two Void areas keep their own Scene3D layers" {
	const root: MockNode = mockNode("root");
	const [position, setPosition] = createSignal<Vec3>(vec3(0.0, 0.0, 0.0));
	render(element(<View>
		<Void><Scene3D><Group position={position()} /></Scene3D></Void>
		<Void><Scene3D><Group /></Scene3D><Scene3D /></Void>
	</View>), mockHost(), root as unknown as HostNode);
	const first = root.children[0].children[0];
	const second = root.children[0].children[1];
	assert mockAreaHub(first).layers().length === 1 && mockAreaHub(second).layers().length === 2;
	const before = frameRequests(second);
	setPosition(vec3(2.0, 0.0, 0.0));
	flush();
	assert frameRequests(second) === before, "a change in one area does not wake the other";
}

test "a Scene3D with no active Camera3D views through the default camera until one mounts" {
	const root: MockNode = mockNode("root");
	const [shown, setShown] = createSignal(false);
	const refs: Scene3DHandle[] = [];
	render(element(<Void>
		<Scene3D ref={(value: Scene3DHandle): void => { refs.push(value); }}>
			{Show({ when: accessor(() => shown()), children: element(
				<Camera3D active={true} position={vec3(0.0, 1.0, 9.0)} />
			) })}
		</Scene3D>
	</Void>), mockHost(), root as unknown as HostNode);
	const first = viewCamera(refs[0]);
	assert first.ok && first.value.position === vec3(0.0, 0.0, 5.0), "the default camera sits at z 5";
	if (!first.ok) { return; }
	const projection = first.value.projection;
	assert projection.kind === ProjectionKind.Perspective && Math.abs(projection.fovY - 1.3089969) < 1e-6, "a 75 degree perspective";
	assert first.value.nearPlane === 0.1 && first.value.farPlane === 1000.0;
	setShown(true);
	flush();
	const active = viewCamera(refs[0]);
	assert active.ok && active.value.position === vec3(0.0, 1.0, 9.0), "an active Camera3D replaces the default";
	setShown(false);
	flush();
	const restored = viewCamera(refs[0]);
	assert restored.ok && restored.value.position === vec3(0.0, 0.0, 5.0), "unmounting it restores the default";
}
