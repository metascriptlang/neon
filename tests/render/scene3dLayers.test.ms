import { createSignal } from "../../src/core/signal";
import { flush } from "../../src/core/runtime";
import { element } from "../../src/macros/ui/element";
import { Show } from "../../src/macros/ui/flow";
import { HostNode, mockHost, mockNode, mockAreaHub, render } from "../../src/render/host";
import { Void, View } from "../../src/components/primitives";
import { Scene3D, Scene3DHandle, Group, Mesh, Light, Camera3D } from "../../src/components/scene3d";
import { NodeId3D, LightKind, layersOf, renderOrderOf, refresh, collectLights, isLive } from "../../../void/src/void3d/scene";
import { DrawItem, MeshId, releaseMesh } from "../../../void/src/void3d/draw";
import { added, litShape } from "../../../void/src/test/drawHelpers";
import { layerBit, DEFAULT_LAYERS } from "../../../void/src/void3d/layers";
import { LIGHT_UNIFORM_LENGTH } from "../../../void/src/void3d/gpu3d";

test "node masks do not prune children and reactive renderOrder reaches the retained draw list" {
	const [mask, setMask] = createSignal<uint32>(layerBit(1));
	const [order, setOrder] = createSignal<int32>(7);
	const refs: Scene3DHandle[] = [];
	const nodes: NodeId3D[] = [];
	const meshes: MeshId[] = [];
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene3D ref={(handle: Scene3DHandle): void => { refs.push(handle); meshes.push(added(handle.context, litShape())); }}>
		<Group layers={layerBit(3)} ref={(node: NodeId3D): void => { nodes.push(node); }}>
			<Mesh mesh={meshes[0]} layers={mask()} renderOrder={order()} ref={(node: NodeId3D): void => { nodes.push(node); }} />
			<Mesh mesh={meshes[0]} ref={(node: NodeId3D): void => { nodes.push(node); }} />
		</Group>
	</Scene3D></Void>), mockHost(), root as unknown as HostNode);
	assert releaseMesh(refs[0].context, meshes[0]).ok;
	try {
		const scene = refs[0].scene;
		let items: Vec<DrawItem> = [];
		assert scene.layersOf(nodes[0]) === layerBit(3);
		assert scene.layersOf(nodes[2]) === DEFAULT_LAYERS;
		assert refresh(scene, items) === 1 && items[0].order === 0;
		setMask(DEFAULT_LAYERS); flush();
		assert refresh(scene, items) === 2 && items[0].order === 7;
		setOrder(-4); flush();
		assert refresh(scene, items) === 2 && items[0].order === -4 && items[1].order === 0;
		assert scene.renderOrderOf(nodes[1]) === -4 && nodes.length === 3;
		setMask(0); flush();
		assert refresh(scene, items) === 1;
	} finally { dispose(); }
	assert refs[0].scene.closed && refs[0].context.closed;
}

test "active camera layers filter both meshes and lights and restore defaults when removed" {
	const [mask, setMask] = createSignal<uint32>(layerBit(1));
	const [active, setActive] = createSignal(true);
	const [shown, setShown] = createSignal(true);
	const refs: Scene3DHandle[] = [];
	const meshes: MeshId[] = [];
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene3D ref={(handle: Scene3DHandle): void => { refs.push(handle); meshes.push(added(handle.context, litShape())); }}>
		<Mesh mesh={meshes[0]} renderOrder={1} />
		<Mesh mesh={meshes[0]} layers={layerBit(1)} renderOrder={2} />
		<Light kind={LightKind.Directional} power={0.25} />
		<Light kind={LightKind.Directional} layers={layerBit(1)} power={0.75} />
		<Show when={shown()}><Camera3D active={active()} layers={mask()} /></Show>
	</Scene3D></Void>), mockHost(), root as unknown as HostNode);
	assert releaseMesh(refs[0].context, meshes[0]).ok;
	try {
		const scene = refs[0].scene;
		let items: Vec<DrawItem> = [];
		let block: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
		assert refresh(scene, items) === 1 && items[0].order === 2;
		assert collectLights(scene, block).ok && block[7] === 0.75;
		const outer = root.children[0];
		const before = outer.attrs.length;
		setMask(DEFAULT_LAYERS); flush();
		assert outer.attrs.length > before;
		assert refresh(scene, items) === 1 && items[0].order === 1;
		assert collectLights(scene, block).ok && block[7] === 0.25;
		setMask(layerBit(1)); setActive(false); flush();
		assert refresh(scene, items) === 1 && items[0].order === 1;
		assert collectLights(scene, block).ok && block[7] === 0.25;
		setActive(true); flush();
		assert refresh(scene, items) === 1 && items[0].order === 2;
		setShown(false); flush();
		assert refresh(scene, items) === 1 && items[0].order === 1;
		assert collectLights(scene, block).ok && block[7] === 0.25;
		assert mockAreaHub(outer).layers().length === 1;
	} finally { dispose(); }
}

test "removing the last active camera restores the earlier camera mask including bit 31" {
	const [shown, setShown] = createSignal(true);
	const refs: Scene3DHandle[] = [];
	const meshes: MeshId[] = [];
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene3D ref={(handle: Scene3DHandle): void => { refs.push(handle); meshes.push(added(handle.context, litShape())); }}>
		<Mesh mesh={meshes[0]} renderOrder={1} />
		<Mesh mesh={meshes[0]} layers={layerBit(31)} renderOrder={31} />
		<Camera3D active={true} layers={layerBit(31)} />
		<Show when={shown()}><Camera3D active={true} /></Show>
	</Scene3D></Void>), mockHost(), root as unknown as HostNode);
	assert releaseMesh(refs[0].context, meshes[0]).ok;
	try {
		let items: Vec<DrawItem> = [];
		assert refresh(refs[0].scene, items) === 1 && items[0].order === 1;
		setShown(false); flush();
		assert refresh(refs[0].scene, items) === 1 && items[0].order === 31;
		setShown(true); flush();
		assert refresh(refs[0].scene, items) === 1 && items[0].order === 1;
	} finally { dispose(); }
}

test "node layer and order updates wake only their owning area and stop after disposal" {
	const [mask, setMask] = createSignal<uint32>(1);
	const [order, setOrder] = createSignal<int32>(0);
	const nodes: NodeId3D[] = [];
	const refs: Scene3DHandle[] = [];
	const root = mockNode("root");
	const dispose = render(element(<View>
		<Void><Scene3D ref={(handle: Scene3DHandle): void => { refs.push(handle); }}>
			<Group layers={mask()} renderOrder={order()} ref={(node: NodeId3D): void => { nodes.push(node); }} />
		</Scene3D></Void>
		<Void><Scene3D><Group /></Scene3D></Void>
	</View>), mockHost(), root as unknown as HostNode);
	const first = root.children[0].children[0];
	const second = root.children[0].children[1];
	try {
		const siblingRequests = second.attrs.length;
		let requested = first.attrs.length;
		setMask(layerBit(31)); flush();
		assert first.attrs.length > requested && second.attrs.length === siblingRequests;
		requested = first.attrs.length;
		setOrder(-9); flush();
		assert first.attrs.length > requested && second.attrs.length === siblingRequests;
		assert refs[0].scene.layersOf(nodes[0]) === layerBit(31);
		assert refs[0].scene.renderOrderOf(nodes[0]) === -9;
	} finally { dispose(); }
	const requested = first.attrs.length;
	setMask(0); setOrder(5); flush();
	assert first.attrs.length === requested && refs[0].scene.closed;
}
