import { Accessor, untrack } from "../../core/signal";
import { createRenderEffect } from "../../core/effect";
import { Cleanup } from "../../core/types";
import { onCleanup } from "../../core/cleanup";
import { Host, HostNode, NeonNode } from "../../render/hostTypes";
import { MeshData } from "../../../../void/src/void3d/meshData";
import { MeshId, MaterialId, addMeshData, releaseMesh } from "../../../../void/src/void3d/draw";
import { NodeId3D, addMeshNode, setMeshOf, setMaterialOf, remove } from "../../../../void/src/void3d/scene";
import { NodeProps, mountOwned, requireScene, localOf, bindNode, mountNodeChildren, defaultMaterialOf } from "./core";

export interface MeshProps extends NodeProps {
	geometry?: Accessor<MeshData> | null;
	mesh?: Accessor<MeshId> | null;
	material?: Accessor<MaterialId> | null;
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
				const initialMaterial = material;
				if (initialMaterial === null) { throw new Error("Mesh: addMeshNode did not select a material"); }
				let selected = initialMaterial;
				createRenderEffect<MaterialId>(
					(prev: MaterialId | null): MaterialId => (props.material as () => MaterialId)(),
					(value: MaterialId, prev: MaterialId | null): Cleanup | null => {
						if (value !== selected) {
							const changed = setMaterialOf(scene, mounted, value);
							if (!changed.ok) {
								throw new Error("Mesh: setMaterialOf failed: " + changed.error.toString());
							}
							selected = value;
							scope.state.invalidate();
						}
						return null;
					},
				);
			}
			bindNode(scope.state, mounted, props, local);
			mountNodeChildren(scope, mounted, props, host, parent, before);
		});
	};
}
