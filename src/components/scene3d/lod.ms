import { Accessor } from "../../core/signal";
import { createRenderEffect } from "../../core/effect";
import { Cleanup } from "../../core/types";
import { Host, HostNode, NeonNode } from "../../render/hostTypes";
import { CameraView } from "../../../../void/src/void3d/camera";
import { NodeId3D, addGroup, setVisible, worldOf } from "../../../../void/src/void3d/scene";
import { MeshLod, MeshLodProjectedSize } from "../../../../void/src/void3d/meshLod";
import { Mat4, vec3, position, length, determinant3x3, inverse } from "../../../../void/src/math/math3d";
import { NodeProps, mountOwned, requireScene, localOf, bindNode, ownNode, mountNodeChildren, onBeforeRefresh, viewCamera } from "./core";

export interface LodProps extends NodeProps {
	radius: Accessor<float32>;
	thresholds: Accessor<float32[]>;
	cullingRatio?: Accessor<float32> | null;
	forcedLevel?: Accessor<int32 | null> | null;
}

function configOf(thresholds: float32[], cullingRatio: float32): MeshLod {
	const ratios: float64[] = [];
	for (const threshold of thresholds) { ratios.push(threshold as float64); }
	if (!Number.isFinite(cullingRatio) || cullingRatio < 0.0) { throw new Error("Lod: cullingRatio must be finite and non-negative"); }
	const made = MeshLod.create(1, ratios, cullingRatio as float64);
	if (!made.ok) { throw new Error("Lod: thresholds must be finite, non-negative and descending"); }
	return made.value;
}

function projectedSize(view: CameraView, world: Mat4, radius: float32, nearPlane: float32): MeshLodProjectedSize {
	const projection = view.basis.makeCameraMatrix(view.eye).inverse() * view.viewProj;
	return {
		localOriginRadius: radius as float64,
		worldScaleX: vec3(world.m11, world.m12, world.m13).length() as float64,
		worldScaleY: vec3(world.m21, world.m22, world.m23).length() as float64,
		worldScaleZ: vec3(world.m31, world.m32, world.m33).length() as float64,
		worldMirrored: world.determinant3x3() < 0.0,
		cameraDistanceFromWorldOrigin: (view.eye - world.position()).length() as float64,
		projectionDiagonalX: projection.m11 as float64,
		projectionDiagonalY: projection.m22 as float64,
		nearPlane: nearPlane as float64,
		meshLodScale: 1.0,
	};
}

export function Lod(props: LodProps): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		const scope = requireScene("Lod");
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
			createRenderEffect<[float32[], float32, float32, int32 | null]>(
				(prev: [float32[], float32, float32, int32 | null] | null): [float32[], float32, float32, int32 | null] => [
					props.thresholds(),
					props.cullingRatio === null ? 0.0 : (props.cullingRatio as () => float32)(),
					props.radius(),
					props.forcedLevel === null ? null : (props.forcedLevel as () => int32 | null)(),
				],
				(value: [float32[], float32, float32, int32 | null], prev: [float32[], float32, float32, int32 | null] | null): Cleanup | null => {
					if (!Number.isFinite(value[2]) || value[2] < 0.0) { throw new Error("Lod: radius must be finite and non-negative"); }
					if (value[3] !== null && (value[3] as int32) < 0) { throw new Error("Lod: forcedLevel must be non-negative"); }
					lod = configOf(value[0], value[1]);
					radius = value[2];
					forced = value[3] === null ? -1 : value[3] as int32;
					state.invalidate();
					return null;
				},
			);
			const show = (level: NodeId3D, shown: boolean): void => {
				if (scene.nodes[level.index].isVisible() !== shown) { setVisible(scene, level, shown); }
			};
			onBeforeRefresh(state, (view: CameraView): void => {
				const count = scene.nodes[node.index].children.length as int32;
				if (count === 0) { return; }
				const world = worldOf(scene, node);
				const camera = viewCamera(state.handle);
				if (!world.ok || !camera.ok) { return; }
				const ratio = projectedSize(view, world.value, radius, camera.value.nearPlane).referenceScreenRatioHeuristic();
				if (!ratio.ok) { throw new Error("Lod: no projected size: " + ratio.error.toString()); }
				lod.lodCount = count;
				const selected = lod.select(ratio.value, forced);
				if (!selected.ok) { throw new Error("Lod: MeshLod.select failed: " + selected.error.toString()); }
				for (let i = 0; i < count; i++) {
					show(scene.nodeIdAt(scene.nodes[node.index].children[i]), !selected.value.culled && i === selected.value.lod);
				}
			});
			mountNodeChildren(scope, node, props, host, parent, before);
		});
	};
}
