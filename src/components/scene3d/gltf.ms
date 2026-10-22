import { Accessor, createSignal } from "../../core/signal";
import { createRenderEffect } from "../../core/effect";
import { Cleanup } from "../../core/types";
import { Host, HostNode, NeonNode } from "../../render/hostTypes";
import {
	Scene3D as VoidScene3D, NodeId3D, NO_NODE_ID, Transform3D, addGroup, remove, insertBefore, findByName,
} from "../../../../void/src/void3d/scene";
import { GltfData, GltfDiagnostic, describe, validateGltfGraph } from "../../../../void/src/void3d/gltf";
import {
	GltfAssets, GltfMaterialSetup, GltfSceneError, addGltfAssets, addGltfBoundNodes, closeGltfAssets,
} from "../../../../void/src/void3d/gltfScene";
import { NodeProps, mountOwned, requireScene, localOf, bindNode, ownNode, mountNodeChildren } from "./core";

// The imported subtree of one Gltf; `root` changes on every reload, so a reader inside an effect follows it.
export interface GltfGraph {
	root: Accessor<NodeId3D>;
	find: (name: string) => NodeId3D | null;
}

export interface GltfProps extends NodeProps {
	data: Accessor<GltfData>;
	setup?: Accessor<GltfMaterialSetup> | null;
	assets?: Accessor<GltfAssets> | null;
	graph?: ((graph: GltfGraph) => void) | null;
}

export function gltfData(loaded: Result<GltfData, GltfDiagnostic>): GltfData {
	if (!loaded.ok) { throw new Error("Gltf: " + loaded.error.describe()); }
	return loaded.value;
}

function sceneFailure(call: string, error: GltfSceneError, data: GltfData): Error {
	let detail = error.toString();
	if (error === GltfSceneError.InvalidData) {
		const graph = validateGltfGraph(data);
		if (!graph.ok) { detail = detail + " (" + graph.error.toString() + ")"; }
	}
	return new Error("Gltf: " + call + " failed: " + detail);
}

function mountGraph(scene: VoidScene3D, parent: NodeId3D, data: GltfData, assets: GltfAssets): NodeId3D {
	const staging = addGroup(scene, parent, Transform3D.identity());
	const mounted = addGltfBoundNodes(scene, staging, data, assets.bindings);
	if (!mounted.ok) {
		const removed = remove(scene, staging);
		throw sceneFailure("addGltfBoundNodes", mounted.error, data);
	}
	return staging;
}

function ownedGraph(scene: VoidScene3D, parent: NodeId3D, data: GltfData, setup: GltfMaterialSetup): NodeId3D {
	const added = addGltfAssets(scene.context, data, setup);
	if (!added.ok) { throw sceneFailure("addGltfAssets", added.error, data); }
	try {
		return mountGraph(scene, parent, data, added.value);
	} finally { closeGltfAssets(added.value); }
}

function borrowedGraph(scene: VoidScene3D, parent: NodeId3D, data: GltfData, assets: GltfAssets): NodeId3D {
	if (assets.closed) { throw new Error("Gltf: borrowed assets were closed by their owner"); }
	if (assets.context !== scene.context) { throw new Error("Gltf: borrowed assets belong to another Scene3D context"); }
	return mountGraph(scene, parent, data, assets);
}

export function Gltf(props: GltfProps): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		const scope = requireScene("Gltf");
		if ((props.setup === null) === (props.assets === null)) {
			throw new Error("Gltf: provide exactly one setup (Gltf uploads its own assets) or assets (borrowed GltfAssets)");
		}
		mountOwned((): void => {
			const scene = scope.state.handle.scene;
			const local = localOf(props);
			const wrapper = addGroup(scene, scope.parent, local);
			ownNode(scope.state, wrapper);
			bindNode(scope.state, wrapper, props, local);
			const [root, setRoot] = createSignal<NodeId3D>(NO_NODE_ID, { ownedWrite: true });
			let imported: NodeId3D | null = null;
			const replace = (next: NodeId3D): void => {
				const previous = imported;
				if (previous !== null) {
					insertBefore(scene, wrapper, next, previous);
					const removed = remove(scene, previous);
				}
				imported = next;
				setRoot(next);
				scope.state.invalidate();
			};
			if (props.assets !== null) {
				const assets = props.assets as () => GltfAssets;
				createRenderEffect<[GltfData, GltfAssets]>(
					(prev: [GltfData, GltfAssets] | null): [GltfData, GltfAssets] => [props.data(), assets()],
					(value: [GltfData, GltfAssets], prev: [GltfData, GltfAssets] | null): Cleanup | null => {
						replace(borrowedGraph(scene, wrapper, value[0], value[1]));
						return null;
					},
				);
			} else {
				const setup = props.setup as () => GltfMaterialSetup;
				createRenderEffect<[GltfData, GltfMaterialSetup]>(
					(prev: [GltfData, GltfMaterialSetup] | null): [GltfData, GltfMaterialSetup] => [props.data(), setup()],
					(value: [GltfData, GltfMaterialSetup], prev: [GltfData, GltfMaterialSetup] | null): Cleanup | null => {
						replace(ownedGraph(scene, wrapper, value[0], value[1]));
						return null;
					},
				);
			}
			if (props.graph !== null) {
				(props.graph as (graph: GltfGraph) => void)({
					root: root,
					find: (name: string): NodeId3D | null => {
						const from = root();
						if (!scene.isLive(from)) { return null; }
						const found = scene.findByName(from, name);
						return found.ok ? found.value : null;
					},
				});
			}
			mountNodeChildren(scope, wrapper, props, host, parent, before);
		});
	};
}
