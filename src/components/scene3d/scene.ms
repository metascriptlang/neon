import { Accessor, accessor, untrack } from "../../core/signal";
import { createRenderEffect } from "../../core/effect";
import { Cleanup } from "../../core/types";
import { onCleanup } from "../../core/cleanup";
import { useContext } from "../../render/context";
import { VoidSpace, getVoidScopeContext, getVoidAreaContext, useVoidSpace } from "../../render/voidScope";
import { layerAnchor } from "../../render/voidLayer";
import { AreaLayer } from "../../render/voidAreaHandle";
import { Host, HostNode, NeonNode, VoidArea } from "../../render/hostTypes";
import { Vec3, Vec4 } from "../../../../void/src/math/math3d";
import { VERTEX_UNIFORM_LENGTH, LIGHT_UNIFORM_LENGTH } from "../../../../void/src/void3d/gpu3d";
import { DrawContext, DrawItem, releaseMaterial, closeContext, buryDoomed } from "../../../../void/src/void3d/draw";
import {
	ForwardRenderer, ForwardError, create, createHdrWhere, prepareFrame, drawOverScreen, closeForward,
	setOutlineBlend, setOutlineSettings, setBloom,
} from "../../../../void/src/void3d/forwardRenderer";
import { ToneMode, setToneMode, setExposure, setElapsedTime, attachShadow, markChanged } from "../../../../void/src/void3d/renderer";
import { BloomSettings } from "../../../../void/src/void3d/bloom";
import { DirShadowMap, closeDirShadow } from "../../../../void/src/void3d/dirShadowMap";
import { ForwardOutlineSettings, defaults, valid, FORWARD_OUTLINE_BLOCKS } from "../../../../void/src/void3d/forwardOutline";
import { fits } from "../../../../void/src/void3d/uniformPool";
import { PixelFormat, contextGeneration, formatRenderable } from "../../../../void/src/gpu/door";
import { Scene3D as VoidScene3D, NodeId3D, NO_NODE_ID, closeScene, setAmbient, refresh, collectLights } from "../../../../void/src/void3d/scene";
import { resolve, writeCameraBlock } from "../../../../void/src/void3d/camera";
import { Scene3DHandle, SceneState, LightShadow, SCENE_UNIFORM_CAPACITY, mountOwned, mountSceneChildren, viewCamera } from "./core";
import { runBeforeRefresh } from "./core";
import { useVoidClock } from "../../render/voidClock";
import { NeonEvent } from "../../render/event";
import { createPointer3D, providePointer } from "./pointer";

export interface Scene3DProps {
	ambient?: Accessor<Vec3> | null;
	outlineBlend?: Accessor<float32> | null;
	outlineSettings?: Accessor<ForwardOutlineSettings> | null;
	hdr?: Accessor<boolean> | null;
	bloom?: Accessor<BloomSettings | null> | null;
	toneMapping?: Accessor<ToneMode> | null;
	exposure?: Accessor<float32> | null;
	onPressMissed?: ((e: NeonEvent) => void) | null;
	ref?: ((handle: Scene3DHandle) => void) | null;
	children?: NeonNode | null;
}

function validBloom(settings: BloomSettings): boolean {
	return Number.isFinite(settings.intensity) && settings.intensity >= 0.0 && settings.maxMipDimension >= 4 &&
		settings.highPassFrequency > 0.0 && settings.lowFrequencyBoostCurvature < 1.0;
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
			const hdr = props.hdr === null ? false : untrack(props.hdr as () => boolean);
			if (props.bloom !== null && !hdr) {
				closeScene(scene);
				closeContext(context);
				throw new Error("Scene3D: bloom needs hdr");
			}
			const clear: Vec4 = { x: 0.0, y: 0.0, z: 0.0, w: 0.0 };
			const made: Result<ForwardRenderer, ForwardError> = hdr ?
				ForwardRenderer.createHdrWhere(context, clear, true) : ForwardRenderer.create(context, clear);
			if (!made.ok) {
				closeScene(scene);
				closeContext(context);
				throw new Error("Scene3D: ForwardRenderer.create failed: " + made.error.toString());
			}
			const renderer = made.value;
			let deviceChecked = !hdr;
			const invalidate = (): void => { area.handle.requestFrame(); };
			const handle: Scene3DHandle = { context: context, scene: scene, camera: null, renderer: renderer, invalidate: invalidate };
			let shadow: DirShadowMap | null = null;
			let caster: NodeId3D = NO_NODE_ID;
			const dropShadow = (): void => {
				const held = shadow;
				if (held === null) { return; }
				attachShadow(renderer.core, null);
				closeDirShadow(held);
				shadow = null;
				caster = NO_NODE_ID;
			};
			const shadowOf = (light: NodeId3D, settings: LightShadow | null): void => {
				if (renderer.closed) { return; }
				const owns = shadow !== null && caster.index === light.index && caster.generation === light.generation;
				if (settings === null) {
					if (owns) { dropShadow(); invalidate(); }
					return;
				}
				if (shadow !== null && !owns) { throw new Error("Light: only one Light casts shadows in a Scene3D"); }
				let held = shadow;
				if (held === null) {
					const created = DirShadowMap.create(context, settings.mapSize);
					if (!created.ok) { throw new Error("Light: castShadow failed: " + created.error.toString()); }
					attachShadow(renderer.core, created.value);
					held = created.value;
					shadow = held;
					caster = light;
				}
				held.size = settings.mapSize;
				held.bias = settings.bias;
				held.opacity = settings.opacity;
				markChanged(renderer.core);
				invalidate();
			};
			const state: SceneState = {
				handle: handle, defaultMaterial: null, cameras: [], geometries: [], invalidate: invalidate, beforeRefresh: [],
				shadowMaterials: [null, null, null, null], shadowOf: shadowOf,
			};
			if (hdr) { setToneMode(renderer.core, ToneMode.Filmic); }
			let items: Vec<DrawItem> = [];
			let cameraBlock: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
			let lightBlock: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
			let prepared = false;
			let unspentSeconds: float64 = 0.0;
			const wakeTime = useVoidClock(
				(): boolean => !renderer.closed && renderer.core.readsTime,
				(seconds: float64): void => { unspentSeconds += seconds; },
			);
			const pointer = createPointer3D(state, area.handle, props.onPressMissed);
			const layer: AreaLayer = {
				anchor,
				layout: (pixelWidth: int32, pixelHeight: int32): void => {},
				prepare: (pixelWidth: int32, pixelHeight: int32): void => {
					prepared = false;
					if (!deviceChecked) {
						if (!formatRenderable(PixelFormat.Rgba16f)) { throw new Error("Scene3D: hdr needs a device that renders Rgba16f"); }
						deviceChecked = true;
					}
					runBeforeRefresh(state, pixelWidth, pixelHeight);
					refresh(scene, items);
					const lights = collectLights(scene, lightBlock);
					if (!lights.ok) { throw new Error("Scene3D: collectLights failed: " + lights.error.toString()); }
					const world = viewCamera(handle);
					if (!world.ok) { throw new Error("Scene3D: the active camera has no world pose: " + world.error.toString()); }
					const view = world.value.resolve(pixelWidth, pixelHeight);
					if (!view.ok) { throw new Error("Scene3D: the active camera does not resolve: " + view.error.toString()); }
					view.value.writeCameraBlock(cameraBlock);
					const buried = buryDoomed(context, contextGeneration());
					setElapsedTime(renderer.core, unspentSeconds);
					unspentSeconds = 0.0;
					const frame = prepareFrame(renderer, items, cameraBlock, lightBlock, pixelWidth, pixelHeight);
					if (!frame.ok) { throw new Error("Scene3D: prepareFrame failed: " + frame.error.toString()); }
					prepared = true;
					wakeTime();
				},
				draw: (): void => {
					if (!prepared) { return; }
					prepared = false;
					drawOverScreen(renderer);
				},
				hit: pointer.hit,
			};
			const unregister = area.addLayer(layer);
			onCleanup((): void => {
				unregister();
				dropShadow();
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
				for (let i = 0; i < state.shadowMaterials.length; i++) {
					const variant = state.shadowMaterials[i];
					if (variant === null) { continue; }
					const released = releaseMaterial(context, variant);
					if (!released.ok) { throw new Error("Scene3D: releaseMaterial failed: " + released.error.toString()); }
					state.shadowMaterials[i] = null;
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
			if (props.hdr !== null) {
				createRenderEffect<boolean>(
					(prev: boolean | null): boolean => (props.hdr as () => boolean)(),
					(value: boolean, prev: boolean | null): Cleanup | null => {
						if (value !== hdr) { throw new Error("Scene3D: hdr is fixed at mount; remount the Scene3D to change it"); }
						return null;
					},
				);
			}
			if (props.bloom !== null) {
				createRenderEffect<BloomSettings | null>(
					(prev: BloomSettings | null | null): BloomSettings | null => (props.bloom as () => BloomSettings | null)(),
					(value: BloomSettings | null, prev: BloomSettings | null | null): Cleanup | null => {
						if (value !== null && !validBloom(value as BloomSettings)) { throw new Error("Scene3D: invalid bloom settings"); }
						setBloom(renderer, value);
						state.invalidate();
						return null;
					},
				);
			}
			if (props.toneMapping !== null) {
				createRenderEffect<ToneMode>(
					(prev: ToneMode | null): ToneMode => (props.toneMapping as () => ToneMode)(),
					(value: ToneMode, prev: ToneMode | null): Cleanup | null => { setToneMode(renderer.core, value); state.invalidate(); return null; },
				);
			}
			if (props.exposure !== null) {
				createRenderEffect<float32>(
					(prev: float32 | null): float32 => (props.exposure as () => float32)(),
					(value: float32, prev: float32 | null): Cleanup | null => {
						if (!Number.isFinite(value) || !(value > 0.0)) { throw new Error("Scene3D: exposure must be a finite multiplier above 0"); }
						setExposure(renderer.core, Math.log(value) as float32);
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
			if (children !== null) { mountSceneChildren(state, providePointer(pointer, children)); }
		});
	};
}
