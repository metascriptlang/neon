import { Accessor } from "../../core/signal";
import { createRenderEffect } from "../../core/effect";
import { Cleanup } from "../../core/types";
import { Host, HostNode, NeonNode } from "../../render/hostTypes";
import { CameraView } from "../../../../void/src/void3d/camera";
import { NodeId3D, addGroup, setVisible, worldOf } from "../../../../void/src/void3d/scene";
import { MeshLod, MeshLodProjectedSize } from "../../../../void/src/void3d/meshLod";
import { Mat4, Vec3, vec3, identity, position, length, determinant3x3 } from "../../../../void/src/math/math3d";
import { NodeProps, mountOwned, requireScene, localOf, bindNode, ownNode, mountNodeChildren, onBeforeRefresh, valueOr } from "./core";

export interface DetailedProps extends NodeProps {
	radius: Accessor<float32>;
	thresholds: Accessor<float32[]>;
	cullingRatio?: Accessor<float32> | null;
	forcedLevel?: Accessor<int32 | null> | null;
}

function configOf(thresholds: float32[], cullingRatio: float32): MeshLod {
	const ratios: float64[] = [];
	for (const threshold of thresholds) { ratios.push(threshold as float64); }
	if (!Number.isFinite(cullingRatio) || cullingRatio < 0.0) { throw new Error("Detailed: cullingRatio must be finite and non-negative"); }
	const made = MeshLod.create(thresholds.length as int32 + 1, ratios, cullingRatio as float64);
	if (!made.ok) { throw new Error("Detailed: thresholds must be finite, non-negative and descending"); }
	return made.value;
}

// Void's renderer hands MeshLod the projection diagonals, the near plane and `meshLodScale` as they are (renderer.ms:720-721).
function projectedSize(view: CameraView, world: Mat4, radius: float32, meshLodScale: float64): MeshLodProjectedSize {
	return {
		localOriginRadius: radius as float64,
		worldScaleX: vec3(world.m11, world.m12, world.m13).length() as float64,
		worldScaleY: vec3(world.m21, world.m22, world.m23).length() as float64,
		worldScaleZ: vec3(world.m31, world.m32, world.m33).length() as float64,
		worldMirrored: world.determinant3x3() < 0.0,
		cameraDistanceFromWorldOrigin: (view.eye - world.position()).length() as float64,
		projectionDiagonalX: view.projectionX as float64,
		projectionDiagonalY: view.projectionY as float64,
		nearPlane: view.nearPlane as float64,
		meshLodScale: meshLodScale,
	};
}

export function Detailed(props: DetailedProps): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		const scope = requireScene("Detailed");
		mountOwned((): void => {
			const state = scope.state;
			const scene = state.handle.scene;
			const local = localOf(props);
			const node = addGroup(scene, scope.parent, local);
			ownNode(state, node);
			bindNode(state, node, props, local);
			let lod: MeshLod = configOf([], 0.0);
			let radius: float32 = 0.0;
			let forced: int32 = -1;
			// What the last selection read; the next frame repeats it only when one of these moved.
			let settled = false;
			let settledWorld = identity();
			let settledEye: Vec3 = vec3(0.0, 0.0, 0.0);
			let settledX: float32 = 0.0;
			let settledY: float32 = 0.0;
			let settledNear: float32 = 0.0;
			let settledScale: float64 = 0.0;
			const settledLevels: int32[] = [];
			createRenderEffect<[float32[], float32, float32, int32 | null]>(
				(prev: [float32[], float32, float32, int32 | null] | null): [float32[], float32, float32, int32 | null] => [
					props.thresholds(),
					valueOr<float32>(props.cullingRatio, 0.0),
					props.radius(),
					props.forcedLevel === null ? null : (props.forcedLevel as () => int32 | null)(),
				],
				(value: [float32[], float32, float32, int32 | null], prev: [float32[], float32, float32, int32 | null] | null): Cleanup | null => {
					if (!Number.isFinite(value[2]) || value[2] < 0.0) { throw new Error("Detailed: radius must be finite and non-negative"); }
					if (value[3] !== null && (value[3] as int32) < 0) { throw new Error("Detailed: forcedLevel must be non-negative"); }
					lod = configOf(value[0], value[1]);
					radius = value[2];
					forced = value[3] === null ? -1 : value[3] as int32;
					settled = false;
					state.invalidate();
					return null;
				},
			);
			const show = (level: NodeId3D, shown: boolean): void => {
				if (scene.nodes[level.index].isVisible() !== shown) { setVisible(scene, level, shown); }
			};
			onBeforeRefresh(state, (view: CameraView): void => {
				const children = scene.nodes[node.index].children;
				const count = children.length as int32;
				if (count === 0) { return; }
				if (count !== lod.lodCount) {
					throw new Error("Detailed: " + (lod.lodCount - 1).toString() + " thresholds name " + lod.lodCount.toString()
						+ " levels, but " + count.toString() + " children are mounted");
				}
				const world = worldOf(scene, node);
				if (!world.ok) { throw new Error("Detailed: no world pose: " + world.error.toString()); }
				const meshLodScale = state.handle.renderer.core.meshLodScale;
				let same = settled && world.value == settledWorld && view.eye == settledEye && view.projectionX == settledX
					&& view.projectionY == settledY && view.nearPlane == settledNear && meshLodScale == settledScale;
				for (let i = 0; same && i < count; i++) { same = children[i] === settledLevels[i]; }
				if (same) { return; }
				const ratio = projectedSize(view, world.value, radius, meshLodScale).referenceScreenRatioHeuristic();
				if (!ratio.ok) { throw new Error("Detailed: no projected size: " + ratio.error.toString()); }
				const selected = lod.select(ratio.value, forced);
				if (!selected.ok) { throw new Error("Detailed: MeshLod.select failed: " + selected.error.toString()); }
				settledLevels.length = 0;
				for (let i = 0; i < count; i++) {
					settledLevels.push(children[i]);
					show(scene.nodeIdAt(children[i]), !selected.value.culled && i === selected.value.lod);
				}
				settledWorld = world.value;
				settledEye = view.eye;
				settledX = view.projectionX;
				settledY = view.projectionY;
				settledNear = view.nearPlane;
				settledScale = meshLodScale;
				settled = true;
			});
			mountNodeChildren(scope, node, props, host, parent, before);
		});
	};
}
