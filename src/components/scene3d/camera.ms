import { Accessor, untrack } from "../../core/signal";
import { createRenderEffect } from "../../core/effect";
import { Cleanup } from "../../core/types";
import { onCleanup } from "../../core/cleanup";
import { Host, HostNode, NeonNode } from "../../render/hostTypes";
import { Vec3, vec3, eulerQuat } from "../../../../void/src/math/math3d";
import { Transform3D, addCameraNode, setCameraOf, setActiveCamera, setLocal, setCameraLayers } from "../../../../void/src/void3d/scene";
import { Camera3D as VoidCamera3D, CameraProjection, ProjectionKind } from "../../../../void/src/void3d/camera";
import { SceneState, CameraEntry, mountOwned, requireScene, ownNode } from "./core";

export interface Camera3DProps {
	position?: Accessor<Vec3> | null;
	yaw?: Accessor<float32> | null;
	pitch?: Accessor<float32> | null;
	nearPlane?: Accessor<float32> | null;
	farPlane?: Accessor<float32> | null;
	projection?: Accessor<CameraProjection> | null;
	active?: Accessor<boolean> | null;
	layers?: Accessor<uint32> | null;
}

function cameraOf(props: Camera3DProps): VoidCamera3D {
	const projection: CameraProjection = props.projection === null ? {
		kind: ProjectionKind.Perspective, fovY: 1.0471975511965976,
	} : (props.projection as () => CameraProjection)();
	return {
		position: props.position === null ? vec3(0.0, 0.0, 0.0) : (props.position as () => Vec3)(),
		yaw: props.yaw === null ? 0.0 : (props.yaw as () => float32)(),
		pitch: props.pitch === null ? 0.0 : (props.pitch as () => float32)(),
		nearPlane: props.nearPlane === null ? 0.1 : (props.nearPlane as () => float32)(),
		farPlane: props.farPlane === null ? 1000.0 : (props.farPlane as () => float32)(),
		projection: projection,
	};
}

function cameraLocal(camera: VoidCamera3D): Transform3D {
	return {
		position: camera.position, rotation: eulerQuat(-camera.pitch, camera.yaw, 0.0),
		scale: vec3(1.0, 1.0, 1.0),
	};
}

function selectCamera(state: SceneState): void {
	const scene = state.handle.scene;
	if (scene.closed) { state.handle.camera = null; return; }
	for (let i = state.cameras.length - 1; i >= 0; i--) {
		const entry = state.cameras[i];
		if (entry.active && scene.isLive(entry.node)) {
			setActiveCamera(scene, entry.node);
			state.handle.camera = entry.camera;
			return;
		}
	}
	setActiveCamera(scene, null);
	state.handle.camera = null;
}

export function Camera3D(props: Camera3DProps): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		const scope = requireScene("Camera3D");
		mountOwned((): void => {
			const state = scope.state;
			const scene = state.handle.scene;
			const initial = untrack(() => cameraOf(props));
			let local = cameraLocal(initial);
			const node = addCameraNode(scene, scope.parent, local, initial);
			ownNode(scope.state, node);
			if (props.layers !== null) {
				const layers = props.layers as () => uint32;
				createRenderEffect<uint32>(
					(prev: uint32 | null): uint32 => layers(),
					(value: uint32, prev: uint32 | null): Cleanup | null => { setCameraLayers(scene, node, value); state.invalidate(); return null; },
				);
			}
			let entry: CameraEntry | null = null;
			onCleanup((): void => {
				const mounted = entry;
				if (mounted === null) { return; }
				for (let i = 0; i < state.cameras.length; i++) {
					if (state.cameras[i] !== mounted) { continue; }
					for (let j = i; j < state.cameras.length - 1; j++) { state.cameras[j] = state.cameras[j + 1]; }
					state.cameras.pop();
					break;
				}
				entry = null;
				selectCamera(state);
				state.invalidate();
			});
			createRenderEffect<[VoidCamera3D, boolean]>(
				(prev: [VoidCamera3D, boolean] | null): [VoidCamera3D, boolean] => [
					cameraOf(props), props.active === null ? false : (props.active as () => boolean)(),
				],
				(value: [VoidCamera3D, boolean], prev: [VoidCamera3D, boolean] | null): Cleanup | null => {
					const camera = value[0];
					const active = value[1];
					const nextLocal = cameraLocal(camera);
					if (nextLocal !== local) { setLocal(scene, node, nextLocal); local = nextLocal; }
					setCameraOf(scene, node, camera);
					const mounted = entry;
					if (mounted === null) {
						const added: CameraEntry = { node: node, camera: camera, active: active };
						entry = added;
						state.cameras.push(added);
					} else {
						mounted.camera = camera;
						mounted.active = active;
					}
					selectCamera(state);
					state.invalidate();
					return null;
				},
			);

		});
	};
}
