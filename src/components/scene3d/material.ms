import { Accessor, untrack } from "../../core/signal";
import { createMemo } from "../../core/memo";
import { createRenderEffect } from "../../core/effect";
import { Cleanup } from "../../core/types";
import { onCleanup } from "../../core/cleanup";
import { Color, Vec2 } from "../../../../void/src/void2d/types";
import { Face } from "../../../../void/src/gpu/state";
import {
	Program,
	MATERIAL_UNIFORM_SLOT,
	MATERIAL_SATURATION,
	MATERIAL_DOUBLE_SIDED,
	MATERIAL_ALPHA_KILL,
	MATERIAL_COLOR,
	UNLIT_MATERIAL_COLOR,
	MOVING_UV_MATRIX,
	MOVING_UV_OFFSET,
	MOVING_UV_SCROLL,
	MOVING_BACK_UV_MATRIX,
	MOVING_DISSOLVE_THRESHOLD,
	MOVING_DISSOLVE_EDGE_WIDTH,
	MOVING_DISSOLVE_EDGE_COLOR,
	PBR_METALNESS,
	PBR_ROUGHNESS,
	PBR_OCCLUSION,
	PBR_UV_MATRIX,
	PBR_UV_OFFSET,
	PBR_UV_SCROLL,
	EMISSIVE_COLOR,
	EMISSIVE_STRENGTH,
	EMISSIVE_LENGTH,
	movingBase,
	emissiveBase,
} from "../../../../void/src/void3d/gpu3d";
import {
	Material, MaterialKind, ShadowCasting, DEFAULT_ALPHA_KILL,
} from "../../../../void/src/void3d/material";
import { PbrProperties } from "../../../../void/src/void3d/pbrResponse";
import { TextureId, NO_TEXTURE } from "../../../../void/src/void3d/texture";
import {
	DrawContext, MaterialId, addMaterial, releaseMaterial, reserveUniforms, writeUniforms, releaseUniforms,
} from "../../../../void/src/void3d/draw";
import { requireScene } from "./core";

export interface MaterialProps {
	unlit?: Accessor<boolean> | null;
	kind?: Accessor<MaterialKind> | null;
	doubleSided?: Accessor<boolean> | null;
	castShadow?: Accessor<boolean> | null;
	receiveShadow?: Accessor<boolean> | null;
	texture?: Accessor<TextureId> | null;
	normalTexture?: Accessor<TextureId> | null;
	emissiveTexture?: Accessor<TextureId> | null;
	backTexture?: Accessor<TextureId> | null;
	dissolveTexture?: Accessor<TextureId> | null;
	color?: Accessor<Color> | null;
	saturation?: Accessor<float32> | null;
	alphaKill?: Accessor<float32> | null;
	metalness?: Accessor<float32> | null;
	roughness?: Accessor<float32> | null;
	emissive?: Accessor<Color> | null;
	emissiveIntensity?: Accessor<float32> | null;
	uvRepeat?: Accessor<Vec2> | null;
	uvOffset?: Accessor<Vec2> | null;
	uvScroll?: Accessor<Vec2> | null;
	dissolve?: Accessor<float32> | null;
	dissolveEdgeWidth?: Accessor<float32> | null;
	dissolveEdgeColor?: Accessor<Color> | null;
}

function refuse(reason: string): Error {
	return new Error("createMaterial: " + reason);
}

function textureOf(read: Accessor<TextureId> | null): TextureId {
	return read === null ? NO_TEXTURE : (read as () => TextureId)();
}

function flagOf(read: Accessor<boolean> | null): boolean {
	return read === null ? false : (read as () => boolean)();
}

function floatOf(read: Accessor<float32> | null, fallback: float32): float32 {
	return read === null ? fallback : (read as () => float32)();
}

function movesUv(props: MaterialProps): boolean {
	return props.uvRepeat !== null || props.uvOffset !== null || props.uvScroll !== null;
}

function pbrOf(props: MaterialProps): boolean {
	return props.metalness !== null || props.roughness !== null;
}

function shapeOf(props: MaterialProps): Material {
	const texture = textureOf(props.texture);
	const normal = textureOf(props.normalTexture);
	const emissive = textureOf(props.emissiveTexture);
	const back = textureOf(props.backTexture);
	const noise = textureOf(props.dissolveTexture);
	const unlit = flagOf(props.unlit);
	const textured = texture.isTexture();
	if (unlit && !textured) { throw refuse("unlit needs a texture; Void has no untextured unlit program"); }
	const litTextured = textured && !unlit;
	if (normal.isTexture() && !litTextured) { throw refuse("normalTexture needs a lit material with a texture"); }
	if (emissive.isTexture() && !litTextured) { throw refuse("emissiveTexture needs a lit material with a texture"); }
	if ((back.isTexture() || noise.isTexture()) && !textured) {
		throw refuse("backTexture and dissolveTexture need a texture");
	}
	const pbr = pbrOf(props);
	if (pbr && unlit) { throw refuse("metalness and roughness need a lit material"); }
	if (pbr && (back.isTexture() || noise.isTexture())) {
		throw refuse("Void has no pbr program with a back texture or a dissolve");
	}
	if (movesUv(props) && !textured) { throw refuse("uvRepeat, uvOffset and uvScroll need a texture"); }
	const program = unlit ? Program.UnlitTextured : textured ? Program.LitTextured : Program.Lit;
	const base = Material.ofKind(program, props.kind === null ? MaterialKind.Opaque : (props.kind as () => MaterialKind)());
	let key = base.program;
	if (pbr) { key = key.withPbr(); }
	if (movesUv(props) && !pbr) { key = key.withUvTransform(); }
	if (back.isTexture()) { key = key.withBackTexture(); }
	if (noise.isTexture()) { key = key.withDissolve(); }
	if (emissive.isTexture()) { key = key.withEmissive(); }
	if (normal.isTexture()) { key = key.withNormalMap(); }
	const shaped: Material = { ...base, program: key };
	const sided: Material = flagOf(props.doubleSided) ?
		{ ...shaped, pass: shaped.pass.withCulling(Face.None) } : shaped;
	return {
		...sided.withShadows(flagOf(props.castShadow) ? ShadowCasting.On : ShadowCasting.Off, flagOf(props.receiveShadow)),
		texture: texture,
		normalTexture: normal,
		emissiveTexture: emissive,
		backTexture: back,
		dissolveTexture: noise,
	};
}

function writeColor(ref values: Vec<float32>, at: int32, color: Color): void {
	values[at] = color.r;
	values[at + 1] = color.g;
	values[at + 2] = color.b;
	values[at + 3] = color.a;
}

function writeUv(ref values: Vec<float32>, props: MaterialProps, matrix: int32, offset: int32, scroll: int32): void {
	const repeat: Vec2 = props.uvRepeat === null ? { x: 1.0, y: 1.0 } : (props.uvRepeat as () => Vec2)();
	values[matrix] = repeat.x;
	values[matrix + 3] = repeat.y;
	if (props.uvOffset !== null) {
		const by = (props.uvOffset as () => Vec2)();
		values[offset] = by.x;
		values[offset + 1] = by.y;
	}
	if (props.uvScroll !== null) {
		const speed = (props.uvScroll as () => Vec2)();
		values[scroll] = speed.x;
		values[scroll + 1] = speed.y;
	}
}

function blockOf(material: Material, props: MaterialProps): Vec<float32> {
	const key = material.program;
	if (props.color !== null && key.program != Program.UnlitTextured) {
		throw refuse("color needs an unlit material; Void's lit programs have no colour uniform");
	}
	if ((props.emissive !== null || props.emissiveIntensity !== null) && !key.emissive) {
		throw refuse("emissive and emissiveIntensity need an emissiveTexture");
	}
	const dissolves = props.dissolve !== null || props.dissolveEdgeWidth !== null || props.dissolveEdgeColor !== null;
	if (dissolves && !key.dissolve) { throw refuse("dissolve values need a dissolveTexture"); }
	let values: Vec<float32> = new Array(emissiveBase(key) + (key.emissive ? EMISSIVE_LENGTH : 0));
	values[MATERIAL_SATURATION] = floatOf(props.saturation, 0.0);
	values[MATERIAL_DOUBLE_SIDED] = material.pass.culling == Face.None ? 1.0 : 0.0;
	const kill = floatOf(props.alphaKill, key.cutout ? DEFAULT_ALPHA_KILL : 0.0);
	if (key.cutout && !(kill > 0.0)) { throw refuse("alphaKill must be above 0 for MaterialKind.AlphaKill"); }
	values[MATERIAL_ALPHA_KILL] = kill;
	if (key.program == Program.UnlitTextured) {
		writeColor(values, UNLIT_MATERIAL_COLOR, props.color === null ? { r: 1.0, g: 1.0, b: 1.0, a: 1.0 } : (props.color as () => Color)());
	} else {
		writeColor(values, MATERIAL_COLOR, { r: 1.0, g: 1.0, b: 1.0, a: 1.0 });
	}
	if (key.pbr) {
		const checked = PbrProperties.heapsValues(floatOf(props.metalness, 0.0), floatOf(props.roughness, 1.0), 1.0);
		if (!checked.ok) { throw refuse("metalness and roughness: " + checked.error.toString()); }
		if (checked.value.roughness == 0.0) { throw refuse("roughness 0 has no valid BRDF in Void"); }
		values[PBR_METALNESS] = checked.value.metalness;
		values[PBR_ROUGHNESS] = checked.value.roughness;
		values[PBR_OCCLUSION] = checked.value.occlusion;
		writeUv(values, props, PBR_UV_MATRIX, PBR_UV_OFFSET, PBR_UV_SCROLL);
	}
	if (key.moves()) {
		const base = movingBase(key);
		writeUv(values, props, base + MOVING_UV_MATRIX, base + MOVING_UV_OFFSET, base + MOVING_UV_SCROLL);
		values[base + MOVING_BACK_UV_MATRIX] = 1.0;
		values[base + MOVING_BACK_UV_MATRIX + 3] = 1.0;
		values[base + MOVING_DISSOLVE_THRESHOLD] = floatOf(props.dissolve, 0.0);
		values[base + MOVING_DISSOLVE_EDGE_WIDTH] = floatOf(props.dissolveEdgeWidth, 0.0);
		if (props.dissolveEdgeColor !== null) {
			writeColor(values, base + MOVING_DISSOLVE_EDGE_COLOR, (props.dissolveEdgeColor as () => Color)());
		}
	}
	if (key.emissive) {
		const at = emissiveBase(key);
		if (props.emissive !== null) {
			const glow = (props.emissive as () => Color)();
			values[at + EMISSIVE_COLOR] = glow.r;
			values[at + EMISSIVE_COLOR + 1] = glow.g;
			values[at + EMISSIVE_COLOR + 2] = glow.b;
		}
		values[at + EMISSIVE_STRENGTH] = floatOf(props.emissiveIntensity, 1.0);
	}
	return values;
}

function addOwned(context: DrawContext, material: Material, values: Vec<float32>): MaterialId {
	const reserved = reserveUniforms(context, MATERIAL_UNIFORM_SLOT, values.length as int32);
	if (!reserved.ok) { throw refuse("reserveUniforms failed: " + reserved.error.toString()); }
	const block = reserved.value;
	const giveBack = (failure: string): Error => {
		const released = releaseUniforms(context, block);
		if (!released.ok) { return refuse("releaseUniforms failed: " + released.error.toString()); }
		return refuse(failure);
	};
	const written = writeUniforms(context, block, values);
	if (!written.ok) { throw giveBack("writeUniforms failed: " + written.error.toString()); }
	const made = addMaterial(context, { ...material, uniforms: block });
	if (!made.ok) { throw giveBack("addMaterial failed: " + made.error.toString()); }
	return made.value;
}

export function createMaterial(props: MaterialProps): Accessor<MaterialId> {
	const state = requireScene("createMaterial").state;
	const context = state.handle.context;
	const material = createMemo<MaterialId>((prev: MaterialId | null): MaterialId => {
		const shape = shapeOf(props);
		const values = untrack((): Vec<float32> => blockOf(shape, props));
		const id = addOwned(context, shape, values);
		onCleanup((): void => {
			const released = releaseMaterial(context, id);
			if (!released.ok) { throw refuse("releaseMaterial failed: " + released.error.toString()); }
			state.invalidate();
		});
		return id;
	});
	createRenderEffect<[MaterialId, Vec<float32>]>(
		(prev: [MaterialId, Vec<float32>] | null): [MaterialId, Vec<float32>] => {
			const id = material();
			return [id, blockOf(context.materials[id.index], props)];
		},
		(value: [MaterialId, Vec<float32>], prev: [MaterialId, Vec<float32>] | null): Cleanup | null => {
			if (prev === null || prev[0] !== value[0]) { return null; }
			const written = writeUniforms(context, context.materials[value[0].index].uniforms, value[1]);
			if (!written.ok) { throw refuse("writeUniforms failed: " + written.error.toString()); }
			state.invalidate();
			return null;
		},
	);
	return material;
}
