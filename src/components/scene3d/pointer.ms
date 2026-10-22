import { accessor } from "../../core/signal";
import { onCleanup } from "../../core/cleanup";
import { createContext, useContext } from "../../render/context";
import { NeonEvent, neonEvent } from "../../render/event";
import { AreaPointerKind, VoidAreaHandle } from "../../render/voidAreaHandle";
import { NeonNode } from "../../render/hostTypes";
import { LONG_PRESS_DELAY_MS, PressEvents, pressEvents } from "../pressability";
import { Vec3 } from "../../../../void/src/math/math3d";
import { Ray } from "../../../../void/src/void3d/ray";
import { Uv } from "../../../../void/src/void3d/meshData";
import { LowResView } from "../../../../void/src/void3d/blit";
import { rayFromScreen, resolve } from "../../../../void/src/void3d/camera";
import { PickHit, PickError, pickNearestOn } from "../../../../void/src/void3d/pick";
import { DEFAULT_LAYERS } from "../../../../void/src/void3d/layers";
import { NodeId3D, NodeFlag, NO_NODE_3D, NO_NODE_ID, setPickable, syncWorld, cameraLayersOf } from "../../../../void/src/void3d/scene";
import { NodeProps, SceneState, viewCamera } from "./core";

// R3F ThreeEvent: the window's event plus the intersection. One object per receiving node, as R3F builds one per hit.
export interface Pointer3DEvent extends NeonEvent {
	node: NodeId3D;
	currentNode: NodeId3D;
	point: Vec3;
	distance: float32;
	ray: Ray;
	uv: Uv | null;
}

export interface PointerProps extends NodeProps {
	onPress?: ((e: Pointer3DEvent) => void) | null;
	onPressIn?: ((e: Pointer3DEvent) => void) | null;
	onPressOut?: ((e: Pointer3DEvent) => void) | null;
	onLongPress?: ((e: Pointer3DEvent) => void) | null;
	onHoverIn?: ((e: Pointer3DEvent) => void) | null;
	onHoverOut?: ((e: Pointer3DEvent) => void) | null;
}

interface PointerEntry {
	node: NodeId3D;
	events: PressEvents<Pointer3DEvent>;
	hovers: boolean;
}

export interface Pointer3D {
	hit: (x: float32, y: float32, kind: AreaPointerKind, e: NeonEvent) => boolean;
	add: (entry: PointerEntry) => void;
	drop: (entry: PointerEntry) => void;
}

export const pointerScope = createContext<Pointer3D | null>(null);

const NO_RAY: Ray = { origin: { x: 0.0, y: 0.0, z: 0.0 }, direction: { x: 0.0, y: 0.0, z: 0.0 } };
const NO_HIT: PickHit = { owner: NO_NODE_ID, mesh: NO_NODE_ID, distance: -1.0, point: { x: 0.0, y: 0.0, z: 0.0 }, uv: null };
const MISS_SLOP: float32 = 2.0;

function pointerEventOf(type: string, base: NeonEvent, current: NodeId3D, ray: Ray, hit: PickHit): Pointer3DEvent {
	return {
		...base, type, propagationStopped: false,
		node: hit.mesh, currentNode: current, point: hit.point, distance: hit.distance, ray, uv: hit.uv,
	};
}

function deliver(handler: ((e: Pointer3DEvent) => void) | null, e: Pointer3DEvent): boolean {
	if (handler === null) { return false; }
	(handler as (x: Pointer3DEvent) => void)(e);
	return e.propagationStopped;
}

function samePath(a: PointerEntry[], b: PointerEntry[]): boolean {
	if (a.length !== b.length) { return false; }
	for (let i = 0; i < a.length; i++) {
		if (a[i] !== b[i]) { return false; }
	}
	return true;
}

function without(list: PointerEntry[], entry: PointerEntry): void {
	const at = list.indexOf(entry);
	if (at >= 0) { list.splice(at, 1); }
}

// Ion numbers the left button 1; 0 is a touch.
function primary(button: number): boolean {
	return button === 0 || button === 1;
}

export function createPointer3D(state: SceneState, area: VoidAreaHandle, onMissed: ((e: NeonEvent) => void) | null): Pointer3D {
	const scene = state.handle.scene;
	let byRow: (PointerEntry | null)[] = [];
	let count: int32 = 0;
	let hovers: int32 = 0;
	let hovered: PointerEntry[] = [];
	let pressed: PointerEntry[] = [];
	let pressTracks = false;
	let pressButton: number = 0;
	let missing = false;
	let missX: float32 = 0.0;
	let missY: float32 = 0.0;
	let ray: Ray = NO_RAY;
	let aimed: PickHit = NO_HIT;
	const scratch: PointerEntry[] = [];

	// The entries on the path from the nearest hit to the root, nearest first, into `scratch`.
	const aim = (x: float32, y: float32): void => {
		scratch.length = 0;
		aimed = NO_HIT;
		const width = area.pixelWidth();
		const height = area.pixelHeight();
		if (width <= 0 || height <= 0) { return; }
		const synced = syncWorld(scene);
		const world = viewCamera(state.handle);
		if (!world.ok) { return; }
		const view = world.value.resolve(width, height);
		if (!view.ok) { return; }
		const dpi = area.scale();
		const screen: LowResView = { width, height, scale: 1, offsetX: 0.0, offsetY: 0.0 };
		ray = view.value.rayFromScreen(x * dpi, y * dpi, screen, true);
		const eye = scene.activeCamera;
		const layers = eye === null ? DEFAULT_LAYERS : cameraLayersOf(scene, eye as NodeId3D);
		const picked = pickNearestOn(scene, ray, layers);
		if (!picked.ok) {
			if (picked.error === PickError.NothingHit) { return; }
			throw new Error("Scene3D: picking failed: " + picked.error.toString());
		}
		aimed = picked.value;
		for (let at = aimed.mesh.index; at != NO_NODE_3D; at = scene.nodes[at].parent) {
			if (at >= byRow.length) { continue; }
			const entry = byRow[at];
			if (entry !== null && scene.isLive((entry as PointerEntry).node)) { scratch.push(entry as PointerEntry); }
		}
	};

	// W3C pointerenter/pointerleave: no bubbling; left nodes hear it deepest first, entered nodes outermost first.
	const hoverTo = (next: PointerEntry[], e: NeonEvent): void => {
		if (samePath(next, hovered)) { return; }
		const was = hovered;
		hovered = next.slice(0);
		for (const entry of was) {
			if (hovered.indexOf(entry) < 0) {
				deliver(entry.events.onPointerLeave, pointerEventOf("pointerleave", e, entry.node, ray, aimed));
			}
		}
		for (let i = hovered.length - 1; i >= 0; i -= 1) {
			const entry = hovered[i];
			if (was.indexOf(entry) < 0) {
				deliver(entry.events.onPointerEnter, pointerEventOf("pointerenter", e, entry.node, ray, aimed));
			}
		}
	};

	const takeMiss = (x: float32, y: float32): boolean => {
		if (onMissed === null) { return false; }
		missing = true;
		missX = x;
		missY = y;
		return true;
	};

	const pointerDown = (x: float32, y: float32, e: NeonEvent): boolean => {
		if (!primary(e.button) || pressed.length > 0) { return false; }
		if (count === 0) { return takeMiss(x, y); }
		aim(x, y);
		hoverTo(scratch, e);
		if (scratch.length === 0) { return takeMiss(x, y); }
		let presses = false;
		for (const entry of scratch) {
			if (entry.events.onPress !== null || entry.events.onPointerDown !== null) { presses = true; }
		}
		if (!presses) { return false; }
		const path = scratch.slice(0);
		pressButton = e.button;
		pressTracks = false;
		for (const entry of path) {
			pressed.push(entry);
			if (entry.events.onPointerDown !== null) { pressTracks = true; }
			if (deliver(entry.events.onPointerDown, pointerEventOf("pointerdown", e, entry.node, ray, aimed))) { break; }
		}
		return true;
	};

	const pointerUp = (x: float32, y: float32, e: NeonEvent): boolean => {
		if (missing) {
			missing = false;
			if (count > 0) { aim(x, y); } else { scratch.length = 0; }
			const still = Math.abs(x - missX) <= MISS_SLOP && Math.abs(y - missY) <= MISS_SLOP;
			if (still && scratch.length === 0 && onMissed !== null) {
				(onMissed as (x: NeonEvent) => void)({ ...e, type: "pressmissed", propagationStopped: false });
			}
			return true;
		}
		if (pressed.length === 0 || e.button !== pressButton) { return pressed.length > 0; }
		aim(x, y);
		hoverTo(scratch, e);
		const was = pressed;
		pressed = [];
		pressTracks = false;
		for (const entry of was) {
			if (entry.events.onPointerUp !== null) {
				if (deliver(entry.events.onPointerUp, pointerEventOf("pointerup", e, entry.node, ray, aimed))) { break; }
			} else if (entry.events.onPress !== null && scratch.indexOf(entry) >= 0) {
				if (deliver(entry.events.onPress, pointerEventOf("press", e, entry.node, ray, aimed))) { break; }
			}
		}
		return true;
	};

	const pointerMove = (x: float32, y: float32, e: NeonEvent): boolean => {
		if (hovers === 0 && !pressTracks) { return pressed.length > 0; }
		aim(x, y);
		hoverTo(scratch, e);
		return hovered.length > 0 || pressed.length > 0;
	};

	const pointerLeave = (e: NeonEvent): void => {
		missing = false;
		aimed = NO_HIT;
		scratch.length = 0;
		hoverTo(scratch, e);
		const was = pressed;
		pressed = [];
		pressTracks = false;
		for (const entry of was) {
			deliver(entry.events.onPointerCancel, pointerEventOf("pointercancel", e, entry.node, ray, aimed));
		}
	};

	return {
		hit: (x: float32, y: float32, kind: AreaPointerKind, e: NeonEvent): boolean => {
			if (scene.closed) { return false; }
			return match (kind) {
				AreaPointerKind.Button => e.pressed ? pointerDown(x, y, e) : pointerUp(x, y, e),
				AreaPointerKind.Motion => pointerMove(x, y, e),
				AreaPointerKind.Wheel => false,
				AreaPointerKind.Leave => {
					pointerLeave(e);
					return false;
				},
			};
		},
		add: (entry: PointerEntry): void => {
			const row = entry.node.index;
			while (byRow.length <= row) { byRow.push(null); }
			if (byRow[row] !== null) { throw new Error("Scene3D: a node takes pointer handlers from one component only"); }
			byRow[row] = entry;
			count += 1;
			if (entry.hovers) { hovers += 1; }
		},
		drop: (entry: PointerEntry): void => {
			const row = entry.node.index;
			if (row < byRow.length && byRow[row] === entry) {
				byRow[row] = null;
				count -= 1;
				if (entry.hovers) { hovers -= 1; }
			}
			without(hovered, entry);
			without(pressed, entry);
		},
	};
}

function cancelled(node: NodeId3D): () => Pointer3DEvent {
	return (): Pointer3DEvent => pointerEventOf("pointercancel", neonEvent("pointercancel"), node, NO_RAY, NO_HIT);
}

export function hasPointerHandlers(props: PointerProps): boolean {
	return props.onPress !== null || props.onPressIn !== null || props.onPressOut !== null ||
		props.onLongPress !== null || props.onHoverIn !== null || props.onHoverOut !== null;
}

// A node with a pointer handler is made pickable unless the author set `pickable`, and gets its own flag back on unmount.
export function bindPointer(state: SceneState, node: NodeId3D, props: PointerProps): void {
	if (!hasPointerHandlers(props)) { return; }
	const router = useContext(pointerScope);
	if (router === null) { throw new Error("Scene3D: pointer handlers need a Scene3D that routes pointer events"); }
	const pointer = router as Pointer3D;
	const scene = state.handle.scene;
	const events = pressEvents<Pointer3DEvent>({
		onPress: props.onPress,
		onPressIn: props.onPressIn,
		onPressOut: props.onPressOut,
		onLongPress: props.onLongPress,
		onHoverIn: props.onHoverIn,
		onHoverOut: props.onHoverOut,
		delayLongPress: accessor((): number => LONG_PRESS_DELAY_MS),
	}, cancelled(node));
	const entry: PointerEntry = { node, events, hovers: props.onHoverIn !== null || props.onHoverOut !== null };
	const wasPickable = scene.nodes[node.index].flags.has(NodeFlag.Pickable);
	if (props.pickable === null) { setPickable(scene, node, true); }
	pointer.add(entry);
	onCleanup((): void => {
		pointer.drop(entry);
		if (props.pickable === null && scene.isLive(node)) { setPickable(scene, node, wasPickable); }
	});
}

export function providePointer(pointer: Pointer3D, children: NeonNode): NeonNode {
	return pointerScope.provider({ value: accessor((): Pointer3D | null => pointer), children: children });
}
