import { Accessor, untrack } from "../../core/signal";
import { createRenderEffect } from "../../core/effect";
import { Cleanup } from "../../core/types";
import { onCleanup } from "../../core/cleanup";
import { Host, HostNode, NeonNode } from "../../render/hostTypes";
import { Mat4, identity } from "../../../../void/src/math/math3d";
import { makeStreamBuffer, updateBuffer, destroyBuffer } from "../../../../void/src/void3d/gpu3d";
import { contextGeneration } from "../../../../void/src/gpu/door";
import { DrawContext, GpuMesh, MeshId, MaterialId, addMesh, billboards, releaseMesh } from "../../../../void/src/void3d/draw";
import { BillboardInstance, BILLBOARD_INSTANCE_STRIDE, pushTo } from "../../../../void/src/void3d/billboard";
import { addMeshNode, setMeshOf, setMaterialOf, worldOf } from "../../../../void/src/void3d/scene";
import { CameraView } from "../../../../void/src/void3d/camera";
import { NodeProps, mountOwned, requireScene, localOf, bindNode, ownNode, mountNodeChildren, onBeforeRefresh } from "./core";

export interface BillboardsProps extends NodeProps {
	instances: Accessor<BillboardInstance[]>;
	material: Accessor<MaterialId>;
}

function instanceMesh(context: DrawContext, buffer: uint32, count: int32, tag: string): MeshId {
	const added = addMesh(context, GpuMesh.billboards(buffer, count));
	if (!added.ok) { throw new Error(tag + ": addMesh failed: " + added.error.toString()); }
	return added.value;
}

export function Billboards(props: BillboardsProps): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		const scope = requireScene("Billboards");
		mountOwned((): void => {
			const state = scope.state;
			const scene = state.handle.scene;
			const context = state.handle.context;
			const local = localOf(props);
			let material = untrack(() => props.material());
			const placeholder = instanceMesh(context, 0, 0, "Billboards");
			const added = addMeshNode(scene, scope.parent, local, placeholder, material);
			const released = releaseMesh(context, placeholder);
			if (!added.ok) { throw new Error("Billboards: addMeshNode failed: " + added.error.toString()); }
			if (!released.ok) { throw new Error("Billboards: releaseMesh failed: " + released.error.toString()); }
			const node = added.value;
			ownNode(state, node);
			let buffer: uint32 = 0;
			let capacity: int32 = 0;
			let generation: int32 = 0;
			let shownBuffer: uint32 = 0;
			let shownCount: int32 = 0;
			let instances: BillboardInstance[] = [];
			let dirty = true;
			let placed: Mat4 = identity();
			onCleanup((): void => {
				if (buffer !== 0 && generation === contextGeneration()) { destroyBuffer(buffer); }
				buffer = 0;
				capacity = 0;
			});
			createRenderEffect<BillboardInstance[]>(
				(prev: BillboardInstance[] | null): BillboardInstance[] => props.instances(),
				(value: BillboardInstance[], prev: BillboardInstance[] | null): Cleanup | null => {
					instances = value;
					dirty = true;
					state.invalidate();
					return null;
				},
			);
			createRenderEffect<MaterialId>(
				(prev: MaterialId | null): MaterialId => props.material(),
				(value: MaterialId, prev: MaterialId | null): Cleanup | null => {
					if (value !== material) {
						const changed = setMaterialOf(scene, node, value);
						if (!changed.ok) { throw new Error("Billboards: setMaterialOf failed: " + changed.error.toString()); }
						material = value;
						state.invalidate();
					}
					return null;
				},
			);
			onBeforeRefresh(state, (view: CameraView): void => {
				const world = worldOf(scene, node);
				if (!world.ok) { return; }
				const lost = buffer !== 0 && generation !== contextGeneration();
				if (!dirty && !lost && world.value === placed) { return; }
				if (lost) {
					buffer = 0;
					capacity = 0;
				}
				const count = instances.length as int32;
				if (count > capacity) {
					const grown = Math.max(count, capacity * 2);
					const made = makeStreamBuffer(grown * BILLBOARD_INSTANCE_STRIDE);
					if (made === 0) { throw new Error("Billboards: the GPU refused a buffer for " + grown.toString() + " instances"); }
					if (buffer !== 0) { destroyBuffer(buffer); }
					buffer = made;
					capacity = grown;
					generation = contextGeneration();
				}
				if (count > 0) {
					let packed: Vec<float32> = [];
					for (const instance of instances) {
						const placedInstance: BillboardInstance = { ...instance, position: instance.position * world.value };
						placedInstance.pushTo(packed);
					}
					if (!updateBuffer(buffer, packed)) { throw new Error("Billboards: updateBuffer refused " + count.toString() + " instances"); }
				}
				if (buffer !== shownBuffer || count !== shownCount) {
					const mesh = instanceMesh(context, buffer, count, "Billboards");
					const swapped = setMeshOf(scene, node, mesh);
					const releasedMesh = releaseMesh(context, mesh);
					if (!swapped.ok) { throw new Error("Billboards: setMeshOf failed: " + swapped.error.toString()); }
					if (!releasedMesh.ok) { throw new Error("Billboards: releaseMesh failed: " + releasedMesh.error.toString()); }
					shownBuffer = buffer;
					shownCount = count;
				}
				dirty = false;
				placed = world.value;
			});
			bindNode(state, node, props, local);
			mountNodeChildren(scope, node, props, host, parent, before);
		});
	};
}
