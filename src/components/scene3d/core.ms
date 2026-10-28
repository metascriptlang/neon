import { Accessor, accessor } from "../../core/signal";
import { createRenderEffect } from "../../core/effect";
import { Cleanup } from "../../core/types";
import { createRoot } from "../../core/owner";
import { onCleanup } from "../../core/cleanup";
import { createContext, useContext } from "../../render/context";
import { VoidSpace, getVoidScopeContext, useVoidSpace } from "../../render/voidScope";
import { Host, HostNode, NeonNode } from "../../render/hostTypes";
import { NeonEvent } from "../../render/event";
import { Style } from "../../render/style";
import { place } from "../../render/reconcile";
import { Vec3, Quat, vec3 } from "../../../../void/src/math/math3d";
import { RenderState } from "../../../../void/src/gpu/state";
import { Program, MATERIAL_UNIFORM_SLOT, MATERIAL_UNIFORM_LENGTH } from "../../../../void/src/void3d/gpu3d";
import { Material, Phase } from "../../../../void/src/void3d/material";
import { MeshId } from "../../../../void/src/void3d/draw";
import { DrawContext, MaterialId, addMaterial, reserveUniforms, writeUniforms, releaseUniforms } from "../../../../void/src/void3d/draw";
import {
	Scene3D as VoidScene3D, NodeId3D, Transform3D, NO_NODE_3D, NO_NODE_ID,
	addGroup, attach, insertBefore, setActiveCamera,
	setLocal, remove, setVisible, setPickable, setName, setLayers, setRenderOrder, cameraOf as worldCameraOf,
} from "../../../../void/src/void3d/scene";
import { Camera3D as VoidCamera3D, ProjectionKind, CameraError } from "../../../../void/src/void3d/camera";
import { ForwardRenderer } from "../../../../void/src/void3d/forwardRenderer";
import { CameraView, resolve } from "../../../../void/src/void3d/camera";
import { syncWorld } from "../../../../void/src/void3d/scene";

export interface Scene3DHandle {
	context: DrawContext;
	scene: VoidScene3D;
	camera: VoidCamera3D | null;
	invalidate: () => void;
	renderer: ForwardRenderer;
}

export interface LightShadow {
	mapSize: int32;
	bias: float32;
	opacity: float32;
}

export interface CameraEntry {
	node: NodeId3D;
	camera: VoidCamera3D;
	active: boolean | null;
}

export interface SharedGeometry {
	mesh: MeshId;
	users: int32;
}

export interface SceneState {
	handle: Scene3DHandle;
	defaultMaterial: MaterialId | null;
	cameras: CameraEntry[];
	geometries: SharedGeometry[];
	invalidate: () => void;
	limbo?: NodeId3D | null;
	shadowMaterials: Vec<MaterialId | null>;
	shadowOf: (light: NodeId3D, shadow: LightShadow | null) => void;
	beforeRefresh: FrameHook[];
}

export interface FrameHook {
	run: (view: CameraView) => void;
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
export const SCENE_UNIFORM_CAPACITY: int32 = 4096;

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
			if (next !== local && scene.isLive(node)) {
				setLocal(scene, node, next);
				local = next;
				invalidate();
			}
			return null;
		},
	);
}

function bindWrite<T>(state: SceneState, node: NodeId3D, read: () => T, write: (scene: VoidScene3D, node: NodeId3D, value: T) => void): void {
	const scene = state.handle.scene;
	createRenderEffect<T>(
		(prev: T | null): T => read(),
		(value: T, prev: T | null): Cleanup | null => {
			if (scene.isLive(node)) {
				write(scene, node, value);
				state.invalidate();
			}
			return null;
		},
	);
}

export function bindNode(state: SceneState, node: NodeId3D, props: NodeProps, initial: Transform3D): void {
	bindLocal(state.handle.scene, node, props, initial, state.invalidate);
	if (props.visible !== null) { bindWrite<boolean>(state, node, props.visible as () => boolean, setVisible); }
	if (props.pickable !== null) { bindWrite<boolean>(state, node, props.pickable as () => boolean, setPickable); }
	if (props.layers !== null) { bindWrite<uint32>(state, node, props.layers as () => uint32, setLayers); }
	if (props.renderOrder !== null) { bindWrite<int32>(state, node, props.renderOrder as () => int32, setRenderOrder); }
	if (props.name !== null) { bindWrite<string>(state, node, props.name as () => string, setName); }
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

// A host node of a Scene3D: the Void node it stands for, and its place among the nodes Neon put there.
export class SceneNode3D {
	id: NodeId3D;
	parent: SceneNode3D | null = null;
	children: SceneNode3D[] = [];
	freed: boolean = false;
	returnNode: (() => void) | null = null;
	returned: boolean = false;

	constructor(id: NodeId3D) {
		this.id = id;
	}
}

function placed(scene: VoidScene3D, n: SceneNode3D): boolean {
	return !n.returned && scene.isLive(n.id);
}

function holds(scene: VoidScene3D, row: int32, ancestor: int32): boolean {
	for (let at = row; at != NO_NODE_3D; at = scene.nodes[at].parent) {
		if (at == ancestor) { return true; }
	}
	return false;
}

export function connected(scene: VoidScene3D, id: NodeId3D): boolean {
	return scene.isLive(id) && holds(scene, id.index, scene.root);
}

export function selectCamera(state: SceneState): void {
	const scene = state.handle.scene;
	if (scene.closed) { state.handle.camera = null; return; }
	for (let i = state.cameras.length - 1; i >= 0; i--) {
		const entry = state.cameras[i];
		if (entry.active === true && connected(scene, entry.node)) {
			setActiveCamera(scene, entry.node);
			state.handle.camera = entry.camera;
			return;
		}
	}
	for (const entry of state.cameras) {
		if (entry.active === null && connected(scene, entry.node)) {
			setActiveCamera(scene, entry.node);
			state.handle.camera = entry.camera;
			return;
		}
	}
	setActiveCamera(scene, null);
	state.handle.camera = null;
}

function placeInVoid(scene: VoidScene3D, p: SceneNode3D, n: SceneNode3D, at: int32): void {
	if (!placed(scene, p) || !placed(scene, n)) { return; }
	if (holds(scene, p.id.index, n.id.index)) { throw new Error("Scene3D: a node cannot be placed inside itself or its own descendant"); }
	for (let i = at + 1; i < p.children.length; i++) {
		const next = p.children[i];
		if (placed(scene, next) && scene.nodes[next.id.index].parent == p.id.index) {
			insertBefore(scene, p.id, n.id, next.id);
			return;
		}
	}
	attach(scene, p.id, n.id);
}

function freeTree(scene: VoidScene3D, n: SceneNode3D): void {
	const giveBack = n.returnNode;
	if (giveBack !== null) {
		giveBack();
	} else {
		freeBorrowedUnder(scene, n);
		if (scene.isLive(n.id)) { const removed = remove(scene, n.id); }
	}
	n.freed = true;
}

function freeBorrowedUnder(scene: VoidScene3D, n: SceneNode3D): void {
	for (const c of n.children) {
		if (c.returnNode !== null) { freeTree(scene, c); } else {
			freeBorrowedUnder(scene, c);
			c.freed = true;
		}
	}
}

// Frees what Neon put under a borrowed node, so the node goes back holding only its own children.
export function freeChildren(scene: VoidScene3D, n: SceneNode3D): void {
	for (const c of n.children) {
		c.parent = null;
		freeTree(scene, c);
	}
	n.children = [];
}

function hostNode(node: HostNode, op: string): SceneNode3D {
	const n = node as SceneNode3D;
	if (n.freed) { throw new Error("Scene3D: " + op + " on a node that was removed and freed"); }
	return n;
}

function no3D(op: string): Error {
	return new Error("Scene3D: " + op + " has no 3D node to act on; put 2D content in <Void>, <Texture> or a 2D parent");
}

export function sceneHost(state: SceneState): Host {
	const scene = state.handle.scene;
	const moved = (): void => {
		if (state.cameras.length > 0) { selectCamera(state); }
		state.invalidate();
	};
	const put = (parent: HostNode, node: HostNode, before: HostNode | null): void => {
		const p = hostNode(parent, "insertBefore");
		const n = hostNode(node, "insertBefore");
		for (let up: SceneNode3D | null = p; up !== null; up = (up as SceneNode3D).parent) {
			if (up === n) { throw new Error("insertBefore: a node cannot be placed inside itself or its own descendant"); }
		}
		let at = p.children.length as int32;
		if (before !== null) {
			const r = hostNode(before, "insertBefore");
			if (r === n) { return; }
			at = p.children.indexOf(r) as int32;
			if (at < 0) { throw new Error("insertBefore: the reference node is not a child of the parent"); }
		}
		const from = n.parent;
		if (from !== null) {
			const was = (from as SceneNode3D).children.indexOf(n) as int32;
			(from as SceneNode3D).children.splice(was, 1);
			if (from === p && was < at) { at -= 1; }
		}
		p.children.splice(at, 0, n);
		n.parent = p;
		placeInVoid(scene, p, n, at);
		moved();
	};
	const host: Host = {
		createElement: (tag: string): HostNode => {
			if (tag === "view") { throw new Error("<View> belongs in <Void>, <Texture> or a 2D parent, not directly in <Scene3D>"); }
			if (tag !== "holder") { throw no3D("<" + tag + ">"); }
			const holder = addGroup(scene, null, Transform3D.identity());
			setVisible(scene, holder, false);
			return new SceneNode3D(holder);
		},
		createText: (s: string): HostNode => {
			if (s !== "") { throw no3D("text \"" + s + "\""); }
			return new SceneNode3D(NO_NODE_ID);
		},
		setText: (node: HostNode, s: string): void => {
			const n = hostNode(node, "setText");
			if (s !== "") { throw no3D("text \"" + s + "\""); }
		},
		setAttr: (node: HostNode, name: string, value: string): void => { throw no3D("attribute " + name); },
		removeAttr: (node: HostNode, name: string): void => { throw no3D("attribute " + name); },
		setStyle: (node: HostNode, style: Style): void => { throw no3D("style"); },
		setStyleProp: null,
		setStyleClass: null,
		addEvent: (node: HostNode, name: string, handler: (e: NeonEvent) => void): void => { throw no3D("event " + name); },
		append: (parent: HostNode, child: HostNode): void => { put(parent, child, null); },
		insertBefore: put,
		removeChild: (parent: HostNode, node: HostNode): void => {
			const p = hostNode(parent, "removeChild");
			const n = hostNode(node, "removeChild");
			const at = p.children.indexOf(n);
			if (at < 0) { throw new Error("removeChild: the node is not a child of the parent"); }
			p.children.splice(at, 1);
			n.parent = null;
			freeTree(scene, n);
			moved();
		},
		parentOf: (node: HostNode): HostNode | null => {
			const up = hostNode(node, "parentOf").parent;
			return up === null ? null : up as HostNode;
		},
		release: (node: HostNode): void => {
			const n = hostNode(node, "release");
			if (n.parent !== null) { throw new Error("release: the node still has a parent; remove it first"); }
			freeTree(scene, n);
			moved();
		},
		nextSibling: (node: HostNode): HostNode | null => {
			const n = hostNode(node, "nextSibling");
			const up = n.parent;
			if (up === null) { return null; }
			const kids = (up as SceneNode3D).children;
			const at = kids.indexOf(n);
			return at < 0 || at + 1 >= kids.length ? null : kids[at + 1];
		},
		firstChild: (node: HostNode): HostNode | null => {
			const n = hostNode(node, "firstChild");
			return n.children.length === 0 ? null : n.children[0];
		},
		cloneNode: null,
		voidArea: null,
		scrollTo: null,
		measureText: null,
	};
	return host;
}

function unlinkTree(n: SceneNode3D): void {
	for (const c of n.children) { unlinkTree(c); }
	n.children = [];
	n.parent = null;
}

export function mountSceneChildren(state: SceneState, children: NeonNode): void {
	const scene = state.handle.scene;
	const root = new SceneNode3D(scene.rootId());
	onCleanup((): void => { unlinkTree(root); });
	const scope: NodeScope = { state: state, parent: root.id };
	getVoidScopeContext().provider({
		value: accessor(() => VoidSpace.Scene3D),
		children: sceneScope.provider({ value: accessor(() => scope), children: children }),
	})(sceneHost(state), root, null);
}

export function placeNodeChildren(scope: NodeScope, node: SceneNode3D, props: NodeProps, host: Host, parent: HostNode, before: HostNode | null): void {
	place(host, parent, node, before);
	if (props.ref !== null) { (props.ref as (value: NodeId3D) => void)(node.id); }
	const children = props.children;
	if (children !== null) {
		const next: NodeScope = { state: scope.state, parent: node.id };
		sceneScope.provider({ value: accessor(() => next), children: children })(host, node, null);
	}
}

export function mountNodeChildren(scope: NodeScope, node: NodeId3D, props: NodeProps, host: Host, parent: HostNode, before: HostNode | null): void {
	placeNodeChildren(scope, new SceneNode3D(node), props, host, parent, before);
}

export function useScene3D(): Scene3DHandle {
	return requireScene("useScene3D").state.handle;
}

export function useSceneNode(): NodeId3D {
	return requireScene("useSceneNode").parent;
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


export function onBeforeRefresh(state: SceneState, run: (view: CameraView) => void): void {
	const hook: FrameHook = { run };
	state.beforeRefresh.push(hook);
	onCleanup((): void => {
		const at = state.beforeRefresh.indexOf(hook);
		if (at >= 0) { state.beforeRefresh.splice(at, 1); }
	});
}

export function runBeforeRefresh(state: SceneState, pixelWidth: int32, pixelHeight: int32): void {
	if (state.beforeRefresh.length === 0) { return; }
	const synced = syncWorld(state.handle.scene);
	const world = viewCamera(state.handle);
	if (!world.ok) { throw new Error("Scene3D: the active camera has no world pose: " + world.error.toString()); }
	const view = world.value.resolve(pixelWidth, pixelHeight);
	if (!view.ok) { throw new Error("Scene3D: the active camera does not resolve: " + view.error.toString()); }
	for (const hook of state.beforeRefresh.slice(0)) {
		if (state.beforeRefresh.indexOf(hook) >= 0) { hook.run(view.value); }
	}
}
