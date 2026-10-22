import { Accessor, accessor } from "../../core/signal";
import { createRenderEffect } from "../../core/effect";
import { Cleanup } from "../../core/types";
import { onCleanup } from "../../core/cleanup";
import { useContext } from "../../render/context";
import { VoidSpace, getVoidScopeContext, getVoidAreaContext, useVoidSpace } from "../../render/voidScope";
import { layerAnchor } from "../../render/voidLayer";
import { AreaLayer } from "../../render/voidAreaHandle";
import { Host, HostNode, NeonNode, VoidArea } from "../../render/hostTypes";
import { Vec3 } from "../../../../void/src/math/math3d";
import { VERTEX_UNIFORM_LENGTH, LIGHT_UNIFORM_LENGTH } from "../../../../void/src/void3d/gpu3d";
import { DrawContext, DrawItem, releaseMaterial, closeContext, buryDoomed } from "../../../../void/src/void3d/draw";
import {
	ForwardRenderer, create, prepareFrame, drawOverScreen, closeForward, setOutlineBlend, setOutlineSettings,
} from "../../../../void/src/void3d/forwardRenderer";
import { ForwardOutlineSettings, defaults, valid, FORWARD_OUTLINE_BLOCKS } from "../../../../void/src/void3d/forwardOutline";
import { fits } from "../../../../void/src/void3d/uniformPool";
import { contextGeneration } from "../../../../void/src/gpu/door";
import { Scene3D as VoidScene3D, closeScene, setAmbient, refresh, collectLights } from "../../../../void/src/void3d/scene";
import { resolve, writeCameraBlock } from "../../../../void/src/void3d/camera";
import { Scene3DHandle, SceneState, NodeScope, sceneScope, SCENE_UNIFORM_CAPACITY, mountOwned, viewCamera } from "./core";

export interface Scene3DProps {
	ambient?: Accessor<Vec3> | null;
	outlineBlend?: Accessor<float32> | null;
	outlineSettings?: Accessor<ForwardOutlineSettings> | null;
	ref?: ((handle: Scene3DHandle) => void) | null;
	children?: NeonNode | null;
}

export function Scene3D(props: Scene3DProps): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		if (useVoidSpace() !== VoidSpace.Area) { throw new Error("Scene3D: mount directly within Void, outside another Scene3D"); }
		mountOwned((): void => {
			const opened = useContext(getVoidAreaContext());
			if (opened === null) { throw new Error("Scene3D: the Void area did not provide its frame"); }
			const anchor = layerAnchor(opened as VoidArea, host, parent, before);
			const area = (opened as VoidArea).hub;
			const context = DrawContext.withUniformCapacity(SCENE_UNIFORM_CAPACITY);
			const scene = VoidScene3D.create(context);
			const handle: Scene3DHandle = { context: context, scene: scene, camera: null };
			const state: SceneState = {
				handle: handle, defaultMaterial: null, cameras: [],
				geometries: [],
				invalidate: (): void => { area.handle.requestFrame(); },
			};
			const made = ForwardRenderer.create(context, { x: 0.0, y: 0.0, z: 0.0, w: 0.0 });
			if (!made.ok) {
				closeScene(scene);
				closeContext(context);
				throw new Error("Scene3D: ForwardRenderer.create failed: " + made.error.toString());
			}
			const renderer = made.value;
			let items: Vec<DrawItem> = [];
			let cameraBlock: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
			let lightBlock: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
			let prepared = false;
			const layer: AreaLayer = {
				anchor,
				layout: (pixelWidth: int32, pixelHeight: int32): void => {},
				prepare: (pixelWidth: int32, pixelHeight: int32): void => {
					prepared = false;
					refresh(scene, items);
					const lights = collectLights(scene, lightBlock);
					if (!lights.ok) { throw new Error("Scene3D: collectLights failed: " + lights.error.toString()); }
					const world = viewCamera(handle);
					if (!world.ok) { throw new Error("Scene3D: the active camera has no world pose: " + world.error.toString()); }
					const view = world.value.resolve(pixelWidth, pixelHeight);
					if (!view.ok) { throw new Error("Scene3D: the active camera does not resolve: " + view.error.toString()); }
					view.value.writeCameraBlock(cameraBlock);
					const buried = buryDoomed(context, contextGeneration());
					const frame = prepareFrame(renderer, items, cameraBlock, lightBlock, pixelWidth, pixelHeight);
					if (!frame.ok) { throw new Error("Scene3D: prepareFrame failed: " + frame.error.toString()); }
					prepared = true;
				},
				draw: (): void => {
					if (!prepared) { return; }
					prepared = false;
					drawOverScreen(renderer);
				},
			};
			const unregister = area.addLayer(layer);
			onCleanup((): void => {
				unregister();
				closeForward(renderer);
				state.invalidate();
				handle.camera = null;
				closeScene(scene);
				const material = state.defaultMaterial;
				if (material !== null) {
					const released = releaseMaterial(context, material);
					if (!released.ok) { throw new Error("Scene3D: releaseMaterial failed: " + released.error.toString()); }
					state.defaultMaterial = null;
				}
				closeContext(context);
			});
			if (props.outlineBlend !== null || props.outlineSettings !== null) {
				createRenderEffect<[float32, ForwardOutlineSettings]>(
					(prev: [float32, ForwardOutlineSettings] | null): [float32, ForwardOutlineSettings] => [
						props.outlineBlend === null ? 0.0 : (props.outlineBlend as () => float32)(),
						props.outlineSettings === null ? ForwardOutlineSettings.defaults() : (props.outlineSettings as () => ForwardOutlineSettings)(),
					],
					(value: [float32, ForwardOutlineSettings], prev: [float32, ForwardOutlineSettings] | null): Cleanup | null => {
						const blend = value[0];
						const settings = value[1];
						if (!Number.isFinite(blend) || blend < 0.0 || blend > 1.0) {
							throw new Error("Scene3D: outlineBlend must be finite and in [0,1]");
						}
						if (!settings.valid()) { throw new Error("Scene3D: invalid outlineSettings"); }
						if (blend > 0.0 && renderer.outline === null && !context.uniforms.fits(FORWARD_OUTLINE_BLOCKS).ok) {
							throw new Error("Scene3D: outlineBlend needs additional uniform capacity");
						}
						setOutlineSettings(renderer, settings);
						setOutlineBlend(renderer, blend);
						state.invalidate();
						return null;
					},
				);
			}
			if (props.ambient !== null) {
				const ambient = props.ambient as () => Vec3;
				createRenderEffect<Vec3>(
					(prev: Vec3 | null): Vec3 => ambient(),
					(value: Vec3, prev: Vec3 | null): Cleanup | null => { setAmbient(scene, value); state.invalidate(); return null; },
				);
			}
			if (props.ref !== null) { (props.ref as (value: Scene3DHandle) => void)(handle); }
			state.invalidate();
			const children = props.children;
			if (children !== null) {
				const scope: NodeScope = { state: state, parent: scene.rootId() };
				getVoidScopeContext().provider({
					value: accessor(() => VoidSpace.Scene3D),
					children: sceneScope.provider({ value: accessor(() => scope), children: children }),
				})(host, parent, before);
			}
		});
	};
}
