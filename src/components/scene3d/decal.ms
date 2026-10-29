import { Accessor, untrack } from "../../core/signal";
import { createMemo } from "../../core/memo";
import { createRenderEffect } from "../../core/effect";
import { Cleanup } from "../../core/types";
import { onCleanup } from "../../core/cleanup";
import { Host, HostNode, NeonNode } from "../../render/hostTypes";
import { Color } from "../../../../void/src/void2d/types";
import { vec3 } from "../../../../void/src/math/math3d";
import { Material, UniformBlock } from "../../../../void/src/void3d/material";
import { TextureId } from "../../../../void/src/void3d/texture";
import { MeshData, Rgba, addQuad } from "../../../../void/src/void3d/meshData";
import { DecalOverlay, DecalPass, DecalError, decalBlock } from "../../../../void/src/void3d/decal";
import {
	DrawContext, MaterialId, addMeshData, releaseMesh, releaseMaterial, writeUniforms,
} from "../../../../void/src/void3d/draw";
import { NodeId3D, addMeshNode, setMaterialOf } from "../../../../void/src/void3d/scene";
import {
	NodeProps, mountOwned, requireScene, localOf, bindNode, ownNode, mountNodeChildren, valueOr, addUniformMaterial,
} from "./core";

export struct DecalNormalFade {
	start: float32;
	end: float32;
}

// map, position, rotation and scale are drei's Decal props (Decal.tsx:8-20). The rest have no
// drei name; mesh, polygonOffsetFactor, depthTest and debug are drei's and have no Void
// counterpart, so a Decal given one refuses it at mount.
export interface DecalProps extends NodeProps {
	map: Accessor<TextureId>;
	color?: Accessor<Color> | null;
	fadeStart?: Accessor<float32> | null;
	fadeEnd?: Accessor<float32> | null;
	fadePower?: Accessor<float32> | null;
	normalFade?: Accessor<DecalNormalFade> | null;
	emissive?: Accessor<float32> | null;
	afterToneMap?: Accessor<boolean> | null;
	mesh?: Accessor<NodeId3D> | null;
	polygonOffsetFactor?: Accessor<float32> | null;
	depthTest?: Accessor<boolean> | null;
	debug?: Accessor<boolean> | null;
}

function refuse(reason: string): Error {
	return new Error("Decal: " + reason);
}

function refuseUnmapped(props: DecalProps): void {
	if (props.mesh !== null) {
		throw refuse("mesh has no counterpart; Void's decal is a depth-read box volume that tints whatever the scene drew inside it, so it has no target mesh");
	}
	if (props.polygonOffsetFactor !== null) {
		throw refuse("polygonOffsetFactor has no counterpart; a Void decal reads the scene depth instead of offsetting projected geometry");
	}
	if (props.depthTest !== null) {
		throw refuse("depthTest has no counterpart; Void's decal pass reads the scene depth as a texture and has no depth attachment");
	}
	if (props.debug !== null) {
		throw refuse("debug has no counterpart; mount a Mesh with the same transform to see the box");
	}
}

function finite(value: float32, name: string): float32 {
	if (!Number.isFinite(value)) { throw refuse(name + " must be finite"); }
	return value;
}

function passOf(props: DecalProps): DecalPass {
	return valueOr<boolean>(props.afterToneMap, false) ? DecalPass.AfterToneMap : DecalPass.BeforeToneMap;
}

function overlayOf(props: DecalProps): DecalOverlay {
	const base = DecalOverlay.defaults();
	const tint: Color = props.color === null ? { r: 1.0, g: 1.0, b: 1.0, a: 1.0 } : (props.color as () => Color)();
	const fade = props.normalFade === null ? null : (props.normalFade as () => DecalNormalFade)();
	return {
		...base,
		color: {
			red: finite(tint.r, "color"), green: finite(tint.g, "color"),
			blue: finite(tint.b, "color"), alpha: finite(tint.a, "color"),
		},
		fadeStart: finite(valueOr<float32>(props.fadeStart, base.fadeStart), "fadeStart"),
		fadeEnd: finite(valueOr<float32>(props.fadeEnd, base.fadeEnd), "fadeEnd"),
		fadePower: finite(valueOr<float32>(props.fadePower, base.fadePower), "fadePower"),
		emissive: finite(valueOr<float32>(props.emissive, base.emissive), "emissive"),
		normalFade: fade !== null,
		normalFadeStart: fade === null ? base.normalFadeStart : finite(fade.start, "normalFade start"),
		normalFadeEnd: fade === null ? base.normalFadeEnd : finite(fade.end, "normalFade end"),
	};
}

function blockOf(props: DecalProps, pass: DecalPass): Vec<float32> {
	const made = decalBlock(overlayOf(props), pass);
	if (!made.ok) {
		throw refuse(made.error == DecalError.FadeRange ?
			"fadeEnd must be above fadeStart" : "normalFade end must be above its start");
	}
	return made.value;
}

// h3d.prim.Cube centred: the unit box a decal's node scales, every face wound outward.
function unitBox(): MeshData {
	let data = MeshData.empty();
	const white: Rgba = { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 };
	const lo: float32 = -0.5;
	const hi: float32 = 0.5;
	const faces = [
		[vec3(lo, lo, hi), vec3(hi, lo, hi), vec3(hi, hi, hi), vec3(lo, hi, hi), vec3(0.0, 0.0, 1.0)],
		[vec3(hi, lo, lo), vec3(lo, lo, lo), vec3(lo, hi, lo), vec3(hi, hi, lo), vec3(0.0, 0.0, -1.0)],
		[vec3(hi, lo, hi), vec3(hi, lo, lo), vec3(hi, hi, lo), vec3(hi, hi, hi), vec3(1.0, 0.0, 0.0)],
		[vec3(lo, lo, lo), vec3(lo, lo, hi), vec3(lo, hi, hi), vec3(lo, hi, lo), vec3(-1.0, 0.0, 0.0)],
		[vec3(lo, hi, hi), vec3(hi, hi, hi), vec3(hi, hi, lo), vec3(lo, hi, lo), vec3(0.0, 1.0, 0.0)],
		[vec3(lo, lo, lo), vec3(hi, lo, lo), vec3(hi, lo, hi), vec3(lo, lo, hi), vec3(0.0, -1.0, 0.0)],
	];
	for (const f of faces) {
		if (!addQuad(data, f[0], f[1], f[2], f[3], f[4], white).ok) { throw refuse("addQuad failed building the box"); }
	}
	return data;
}

export function Decal(props: DecalProps): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		refuseUnmapped(props);
		const scope = requireScene("Decal");
		mountOwned((): void => {
			const state = scope.state;
			const scene = state.handle.scene;
			const context: DrawContext = state.handle.context;
			const local = localOf(props);
			const material = createMemo<MaterialId>((prev: MaterialId | null): MaterialId => {
				const map = props.map();
				const pass = passOf(props);
				if (!map.isTexture()) { throw refuse("map must be a texture; a Decal projects its map, so there is no untextured decal"); }
				const values = untrack((): Vec<float32> => blockOf(props, pass));
				const id = addUniformMaterial(context, "Decal", values, (block: UniformBlock): Material => ({
					...Material.decal(pass), texture: map, uniforms: block,
				}));
				onCleanup((): void => {
					const released = releaseMaterial(context, id);
					if (!released.ok) { throw refuse("releaseMaterial failed: " + released.error.toString()); }
					state.invalidate();
				});
				return id;
			});
			let shown = material();
			const box = addMeshData(context, unitBox());
			if (!box.ok) { throw refuse("addMeshData failed: " + box.error.toString()); }
			const placed = addMeshNode(scene, scope.parent, local, box.value, shown);
			const released = releaseMesh(context, box.value);
			if (!placed.ok) { throw refuse("addMeshNode failed: " + placed.error.toString()); }
			if (!released.ok) { throw refuse("releaseMesh failed: " + released.error.toString()); }
			const node = placed.value;
			ownNode(state, node);
			createRenderEffect<[MaterialId, Vec<float32>]>(
				(prev: [MaterialId, Vec<float32>] | null): [MaterialId, Vec<float32>] =>
					[material(), blockOf(props, passOf(props))],
				(value: [MaterialId, Vec<float32>], prev: [MaterialId, Vec<float32>] | null): Cleanup | null => {
					if (prev === null) { return null; }
					if (value[0] !== shown) {
						const changed = setMaterialOf(scene, node, value[0]);
						if (!changed.ok) { throw refuse("setMaterialOf failed: " + changed.error.toString()); }
						shown = value[0];
					} else {
						const written = writeUniforms(context, context.materials[value[0].index].uniforms, value[1]);
						if (!written.ok) { throw refuse("writeUniforms failed: " + written.error.toString()); }
					}
					state.invalidate();
					return null;
				},
			);
			bindNode(state, node, props, local);
			mountNodeChildren(scope, node, props, host, parent, before);
		});
	};
}
