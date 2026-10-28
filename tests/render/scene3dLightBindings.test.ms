import { createSignal } from "../../src/core/signal";
import { flush, resetErrorHalt } from "../../src/core/runtime";
import { element } from "../../src/macros/ui/element";
import { HostNode, MockNode, mockNode, mockHost, render } from "../../src/render/host";
import { Void, View } from "../../src/components/primitives";
import { Scene3D, Scene3DHandle, Light, DirectionalLight, PointLight } from "../../src/components/scene3d";
import {
	NodeId3D, NO_NODE_ID, LightKind, collectLights, nodeCount,
} from "../../../void/src/void3d/scene";
import { LIGHT_UNIFORM_LENGTH, LIGHT_RECORD_LENGTH, LIGHT_RECORD_COLOR } from "../../../void/src/void3d/gpu3d";
import { vec3 } from "../../../void/src/math/math3d";
import { approx } from "../../../void/src/test/helpers";
import { DirShadowMap } from "../../../void/src/void3d/dirShadowMap";

function frameRequests(outer: MockNode): int32 {
	let count: int32 = 0;
	for (const attr of outer.attrs) {
		if (attr.name === "frameRequested") { count += 1; }
	}
	return count;
}

test "Light color radius priority power and pose update retained nodes and collected slots" {
	const refs: Scene3DHandle[] = [];
	const nodes: NodeId3D[] = [];
	const [value, setValue] = createSignal<float32>(1.0);
	const [priority, setPriority] = createSignal(5);
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene3D
		ref={(handle: Scene3DHandle): void => { refs.push(handle); }}>
		<Light kind={LightKind.Point} color={vec3(value(), 0.2, 0.3)} radius={value() + 2.0}
			priority={priority()} power={value() * 2.0} position={vec3(value(), 0.0, 0.0)}
			ref={(node: NodeId3D): void => { nodes.push(node); }} />
		<Light kind={LightKind.Point} color={vec3(0.4, 0.5, 0.6)} radius={8.0}
			priority={3} power={4.0} position={vec3(20.0, 0.0, 0.0)}
			ref={(node: NodeId3D): void => { nodes.push(node); }} />
	</Scene3D></Void>), mockHost(), root as unknown as HostNode);
	const outer = root.children[0];
	try {
		const scene = refs[0].scene;
		let block: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
		const first = LIGHT_UNIFORM_LENGTH;
		const second = LIGHT_UNIFORM_LENGTH + LIGHT_RECORD_LENGTH;
		assert collectLights(scene, block).ok;
		assert approx(block[first], 1.0) && approx(block[first + 3], 2.0);
		const requests = frameRequests(root.children[0]);
		setValue(7.0); setPriority(0); flush();
		assert nodes.length === 2 && scene.nodeCount() === 3;
		assert collectLights(scene, block).ok;
		assert approx(block[first], 7.0) && approx(block[first + 3], 14.0);
		assert approx(block[first + LIGHT_RECORD_COLOR], 7.0) && approx(block[first + LIGHT_RECORD_COLOR + 3], 9.0);
		assert approx(block[second], 20.0) && approx(block[second + 3], 4.0);
		assert approx(block[second + LIGHT_RECORD_COLOR], 0.4) && approx(block[second + LIGHT_RECORD_COLOR + 3], 8.0);
		assert scene.lights[scene.nodes[nodes[0].index].payload].priority === 0;
		assert scene.lights[scene.nodes[nodes[1].index].payload].priority === 3;
		assert frameRequests(root.children[0]) > requests;
		setValue(2.0); setPriority(9); flush();
		assert collectLights(scene, block).ok;
		assert approx(block[first], 2.0) && approx(block[first + 3], 4.0);
		assert approx(block[first + LIGHT_RECORD_COLOR], 2.0) && approx(block[first + LIGHT_RECORD_COLOR + 3], 4.0);
		assert approx(block[second], 20.0), "the sibling's record is unchanged";
		assert scene.lights[scene.nodes[nodes[0].index].payload].priority === 9;
	} finally { dispose(); resetErrorHalt(); }
	const requests = frameRequests(outer);
	setValue(3.0); setPriority(1); flush();
	assert refs[0].context.closed && refs[0].scene.nodeCount() === 0;
	assert frameRequests(outer) === requests;
}

test "Light parameter binders each invalidate only their own area" {
	const refs: Scene3DHandle[] = [];
	const [color, setColor] = createSignal<float32>(0.2);
	const [radius, setRadius] = createSignal<float32>(2.0);
	const [priority, setPriority] = createSignal(0);
	const root = mockNode("root");
	const dispose = render(element(<View>
		<Void><Scene3D ref={(handle: Scene3DHandle): void => { refs.push(handle); }}>
			<Light kind={LightKind.Point} color={vec3(color(), 0.3, 0.4)}
				radius={radius()} priority={priority()} />
		</Scene3D></Void>
		<Void><Scene3D ref={(handle: Scene3DHandle): void => { refs.push(handle); }}>
			<Light kind={LightKind.Point} />
		</Scene3D></Void>
	</View>), mockHost(), root as unknown as HostNode);
	try {
		const first = root.children[0].children[0];
		const sibling = root.children[0].children[1];
		let requested = frameRequests(first);
		const siblingRequests = frameRequests(sibling);
		setColor(0.8); flush();
		assert frameRequests(first) > requested;
		requested = frameRequests(first);
		setRadius(9.0); flush();
		assert frameRequests(first) > requested;
		requested = frameRequests(first);
		setPriority(7); flush();
		assert frameRequests(first) > requested;
		assert frameRequests(sibling) === siblingRequests;
		assert refs[0].scene.lights[0].color === vec3(0.8, 0.3, 0.4);
		assert approx(refs[0].scene.lights[0].radius, 9.0);
		assert refs[0].scene.lights[0].priority === 7;
		assert refs[1].scene.lights[0].color === vec3(1.0, 1.0, 1.0);
		assert approx(refs[1].scene.lights[0].radius, 10.0);
		assert refs[1].scene.lights[0].priority === 0;
	} finally { dispose(); resetErrorHalt(); }
}

test "Directional Light color updates without changing fixed kind or power" {
	const refs: Scene3DHandle[] = [];
	const [value, setValue] = createSignal<float32>(0.2);
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene3D
		ref={(handle: Scene3DHandle): void => { refs.push(handle); }}>
		<Light kind={LightKind.Directional} color={vec3(value(), 0.3, 0.4)} power={0.5} />
	</Scene3D></Void>), mockHost(), root as unknown as HostNode);
	try {
		setValue(0.8); flush();
		let block: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
		assert collectLights(refs[0].scene, block).ok;
		assert approx(block[8], 0.8) && approx(block[9], 0.3) && approx(block[10], 0.4);
		assert approx(block[7], 0.5);
	} finally { dispose(); resetErrorHalt(); }
}

test "Light keeps named kind refusal and applies other parameters after reset and retry" {
	const refs: Scene3DHandle[] = [];
	let node = NO_NODE_ID;
	const [directional, setDirectional] = createSignal(false);
	const [radius, setRadius] = createSignal<float32>(2.0);
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene3D
		ref={(handle: Scene3DHandle): void => { refs.push(handle); }}>
		<Light kind={directional() ? LightKind.Directional : LightKind.Point}
			color={vec3(radius(), 0.0, 0.0)} radius={radius()} priority={4}
			ref={(value: NodeId3D): void => { node = value; }} />
	</Scene3D></Void>), mockHost(), root as unknown as HostNode);
	try {
		let message = "";
		try { setDirectional(true); setRadius(5.0); flush(); }
		catch (error) { message = error.toString(); }
		finally { resetErrorHalt(); }
		assert message.includes("Light: kind cannot change; Void has no light-kind binder");
		const scene = refs[0].scene;
		const row = scene.nodes[node.index].payload;
		assert scene.lights[row].kind === LightKind.Point;
		assert approx(scene.lights[row].radius, 2.0);
		assert scene.lights[row].color === vec3(2.0, 0.0, 0.0);
		setDirectional(false); flush();
		assert scene.lights[row].kind === LightKind.Point;
		assert approx(scene.lights[row].radius, 5.0);
		assert scene.lights[row].color === vec3(5.0, 0.0, 0.0);
		assert scene.lights[row].priority === 4 && approx(scene.lights[row].power, 1.0);
	} finally { dispose(); resetErrorHalt(); }
}

test "DirectionalLight and PointLight mount the Light of their kind with reactive props" {
	const refs: Scene3DHandle[] = [];
	const [value, setValue] = createSignal<float32>(0.2);
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene3D
		ref={(handle: Scene3DHandle): void => { refs.push(handle); }}>
		<DirectionalLight color={vec3(value(), 0.3, 0.4)} power={0.5} castShadow={true} shadowOpacity={0.5} />
		<PointLight color={vec3(0.4, 0.5, 0.6)} radius={value() + 2.0} power={3.0} priority={2} position={vec3(4.0, 0.0, 0.0)} />
	</Scene3D></Void>), mockHost(), root as unknown as HostNode);
	try {
		const scene = refs[0].scene;
		assert scene.lights[0].kind === LightKind.Directional && scene.lights[1].kind === LightKind.Point;
		const shadow = refs[0].renderer.core.shadow;
		assert shadow !== null && (shadow as DirShadowMap).opacity === 0.5;
		setValue(0.8); flush();
		let block: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
		const colorAt = 12 + MAX_POINT_LIGHTS * 4;
		assert collectLights(scene, block).ok;
		assert approx(block[7], 0.5) && approx(block[8], 0.8);
		assert approx(block[12], 4.0) && approx(block[15], 3.0) && approx(block[colorAt + 3], 2.8);
		assert scene.lights[1].priority === 2;
	} finally { dispose(); resetErrorHalt(); }
	assert refs[0].renderer.closed && refs[0].scene.nodeCount() === 0;
}
