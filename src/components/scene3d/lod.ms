import { Accessor } from "../../core/signal";
import { createRenderEffect } from "../../core/effect";
import { Cleanup } from "../../core/types";
import { Host, HostNode, NeonNode } from "../../render/hostTypes";
import { CameraView } from "../../../../void/src/void3d/camera";
import { NodeId3D, addGroup, setVisible, worldOf } from "../../../../void/src/void3d/scene";
import { position, length } from "../../../../void/src/math/math3d";
import { NodeProps, mountOwned, requireScene, localOf, bindNode, ownNode, mountNodeChildren, onBeforeRefresh } from "./core";

export interface LodProps extends NodeProps {
	distances: Accessor<float32[]>;
	hysteresis?: Accessor<float32> | null;
}

function validDistances(distances: float32[]): boolean {
	for (let i = 0; i < distances.length; i++) {
		if (!Number.isFinite(distances[i]) || distances[i] < 0.0) { return false; }
		if (i > 0 && distances[i] < distances[i - 1]) { return false; }
	}
	return true;
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
			let distances: float32[] = [];
			let hysteresis: float32 = 0.0;
			createRenderEffect<[float32[], float32]>(
				(prev: [float32[], float32] | null): [float32[], float32] => [
					props.distances(),
					props.hysteresis === null ? 0.0 : (props.hysteresis as () => float32)(),
				],
				(value: [float32[], float32], prev: [float32[], float32] | null): Cleanup | null => {
					if (!validDistances(value[0])) { throw new Error("Lod: distances must be finite, non-negative and ascending"); }
					if (!Number.isFinite(value[1]) || value[1] < 0.0 || value[1] >= 1.0) { throw new Error("Lod: hysteresis must be in [0,1)"); }
					distances = value[0];
					hysteresis = value[1];
					state.invalidate();
					return null;
				},
			);
			const show = (level: NodeId3D, shown: boolean): void => {
				if (scene.nodes[level.index].isVisible() !== shown) { setVisible(scene, level, shown); }
			};
			onBeforeRefresh(state, (view: CameraView): void => {
				const world = worldOf(scene, node);
				if (!world.ok) { return; }
				const distance = (view.eye - world.value.position()).length();
				const count = scene.nodes[node.index].children.length as int32;
				const levels = Math.min(count, distances.length as int32);
				let selected: int32 = 0;
				for (let i = 1; i < levels; i++) {
					const level = scene.nodeIdAt(scene.nodes[node.index].children[i]);
					let threshold = distances[i];
					if (scene.nodes[level.index].isVisible()) { threshold -= threshold * hysteresis; }
					if (distance < threshold) { break; }
					selected = i;
				}
				for (let i = 0; i < count; i++) {
					show(scene.nodeIdAt(scene.nodes[node.index].children[i]), i === selected && i < levels);
				}
			});
			mountNodeChildren(scope, node, props, host, parent, before);
		});
	};
}
