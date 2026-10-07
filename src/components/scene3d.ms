import { Accessor, accessor, untrack } from "../core/signal";
import { createEffect } from "../core/effect";
import { createRoot } from "../core/owner";
import { onCleanup } from "../core/cleanup";
import { createContext, useContext } from "../render/context";
import { VoidSpace, voidScope } from "../render/voidScope";
import { Host, HostNode, NeonNode } from "../render/hostTypes";
import { Vec3, Quat, vec3, eulerQuat } from "../../../void/src/math/math3d";
import { RenderState } from "../../../void/src/gpu/state";
import { Program, MATERIAL_UNIFORM_SLOT, MATERIAL_UNIFORM_LENGTH } from "../../../void/src/void3d/gpu3d";
import { Material, Phase } from "../../../void/src/void3d/material";
import { MeshData } from "../../../void/src/void3d/meshData";
import {
	DrawContext, MeshId, MaterialId, addMeshData, releaseMesh, addMaterial,
	releaseMaterial, reserveUniforms, writeUniforms, releaseUniforms, closeContext,
} from "../../../void/src/void3d/draw";
import {
	Scene3D as VoidScene3D, NodeId3D, Transform3D, LightKind, LightInstance,
	addGroup, addLightNode, addMeshNode, setLocal, setLightPower, setMeshOf,
	remove, closeScene, addCameraNode, setCameraOf, setActiveCamera,
	setVisible, setPickable, setName, setAmbient,
} from "../../../void/src/void3d/scene";
import {
	Camera3D as VoidCamera3D, CameraProjection, ProjectionKind,
} from "../../../void/src/void3d/camera";

export interface Scene3DHandle {
	context: DrawContext;
	scene: VoidScene3D;
	camera: VoidCamera3D | null;
}

interface CameraEntry {
	node: NodeId3D;
	camera: VoidCamera3D;
	active: boolean;
}

interface SceneState {
	handle: Scene3DHandle;
	defaultMaterial: MaterialId | null;
	cameras: CameraEntry[];
}

interface NodeScope {
	state: SceneState;
	parent: NodeId3D;
}

interface Scene3DProps {
	ambient?: Accessor<Vec3> | null;
	ref?: ((handle: Scene3DHandle) => void) | null;
	children?: NeonNode | null;
}

interface TransformProps {
	position?: Accessor<Vec3> | null;
	rotation?: Accessor<Quat> | null;
	scale?: Accessor<Vec3> | null;
	transform?: Accessor<Transform3D> | null;
}

interface NodeProps extends TransformProps {
	visible?: Accessor<boolean> | null;
	pickable?: Accessor<boolean> | null;
	name?: Accessor<string> | null;
	ref?: ((node: NodeId3D) => void) | null;
	children?: NeonNode | null;
}

interface LightProps extends NodeProps {
	kind: Accessor<LightKind>;
	color?: Accessor<Vec3> | null;
	radius?: Accessor<float32> | null;
	power?: Accessor<float32> | null;
	priority?: Accessor<int32> | null;
}

interface MeshProps extends NodeProps {
	geometry?: Accessor<MeshData> | null;
	mesh?: Accessor<MeshId> | null;
	material?: Accessor<MaterialId> | null;
}

interface Camera3DProps {
	position?: Accessor<Vec3> | null;
	yaw?: Accessor<float32> | null;
	pitch?: Accessor<float32> | null;
	nearPlane?: Accessor<float32> | null;
	farPlane?: Accessor<float32> | null;
	projection?: Accessor<CameraProjection> | null;
	active?: Accessor<boolean> | null;
}

const sceneScope = createContext<NodeScope | null>(null);
const SCENE_UNIFORM_CAPACITY: int32 = 256;

function mountOwned(body: () => void): void {
	const dispose = createRoot((dispose) => {
		try {
			body();
		} catch (error) {
			dispose();
			throw error;
		}
		return dispose;
	});
	onCleanup(dispose);
}

function requireScene(tag: string): NodeScope {
	const scope = useContext(sceneScope);
	if (scope === null || useContext(voidScope) !== VoidSpace.Scene3D) {
		throw new Error(tag + ": mount inside Scene3D within Void");
	}
	return scope;
}

function localOf(props: TransformProps): Transform3D {
	let local = props.transform === null ? Transform3D.identity() : (props.transform as () => Transform3D)();
	if (props.position !== null) { local.position = (props.position as () => Vec3)(); }
	if (props.rotation !== null) { local.rotation = (props.rotation as () => Quat)(); }
	if (props.scale !== null) { local.scale = (props.scale as () => Vec3)(); }
	return local;
}

function bindLocal(scene: VoidScene3D, node: NodeId3D, props: TransformProps, initial: Transform3D): void {
	if (props.transform === null && props.position === null && props.rotation === null && props.scale === null) { return; }
	let local = initial;
	createEffect((): void => {
		const next = localOf(props);
		if (next !== local) {
			setLocal(scene, node, next);
			local = next;
		}
	});
}

function bindNode(scene: VoidScene3D, node: NodeId3D, props: NodeProps, initial: Transform3D): void {
	bindLocal(scene, node, props, initial);
	if (props.visible !== null) {
		const visible = props.visible as () => boolean;
		createEffect((): void => { setVisible(scene, node, visible()); });
	}
	if (props.pickable !== null) {
		const pickable = props.pickable as () => boolean;
		createEffect((): void => { setPickable(scene, node, pickable()); });
	}
	if (props.name !== null) {
		const name = props.name as () => string;
		createEffect((): void => { setName(scene, node, name()); });
	}
}

function ownNode(scene: VoidScene3D, node: NodeId3D): void {
	onCleanup((): void => {
		if (scene.isLive(node)) { const removed = remove(scene, node); }
	});
}

function mountNodeChildren(scope: NodeScope, node: NodeId3D, props: NodeProps, host: Host, parent: HostNode, before: HostNode | null): void {
	if (props.ref !== null) { (props.ref as (value: NodeId3D) => void)(node); }
	const children = props.children;
	if (children !== null) {
		const next: NodeScope = { state: scope.state, parent: node };
		sceneScope.Provider({ value: accessor(() => next), children: children })(host, parent, before);
	}
}

function defaultMaterialOf(state: SceneState): MaterialId {
	const existing = state.defaultMaterial;
	if (existing !== null) { return existing; }
	const context = state.handle.context;
	const reserved = reserveUniforms(context, MATERIAL_UNIFORM_SLOT, MATERIAL_UNIFORM_LENGTH);
	if (!reserved.ok) { throw new Error("Mesh: reserveUniforms failed: " + reserved.error.toString()); }
	const block = reserved.value;
	try {
		const values: Vec<float32> = [0.0, 0.0, 0.0, 0.0];
		const written = writeUniforms(context, block, values);
		if (!written.ok) { throw new Error("Mesh: writeUniforms failed: " + written.error.toString()); }
		const added = addMaterial(context, {
			...Material.plain(Program.Lit, RenderState.defaults(), Phase.Opaque),
			uniforms: block,
		});
		if (!added.ok) { throw new Error("Mesh: addMaterial failed: " + added.error.toString()); }
		state.defaultMaterial = added.value;
		return added.value;
	} catch (error) {
		const released = releaseUniforms(context, block);
		if (!released.ok) { throw new Error("Mesh: releaseUniforms failed: " + released.error.toString()); }
		throw error;
	}
}

export function Scene3D(props: Scene3DProps): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		if (useContext(voidScope) !== VoidSpace.Area) { throw new Error("Scene3D: mount directly within Void, outside another Scene3D"); }
		mountOwned((): void => {
			const context = DrawContext.withUniformCapacity(SCENE_UNIFORM_CAPACITY);
			const scene = VoidScene3D.create(context);
			const handle: Scene3DHandle = { context: context, scene: scene, camera: null };
			const state: SceneState = { handle: handle, defaultMaterial: null, cameras: [] };
			onCleanup((): void => {
				handle.camera = null;
				closeScene(scene);
				const material = state.defaultMaterial;
				if (material !== null) {
					const released = releaseMaterial(context, material);
					if (!released.ok) { throw new Error("Scene3D: releaseMaterial failed: " + released.error.toString()); }
					state.defaultMaterial = null;
				}
				closeContext(context);
			});
			if (props.ambient !== null) {
				const ambient = props.ambient as () => Vec3;
				createEffect((): void => { setAmbient(scene, ambient()); });
			}
			if (props.ref !== null) { (props.ref as (value: Scene3DHandle) => void)(handle); }
			const children = props.children;
			if (children !== null) {
				const scope: NodeScope = { state: state, parent: scene.rootId() };
				voidScope.Provider({
					value: accessor(() => VoidSpace.Scene3D),
					children: sceneScope.Provider({ value: accessor(() => scope), children: children }),
				})(host, parent, before);
			}
		});
	};
}

export function Group(props: NodeProps): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		const scope = requireScene("Group");
		mountOwned((): void => {
			const scene = scope.state.handle.scene;
			const local = localOf(props);
			const node = addGroup(scene, scope.parent, local);
			ownNode(scene, node);
			bindNode(scene, node, props, local);
			mountNodeChildren(scope, node, props, host, parent, before);
		});
	};
}

export function Light(props: LightProps): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		const scope = requireScene("Light");
		mountOwned((): void => {
			const scene = scope.state.handle.scene;
			const local = localOf(props);
			const light: LightInstance = {
				kind: props.kind(),
				color: props.color === null ? vec3(1.0, 1.0, 1.0) : (props.color as () => Vec3)(),
				radius: props.radius === null ? 10.0 : (props.radius as () => float32)(),
				power: props.power === null ? 1.0 : (props.power as () => float32)(),
				priority: props.priority === null ? 0 : (props.priority as () => int32)(),
			};
			const node = addLightNode(scene, scope.parent, local, light);
			ownNode(scene, node);
			bindNode(scene, node, props, local);
			createEffect((): void => {
				if (props.kind() !== light.kind) { throw new Error("Light: kind cannot change; Void has no light-kind binder"); }
				if (props.color !== null && (props.color as () => Vec3)() !== light.color) { throw new Error("Light: color cannot change; Void has no light-color binder"); }
				if (props.radius !== null && (props.radius as () => float32)() !== light.radius) { throw new Error("Light: radius cannot change; Void has no light-radius binder"); }
				if (props.priority !== null && (props.priority as () => int32)() !== light.priority) { throw new Error("Light: priority cannot change; Void has no light-priority binder"); }
			});
			if (props.power !== null) {
				let power = light.power;
				createEffect((): void => {
					const next = (props.power as () => float32)();
					if (next !== power) {
						setLightPower(scene, node, next);
						power = next;
					}
				});
			}
			mountNodeChildren(scope, node, props, host, parent, before);
		});
	};
}

export function Mesh(props: MeshProps): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		const scope = requireScene("Mesh");
		if ((props.geometry === null) === (props.mesh === null)) { throw new Error("Mesh: provide exactly one geometry (MeshData) or mesh (MeshId)"); }
		mountOwned((): void => {
			const scene = scope.state.handle.scene;
			const context = scope.state.handle.context;
			const local = localOf(props);
			let node: NodeId3D | null = null;
			let material: MaterialId | null = null;
			let shown: MeshId | null = null;
			onCleanup((): void => {
				const mounted = node;
				if (mounted !== null && scene.isLive(mounted)) { const removed = remove(scene, mounted); }
				node = null;
			});
			const bindMesh = (mesh: MeshId): void => {
				const mounted = node;
				if (mounted === null) {
					const selected = props.material === null ? defaultMaterialOf(scope.state) : untrack(() => (props.material as () => MaterialId)());
					const added = addMeshNode(scene, scope.parent, local, mesh, selected);
					if (!added.ok) { throw new Error("Mesh: addMeshNode failed: " + added.error.toString()); }
					node = added.value;
					material = selected;
				} else if (shown === null || mesh !== shown) {
					const changed = setMeshOf(scene, mounted, mesh);
					if (!changed.ok) { throw new Error("Mesh: setMeshOf failed: " + changed.error.toString()); }
				}
				shown = mesh;
			};
			if (props.geometry !== null) {
				createEffect((): void => {
					const uploaded = addMeshData(context, (props.geometry as () => MeshData)());
					if (!uploaded.ok) { throw new Error("Mesh: addMeshData failed: " + uploaded.error.toString()); }
					const mesh = uploaded.value;
					try {
						bindMesh(mesh);
					} finally {
						const released = releaseMesh(context, mesh);
						if (!released.ok) { throw new Error("Mesh: releaseMesh failed: " + released.error.toString()); }
					}
				});
			} else {
				createEffect((): void => { bindMesh((props.mesh as () => MeshId)()); });
			}
			const mounted = node;
			if (mounted === null) { throw new Error("Mesh: addMeshNode did not mount a node"); }
			if (props.material !== null) {
				const selected = material;
				if (selected === null) { throw new Error("Mesh: addMeshNode did not select a material"); }
				createEffect((): void => {
					if ((props.material as () => MaterialId)() !== selected) { throw new Error("Mesh: material cannot change; Void has no material-node binder"); }
				});
			}
			bindNode(scene, mounted, props, local);
			mountNodeChildren(scope, mounted, props, host, parent, before);
		});
	};
}

function cameraOf(props: Camera3DProps): VoidCamera3D {
	const projection: CameraProjection = props.projection === null ? {
		kind: ProjectionKind.Perspective, fovY: 1.0471975511965976,
	} : (props.projection as () => CameraProjection)();
	return {
		position: props.position === null ? vec3(0.0, 0.0, 0.0) : (props.position as () => Vec3)(),
		yaw: props.yaw === null ? 0.0 : (props.yaw as () => float32)(),
		pitch: props.pitch === null ? 0.0 : (props.pitch as () => float32)(),
		nearPlane: props.nearPlane === null ? 0.1 : (props.nearPlane as () => float32)(),
		farPlane: props.farPlane === null ? 1000.0 : (props.farPlane as () => float32)(),
		projection: projection,
	};
}

function cameraLocal(camera: VoidCamera3D): Transform3D {
	return {
		position: camera.position, rotation: eulerQuat(-camera.pitch, camera.yaw, 0.0),
		scale: vec3(1.0, 1.0, 1.0),
	};
}

function selectCamera(state: SceneState): void {
	const scene = state.handle.scene;
	if (scene.closed) { state.handle.camera = null; return; }
	for (let i = state.cameras.length - 1; i >= 0; i--) {
		const entry = state.cameras[i];
		if (entry.active && scene.isLive(entry.node)) {
			setActiveCamera(scene, entry.node);
			state.handle.camera = entry.camera;
			return;
		}
	}
	setActiveCamera(scene, null);
	state.handle.camera = null;
}

export function Camera3D(props: Camera3DProps): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		const scope = requireScene("Camera3D");
		mountOwned((): void => {
			const state = scope.state;
			const scene = state.handle.scene;
			const initial = untrack(() => cameraOf(props));
			let local = cameraLocal(initial);
			const node = addCameraNode(scene, scope.parent, local, initial);
			ownNode(scene, node);
			let entry: CameraEntry | null = null;
			onCleanup((): void => {
				const mounted = entry;
				if (mounted === null) { return; }
				for (let i = 0; i < state.cameras.length; i++) {
					if (state.cameras[i] !== mounted) { continue; }
					for (let j = i; j < state.cameras.length - 1; j++) { state.cameras[j] = state.cameras[j + 1]; }
					state.cameras.pop();
					break;
				}
				entry = null;
				selectCamera(state);
			});
			createEffect((): void => {
				const camera = cameraOf(props);
				const active = props.active === null ? false : (props.active as () => boolean)();
				const nextLocal = cameraLocal(camera);
				if (nextLocal !== local) { setLocal(scene, node, nextLocal); local = nextLocal; }
				setCameraOf(scene, node, camera);
				const mounted = entry;
				if (mounted === null) {
					const added: CameraEntry = { node: node, camera: camera, active: active };
					entry = added;
					state.cameras.push(added);
				} else {
					mounted.camera = camera;
					mounted.active = active;
				}
				selectCamera(state);
			});
		});
	};
}
