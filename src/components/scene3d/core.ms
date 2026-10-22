import { Accessor, accessor } from "../../core/signal";
import { createRenderEffect } from "../../core/effect";
import { Cleanup } from "../../core/types";
import { createRoot } from "../../core/owner";
import { onCleanup } from "../../core/cleanup";
import { createContext, useContext } from "../../render/context";
import { VoidSpace, useVoidSpace } from "../../render/voidScope";
import { Host, HostNode, NeonNode } from "../../render/hostTypes";
import { Vec3, Quat, vec3 } from "../../../../void/src/math/math3d";
import { RenderState } from "../../../../void/src/gpu/state";
import { Program, MATERIAL_UNIFORM_SLOT, MATERIAL_UNIFORM_LENGTH } from "../../../../void/src/void3d/gpu3d";
import { Material, Phase } from "../../../../void/src/void3d/material";
import { DrawContext, MaterialId, addMaterial, reserveUniforms, writeUniforms, releaseUniforms } from "../../../../void/src/void3d/draw";
import {
	Scene3D as VoidScene3D, NodeId3D, Transform3D,
	setLocal, remove, setVisible, setPickable, setName, setLayers, setRenderOrder, cameraOf as worldCameraOf,
} from "../../../../void/src/void3d/scene";
import { Camera3D as VoidCamera3D, ProjectionKind, CameraError } from "../../../../void/src/void3d/camera";

export interface Scene3DHandle {
	context: DrawContext;
	scene: VoidScene3D;
	camera: VoidCamera3D | null;
}

export interface CameraEntry {
	node: NodeId3D;
	camera: VoidCamera3D;
	active: boolean;
}

export interface SceneState {
	handle: Scene3DHandle;
	defaultMaterial: MaterialId | null;
	cameras: CameraEntry[];
	invalidate: () => void;
}

export interface NodeScope {
	state: SceneState;
	parent: NodeId3D;
}

export interface TransformProps {
	position?: Accessor<Vec3> | null;
	rotation?: Accessor<Quat> | null;
	scale?: Accessor<Vec3> | null;
	transform?: Accessor<Transform3D> | null;
}

export interface NodeProps extends TransformProps {
	visible?: Accessor<boolean> | null;
	pickable?: Accessor<boolean> | null;
	layers?: Accessor<uint32> | null;
	renderOrder?: Accessor<int32> | null;
	name?: Accessor<string> | null;
	ref?: ((node: NodeId3D) => void) | null;
	children?: NeonNode | null;
}

export const sceneScope = createContext<NodeScope | null>(null);
export const SCENE_UNIFORM_CAPACITY: int32 = 256;

export function mountOwned(body: () => void): void {
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

export function requireScene(tag: string): NodeScope {
	const scope = useContext(sceneScope);
	if (scope === null || useVoidSpace() !== VoidSpace.Scene3D) {
		throw new Error(tag + ": mount inside Scene3D within Void");
	}
	return scope;
}

export function localOf(props: TransformProps): Transform3D {
	let local = props.transform === null ? Transform3D.identity() : (props.transform as () => Transform3D)();
	if (props.position !== null) { local.position = (props.position as () => Vec3)(); }
	if (props.rotation !== null) { local.rotation = (props.rotation as () => Quat)(); }
	if (props.scale !== null) { local.scale = (props.scale as () => Vec3)(); }
	return local;
}

export function bindLocal(scene: VoidScene3D, node: NodeId3D, props: TransformProps, initial: Transform3D, invalidate: () => void): void {
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

export function bindNode(state: SceneState, node: NodeId3D, props: NodeProps, initial: Transform3D): void {
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

export function ownNode(state: SceneState, node: NodeId3D): void {
	const scene = state.handle.scene;
	onCleanup((): void => {
		if (scene.isLive(node)) {
			const removed = remove(scene, node);
			state.invalidate();
		}
	});
	state.invalidate();
}

export function mountNodeChildren(scope: NodeScope, node: NodeId3D, props: NodeProps, host: Host, parent: HostNode, before: HostNode | null): void {
	if (props.ref !== null) { (props.ref as (value: NodeId3D) => void)(node); }
	const children = props.children;
	if (children !== null) {
		const next: NodeScope = { state: scope.state, parent: node };
		sceneScope.provider({ value: accessor(() => next), children: children })(host, parent, before);
	}
}

export function defaultMaterialOf(state: SceneState): MaterialId {
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

export const DEFAULT_CAMERA: VoidCamera3D = {
	position: vec3(0.0, 0.0, 5.0), yaw: 0.0, pitch: 0.0, nearPlane: 0.1, farPlane: 1000.0,
	projection: { kind: ProjectionKind.Perspective, fovY: 1.3089969389957472 },
};

export function viewCamera(handle: Scene3DHandle): Result<VoidCamera3D, CameraError> {
	return worldCameraOf(handle.scene, DEFAULT_CAMERA);
}

