import { Accessor, untrack } from "../../core/signal";
import { createRenderEffect } from "../../core/effect";
import { Cleanup } from "../../core/types";
import { onCleanup } from "../../core/cleanup";
import { useContext } from "../../render/context";
import { NeonEvent } from "../../render/event";
import { VoidAreaHandle } from "../../render/voidAreaHandle";
import { Host, HostNode, NeonNode } from "../../render/hostTypes";
import { Vec3, vec3, eulerQuat } from "../../../../void/src/math/math3d";
import { ProjectionKind } from "../../../../void/src/void3d/camera";
import { NodeId3D, Transform3D, setLocal, cameraViewOf } from "../../../../void/src/void3d/scene";
import { mountOwned, requireScene } from "./core";
import { Pointer3D, PointerDrag, pointerScope } from "./pointer";

// drei <OrbitControls> over three's OrbitControls: left drag orbits the target, right drag pans it, the wheel dollies.
export interface OrbitControlsProps {
	target?: Accessor<Vec3> | null;
	enableRotate?: Accessor<boolean> | null;
	enableZoom?: Accessor<boolean> | null;
	enablePan?: Accessor<boolean> | null;
	rotateSpeed?: Accessor<float32> | null;
	zoomSpeed?: Accessor<float32> | null;
	panSpeed?: Accessor<float32> | null;
	minDistance?: Accessor<float32> | null;
	maxDistance?: Accessor<float32> | null;
	minPolarAngle?: Accessor<float32> | null;
	maxPolarAngle?: Accessor<float32> | null;
	onChange?: (() => void) | null;
}

// three OrbitControls keeps the polar angle this far inside the poles so the view never flips.
const POLE_EPS: float32 = 0.000001;
const PI: float32 = 3.141592653589793;
const RIGHT_BUTTON: number = 2;

enum OrbitMode {
	Idle,
	Rotate,
	Pan,
}

function read(value: Accessor<float32> | null, fallback: float32): float32 {
	return value === null ? fallback : (value as () => float32)();
}

function enabled(value: Accessor<boolean> | null): boolean {
	return value === null ? true : (value as () => boolean)();
}

export function OrbitControls(props: OrbitControlsProps): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		const scope = requireScene("OrbitControls");
		const router = useContext(pointerScope);
		if (router === null) { throw new Error("OrbitControls: mount inside Scene3D"); }
		mountOwned((): void => {
			const state = scope.state;
			const scene = state.handle.scene;
			const pointer = router as Pointer3D;
			const area: VoidAreaHandle = pointer.area;
			let target: Vec3 = props.target === null ? vec3(0.0, 0.0, 0.0) : untrack(props.target as () => Vec3);
			let mode = OrbitMode.Idle;
			let lastX: float32 = 0.0;
			let lastY: float32 = 0.0;

			const camera = (): NodeId3D => {
				const active = scene.activeCamera;
				if (active === null || !scene.isLive(active as NodeId3D)) { throw new Error("OrbitControls: needs an active Camera3D"); }
				return active as NodeId3D;
			};

			const viewHeight = (): float32 => {
				const height = (area.pixelHeight() as float32) / area.scale();
				return height > 0.0 ? height : 1.0;
			};

			// three Spherical with y up: theta around y from +z, phi down from +y.
			const pose = (id: NodeId3D, radius: float32, theta: float32, phi: float32): void => {
				const lowPole = Math.max(read(props.minPolarAngle, 0.0), POLE_EPS) as float32;
				const highPole = Math.min(read(props.maxPolarAngle, PI), PI - POLE_EPS) as float32;
				const polar = Math.min(Math.max(phi, lowPole), highPole) as float32;
				const near = read(props.minDistance, 0.0);
				const far = read(props.maxDistance, Infinity as float32);
				const distance = Math.min(Math.max(radius, near), far) as float32;
				const across = Math.sin(polar) as float32;
				const offset = vec3(
					distance * across * (Math.sin(theta) as float32),
					distance * (Math.cos(polar) as float32),
					distance * across * (Math.cos(theta) as float32),
				);
				const pitch = PI / 2.0 - polar;
				const local: Transform3D = {
					position: target + offset, rotation: eulerQuat(-pitch, theta, 0.0), scale: vec3(1.0, 1.0, 1.0),
				};
				setLocal(scene, id, local);
				state.invalidate();
				const changed = props.onChange;
				if (changed !== null) { (changed as () => void)(); }
			};

			const spherical = (id: NodeId3D): Vec3 => {
				const offset = scene.nodes[id.index].local.position - target;
				const radius = offset.length();
				if (radius <= 0.0) { return vec3(0.0, 0.0, PI / 2.0); }
				const cosPolar = Math.min(Math.max(offset.y / radius, -1.0), 1.0);
				return vec3(radius, Math.atan2(offset.x, offset.z) as float32, Math.acos(cosPolar) as float32);
			};

			const rotate = (dx: float32, dy: float32): void => {
				const id = camera();
				const at = spherical(id);
				const turn = 2.0 * PI * read(props.rotateSpeed, 1.0) / viewHeight();
				pose(id, at.x, at.y - dx * turn, at.z - dy * turn);
			};

			const pan = (dx: float32, dy: float32): void => {
				const id = camera();
				const at = spherical(id);
				const view = cameraViewOf(scene, id);
				if (!view.ok) { throw new Error("OrbitControls: the active camera has no world pose: " + view.error.toString()); }
				let halfFov: float32 = 0.5;
				const projection = view.value.projection;
				match (projection.kind) {
					ProjectionKind.Perspective => { halfFov = projection.fovY / 2.0; },
					ProjectionKind.Orthographic => {},
				}
				const span = 2.0 * at.x * (Math.tan(halfFov) as float32) * read(props.panSpeed, 1.0) / viewHeight();
				const yaw = at.y;
				const pitch = PI / 2.0 - at.z;
				const right = vec3(Math.cos(yaw) as float32, 0.0, -(Math.sin(yaw) as float32));
				const up = vec3(
					-(Math.sin(yaw) as float32) * (Math.sin(pitch) as float32),
					Math.cos(pitch) as float32,
					-(Math.cos(yaw) as float32) * (Math.sin(pitch) as float32),
				);
				target = target - right.scaled(dx * span) + up.scaled(dy * span);
				pose(id, at.x, at.y, at.z);
			};

			const drag: PointerDrag = {
				begin: (x: float32, y: float32, e: NeonEvent): boolean => {
					const panning = e.button === RIGHT_BUTTON;
					if (panning ? !enabled(props.enablePan) : !enabled(props.enableRotate)) { return false; }
					mode = panning ? OrbitMode.Pan : OrbitMode.Rotate;
					lastX = x;
					lastY = y;
					return true;
				},
				drag: (x: float32, y: float32, e: NeonEvent): void => {
					const dx = x - lastX;
					const dy = y - lastY;
					if (dx === 0.0 && dy === 0.0) { return; }
					lastX = x;
					lastY = y;
					match (mode) {
						OrbitMode.Rotate => { rotate(dx, dy); },
						OrbitMode.Pan => { pan(dx, dy); },
						OrbitMode.Idle => {},
					}
				},
				end: (x: float32, y: float32, e: NeonEvent): void => { mode = OrbitMode.Idle; },
				// three getZoomScale: 0.95 per step; Ion's wheel dy > 0 turns away from the user, which dollies in.
				wheel: (x: float32, y: float32, e: NeonEvent): boolean => {
					if (!enabled(props.enableZoom) || e.deltaY === 0) { return false; }
					const id = camera();
					const at = spherical(id);
					const step = Math.pow(0.95, read(props.zoomSpeed, 1.0)) as float32;
					pose(id, e.deltaY > 0 ? at.x * step : at.x / step, at.y, at.z);
					return true;
				},
			};
			onCleanup(pointer.addDrag(drag));
			if (props.target !== null) {
				createRenderEffect<Vec3>(
					(prev: Vec3 | null): Vec3 => (props.target as () => Vec3)(),
					(value: Vec3, prev: Vec3 | null): Cleanup | null => {
						target = value;
						const active = scene.activeCamera;
						if (active !== null && scene.isLive(active as NodeId3D)) {
							const at = spherical(active as NodeId3D);
							pose(active as NodeId3D, at.x, at.y, at.z);
						}
						return null;
					},
				);
			}
		});
	};
}
