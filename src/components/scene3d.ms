import { Accessor, accessor, untrack } from "../core/signal";
import { createRenderEffect } from "../core/effect";
import { Cleanup } from "../core/types";
import { createRoot } from "../core/owner";
import { onCleanup } from "../core/cleanup";
import { createContext, useContext } from "../render/context";
import { VoidSpace, getVoidScopeContext, getVoidAreaContext, useVoidSpace } from "../render/voidScope";
import { layerAnchor } from "../render/voidLayer";
import { AreaLayer } from "../render/voidAreaHandle";
import { Host, HostNode, NeonNode, VoidArea } from "../render/hostTypes";
import { Vec3, Quat, vec3, eulerQuat } from "../../../void/src/math/math3d";
import { RenderState } from "../../../void/src/gpu/state";
import { Program, MATERIAL_UNIFORM_SLOT, MATERIAL_UNIFORM_LENGTH, VERTEX_UNIFORM_LENGTH, LIGHT_UNIFORM_LENGTH } from "../../../void/src/void3d/gpu3d";
import { Material, Phase } from "../../../void/src/void3d/material";
import { MeshData } from "../../../void/src/void3d/meshData";
import {
	DrawContext, DrawItem, MeshId, MaterialId, addMeshData, releaseMesh, addMaterial,
	releaseMaterial, reserveUniforms, writeUniforms, releaseUniforms, closeContext, buryDoomed,
} from "../../../void/src/void3d/draw";
import {
	ForwardRenderer, create, prepareFrame, drawOverScreen, closeForward, setOutlineBlend, setOutlineSettings,
} from "../../../void/src/void3d/forwardRenderer";
import { ForwardOutlineSettings, defaults, valid, FORWARD_OUTLINE_BLOCKS } from "../../../void/src/void3d/forwardOutline";
import { fits } from "../../../void/src/void3d/uniformPool";
import { contextGeneration } from "../../../void/src/gpu/door";
import {
	Scene3D as VoidScene3D, NodeId3D, Transform3D, LightKind, LightInstance,
	addGroup, addLightNode, addMeshNode, setLocal, setLightPower, setMeshOf,
	setLightColor, setLightRadius, setLightPriority,
	remove, insertBefore, closeScene, addCameraNode, setCameraOf, setActiveCamera,
	setVisible, setPickable, setName, setAmbient, refresh, collectLights, setLayers, setRenderOrder, setCameraLayers,
	cameraOf as worldCameraOf,
} from "../../../void/src/void3d/scene";
import { GltfData } from "../../../void/src/void3d/gltf";
import {
	GltfMaterialSetup, addGltfAssets, addGltfNodes, closeGltfAssets,
} from "../../../void/src/void3d/gltfScene";
import {
	Camera3D as VoidCamera3D, CameraProjection, ProjectionKind, CameraError, resolve, writeCameraBlock,
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
	invalidate: () => void;
}

interface NodeScope {
	state: SceneState;
	parent: NodeId3D;
}

interface Scene3DProps {
	ambient?: Accessor<Vec3> | null;
	outlineBlend?: Accessor<float32> | null;
	outlineSettings?: Accessor<ForwardOutlineSettings> | null;
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
	layers?: Accessor<uint32> | null;
	renderOrder?: Accessor<int32> | null;
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

interface GltfProps extends NodeProps {
	data: Accessor<GltfData>;
	setup: Accessor<GltfMaterialSetup>;
}

interface Camera3DProps {
	position?: Accessor<Vec3> | null;
	yaw?: Accessor<float32> | null;
	pitch?: Accessor<float32> | null;
	nearPlane?: Accessor<float32> | null;
	farPlane?: Accessor<float32> | null;
	projection?: Accessor<CameraProjection> | null;
	active?: Accessor<boolean> | null;
	layers?: Accessor<uint32> | null;
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
	if (scope === null || useVoidSpace() !== VoidSpace.Scene3D) {
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

function bindLocal(scene: VoidScene3D, node: NodeId3D, props: TransformProps, initial: Transform3D, invalidate: () => void): void {
	if (props.transform === null && props.position === null && props.rotation === null && props.scale === null) { return; }
	let local = initial;
	createRenderEffect<Transform3D>(
		(prev: Transform3D | null): Transform3D => localOf(props),
		(next: Transform3D, prev: Transform3D | null): Cleanup | null => {
			if (next !== local) {
				setLocal(scene, node, next);
				local = next;
				invalidate();
			}
			return null;
		},
	);
}

function bindNode(state: SceneState, node: NodeId3D, props: NodeProps, initial: Transform3D): void {
	const scene = state.handle.scene;
	bindLocal(scene, node, props, initial, state.invalidate);
	if (props.visible !== null) {
		const visible = props.visible as () => boolean;
		createRenderEffect<boolean>(
			(prev: boolean | null): boolean => visible(),
			(value: boolean, prev: boolean | null): Cleanup | null => { setVisible(scene, node, value); state.invalidate(); return null; },
		);
	}
	if (props.pickable !== null) {
		const pickable = props.pickable as () => boolean;
		createRenderEffect<boolean>(
			(prev: boolean | null): boolean => pickable(),
			(value: boolean, prev: boolean | null): Cleanup | null => { setPickable(scene, node, value); state.invalidate(); return null; },
		);
	}
	if (props.layers !== null) {
		const layers = props.layers as () => uint32;
		createRenderEffect<uint32>(
			(prev: uint32 | null): uint32 => layers(),
			(value: uint32, prev: uint32 | null): Cleanup | null => { setLayers(scene, node, value); state.invalidate(); return null; },
		);
	}
	if (props.renderOrder !== null) {
		const order = props.renderOrder as () => int32;
		createRenderEffect<int32>(
			(prev: int32 | null): int32 => order(),
			(value: int32, prev: int32 | null): Cleanup | null => { setRenderOrder(scene, node, value); state.invalidate(); return null; },
		);
	}
	if (props.name !== null) {
		const name = props.name as () => string;
		createRenderEffect<string>(
			(prev: string | null): string => name(),
			(value: string, prev: string | null): Cleanup | null => { setName(scene, node, value); state.invalidate(); return null; },
		);
	}
}

function ownNode(state: SceneState, node: NodeId3D): void {
	const scene = state.handle.scene;
	onCleanup((): void => {
		if (scene.isLive(node)) {
			const removed = remove(scene, node);
			state.invalidate();
		}
	});
	state.invalidate();
}

function mountNodeChildren(scope: NodeScope, node: NodeId3D, props: NodeProps, host: Host, parent: HostNode, before: HostNode | null): void {
	if (props.ref !== null) { (props.ref as (value: NodeId3D) => void)(node); }
	const children = props.children;
	if (children !== null) {
		const next: NodeScope = { state: scope.state, parent: node };
		sceneScope.provider({ value: accessor(() => next), children: children })(host, parent, before);
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

const DEFAULT_CAMERA: VoidCamera3D = {
	position: vec3(0.0, 0.0, 5.0), yaw: 0.0, pitch: 0.0, nearPlane: 0.1, farPlane: 1000.0,
	projection: { kind: ProjectionKind.Perspective, fovY: 1.3089969389957472 },
};

export function viewCamera(handle: Scene3DHandle): Result<VoidCamera3D, CameraError> {
	return worldCameraOf(handle.scene, DEFAULT_CAMERA);
}

export function Scene3D(props: Scene3DProps): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		if (useVoidSpace() !== VoidSpace.Area) { throw new Error("Scene3D: mount directly within Void, outside another Scene3D"); }
		mountOwned((): void => {
			const opened = useContext(getVoidAreaContext());
			if (opened === null) { throw new Error("Scene3D: the Void area did not provide its frame"); }
			const anchor = layerAnchor(opened as VoidArea, host, parent, before);
			const area = (opened as VoidArea).hub;
			const context = DrawContext.withUniformCapacity(SCENE_UNIFORM_CAPACITY);
			const scene = VoidScene3D.create(context);
			const handle: Scene3DHandle = { context: context, scene: scene, camera: null };
			const state: SceneState = {
				handle: handle, defaultMaterial: null, cameras: [],
				invalidate: (): void => { area.handle.requestFrame(); },
			};
			const made = ForwardRenderer.create(context, { x: 0.0, y: 0.0, z: 0.0, w: 0.0 });
			if (!made.ok) {
				closeScene(scene);
				closeContext(context);
				throw new Error("Scene3D: ForwardRenderer.create failed: " + made.error.toString());
			}
			const renderer = made.value;
			let items: Vec<DrawItem> = [];
			let cameraBlock: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
			let lightBlock: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
			let prepared = false;
			const layer: AreaLayer = {
				anchor,
				layout: (pixelWidth: int32, pixelHeight: int32): void => {},
				prepare: (pixelWidth: int32, pixelHeight: int32): void => {
					prepared = false;
					refresh(scene, items);
					const lights = collectLights(scene, lightBlock);
					if (!lights.ok) { throw new Error("Scene3D: collectLights failed: " + lights.error.toString()); }
					const world = viewCamera(handle);
					if (!world.ok) { throw new Error("Scene3D: the active camera has no world pose: " + world.error.toString()); }
					const view = world.value.resolve(pixelWidth, pixelHeight);
					if (!view.ok) { throw new Error("Scene3D: the active camera does not resolve: " + view.error.toString()); }
					view.value.writeCameraBlock(cameraBlock);
					const buried = buryDoomed(context, contextGeneration());
					const frame = prepareFrame(renderer, items, cameraBlock, lightBlock, pixelWidth, pixelHeight);
					if (!frame.ok) { throw new Error("Scene3D: prepareFrame failed: " + frame.error.toString()); }
					prepared = true;
				},
				draw: (): void => {
					if (!prepared) { return; }
					prepared = false;
					drawOverScreen(renderer);
				},
			};
			const unregister = area.addLayer(layer);
			onCleanup((): void => {
				unregister();
				closeForward(renderer);
				state.invalidate();
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
			if (props.outlineBlend !== null || props.outlineSettings !== null) {
				createRenderEffect<[float32, ForwardOutlineSettings]>(
					(prev: [float32, ForwardOutlineSettings] | null): [float32, ForwardOutlineSettings] => [
						props.outlineBlend === null ? 0.0 : (props.outlineBlend as () => float32)(),
						props.outlineSettings === null ? ForwardOutlineSettings.defaults() : (props.outlineSettings as () => ForwardOutlineSettings)(),
					],
					(value: [float32, ForwardOutlineSettings], prev: [float32, ForwardOutlineSettings] | null): Cleanup | null => {
						const blend = value[0];
						const settings = value[1];
						if (!Number.isFinite(blend) || blend < 0.0 || blend > 1.0) {
							throw new Error("Scene3D: outlineBlend must be finite and in [0,1]");
						}
						if (!settings.valid()) { throw new Error("Scene3D: invalid outlineSettings"); }
						if (blend > 0.0 && renderer.outline === null && !context.uniforms.fits(FORWARD_OUTLINE_BLOCKS).ok) {
							throw new Error("Scene3D: outlineBlend needs additional uniform capacity");
						}
						setOutlineSettings(renderer, settings);
						setOutlineBlend(renderer, blend);
						state.invalidate();
						return null;
					},
				);
			}
			if (props.ambient !== null) {
				const ambient = props.ambient as () => Vec3;
				createRenderEffect<Vec3>(
					(prev: Vec3 | null): Vec3 => ambient(),
					(value: Vec3, prev: Vec3 | null): Cleanup | null => { setAmbient(scene, value); state.invalidate(); return null; },
				);
			}
			if (props.ref !== null) { (props.ref as (value: Scene3DHandle) => void)(handle); }
			state.invalidate();
			const children = props.children;
			if (children !== null) {
				const scope: NodeScope = { state: state, parent: scene.rootId() };
				getVoidScopeContext().provider({
					value: accessor(() => VoidSpace.Scene3D),
					children: sceneScope.provider({ value: accessor(() => scope), children: children }),
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
			ownNode(scope.state, node);
			bindNode(scope.state, node, props, local);
			mountNodeChildren(scope, node, props, host, parent, before);
		});
	};
}

function instantiateGltf(
	scene: VoidScene3D, parent: NodeId3D, data: GltfData, setup: GltfMaterialSetup,
): NodeId3D {
	const added = addGltfAssets(scene.context, data, setup);
	if (!added.ok) {
		throw new Error("Gltf: addGltfAssets failed: " + added.error.toString());
	}
	const assets = added.value;
	const staging = addGroup(scene, parent, Transform3D.identity());
	try {
		const mounted = addGltfNodes(scene, staging, data, assets.bindings);
		if (!mounted.ok) {
			throw new Error("Gltf: addGltfNodes failed: " + mounted.error.toString());
		}
		return staging;
	} catch (error) {
		const removed = remove(scene, staging);
		throw error;
	} finally { closeGltfAssets(assets); }
}

export function Gltf(props: GltfProps): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		const scope = requireScene("Gltf");
		mountOwned((): void => {
			const scene = scope.state.handle.scene;
			const local = localOf(props);
			const wrapper = addGroup(scene, scope.parent, local);
			ownNode(scope.state, wrapper);
			bindNode(scope.state, wrapper, props, local);
			let imported: NodeId3D | null = null;
			createRenderEffect<[GltfData, GltfMaterialSetup]>(
				(prev: [GltfData, GltfMaterialSetup] | null): [GltfData, GltfMaterialSetup] => [props.data(), props.setup()],
				(value: [GltfData, GltfMaterialSetup], prev: [GltfData, GltfMaterialSetup] | null): Cleanup | null => {
					const next = instantiateGltf(scene, wrapper, value[0], value[1]);
					const previous = imported;
					if (previous !== null) {
						insertBefore(scene, wrapper, next, previous);
						const removed = remove(scene, previous);
					}
					imported = next;
					scope.state.invalidate();
					return null;
				},
			);
			mountNodeChildren(scope, wrapper, props, host, parent, before);
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
			ownNode(scope.state, node);
			bindNode(scope.state, node, props, local);
			let color = light.color;
			let radius = light.radius;
			let priority = light.priority;
			createRenderEffect<LightInstance>(
				(prev: LightInstance | null): LightInstance => ({
					...light, kind: props.kind(),
					color: props.color === null ? light.color : (props.color as () => Vec3)(),
					radius: props.radius === null ? light.radius : (props.radius as () => float32)(),
					priority: props.priority === null ? light.priority : (props.priority as () => int32)(),
				}),
				(value: LightInstance, prev: LightInstance | null): Cleanup | null => {
					if (value.kind !== light.kind) { throw new Error("Light: kind cannot change; Void has no light-kind binder"); }
					let changed = false;
					if (value.color !== color) {
						setLightColor(scene, node, value.color);
						color = value.color;
						changed = true;
					}
					if (value.radius !== radius) {
						setLightRadius(scene, node, value.radius);
						radius = value.radius;
						changed = true;
					}
					if (value.priority !== priority) {
						setLightPriority(scene, node, value.priority);
						priority = value.priority;
						changed = true;
					}
					if (changed) { scope.state.invalidate(); }
					return null;
				},
			);
			if (props.power !== null) {
				let power = light.power;
				createRenderEffect<float32>(
					(prev: float32 | null): float32 => (props.power as () => float32)(),
					(next: float32, prev: float32 | null): Cleanup | null => {
						if (next !== power) {
							setLightPower(scene, node, next);
							power = next;
							scope.state.invalidate();
						}
						return null;
					},
				);
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
				if (mounted !== null && scene.isLive(mounted)) {
					const removed = remove(scene, mounted);
					scope.state.invalidate();
				}
				node = null;
			});
			const bindMesh = (mesh: MeshId, snapshotMaterial: MaterialId | null): void => {
				const mounted = node;
				if (mounted === null) {
					const selected = snapshotMaterial === null ? defaultMaterialOf(scope.state) : snapshotMaterial;
					const added = addMeshNode(scene, scope.parent, local, mesh, selected);
					if (!added.ok) { throw new Error("Mesh: addMeshNode failed: " + added.error.toString()); }
					node = added.value;
					material = selected;
				} else if (shown === null || mesh !== shown) {
					const changed = setMeshOf(scene, mounted, mesh);
					if (!changed.ok) { throw new Error("Mesh: setMeshOf failed: " + changed.error.toString()); }
				}
				shown = mesh;
				scope.state.invalidate();
			};
			if (props.geometry !== null) {
				createRenderEffect<[MeshData, MaterialId | null]>(
					(prev: [MeshData, MaterialId | null] | null): [MeshData, MaterialId | null] => [
						(props.geometry as () => MeshData)(),
						props.material === null ? null : untrack(() => (props.material as () => MaterialId)()),
					],
					(value: [MeshData, MaterialId | null], prev: [MeshData, MaterialId | null] | null): Cleanup | null => {
						const uploaded = addMeshData(context, value[0]);
						if (!uploaded.ok) { throw new Error("Mesh: addMeshData failed: " + uploaded.error.toString()); }
						const mesh = uploaded.value;
						try {
							bindMesh(mesh, value[1]);
						} finally {
							const released = releaseMesh(context, mesh);
							if (!released.ok) { throw new Error("Mesh: releaseMesh failed: " + released.error.toString()); }
						}
						return null;
					},
				);
			} else {
				createRenderEffect<[MeshId, MaterialId | null]>(
					(prev: [MeshId, MaterialId | null] | null): [MeshId, MaterialId | null] => [
						(props.mesh as () => MeshId)(),
						props.material === null ? null : untrack(() => (props.material as () => MaterialId)()),
					],
					(value: [MeshId, MaterialId | null], prev: [MeshId, MaterialId | null] | null): Cleanup | null => {
						bindMesh(value[0], value[1]);
						return null;
					},
				);
			}
			const mounted = node;
			if (mounted === null) { throw new Error("Mesh: addMeshNode did not mount a node"); }
			if (props.material !== null) {
				const selected = material;
				if (selected === null) { throw new Error("Mesh: addMeshNode did not select a material"); }
				createRenderEffect<MaterialId>(
					(prev: MaterialId | null): MaterialId => (props.material as () => MaterialId)(),
					(value: MaterialId, prev: MaterialId | null): Cleanup | null => {
						if (value !== selected) { throw new Error("Mesh: material cannot change; Void has no material-node binder"); }
						return null;
					},
				);
			}
			bindNode(scope.state, mounted, props, local);
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
			ownNode(scope.state, node);
			if (props.layers !== null) {
				const layers = props.layers as () => uint32;
				createRenderEffect<uint32>(
					(prev: uint32 | null): uint32 => layers(),
					(value: uint32, prev: uint32 | null): Cleanup | null => { setCameraLayers(scene, node, value); state.invalidate(); return null; },
				);
			}
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
				state.invalidate();
			});
			createRenderEffect<[VoidCamera3D, boolean]>(
				(prev: [VoidCamera3D, boolean] | null): [VoidCamera3D, boolean] => [
					cameraOf(props), props.active === null ? false : (props.active as () => boolean)(),
				],
				(value: [VoidCamera3D, boolean], prev: [VoidCamera3D, boolean] | null): Cleanup | null => {
					const camera = value[0];
					const active = value[1];
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
					state.invalidate();
					return null;
				},
			);

		});
	};
}
