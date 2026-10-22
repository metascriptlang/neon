import { Accessor, accessor } from "../../core/signal";
import { useContext } from "../../render/context";
import { createRenderEffect } from "../../core/effect";
import { Cleanup } from "../../core/types";
import { onCleanup } from "../../core/cleanup";
import { VoidSpace, getVoidScopeContext, getVoidAreaContext } from "../../render/voidScope";
import { AreaLayer, createAreaHub } from "../../render/voidAreaHandle";
import { Host, HostNode, NeonNode, VoidArea } from "../../render/hostTypes";
import { RenderState, BlendMode, FilterMode, Wrap } from "../../../../void/src/gpu/state";
import { PixelFormat, contextGeneration } from "../../../../void/src/gpu/door";
import { RenderTarget, allocate, resize, close } from "../../../../void/src/gpu/target";
import { Scene2D as VoidScene2D } from "../../../../void/src/void2d/node";
import { create, prepare, drawTarget, close as closeScene2D } from "../../../../void/src/void2d/scene";
import { rgba } from "../../../../void/src/void2d/types";
import { Program, ProgramKey, MATERIAL_UNIFORM_SLOT, UNLIT_MATERIAL_UNIFORM_LENGTH, UNLIT_MATERIAL_COLOR } from "../../../../void/src/void3d/gpu3d";
import { Material, Phase } from "../../../../void/src/void3d/material";
import { TextureId, TextureAlpha } from "../../../../void/src/void3d/texture";
import {
	MaterialId, addTargetTexture, addMaterial, releaseMaterial, releaseTexture, reserveUniforms, writeUniforms, releaseUniforms,
} from "../../../../void/src/void3d/draw";
import { mountOwned, requireScene, onBeforeRefresh } from "./core";

export interface RenderTextureHandle {
	texture: TextureId;
	material: MaterialId;
}

export interface RenderTextureProps {
	width: Accessor<int32>;
	height: Accessor<int32>;
	ref?: ((handle: RenderTextureHandle) => void) | null;
	children?: NeonNode | null;
}

function checkedSize(width: int32, height: int32): void {
	if (width <= 0 || height <= 0) { throw new Error("RenderTexture: width and height must be positive"); }
}

function premultipliedPass(): RenderState {
	const pass = RenderState.defaults();
	return pass.withDepth(false, pass.depthTest).withBlendMode(BlendMode.AlphaAdd);
}

export function RenderTexture(props: RenderTextureProps): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		const scope = requireScene("RenderTexture");
		const outer = useContext(getVoidAreaContext());
		if (outer === null) { throw new Error("RenderTexture: the Void area did not provide its frame"); }
		mountOwned((): void => {
			const state = scope.state;
			const context = state.handle.context;
			let width = props.width();
			let height = props.height();
			checkedSize(width, height);
			const target = RenderTarget.allocate(width, height, PixelFormat.Rgba8, true);
			onCleanup((): void => { target.close(); });
			const shown = addTargetTexture(context, target, FilterMode.Linear, Wrap.Clamp, TextureAlpha.Premultiplied);
			if (!shown.ok) { throw new Error("RenderTexture: addTargetTexture failed: " + shown.error.toString()); }
			const texture = shown.value;
			onCleanup((): void => {
				const released = releaseTexture(context, texture);
				if (!released.ok) { throw new Error("RenderTexture: releaseTexture failed: " + released.error.toString()); }
			});
			const reserved = reserveUniforms(context, MATERIAL_UNIFORM_SLOT, UNLIT_MATERIAL_UNIFORM_LENGTH);
			if (!reserved.ok) { throw new Error("RenderTexture: reserveUniforms failed: " + reserved.error.toString()); }
			const block = reserved.value;
			let values: Vec<float32> = new Array(UNLIT_MATERIAL_UNIFORM_LENGTH);
			for (let i: int32 = 0; i < 4; i += 1) { values[UNLIT_MATERIAL_COLOR + i] = 1.0; }
			const written = writeUniforms(context, block, values);
			if (!written.ok) {
				const released = releaseUniforms(context, block);
				if (!released.ok) { throw new Error("RenderTexture: releaseUniforms failed: " + released.error.toString()); }
				throw new Error("RenderTexture: writeUniforms failed: " + written.error.toString());
			}
			const added = addMaterial(context, {
				...Material.keyed(ProgramKey.of(Program.UnlitTextured).withPremultiplied(), premultipliedPass(), Phase.Alpha),
				texture: texture, uniforms: block,
			});
			if (!added.ok) {
				const released = releaseUniforms(context, block);
				if (!released.ok) { throw new Error("RenderTexture: releaseUniforms failed: " + released.error.toString()); }
				throw new Error("RenderTexture: addMaterial failed: " + added.error.toString());
			}
			const material = added.value;
			onCleanup((): void => {
				if (context.materialPins[material.index] > 0) {
					throw new Error("RenderTexture: a Mesh still shows its material; unmount that Mesh first");
				}
				const released = releaseMaterial(context, material);
				if (!released.ok) { throw new Error("RenderTexture: releaseMaterial failed: " + released.error.toString()); }
			});
			let dirty = true;
			const hub = createAreaHub({
				initialPixelWidth: width,
				initialPixelHeight: height,
				requestFrame: (): void => { dirty = true; state.invalidate(); },
				setImeRect: (pixelX: int32, pixelY: int32, pixelW: int32, pixelH: int32): void => {},
				font: (outer as VoidArea).hub.font,
				family: (outer as VoidArea).hub.family,
			});
			let blank: VoidScene2D | null = null;
			onCleanup((): void => {
				hub.close();
				const empty = blank;
				if (empty !== null) { empty.close(); }
			});
			createRenderEffect<[int32, int32]>(
				(prev: [int32, int32] | null): [int32, int32] => [props.width(), props.height()],
				(value: [int32, int32], prev: [int32, int32] | null): Cleanup | null => {
					checkedSize(value[0], value[1]);
					if (value[0] !== width || value[1] !== height) {
						width = value[0];
						height = value[1];
						target.resize(width, height);
						hub.resize({ pixelWidth: width, pixelHeight: height, scale: 1.0 });
						dirty = true;
						state.invalidate();
					}
					return null;
				},
			);
			onBeforeRefresh(state, (): void => {
				if (target.generation !== contextGeneration()) {
					target.resize(width, height);
					dirty = true;
				}
				if (!dirty) { return; }
				const layers = hub.layers();
				if (layers.length > 1) { throw new Error("RenderTexture: draws one Scene2D, found " + layers.length.toString() + " layers"); }
				hub.layoutLayers(width, height);
				if (layers.length === 0) {
					let empty = blank;
					if (empty === null) {
						empty = VoidScene2D.create(rgba(0.0, 0.0, 0.0, 0.0));
						blank = empty;
					}
					empty.prepare(width as float32, height as float32, 1.0);
					empty.drawTarget(target);
				} else {
					const layer: AreaLayer = layers[0];
					if (layer.drawTarget === null) { throw new Error("RenderTexture: only a Scene2D draws into a texture"); }
					hub.prepareLayers(layers, width, height);
					(layer.drawTarget as (target: RenderTarget) => void)(target);
				}
				dirty = false;
			});
			if (props.ref !== null) {
				(props.ref as (handle: RenderTextureHandle) => void)({ texture: texture, material: material });
			}
			const children = props.children;
			if (children !== null) {
				const area: VoidArea = { host: host, root: parent, hub: hub, release: (): void => {} };
				getVoidAreaContext().provider({
					value: accessor(() => area),
					children: getVoidScopeContext().provider({ value: accessor(() => VoidSpace.Area), children: children }),
				})(host, parent, before);
			}
		});
	};
}
