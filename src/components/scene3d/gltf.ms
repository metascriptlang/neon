import { Accessor } from "../../core/signal";
import { createRenderEffect } from "../../core/effect";
import { Cleanup } from "../../core/types";
import { Host, HostNode, NeonNode } from "../../render/hostTypes";
import { Scene3D as VoidScene3D, NodeId3D, Transform3D, addGroup, remove, insertBefore } from "../../../../void/src/void3d/scene";
import { GltfData } from "../../../../void/src/void3d/gltf";
import { GltfMaterialSetup, addGltfAssets, addGltfNodes, closeGltfAssets } from "../../../../void/src/void3d/gltfScene";
import { NodeProps, mountOwned, requireScene, localOf, bindNode, ownNode, mountNodeChildren } from "./core";

export interface GltfProps extends NodeProps {
	data: Accessor<GltfData>;
	setup: Accessor<GltfMaterialSetup>;
}

function instantiateGltf(
	scene: VoidScene3D, parent: NodeId3D, data: GltfData, setup: GltfMaterialSetup,
): NodeId3D {
	const added = addGltfAssets(scene.context, data, setup);
	if (!added.ok) {
		throw new Error("Gltf: addGltfAssets failed: " + added.error.toString());
	}
	const assets = added.value;
	const staging = addGroup(scene, parent, Transform3D.identity());
	try {
		const mounted = addGltfNodes(scene, staging, data, assets.bindings);
		if (!mounted.ok) {
			throw new Error("Gltf: addGltfNodes failed: " + mounted.error.toString());
		}
		return staging;
	} catch (error) {
		const removed = remove(scene, staging);
		throw error;
	} finally { closeGltfAssets(assets); }
}

export function Gltf(props: GltfProps): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		const scope = requireScene("Gltf");
		mountOwned((): void => {
			const scene = scope.state.handle.scene;
			const local = localOf(props);
			const wrapper = addGroup(scene, scope.parent, local);
			ownNode(scope.state, wrapper);
			bindNode(scope.state, wrapper, props, local);
			let imported: NodeId3D | null = null;
			createRenderEffect<[GltfData, GltfMaterialSetup]>(
				(prev: [GltfData, GltfMaterialSetup] | null): [GltfData, GltfMaterialSetup] => [props.data(), props.setup()],
				(value: [GltfData, GltfMaterialSetup], prev: [GltfData, GltfMaterialSetup] | null): Cleanup | null => {
					const next = instantiateGltf(scene, wrapper, value[0], value[1]);
					const previous = imported;
					if (previous !== null) {
						insertBefore(scene, wrapper, next, previous);
						const removed = remove(scene, previous);
					}
					imported = next;
					scope.state.invalidate();
					return null;
				},
			);
			mountNodeChildren(scope, wrapper, props, host, parent, before);
		});
	};
}
