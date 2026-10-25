import { accessor, createSignal } from "../../src/core/signal";
import { createRoot } from "../../src/core/owner";
import { flush, resetErrorHalt } from "../../src/core/runtime";
import { element } from "../../src/macros/ui/element";
import { Show } from "../../src/macros/ui/flow";
import { NeonNode } from "../../src/render/node";
import { HostNode, MockNode, mockNode, mockHost, render, mockToString } from "../../src/render/host";
import { Void, View, Text, Pressable, TextInput } from "../../src/components/primitives";
import { Scene3D, Scene3DHandle, Group, Mesh, Light, Camera3D } from "../../src/components/scene3d";
import { Vec3, vec3, eulerQuat } from "../../../void/src/math/math3d";
import { NodeId3D, NO_NODE_ID, NodeKind, Transform3D, LightKind, syncWorld, nodeCount, isLive, worldOf, cameraOf } from "../../../void/src/void3d/scene";
import { MeshId, MaterialId, NO_MESH, NO_MATERIAL, DrawContext, addMaterial, releaseMesh, releaseMaterial, hasMesh, hasMaterial } from "../../../void/src/void3d/draw";
import { Material, Phase } from "../../../void/src/void3d/material";
import { MeshData } from "../../../void/src/void3d/meshData";
import { ProjectionKind, CameraProjection } from "../../../void/src/void3d/camera";
import { Program, ProgramKey, of } from "../../../void/src/void3d/gpu3d";
import { RenderState } from "../../../void/src/gpu/state";
import { added, litShape, meshAt, materialAt, writeTables } from "../../../void/src/test/drawHelpers";
import { approx } from "../../../void/src/test/helpers";
import { holds } from "../../../void/src/void3d/uniformPool";

function mounted(node: NeonNode): () => void {
	const root: MockNode = mockNode("root");
	return render(node, mockHost(), root as unknown as HostNode);
}

function seedMesh(context: DrawContext): MeshId {
	return added(context, litShape());
}

function mountError(node: NeonNode): string {
	let message = "";
	createRoot((dispose: () => void): void => {
		try {
			const root = mockNode("root");
			node(mockHost(), root as unknown as HostNode, null);
		} catch (error) { message = error.toString(); } finally { dispose(); resetErrorHalt(); }
	});
	return message;
}

function nearVec(value: Vec3, x: float32, y: float32, z: float32): boolean {
	return approx(value.x, x) && approx(value.y, y) && approx(value.z, z);
}

test "Scene3D creates and closes its actual scene and context" {
	const refs: Scene3DHandle[] = [];
	const dispose = mounted(element(<Void><Scene3D ref={(value: Scene3DHandle): void => { refs.push(value); }} /></Void>));
	const handle: Scene3DHandle | null = refs.length === 0 ? null : refs[0];
	if (handle === null) { throw new Error("fixture: handle ref did not mount"); }
	assert !handle.scene.closed, "scene is open after mount";
	assert !handle.context.closed, "context is open after mount";
	assert handle.scene.context === handle.context, "scene keeps the context it owns";
	assert handle.scene.nodeCount() === 1, "a fresh scene has only its root";
	assert handle.scene.nodes[handle.scene.root].kind === NodeKind.Group, "root is Void's group";
	assert handle.camera === null, "no mounted active camera means no selected camera";
	dispose();
	assert handle.scene.closed, "scene closes on disposal";
	assert handle.context.closed, "context closes on disposal";
	assert handle.context.uniforms.closed, "owned uniform pool closes too";
	assert handle.scene.nodeCount() === 0, "disposal removes all scene nodes";
}

test "all five components mount real Void nodes without creating host elements" {
	const refs: Scene3DHandle[] = [];
	let mesh = NO_MESH;
	let groupId = NO_NODE_ID;
	let meshId = NO_NODE_ID;
	let lightId = NO_NODE_ID;
	let meshChild = NO_NODE_ID;
	const root = mockNode("root");
	const dispose = render(element(<Void><Scene3D ref={(value: Scene3DHandle): void => {
		refs.push(value);
		mesh = seedMesh(value.context);
	}}>
		<Camera3D active={true} position={vec3(0.0, 3.0, 8.0)} />
		<Group ref={(value: NodeId3D): void => { groupId = value; }}>
			<Mesh mesh={mesh} ref={(value: NodeId3D): void => { meshId = value; }}>
				<Group ref={(value: NodeId3D): void => { meshChild = value; }} />
			</Mesh>
			<Light kind={LightKind.Directional} ref={(value: NodeId3D): void => { lightId = value; }} />
		</Group>
	</Scene3D><View><Text>HUD</Text></View></Void>), mockHost(), root as unknown as HostNode);
	const handle: Scene3DHandle | null = refs.length === 0 ? null : refs[0];
	if (handle === null) { throw new Error("fixture: handle ref did not mount"); }
	assert handle.scene.nodeCount() === 6, "root, camera binding, group, mesh, mesh child and light";
	assert handle.scene.nodes[groupId.index].parent === handle.scene.root, "group parent is scene root";
	assert handle.scene.nodes[meshId.index].parent === groupId.index, "mesh parent is enclosing group";
	assert handle.scene.nodes[lightId.index].parent === groupId.index, "light parent is enclosing group";
	assert handle.scene.nodes[meshChild.index].parent === meshId.index, "mesh establishes a descendant parent";
	assert handle.scene.nodes[meshId.index].kind === NodeKind.Mesh, "mesh is a real Void mesh node";
	assert handle.scene.nodes[lightId.index].kind === NodeKind.Light, "light is a real Void light node";
	assert handle.camera !== null, "active camera is selected";
	const outer = root.children[0];
	assert root.children.length === 1 && outer.tag === "void" && outer.children.length === 1, "the Void is the only host element";
	let otherAttrs = 0;
	for (const a of outer.attrs) { if (a.name !== "frameRequested") { otherAttrs = otherAttrs + 1; } }
	assert outer.attrs.length > 0 && otherAttrs === 0, "the scene only asks its area for frames";
	assert mockToString(outer.children[0]) === "<voidroot><view><text>HUD</text></view></voidroot>", "3D stays out of host element creation, HUD remains 2D";
	const released = releaseMesh(handle.context, mesh);
	assert released.ok, "caller can release its uploaded mesh hold while a node pins it";
	dispose();
	assert !handle.scene.isLive(groupId) && !handle.scene.isLive(meshId) && !handle.scene.isLive(lightId), "all component nodes are removed";
	assert handle.context.meshHolders[mesh.index] === 0, "last node pin releases the mesh";
}

test "nested world transforms follow signals and stop after disposal" {
	const refs: Scene3DHandle[] = [];
	let parent = NO_NODE_ID;
	let child = NO_NODE_ID;
	const [x, setX] = createSignal<float32>(2.0);
	const [y, setY] = createSignal<float32>(3.0);
	const dispose = mounted(element(<Void><Scene3D ref={(value: Scene3DHandle): void => { refs.push(value); }}>
		<Group position={vec3(x(), 0.0, 0.0)} ref={(value: NodeId3D): void => { parent = value; }}>
			<Group position={vec3(0.0, y(), 4.0)} ref={(value: NodeId3D): void => { child = value; }} />
		</Group>
	</Scene3D></Void>));
	const handle: Scene3DHandle | null = refs.length === 0 ? null : refs[0];
	if (handle === null) { throw new Error("fixture: handle ref did not mount"); }
	syncWorld(handle.scene);
	const initial = handle.scene.worldOf(child);
	assert initial.ok, "nested child's world matrix exists";
	if (initial.ok) { assert approx(initial.value.m41, 2.0) && approx(initial.value.m42, 3.0) && approx(initial.value.m43, 4.0), "initial local translations compose"; }
	setX(7.0);
	flush();
	setY(9.0);
	flush();
	syncWorld(handle.scene);
	const changed = handle.scene.worldOf(child);
	assert changed.ok, "nested world remains available";
	if (changed.ok) { assert approx(changed.value.m41, 7.0) && approx(changed.value.m42, 9.0) && approx(changed.value.m43, 4.0), "signals update nested world"; }
	dispose();
	setX(12.0);
	flush();
	setY(15.0);
	flush();
	assert handle.scene.closed && handle.context.closed, "disposed effects never call binders on closed owners";
	assert !handle.scene.isLive(parent) && !handle.scene.isLive(child), "disposed transform handles are stale";
}

test "rotation and scale carry nested offsets and individual props override transform" {
	const refs: Scene3DHandle[] = [];
	let parent = NO_NODE_ID;
	let child = NO_NODE_ID;
	const [turn, setTurn] = createSignal<float32>(1.5707963);
	const base = Transform3D.fromTranslation(vec3(90.0, 90.0, 90.0));
	const dispose = mounted(element(<Void><Scene3D ref={(value: Scene3DHandle): void => { refs.push(value); }}>
		<Group transform={base} position={vec3(5.0, 0.0, 0.0)} rotation={eulerQuat(0.0, turn(), 0.0)} scale={vec3(2.0, 2.0, 2.0)} ref={(value: NodeId3D): void => { parent = value; }}>
			<Group position={vec3(1.0, 0.0, 0.0)} ref={(value: NodeId3D): void => { child = value; }} />
		</Group>
	</Scene3D></Void>));
	const handle: Scene3DHandle | null = refs.length === 0 ? null : refs[0];
	if (handle === null) { throw new Error("fixture: handle ref did not mount"); }
	assert nearVec(handle.scene.nodes[parent.index].local.position, 5.0, 0.0, 0.0), "position overrides full transform";
	const firstSync = syncWorld(handle.scene);
	const first = handle.scene.worldOf(child);
	assert first.ok, "rotated child has world transform";
	if (first.ok) { assert approx(first.value.m41, 5.0) && approx(first.value.m42, 0.0) && approx(first.value.m43, -2.0), "parent rotation and scale transform child's offset"; }
	setTurn(0.0);
	flush();
	const nextSync = syncWorld(handle.scene);
	const next = handle.scene.worldOf(child);
	assert next.ok, "unrotated child has world transform";
	if (next.ok) { assert approx(next.value.m41, 7.0) && approx(next.value.m43, 0.0), "rotation is reactive"; }
	dispose();
}

test "Light power and local pose react under a moving group" {
	const refs: Scene3DHandle[] = [];
	let light = NO_NODE_ID;
	const [power, setPower] = createSignal<float32>(1.5);
	const [height, setHeight] = createSignal<float32>(2.0);
	const [offset, setOffset] = createSignal<float32>(4.0);
	const dispose = mounted(element(<Void><Scene3D ref={(value: Scene3DHandle): void => { refs.push(value); }}>
		<Group position={vec3(offset(), 0.0, 0.0)}>
			<Light kind={LightKind.Point} color={vec3(0.8, 0.4, 0.2)} radius={8.0} priority={3} power={power()} position={vec3(0.0, height(), 0.0)} ref={(value: NodeId3D): void => { light = value; }} />
		</Group>
	</Scene3D></Void>));
	const handle: Scene3DHandle | null = refs.length === 0 ? null : refs[0];
	if (handle === null) { throw new Error("fixture: handle ref did not mount"); }
	const payload = handle.scene.nodes[light.index].payload;
	assert handle.scene.lights[payload].kind === LightKind.Point, "authored kind reaches light";
	assert approx(handle.scene.lights[payload].power, 1.5), "initial power";
	assert nearVec(handle.scene.lights[payload].color, 0.8, 0.4, 0.2), "authored color";
	assert approx(handle.scene.lights[payload].radius, 8.0) && handle.scene.lights[payload].priority === 3, "authored radius and priority";
	setPower(6.0);
	flush();
	setHeight(7.0);
	flush();
	setOffset(9.0);
	flush();
	const synced = syncWorld(handle.scene);
	assert approx(handle.scene.lights[payload].power, 6.0), "power binder follows signal";
	const world = handle.scene.worldOf(light);
	assert world.ok, "light world is available";
	if (world.ok) { assert approx(world.value.m41, 9.0) && approx(world.value.m42, 7.0), "light pose and ancestor pose are reactive"; }
	dispose();
	setPower(12.0);
	flush();
	setHeight(14.0);
	flush();
	assert handle.scene.nodeCount() === 0 && handle.context.closed, "light effects stop with owner";
}

test "Camera3D selection restores active world-bound cameras and reacts" {
	const refs: Scene3DHandle[] = [];
	const [firstActive, setFirstActive] = createSignal(true);
	const [secondActive, setSecondActive] = createSignal(true);
	const [showSecond, setShowSecond] = createSignal(true);
	const [x, setX] = createSignal<float32>(2.0);
	const [yaw, setYaw] = createSignal<float32>(0.1);
	const [pitch, setPitch] = createSignal<float32>(0.2);
	const [near, setNear] = createSignal<float32>(0.3);
	const [far, setFar] = createSignal<float32>(100.0);
	const [projection, setProjection] = createSignal<CameraProjection>({ kind: ProjectionKind.Perspective, fovY: 1.0 });
	const dispose = mounted(element(<Void><Scene3D ref={(value: Scene3DHandle): void => { refs.push(value); }}>
		<Camera3D active={firstActive()} position={vec3(x(), 3.0, 8.0)} yaw={yaw()} pitch={pitch()} nearPlane={near()} farPlane={far()} projection={projection()} />
		{Show({ when: accessor(() => showSecond()), children: element(<Camera3D active={secondActive()} position={vec3(20.0, 0.0, 0.0)} />) })}
	</Scene3D></Void>));
	const handle: Scene3DHandle | null = refs.length === 0 ? null : refs[0];
	if (handle === null) { throw new Error("fixture: handle ref did not mount"); }
	assert handle.scene.nodeCount() === 3, "root and two camera bindings are live";
	assert handle.camera !== null, "most recently mounted active camera wins";
	if (handle.camera !== null) { assert approx(handle.camera.position.x, 20.0), "second camera selected"; }
	setSecondActive(false);
	flush();
	assert handle.camera !== null, "disabling active winner restores prior camera";
	if (handle.camera !== null) { assert approx(handle.camera.position.x, 2.0), "first camera restored"; }
	setX(7.0); setYaw(0.7); setPitch(0.4); setNear(0.5); setFar(250.0);
	flush();
	if (handle.camera !== null) {
		assert nearVec(handle.camera.position, 7.0, 3.0, 8.0), "camera pose follows signal";
		assert approx(handle.camera.yaw, 0.7) && approx(handle.camera.pitch, 0.4), "camera angles follow signals";
		assert approx(handle.camera.nearPlane, 0.5) && approx(handle.camera.farPlane, 250.0), "camera depth range follows signals";
		assert handle.camera.projection.kind === ProjectionKind.Perspective, "authored projection retained";
	}
	setProjection({ kind: ProjectionKind.Orthographic, worldPerTexel: 0.1, snap: false });
	flush();
	if (handle.camera !== null) { assert handle.camera.projection.kind === ProjectionKind.Orthographic, "camera projection follows signal"; }
	setSecondActive(true);
	flush();
	if (handle.camera !== null) { assert approx(handle.camera.position.x, 20.0), "reenabling winner selects it"; }
	setShowSecond(false);
	flush();
	assert !handle.scene.closed && handle.camera !== null, "removing camera leaves scene open and restores another active camera";
	if (handle.camera !== null) { assert approx(handle.camera.position.x, 7.0), "removal restores updated first camera"; }
	setFirstActive(false);
	flush();
	assert handle.camera === null, "no active cameras means null";
	setFirstActive(true);
	flush();
	assert handle.camera !== null, "reactivation selects remaining camera";
	dispose();
	setX(90.0); setFirstActive(false);
	flush();
	assert handle.camera === null, "disposal clears selected camera and stops selection effects";
}

test "Mesh uses seeded resources, shares default material and removes a subtree while scene stays open" {
	const refs: Scene3DHandle[] = [];
	let resource = NO_MESH;
	let removable = NO_NODE_ID;
	let first = NO_NODE_ID;
	let second = NO_NODE_ID;
	const [shown, setShown] = createSignal(true);
	const dispose = mounted(element(<Void><Scene3D ref={(value: Scene3DHandle): void => {
		refs.push(value);
		resource = seedMesh(value.context);
		const data: Vec<MeshData> = [MeshData.empty()];
		const materials: Vec<Material> = [];
		writeTables(value.context, data, materials);
	}}>
		{Show({ when: accessor(() => shown()), children: element(<Group ref={(value: NodeId3D): void => { removable = value; }}><Mesh mesh={resource} ref={(value: NodeId3D): void => { first = value; }} /></Group>) })}
		<Mesh mesh={resource} ref={(value: NodeId3D): void => { second = value; }} />
	</Scene3D></Void>));
	const handle: Scene3DHandle | null = refs.length === 0 ? null : refs[0];
	if (handle === null) { throw new Error("fixture: handle ref did not mount"); }
	assert handle.context.meshAt(resource.index) === resource, "resource is issued by the scene's context";
	const firstMaterial: MaterialId = handle.scene.meshes[handle.scene.nodes[first.index].payload].material;
	const secondMaterial: MaterialId = handle.scene.meshes[handle.scene.nodes[second.index].payload].material;
	assert firstMaterial === secondMaterial, "default material is shared by scene meshes";
	assert handle.context.materialAt(firstMaterial.index) === firstMaterial, "default material is real context resource";
	assert handle.context.materials[firstMaterial.index].program === ProgramKey.of(Program.Lit), "default material uses core lit program without extra features";
	const block = handle.context.materialBlocks[firstMaterial.index];
	assert block.length > 0 && handle.context.uniforms.holds(block), "default material owns a live lit uniform range";
	assert handle.context.meshPins[resource.index] === 2 && handle.context.meshHolders[resource.index] === 3, "borrowed resource retains caller hold and gains two node pins";
	setShown(false);
	flush();
	assert !handle.scene.closed && !handle.context.closed, "structural removal does not close the scene";
	assert handle.scene.nodeCount() === 2, "root and surviving mesh remain";
	assert !handle.scene.isLive(removable) && !handle.scene.isLive(first) && handle.scene.isLive(second), "subtree removed, sibling remains live";
	assert handle.context.meshPins[resource.index] === 1 && handle.context.meshHolders[resource.index] === 2, "removal releases only removed node's pin";
	assert handle.context.hasMaterial(firstMaterial) && handle.context.uniforms.holds(block), "default material survives one consumer removal";
	setShown(true);
	flush();
	assert handle.scene.nodeCount() === 5, "subtree can mount again while same scene is open, beside the Show's hidden holder";
	const restoredMaterial = handle.scene.meshes[handle.scene.nodes[first.index].payload].material;
	assert restoredMaterial === firstMaterial, "remount reuses scene default material";
	const released = releaseMesh(handle.context, resource);
	assert released.ok, "caller releases its original hold before context closes";
	dispose();
	assert handle.context.closed && handle.scene.closed, "resource-bearing owners close successfully";
	assert handle.context.meshHolders[resource.index] === 0 && handle.context.meshPins[resource.index] === 0, "no mesh holds or pins remain";
	assert handle.context.materialHolders[firstMaterial.index] === 0 && handle.context.materialPins[firstMaterial.index] === 0, "no default material holds or pins remain";
	assert !handle.context.uniforms.holds(block), "default material's range is released";
}

test "Mesh borrows explicitly supplied material without taking the caller's hold" {
	const refs: Scene3DHandle[] = [];
	let mesh = NO_MESH;
	let material = NO_MATERIAL;
	let meshNode = NO_NODE_ID;
	const [shown, setShown] = createSignal(true);
	const dispose = mounted(element(<Void><Scene3D ref={(value: Scene3DHandle): void => {
		refs.push(value);
		mesh = seedMesh(value.context);
		const result = addMaterial(value.context, Material.plain(Program.Lit, RenderState.defaults(), Phase.Opaque));
		if (!result.ok) { throw new Error("test fixture addMaterial: " + result.error.toString()); }
		material = result.value;
	}}>{Show({ when: accessor(() => shown()), children: element(<Mesh mesh={mesh} material={material} ref={(value: NodeId3D): void => { meshNode = value; }} />) })}</Scene3D></Void>));
	const handle: Scene3DHandle | null = refs.length === 0 ? null : refs[0];
	if (handle === null) { throw new Error("fixture: handle ref did not mount"); }
	assert handle.scene.meshes[handle.scene.nodes[meshNode.index].payload].material === material, "supplied material reaches node";
	assert handle.context.materialHolders[material.index] === 2 && handle.context.materialPins[material.index] === 1, "node pins supplied material without consuming caller hold";
	setShown(false);
	flush();
	assert handle.context.hasMaterial(material) && handle.context.materialHolders[material.index] === 1, "caller material survives node removal";
	assert handle.context.hasMesh(mesh) && handle.context.meshHolders[mesh.index] === 1, "caller mesh survives node removal";
	const freedMesh = releaseMesh(handle.context, mesh);
	const freedMaterial = releaseMaterial(handle.context, material);
	assert freedMesh.ok && freedMaterial.ok, "caller releases borrowed resource originals";
	dispose();
	assert handle.context.closed, "borrowed resources do not prevent close after caller releases";
}

test "Scene3D and every 3D child reject invalid parent contexts" {
	const outside = mountError(element(<Scene3D />));
	assert outside.includes("Scene3D") && outside.includes("Void"), "Scene3D outside Void names allowed parent: " + outside;
	const group = mountError(element(<Void><Group /></Void>));
	const light = mountError(element(<Void><Light kind={LightKind.Point} /></Void>));
	const mesh = mountError(element(<Void><Mesh geometry={MeshData.empty()} /></Void>));
	const camera = mountError(element(<Void><Camera3D /></Void>));
	assert group.includes("Group") && group.includes("Scene3D"), "Group requires scene: " + group;
	assert light.includes("Light") && light.includes("Scene3D"), "Light requires scene: " + light;
	assert mesh.includes("Mesh") && mesh.includes("Scene3D"), "Mesh requires scene before any upload: " + mesh;
	assert camera.includes("Camera3D") && camera.includes("Scene3D"), "Camera3D requires scene: " + camera;
}

test "View Text Pressable and TextInput reject the open Scene3D context" {
	const view = mountError(element(<Void><Scene3D><View /></Scene3D></Void>));
	const text = mountError(element(<Void><Scene3D><Text>not HUD</Text></Scene3D></Void>));
	const pressable = mountError(element(<Void><Scene3D><Pressable /></Scene3D></Void>));
	const input = mountError(element(<Void><Scene3D><TextInput /></Scene3D></Void>));
	assert view.includes("<View> belongs in <Void>, <Texture> or a 2D parent, not directly in <Scene3D>"), "View names where it belongs: " + view;
	assert text.includes("Scene3D: <text> has no 3D node to act on"), "Text names incompatible scene: " + text;
	assert pressable.includes("Scene3D: <pressable> has no 3D node to act on"), "Pressable names incompatible scene: " + pressable;
	assert input.includes("Scene3D: <textinput> has no 3D node to act on"), "TextInput names incompatible scene: " + input;
}

test "Mesh requires exactly one resource source before calling GPU upload" {
	const missing = mountError(element(<Void><Scene3D><Mesh /></Scene3D></Void>));
	assert missing.includes("Mesh") && missing.includes("geometry") && missing.includes("mesh"), "missing source names both choices: " + missing;
	let mesh = NO_MESH;
	const both = mountError(element(<Void><Scene3D ref={(value: Scene3DHandle): void => {
		mesh = seedMesh(value.context);
		const released = releaseMesh(value.context, mesh);
		if (!released.ok) { throw new Error("test fixture releaseMesh: " + released.error.toString()); }
	}}><Mesh mesh={mesh} geometry={MeshData.empty()} /></Scene3D></Void>));
	assert both.includes("Mesh") && both.includes("geometry") && both.includes("mesh"), "ambiguous source refuses before upload or handle validation: " + both;
}

test "sibling scenes keep their context and parent trees separate" {
	const firstRefs: Scene3DHandle[] = [];
	const secondRefs: Scene3DHandle[] = [];
	let firstNode = NO_NODE_ID;
	let secondNode = NO_NODE_ID;
	const dispose = mounted(element(<Void>
		<Scene3D ref={(value: Scene3DHandle): void => { firstRefs.push(value); }}><Group ref={(value: NodeId3D): void => { firstNode = value; }} /></Scene3D>
		<Scene3D ref={(value: Scene3DHandle): void => { secondRefs.push(value); }}><Group ref={(value: NodeId3D): void => { secondNode = value; }} /></Scene3D>
	</Void>));
	const first: Scene3DHandle | null = firstRefs.length === 0 ? null : firstRefs[0];
	const second: Scene3DHandle | null = secondRefs.length === 0 ? null : secondRefs[0];
	if (first === null) { throw new Error("fixture: first ref did not mount"); }
	if (second === null) { throw new Error("fixture: second ref did not mount"); }
	assert first.context.serial !== second.context.serial && first.scene.serial !== second.scene.serial, "each scene owns a distinct context and scene";
	assert first.scene.isLive(firstNode) && !first.scene.isLive(secondNode), "first context cannot see second tree";
	assert second.scene.isLive(secondNode) && !second.scene.isLive(firstNode), "second context cannot see first tree";
	assert first.scene.nodes[firstNode.index].parent === first.scene.root && second.scene.nodes[secondNode.index].parent === second.scene.root, "each provider establishes its own root parent";
	dispose();
	assert first.context.closed && second.context.closed && first.scene.closed && second.scene.closed, "all sibling owners close";
}

test "Mesh transform and uploaded handle follow signals with balanced borrowed pins" {
	const refs: Scene3DHandle[] = [];
	let first = NO_MESH;
	let second = NO_MESH;
	let meshNode = NO_NODE_ID;
	const [useSecond, setUseSecond] = createSignal(false);
	const [x, setX] = createSignal<float32>(1.0);
	const dispose = mounted(element(<Void><Scene3D ref={(value: Scene3DHandle): void => {
		refs.push(value);
		first = seedMesh(value.context);
		second = seedMesh(value.context);
	}}><Mesh mesh={useSecond() ? second : first} position={vec3(x(), 0.0, 0.0)} ref={(value: NodeId3D): void => { meshNode = value; }} /></Scene3D></Void>));
	const handle: Scene3DHandle | null = refs.length === 0 ? null : refs[0];
	if (handle === null) { throw new Error("fixture: handle ref did not mount"); }
	assert handle.context.meshPins[first.index] === 1 && handle.context.meshPins[second.index] === 0, "initial handle alone is pinned";
	setX(6.0);
	flush();
	setUseSecond(true);
	flush();
	const synced = syncWorld(handle.scene);
	const world = handle.scene.worldOf(meshNode);
	assert world.ok, "mesh remains a live node after reactive resource replacement";
	if (world.ok) { assert approx(world.value.m41, 6.0), "Mesh position follows signal"; }
	assert handle.scene.meshes[handle.scene.nodes[meshNode.index].payload].mesh === second, "existing node uses replacement mesh";
	assert handle.context.meshPins[first.index] === 0 && handle.context.meshHolders[first.index] === 1, "replacement releases old pin, retains caller hold";
	assert handle.context.meshPins[second.index] === 1 && handle.context.meshHolders[second.index] === 2, "replacement pins new mesh beside caller hold";
	const firstRelease = releaseMesh(handle.context, first);
	const secondRelease = releaseMesh(handle.context, second);
	assert firstRelease.ok && secondRelease.ok, "caller releases both borrowed originals";
	dispose();
	assert handle.context.meshHolders[first.index] === 0 && handle.context.meshHolders[second.index] === 0, "replacement leaves no mesh hold";
	setX(10.0);
	flush();
	setUseSecond(false);
	flush();
	assert handle.context.closed, "mesh effects stop after disposal";
}

test "actual geometry upload failures report component API and enum then close owners" {
	const refs: Scene3DHandle[] = [];
	const failure = mountError(element(<Void><Scene3D ref={(value: Scene3DHandle): void => { refs.push(value); }}><Mesh geometry={MeshData.empty()} /></Scene3D></Void>));
	assert failure.includes("Mesh") && failure.includes("addMeshData") && failure.includes("EmptyMesh"), "real uploader failure is surfaced: " + failure;
	const handle: Scene3DHandle | null = refs.length === 0 ? null : refs[0];
	if (handle === null) { throw new Error("fixture: handle ref did not mount"); }
	assert handle.scene.closed && handle.context.closed, "failed mount still closes actual owners";
	assert handle.scene.nodeCount() === 0, "failed mount leaves no nodes";
}

test "Light refuses kind changes without a Void binder rather than silently freezing them" {
	const refs: Scene3DHandle[] = [];
	let light = NO_NODE_ID;
	const [kind, setKind] = createSignal<LightKind>(LightKind.Point);
	const dispose = mounted(element(<Void><Scene3D ref={(value: Scene3DHandle): void => { refs.push(value); }}><Light kind={kind()} radius={2.0} ref={(value: NodeId3D): void => { light = value; }} /></Scene3D></Void>));
	let failure = "";
	try { setKind(LightKind.Directional); flush(); } catch (error) { failure = error.toString(); }
	finally { resetErrorHalt(); }
	assert failure.includes("Light") && failure.includes("kind"), "unsupported update rejects with component and prop: " + failure;
	const handle: Scene3DHandle | null = refs.length === 0 ? null : refs[0];
	if (handle === null) { throw new Error("fixture: handle ref did not mount"); }
	assert handle.scene.lights[handle.scene.nodes[light.index].payload].kind === LightKind.Point, "rejected change preserves kind";
	assert approx(handle.scene.lights[handle.scene.nodes[light.index].payload].radius, 2.0), "rejected change does not mutate light";
	dispose();
	assert handle.context.closed, "rejected update leaves owner disposable";
}

test "Camera3D honors transformed Group parents and disposes world-bound nodes" {
	const refs: Scene3DHandle[] = [];
	const dispose = mounted(element(<Void><Scene3D ref={(value: Scene3DHandle): void => { refs.push(value); }}>
		<Group position={vec3(5.0, 3.0, 1.0)} rotation={eulerQuat(0.0, 0.0, 0.5)}>
			<Camera3D active={true} position={vec3(0.0, 0.0, 8.0)} />
		</Group>
	</Scene3D></Void>));
	const handle: Scene3DHandle | null = refs.length === 0 ? null : refs[0];
	if (handle === null) { throw new Error("fixture: handle ref did not mount"); }
	const request = handle.camera;
	assert request !== null, "nested active camera is selected";
	if (request !== null) {
		const world = cameraOf(handle.scene, request);
		assert world.ok, "Void resolves the camera's enclosing world";
		if (world.ok) {
			assert nearVec(world.value.position, 5.0, 3.0, 9.0), "camera local offset follows parent";
			assert world.value.basisOf().right.y > 0.4, "parent roll reaches camera orientation";
		}
	}
	dispose();
	assert handle.scene.closed && handle.context.closed, "nested camera disposal closes real owners";
	assert handle.scene.nodeCount() === 0 && handle.camera === null, "camera leaves no selected camera or live parent nodes";
}
