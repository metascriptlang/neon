import { Accessor } from "../../core/signal";
import { createRenderEffect } from "../../core/effect";
import { Cleanup } from "../../core/types";
import { Host, HostNode, NeonNode } from "../../render/hostTypes";
import { CameraView } from "../../../../void/src/void3d/camera";
import { Bounds3D, empty, addBounds, isEmpty, size, center, transformed } from "../../../../void/src/void3d/bounds";
import { NodeId3D, NO_NODE_ID, Transform3D, addGroup, setLocal, worldOf } from "../../../../void/src/void3d/scene";
import { Vec3, vec3 } from "../../../../void/src/math/math3d";
import { Group } from "./group";
import { NodeProps, mountOwned, requireScene, localOf, bindNode, ownNode, mountNodeChildren, onBeforeRefresh } from "./core";

// drei's OnCenterCallbackProps without `parent`, `container` and `boundingSphere`; `ref` gives the container.
export interface Centered {
	width: float32;
	height: float32;
	depth: float32;
	boundingBox: Bounds3D;
	center: Vec3;
	verticalAlignment: float32;
	horizontalAlignment: float32;
	depthAlignment: float32;
}

export interface CenterProps extends NodeProps {
	top?: Accessor<boolean> | null;
	right?: Accessor<boolean> | null;
	bottom?: Accessor<boolean> | null;
	left?: Accessor<boolean> | null;
	front?: Accessor<boolean> | null;
	back?: Accessor<boolean> | null;
	disable?: Accessor<boolean> | null;
	disableX?: Accessor<boolean> | null;
	disableY?: Accessor<boolean> | null;
	disableZ?: Accessor<boolean> | null;
	cacheKey?: Accessor<int32> | null;
	onCentered?: ((measured: Centered) => void) | null;
}

const TOP: int32 = 1;
const RIGHT: int32 = 2;
const BOTTOM: int32 = 4;
const LEFT: int32 = 8;
const FRONT: int32 = 16;
const BACK: int32 = 32;
const DISABLE: int32 = 64;
const DISABLE_X: int32 = 128;
const DISABLE_Y: int32 = 256;
const DISABLE_Z: int32 = 512;

function bit(read: Accessor<boolean> | null, flag: int32): int32 {
	return read !== null && (read as () => boolean)() ? flag : 0;
}

function axisOffset(disabled: boolean, center: float32, alignment: float32): float32 {
	return disabled ? 0.0 : -center + alignment;
}

export function Center(props: CenterProps): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		const scope = requireScene("Center");
		mountOwned((): void => {
			const state = scope.state;
			const scene = state.handle.scene;
			const context = state.handle.context;
			const local = localOf(props);
			const node = addGroup(scene, scope.parent, local);
			ownNode(state, node);
			bindNode(state, node, props, local);
			let inner: NodeId3D = NO_NODE_ID;
			let flags: int32 = 0;
			let measured = false;
			// The scene's mesh count when a walk found nothing under the content: with the same count there is nothing new to find.
			let emptyAt: int32 = -1;
			createRenderEffect<[int32, int32]>(
				(prev: [int32, int32] | null): [int32, int32] => [
					bit(props.top, TOP) | bit(props.right, RIGHT) | bit(props.bottom, BOTTOM) | bit(props.left, LEFT) |
						bit(props.front, FRONT) | bit(props.back, BACK) | bit(props.disable, DISABLE) |
						bit(props.disableX, DISABLE_X) | bit(props.disableY, DISABLE_Y) | bit(props.disableZ, DISABLE_Z),
					props.cacheKey === null ? 0 : (props.cacheKey as () => int32)(),
				],
				(value: [int32, int32], prev: [int32, int32] | null): Cleanup | null => {
					flags = value[0];
					measured = false;
					emptyAt = -1;
					state.invalidate();
					return null;
				},
			);
			onBeforeRefresh(state, (view: CameraView): void => {
				if (measured || !scene.isLive(inner)) { return; }
				const meshCount = scene.meshes.length as int32;
				if (meshCount === emptyAt) { return; }
				const innerWorld = worldOf(scene, inner);
				if (!innerWorld.ok) { throw new Error("Center: its content has no world pose: " + innerWorld.error.toString()); }
				const toInner = innerWorld.value.inverse();
				const meshes = scene.getMeshes(inner);
				if (!meshes.ok) { throw new Error("Center: getMeshes failed: " + meshes.error.toString()); }
				let box: Bounds3D = Bounds3D.empty();
				for (const mesh of meshes.value) {
					const world = worldOf(scene, mesh);
					if (!world.ok) { throw new Error("Center: a mesh has no world pose: " + world.error.toString()); }
					const mine = context.meshData[scene.meshes[scene.nodes[mesh.index].payload].mesh.index].bounds;
					addBounds(box, mine.transformed(world.value * toInner));
				}
				if (box.isEmpty()) {
					emptyAt = meshCount;
					return;
				}
				const extent = box.size();
				const middle = box.center();
				const all = (flags & DISABLE) !== 0;
				const vertical: float32 = (flags & TOP) !== 0 ? extent.y / 2.0 : (flags & BOTTOM) !== 0 ? -extent.y / 2.0 : 0.0;
				const horizontal: float32 = (flags & LEFT) !== 0 ? -extent.x / 2.0 : (flags & RIGHT) !== 0 ? extent.x / 2.0 : 0.0;
				const depth: float32 = (flags & FRONT) !== 0 ? extent.z / 2.0 : (flags & BACK) !== 0 ? -extent.z / 2.0 : 0.0;
				const offset = vec3(
					axisOffset(all || (flags & DISABLE_X) !== 0, middle.x, horizontal),
					axisOffset(all || (flags & DISABLE_Y) !== 0, middle.y, vertical),
					axisOffset(all || (flags & DISABLE_Z) !== 0, middle.z, depth),
				);
				setLocal(scene, inner, {
					position: offset, rotation: Transform3D.identity().rotation, scale: vec3(1.0, 1.0, 1.0),
				});
				measured = true;
				const notify = props.onCentered;
				if (notify !== null) {
					(notify as (measured: Centered) => void)({
						width: extent.x, height: extent.y, depth: extent.z, boundingBox: box, center: middle,
						verticalAlignment: vertical, horizontalAlignment: horizontal, depthAlignment: depth,
					});
				}
			});
			const content = Group({ children: props.children, ref: (id: NodeId3D): void => { inner = id; } });
			mountNodeChildren(scope, node, { ref: props.ref, children: content }, host, parent, before);
		});
	};
}
