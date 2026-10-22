import { Accessor, untrack } from "../../core/signal";
import { createRenderEffect } from "../../core/effect";
import { Cleanup } from "../../core/types";
import { onCleanup } from "../../core/cleanup";
import { Host, HostNode, NeonNode } from "../../render/hostTypes";
import { MeshData } from "../../../../void/src/void3d/meshData";
import { MeshId, MaterialId, addMeshData, releaseMesh } from "../../../../void/src/void3d/draw";
import { addMaterial, reserveUniforms, writeUniforms, releaseUniforms } from "../../../../void/src/void3d/draw";
import { Material, Phase, ShadowCasting, withShadows } from "../../../../void/src/void3d/material";
import { Program, MATERIAL_UNIFORM_SLOT, MATERIAL_UNIFORM_LENGTH } from "../../../../void/src/void3d/gpu3d";
import { RenderState } from "../../../../void/src/gpu/state";
import { NodeId3D, addMeshNode, setMeshOf, setMaterialOf, remove } from "../../../../void/src/void3d/scene";
import { NodeProps, SceneState, SharedGeometry, mountOwned, requireScene, localOf, bindNode, mountNodeChildren, defaultMaterialOf } from "./core";

export interface MeshProps extends NodeProps {
	geometry?: Accessor<MeshData> | null;
	mesh?: Accessor<MeshId> | null;
	material?: Accessor<MaterialId> | null;
	castShadow?: Accessor<boolean> | null;
	receiveShadow?: Accessor<boolean> | null;
}

function shadowMaterialOf(state: SceneState, cast: boolean, receive: boolean): MaterialId {
	if (!cast && !receive) { return defaultMaterialOf(state); }
	const slot = (cast ? 2 : 0) + (receive ? 1 : 0);
	const existing = state.shadowMaterials[slot];
	if (existing !== null) { return existing; }
	const context = state.handle.context;
	const reserved = reserveUniforms(context, MATERIAL_UNIFORM_SLOT, MATERIAL_UNIFORM_LENGTH);
	if (!reserved.ok) { throw new Error("Mesh: reserveUniforms failed: " + reserved.error.toString()); }
	const block = reserved.value;
	try {
		const written = writeUniforms(context, block, [0.0, 0.0, 0.0, 0.0]);
		if (!written.ok) { throw new Error("Mesh: writeUniforms failed: " + written.error.toString()); }
		const plain = Material.plain(Program.Lit, RenderState.defaults(), Phase.Opaque);
		const added = addMaterial(context, {
			...plain.withShadows(cast ? ShadowCasting.On : ShadowCasting.Off, receive),
			uniforms: block,
		});
		if (!added.ok) { throw new Error("Mesh: addMaterial failed: " + added.error.toString()); }
		state.shadowMaterials[slot] = added.value;
		return added.value;
	} catch (error) {
		const released = releaseUniforms(context, block);
		if (!released.ok) { throw new Error("Mesh: releaseUniforms failed: " + released.error.toString()); }
		throw error;
	}
}

function acquireGeometry(state: SceneState, data: MeshData): SharedGeometry {
	const context = state.handle.context;
	for (const entry of state.geometries) {
		const at = entry.mesh.index;
		if (context.meshData[at].vertices.length === data.vertices.length
			&& context.meshData[at].bounds == data.bounds && context.meshData[at] == data) {
			entry.users += 1;
			return entry;
		}
	}
	const uploaded = addMeshData(context, data);
	if (!uploaded.ok) { throw new Error("Mesh: addMeshData failed: " + uploaded.error.toString()); }
	const entry: SharedGeometry = { mesh: uploaded.value, users: 1 };
	state.geometries.push(entry);
	return entry;
}

function releaseGeometry(state: SceneState, entry: SharedGeometry): void {
	entry.users -= 1;
	if (entry.users > 0) { return; }
	const last = state.geometries.length - 1;
	for (let i = 0; i <= last; i++) {
		if (state.geometries[i] === entry) {
			state.geometries[i] = state.geometries[last];
			state.geometries.pop();
			break;
		}
	}
	const released = releaseMesh(state.handle.context, entry.mesh);
	if (!released.ok) { throw new Error("Mesh: releaseMesh failed: " + released.error.toString()); }
}

export function Mesh(props: MeshProps): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		const scope = requireScene("Mesh");
		if ((props.geometry === null) === (props.mesh === null)) { throw new Error("Mesh: provide exactly one geometry (MeshData) or mesh (MeshId)"); }
		const shadowFlags = props.castShadow !== null || props.receiveShadow !== null;
		if (shadowFlags && props.material !== null) {
			throw new Error("Mesh: castShadow and receiveShadow need the default material; an app material sets its own with Material.withShadows until Void has per-node shadow flags");
		}
		mountOwned((): void => {
			const scene = scope.state.handle.scene;
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
				let held: SharedGeometry | null = null;
				onCleanup((): void => {
					const last = held;
					held = null;
					if (last !== null) { releaseGeometry(scope.state, last); }
				});
				createRenderEffect<[MeshData, MaterialId | null]>(
					(prev: [MeshData, MaterialId | null] | null): [MeshData, MaterialId | null] => [
						(props.geometry as () => MeshData)(),
						props.material === null ? null : untrack(() => (props.material as () => MaterialId)()),
					],
					(value: [MeshData, MaterialId | null], prev: [MeshData, MaterialId | null] | null): Cleanup | null => {
						const next = acquireGeometry(scope.state, value[0]);
						try {
							bindMesh(next.mesh, value[1]);
						} catch (error) {
							releaseGeometry(scope.state, next);
							throw error;
						}
						const previous = held;
						held = next;
						if (previous !== null) { releaseGeometry(scope.state, previous); }
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
			if (shadowFlags) {
				let shadowed: MaterialId | null = null;
				createRenderEffect<[boolean, boolean]>(
					(prev: [boolean, boolean] | null): [boolean, boolean] => [
						props.castShadow === null ? false : (props.castShadow as () => boolean)(),
						props.receiveShadow === null ? false : (props.receiveShadow as () => boolean)(),
					],
					(value: [boolean, boolean], prev: [boolean, boolean] | null): Cleanup | null => {
						const next = shadowMaterialOf(scope.state, value[0], value[1]);
						if (shadowed === null || next !== shadowed) {
							const changed = setMaterialOf(scene, mounted, next);
							if (!changed.ok) { throw new Error("Mesh: setMaterialOf failed: " + changed.error.toString()); }
							shadowed = next;
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
