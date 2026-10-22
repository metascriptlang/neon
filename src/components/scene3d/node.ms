import { Accessor, untrack } from "../../core/signal";
import { createRenderEffect } from "../../core/effect";
import { Cleanup } from "../../core/types";
import { onCleanup } from "../../core/cleanup";
import { Host, HostNode, NeonNode } from "../../render/hostTypes";
import {
	Scene3D as VoidScene3D, NodeId3D, Transform3D, NO_NODE_3D, addGroup, attach, insertBefore, setVisible,
} from "../../../../void/src/void3d/scene";
import { NodeProps, SceneState, SceneNode3D, mountOwned, requireScene, bindNode, placeNodeChildren, freeChildren } from "./core";

export interface NodeElementProps extends NodeProps {
	id: Accessor<NodeId3D>;
}

// Void exports no detach, so a node that came detached goes back under one hidden, detached group per scene.
function limboOf(state: SceneState): NodeId3D {
	const scene = state.handle.scene;
	const held = state.limbo;
	if (held !== null && scene.isLive(held as NodeId3D)) { return held as NodeId3D; }
	const limbo = addGroup(scene, null, Transform3D.identity());
	setVisible(scene, limbo, false);
	state.limbo = limbo;
	return limbo;
}

function nextSiblingOf(scene: VoidScene3D, row: int32, up: int32): NodeId3D | null {
	const kids = scene.nodes[up].children;
	for (let i = 0; i < kids.length - 1; i++) {
		if (kids[i] == row) { return scene.nodeIdAt(kids[i + 1]); }
	}
	return null;
}

function heldUnder(scene: VoidScene3D, row: int32, ancestor: int32): boolean {
	for (let at = row; at != NO_NODE_3D; at = scene.nodes[at].parent) {
		if (at == ancestor) { return true; }
	}
	return false;
}

// R3F <primitive object>: places a node the app made, and gives it back where it was without freeing it.
export function Node(props: NodeElementProps): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		const scope = requireScene("Node");
		mountOwned((): void => {
			const state = scope.state;
			const scene = state.handle.scene;
			const node = untrack(() => props.id());
			if (!scene.isLive(node)) { throw new Error("Node: id names no live node of this Scene3D"); }
			if (node.index == scene.root) { throw new Error("Node: the scene root cannot be placed under another node"); }
			const up = scene.nodes[node.index].parent;
			const origin: NodeId3D | null = up == NO_NODE_3D ? null : scene.nodeIdAt(up);
			const after: NodeId3D | null = up == NO_NODE_3D ? null : nextSiblingOf(scene, node.index, up);
			const wrapper = new SceneNode3D(node);
			const giveBack = (): void => {
				if (wrapper.returned) { return; }
				freeChildren(scene, wrapper);
				wrapper.returned = true;
				if (!scene.isLive(node)) { return; }
				const home = origin;
				if (home !== null && scene.isLive(home) && !heldUnder(scene, home.index, node.index)) {
					const next = after;
					if (next !== null && scene.isLive(next) && scene.nodes[next.index].parent == home.index) {
						insertBefore(scene, home, node, next);
					} else {
						attach(scene, home, node);
					}
				} else {
					attach(scene, limboOf(state), node);
				}
				state.invalidate();
			};
			wrapper.returnNode = giveBack;
			onCleanup(giveBack);
			createRenderEffect<NodeId3D>(
				(prev: NodeId3D | null): NodeId3D => props.id(),
				(value: NodeId3D, prev: NodeId3D | null): Cleanup | null => {
					if (value !== node) { throw new Error("Node: id cannot change; key the Node to place another node"); }
					return null;
				},
			);
			bindNode(state, node, props, scene.nodes[node.index].local);
			placeNodeChildren(scope, wrapper, props, host, parent, before);
		});
	};
}
