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

// R3F ThreeEvent: the window's event plus the intersection.
export interface Pointer3DEvent extends NeonEvent {
	node: NodeId3D;
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
	onPointerMove?: ((e: Pointer3DEvent) => void) | null;
	onWheel?: ((e: Pointer3DEvent) => void) | null;
}

interface PointerEntry {
	node: NodeId3D;
	events: PressEvents<Pointer3DEvent>;
	hovers: boolean;
	onMove: ((e: Pointer3DEvent) => void) | null;
	onWheel: ((e: Pointer3DEvent) => void) | null;
}

// A control that drives the scene from drags no node takes, as drei's controls listen on the canvas.
export interface PointerDrag {
	begin: (x: float32, y: float32, e: NeonEvent) => boolean;
	drag: (x: float32, y: float32, e: NeonEvent) => void;
	end: (x: float32, y: float32, e: NeonEvent) => void;
	wheel: (x: float32, y: float32, e: NeonEvent) => boolean;
}

export interface Pointer3D {
	area: VoidAreaHandle;
	addDrag: (drag: PointerDrag) => () => void;
	hit: (x: float32, y: float32, kind: AreaPointerKind, e: NeonEvent) => boolean;
	add: (entry: PointerEntry) => void;
	drop: (entry: PointerEntry) => void;
}

export const pointerScope = createContext<Pointer3D | null>(null);

const NO_RAY: Ray = { origin: { x: 0.0, y: 0.0, z: 0.0 }, direction: { x: 0.0, y: 0.0, z: 0.0 } };
const NO_HIT: PickHit = { owner: NO_NODE_ID, mesh: NO_NODE_ID, distance: -1.0, point: { x: 0.0, y: 0.0, z: 0.0 }, uv: null };
const MISS_SLOP: float32 = 2.0;

function pointerEventOf(type: string, base: NeonEvent, ray: Ray, hit: PickHit): Pointer3DEvent {
	return {
		...base, type, propagationStopped: false,
		node: hit.mesh, point: hit.point, distance: hit.distance, ray, uv: hit.uv,
	};
}

function deliver(handler: ((e: Pointer3DEvent) => void) | null, e: Pointer3DEvent): void {
	if (handler !== null) { (handler as (x: Pointer3DEvent) => void)(e); }
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
	let moves: int32 = 0;
	let wheels: int32 = 0;
	let hovered: PointerEntry[] = [];
	let captured: NodeId3D | null = null;
	let pressEntry: PointerEntry | null = null;
	let pressTracks = false;
	let pressButton: number = 0;
	let missing = false;
	let missX: float32 = 0.0;
	let missY: float32 = 0.0;
	let ray: Ray = NO_RAY;
	let aimed: PickHit = NO_HIT;
	const scratch: PointerEntry[] = [];
	const held: PointerEntry[] = [];
	let drags: PointerDrag[] = [];
	let dragging: PointerDrag | null = null;
	let dragButton: number = 0;

	// The entries on the path from a node to the root, nearest first.
	const pathOf = (row: int32, into: PointerEntry[]): void => {
		into.length = 0;
		for (let at = row; at != NO_NODE_3D; at = scene.nodes[at].parent) {
			if (at >= byRow.length) { continue; }
			const entry = byRow[at];
			if (entry !== null && scene.isLive((entry as PointerEntry).node)) { into.push(entry as PointerEntry); }
		}
	};

	// The hit's path into `scratch`.
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
		pathOf(aimed.mesh.index, scratch);
	};

	// W3C pointerenter/pointerleave: no bubbling; left nodes hear it deepest first, entered nodes outermost first.
	const hoverTo = (next: PointerEntry[], e: NeonEvent): void => {
		if (samePath(next, hovered)) { return; }
		const was = hovered;
		hovered = next.slice(0);
		for (const entry of was) {
			if (hovered.indexOf(entry) < 0) {
				deliver(entry.events.onPointerLeave, pointerEventOf("pointerleave", e, ray, aimed));
			}
		}
		for (let i = hovered.length - 1; i >= 0; i -= 1) {
			const entry = hovered[i];
			if (was.indexOf(entry) < 0) {
				deliver(entry.events.onPointerEnter, pointerEventOf("pointerenter", e, ray, aimed));
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

	const beginDrag = (x: float32, y: float32, e: NeonEvent): boolean => {
		for (let i = drags.length - 1; i >= 0; i -= 1) {
			const drag = drags[i];
			if (drag.begin(x, y, e)) {
				dragging = drag;
				dragButton = e.button;
				return true;
			}
		}
		return false;
	};

	// No node takes it: a control may start a drag, and a primary click may still turn out a miss.
	const unclaimed = (x: float32, y: float32, e: NeonEvent): boolean => {
		const started = beginDrag(x, y, e);
		const misses = primary(e.button) && takeMiss(x, y);
		return started || misses;
	};

	// The Void host's walk: one event bubbles from the nearest entry until a handler stops it.
	const along = (path: PointerEntry[], handlerOf: (entry: PointerEntry) => ((e: Pointer3DEvent) => void) | null, ev: Pointer3DEvent): void => {
		for (const entry of path) {
			if (ev.propagationStopped) { return; }
			deliver(handlerOf(entry), ev);
		}
	};

	// The pressed node keeps the pointer until its button's release, as RN's touch target does.
	const heldPath = (): PointerEntry[] => {
		const holder = captured;
		if (holder !== null && scene.isLive(holder as NodeId3D)) {
			pathOf((holder as NodeId3D).index, held);
			return held;
		}
		return scratch;
	};

	const under = (top: NodeId3D): boolean => {
		if (aimed.mesh.scene !== top.scene) { return false; }
		for (let at = aimed.mesh.index; at != NO_NODE_3D; at = scene.nodes[at].parent) {
			if (at == top.index) { return true; }
		}
		return false;
	};

	const pointerDown = (x: float32, y: float32, e: NeonEvent): boolean => {
		if (captured !== null || dragging !== null || missing) { return true; }
		if (count === 0) { return unclaimed(x, y, e); }
		aim(x, y);
		hoverTo(scratch, e);
		if (scratch.length === 0) { return unclaimed(x, y, e); }
		captured = aimed.mesh;
		pressButton = e.button;
		pressEntry = null;
		pressTracks = false;
		for (const entry of scratch) {
			if (entry.events.onPointerDown !== null) { pressTracks = true; }
			if (pressEntry === null && entry.events.onPress !== null && primary(e.button)) { pressEntry = entry; }
		}
		along(scratch, (entry: PointerEntry): ((e: Pointer3DEvent) => void) | null => entry.events.onPointerDown,
			pointerEventOf("pointerdown", e, ray, aimed));
		return true;
	};

	const pointerUp = (x: float32, y: float32, e: NeonEvent): boolean => {
		const drag = dragging;
		if (drag !== null && e.button === dragButton) {
			dragging = null;
			drag.end(x, y, e);
		}
		if (missing) {
			missing = false;
			if (count > 0) { aim(x, y); } else { scratch.length = 0; }
			const still = Math.abs(x - missX) <= MISS_SLOP && Math.abs(y - missY) <= MISS_SLOP;
			if (still && scratch.length === 0 && onMissed !== null) {
				(onMissed as (x: NeonEvent) => void)({ ...e, type: "pressmissed", propagationStopped: false });
			}
			return true;
		}
		if (captured === null) { return drag !== null; }
		aim(x, y);
		hoverTo(scratch, e);
		const path = heldPath();
		const ends = e.button === pressButton;
		const presser = pressEntry;
		if (ends) {
			captured = null;
			pressEntry = null;
			pressTracks = false;
		}
		along(path, (entry: PointerEntry): ((e: Pointer3DEvent) => void) | null => entry.events.onPointerUp,
			pointerEventOf("pointerup", e, ray, aimed));
		if (ends && presser !== null && scene.isLive((presser as PointerEntry).node) && under((presser as PointerEntry).node)) {
			deliver((presser as PointerEntry).events.onPress, pointerEventOf("press", e, ray, aimed));
		}
		return true;
	};

	const pointerMove = (x: float32, y: float32, e: NeonEvent): boolean => {
		const drag = dragging;
		if (drag !== null) { drag.drag(x, y, e); }
		if (hovers === 0 && moves === 0 && !pressTracks) { return captured !== null || dragging !== null; }
		aim(x, y);
		hoverTo(scratch, e);
		along(scratch, (entry: PointerEntry): ((e: Pointer3DEvent) => void) | null => entry.onMove,
			pointerEventOf("pointermove", e, ray, aimed));
		return hovered.length > 0 || captured !== null || dragging !== null;
	};

	const pointerWheel = (x: float32, y: float32, e: NeonEvent): boolean => {
		let taken = false;
		if (wheels > 0) {
			aim(x, y);
			for (const entry of scratch) {
				if (entry.onWheel !== null) { taken = true; }
			}
			along(scratch, (entry: PointerEntry): ((e: Pointer3DEvent) => void) | null => entry.onWheel,
				pointerEventOf("wheel", e, ray, aimed));
		}
		for (let i = drags.length - 1; i >= 0; i -= 1) {
			if (drags[i].wheel(x, y, e)) { return true; }
		}
		return taken;
	};

	const pointerLeave = (x: float32, y: float32, e: NeonEvent): void => {
		const drag = dragging;
		dragging = null;
		if (drag !== null) { drag.end(x, y, e); }
		missing = false;
		aimed = NO_HIT;
		scratch.length = 0;
		hoverTo(scratch, e);
		if (captured === null) { return; }
		const path = heldPath();
		captured = null;
		pressEntry = null;
		pressTracks = false;
		along(path, (entry: PointerEntry): ((e: Pointer3DEvent) => void) | null => entry.events.onPointerCancel,
			pointerEventOf("pointercancel", e, ray, aimed));
	};

	return {
		area,
		addDrag: (drag: PointerDrag): () => void => {
			drags.push(drag);
			return (): void => {
				const at = drags.indexOf(drag);
				if (at >= 0) { drags.splice(at, 1); }
				if (dragging === drag) { dragging = null; }
			};
		},
		hit: (x: float32, y: float32, kind: AreaPointerKind, e: NeonEvent): boolean => {
			if (scene.closed) { return false; }
			return match (kind) {
				AreaPointerKind.Button => e.pressed ? pointerDown(x, y, e) : pointerUp(x, y, e),
				AreaPointerKind.Motion => pointerMove(x, y, e),
				AreaPointerKind.Wheel => pointerWheel(x, y, e),
				AreaPointerKind.Leave => {
					pointerLeave(x, y, e);
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
			if (entry.onMove !== null) { moves += 1; }
			if (entry.onWheel !== null) { wheels += 1; }
		},
		drop: (entry: PointerEntry): void => {
			const row = entry.node.index;
			if (row < byRow.length && byRow[row] === entry) {
				byRow[row] = null;
				count -= 1;
				if (entry.hovers) { hovers -= 1; }
				if (entry.onMove !== null) { moves -= 1; }
				if (entry.onWheel !== null) { wheels -= 1; }
			}
			without(hovered, entry);
			if (pressEntry === entry) { pressEntry = null; }
		},
	};
}

function cancelled(): Pointer3DEvent {
	return pointerEventOf("pointercancel", neonEvent("pointercancel"), NO_RAY, NO_HIT);
}

export function hasPointerHandlers(props: PointerProps): boolean {
	return props.onPress !== null || props.onPressIn !== null || props.onPressOut !== null ||
		props.onLongPress !== null || props.onHoverIn !== null || props.onHoverOut !== null ||
		props.onPointerMove !== null || props.onWheel !== null;
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
	}, cancelled);
	const entry: PointerEntry = { node, events, hovers: props.onHoverIn !== null || props.onHoverOut !== null,
		onMove: props.onPointerMove, onWheel: props.onWheel };
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
