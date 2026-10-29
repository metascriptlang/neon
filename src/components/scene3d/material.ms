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
	MATERIAL_PARALLAX,
	MATERIAL_COLOR,
	MOVING_UV_MATRIX,
	MOVING_UV_OFFSET,
	MOVING_UV_SCROLL,
	MOVING_BACK_UV_MATRIX,
	MOVING_DISSOLVE_THRESHOLD,
	MOVING_DISSOLVE_EDGE_WIDTH,
	MOVING_DISSOLVE_EDGE_COLOR,
	MOVING_FLIPBOOK_COLUMNS,
	MOVING_FLIPBOOK_ROWS,
	MOVING_FLIPBOOK_FRAMES,
	MOVING_FLIPBOOK_SPEED,
	MOVING_FLIPBOOK_START_TIME,
	MOVING_FLIPBOOK_START_FRAME,
	MOVING_FLIPBOOK_LOOP,
	MOVING_FLIPBOOK_BLEND,
	MOVING_FADE_NEAR_START,
	MOVING_FADE_NEAR_END,
	MOVING_FADE_FAR_START,
	MOVING_FADE_FAR_END,
	MOVING_COLOR_KEY,
	PBR_METALNESS,
	PBR_ROUGHNESS,
	PBR_OCCLUSION,
	PBR_OCCLUSION_STRENGTH,
	PBR_PARALLAX_STEPS,
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
import { requireScene, whiteMaterialBlock } from "./core";

// A grid of frames in the base texture, Heaps' AnimatedTexture (void3d/gpu3d.ms MOVING_FLIPBOOK_*).
// numberOfFrames, fps, startFrame and loop are drei's SpriteAnimator props
// (SpriteAnimator.tsx:125-133); columns, rows, startTime (seconds of the frame clock) and blend
// (mix the next frame in by the fraction elapsed) have no drei name.
export struct Flipbook {
	columns: int32;
	rows: int32;
	numberOfFrames: int32;
	fps: float32;
	startFrame: int32;
	startTime: float32;
	loop: boolean;
	blend: boolean;
}

// Heaps' DistanceFade in world units from the camera: alpha rises from 0 to 1 between nearStart
// and nearEnd and falls to 0 between farStart and farEnd. A side with start equal to end is off.
export struct DistanceFade {
	nearStart: float32;
	nearEnd: float32;
	farStart: float32;
	farEnd: float32;
}

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
	metalRoughTexture?: Accessor<TextureId> | null;
	occlusionTexture?: Accessor<TextureId> | null;
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
	aoMapIntensity?: Accessor<float32> | null;
	occlusionChannel?: Accessor<int32> | null;
	parallaxScale?: Accessor<float32> | null;
	parallaxSteps?: Accessor<int32> | null;
	flipbook?: Accessor<Flipbook> | null;
	distanceFade?: Accessor<DistanceFade> | null;
	colorKey?: Accessor<Color> | null;
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
	return props.metalness !== null || props.roughness !== null ||
		props.metalRoughTexture !== null || props.occlusionTexture !== null;
}

function movesBlock(props: MaterialProps): boolean {
	return props.flipbook !== null || props.distanceFade !== null || props.colorKey !== null;
}

function mapsOccluded(props: MaterialProps): boolean {
	return props.aoMapIntensity !== null || props.occlusionChannel !== null;
}

function shapeOf(props: MaterialProps): Material {
	const texture = textureOf(props.texture);
	const normal = textureOf(props.normalTexture);
	const emissive = textureOf(props.emissiveTexture);
	const back = textureOf(props.backTexture);
	const noise = textureOf(props.dissolveTexture);
	const metalRough = textureOf(props.metalRoughTexture);
	const occlusion = textureOf(props.occlusionTexture);
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
	if (metalRough.isTexture() !== occlusion.isTexture()) {
		throw refuse("metalRoughTexture and occlusionTexture go together; Void's pbr maps program reads both");
	}
	const mapped = metalRough.isTexture();
	if (mapped && !litTextured) { throw refuse("metalRoughTexture and occlusionTexture need a lit material with a texture"); }
	if (mapsOccluded(props) && !mapped) {
		throw refuse("aoMapIntensity and occlusionChannel need an occlusionTexture");
	}
	const channel = props.occlusionChannel === null ? 0 : (props.occlusionChannel as () => int32)();
	if (channel < 0 || channel > 1) { throw refuse("occlusionChannel must be 0 or 1; Void reads uv sets 0 and 1"); }
	const parallax = props.parallaxScale !== null;
	if (props.parallaxSteps !== null && !parallax) { throw refuse("parallaxSteps needs parallaxScale"); }
	if (parallax && !(mapped && normal.isTexture())) {
		throw refuse("parallaxScale needs metalRoughTexture, occlusionTexture and normalTexture; Void reads the height in the alpha of metalRoughTexture");
	}
	if (movesBlock(props) && !textured) { throw refuse("flipbook, distanceFade and colorKey need a texture"); }
	if (movesBlock(props) && pbr) {
		throw refuse("flipbook, distanceFade and colorKey need a program without pbr; Void's pbr programs read no moving block");
	}
	const kind = props.kind === null ? MaterialKind.Opaque : (props.kind as () => MaterialKind)();
	if (props.distanceFade !== null && (kind == MaterialKind.Opaque || kind == MaterialKind.AlphaKill)) {
		throw refuse("distanceFade shows only through blending; use MaterialKind.Alpha, Add or SoftAdd");
	}
	if (parallax && kind == MaterialKind.AlphaKill && flagOf(props.castShadow)) {
		throw refuse("parallaxScale with MaterialKind.AlphaKill cannot cast a shadow; Void has no such caster");
	}
	const program = unlit ? Program.UnlitTextured : textured ? Program.LitTextured : Program.Lit;
	const base = Material.ofKind(program, kind);
	let key = base.program;
	if (pbr) { key = key.withPbr(); }
	if (mapped) { key = key.withPbrMaps(); }
	if (mapped && channel == 1) { key = key.withOcclusionUvB(); }
	if ((movesUv(props) && !pbr) || movesBlock(props)) { key = key.withUvTransform(); }
	if (back.isTexture()) { key = key.withBackTexture(); }
	if (noise.isTexture()) { key = key.withDissolve(); }
	if (emissive.isTexture()) { key = key.withEmissive(); }
	if (normal.isTexture()) { key = key.withNormalMap(); }
	if (parallax) { key = key.withParallax(); }
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
		metalRoughTexture: metalRough,
		occlusionTexture: occlusion,
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

function writeFlipbook(ref values: Vec<float32>, base: int32, book: Flipbook): void {
	if (book.columns < 1 || book.rows < 1) { throw refuse("flipbook columns and rows must be at least 1"); }
	const cells = (book.columns as int64) * (book.rows as int64);
	if (book.numberOfFrames < 1 || (book.numberOfFrames as int64) > cells) {
		throw refuse("flipbook numberOfFrames must be from 1 to columns * rows; omit flipbook for none");
	}
	if (book.startFrame < 0 || book.startFrame >= book.numberOfFrames) {
		throw refuse("flipbook startFrame must be below numberOfFrames");
	}
	if (!(Number.isFinite(book.fps) && book.fps >= 0.0) || !Number.isFinite(book.startTime)) {
		throw refuse("flipbook fps must be finite and not negative, and startTime finite");
	}
	values[base + MOVING_FLIPBOOK_COLUMNS] = book.columns as float32;
	values[base + MOVING_FLIPBOOK_ROWS] = book.rows as float32;
	values[base + MOVING_FLIPBOOK_FRAMES] = book.numberOfFrames as float32;
	values[base + MOVING_FLIPBOOK_SPEED] = book.fps;
	values[base + MOVING_FLIPBOOK_START_TIME] = book.startTime;
	values[base + MOVING_FLIPBOOK_START_FRAME] = book.startFrame as float32;
	values[base + MOVING_FLIPBOOK_LOOP] = book.loop ? 1.0 : 0.0;
	values[base + MOVING_FLIPBOOK_BLEND] = book.blend ? 1.0 : 0.0;
}

function writeFade(ref values: Vec<float32>, base: int32, fade: DistanceFade): void {
	const finite = Number.isFinite(fade.nearStart) && Number.isFinite(fade.nearEnd) &&
		Number.isFinite(fade.farStart) && Number.isFinite(fade.farEnd);
	if (!finite) { throw refuse("distanceFade distances must be finite"); }
	if (fade.nearEnd < fade.nearStart || fade.farEnd < fade.farStart) {
		throw refuse("distanceFade needs each end at or past its start; equal turns a side off");
	}
	values[base + MOVING_FADE_NEAR_START] = fade.nearStart;
	values[base + MOVING_FADE_NEAR_END] = fade.nearEnd;
	values[base + MOVING_FADE_FAR_START] = fade.farStart;
	values[base + MOVING_FADE_FAR_END] = fade.farEnd;
}

function writeColorKey(ref values: Vec<float32>, base: int32, key: Color): void {
	if (!(key.a > 0.0) || !Number.isFinite(key.r) || !Number.isFinite(key.g) || !Number.isFinite(key.b)) {
		throw refuse("colorKey needs a finite colour with alpha above 0; Void keys nothing at alpha 0, so omit the prop");
	}
	writeColor(values, base + MOVING_COLOR_KEY, key);
}

function blockOf(material: Material, props: MaterialProps): Vec<float32> {
	const key = material.program;
	if ((props.emissive !== null || props.emissiveIntensity !== null) && !key.emissive) {
		throw refuse("emissive and emissiveIntensity need an emissiveTexture");
	}
	const dissolves = props.dissolve !== null || props.dissolveEdgeWidth !== null || props.dissolveEdgeColor !== null;
	if (dissolves && !key.dissolve) { throw refuse("dissolve values need a dissolveTexture"); }
	let values: Vec<float32> = whiteMaterialBlock(emissiveBase(key) + (key.emissive ? EMISSIVE_LENGTH : 0));
	values[MATERIAL_SATURATION] = floatOf(props.saturation, 0.0);
	values[MATERIAL_DOUBLE_SIDED] = material.pass.culling == Face.None ? 1.0 : 0.0;
	const kill = floatOf(props.alphaKill, key.cutout ? DEFAULT_ALPHA_KILL : 0.0);
	if (key.cutout && !(kill > 0.0)) { throw refuse("alphaKill must be above 0 for MaterialKind.AlphaKill"); }
	values[MATERIAL_ALPHA_KILL] = kill;
	if (props.color !== null) { writeColor(values, MATERIAL_COLOR, (props.color as () => Color)()); }
	if (key.pbr) {
		const checked = PbrProperties.heapsValues(floatOf(props.metalness, 0.0), floatOf(props.roughness, 1.0), 1.0);
		if (!checked.ok) { throw refuse("metalness and roughness: " + checked.error.toString()); }
		if (checked.value.roughness == 0.0) { throw refuse("roughness 0 has no valid BRDF in Void"); }
		values[PBR_METALNESS] = checked.value.metalness;
		values[PBR_ROUGHNESS] = checked.value.roughness;
		values[PBR_OCCLUSION] = checked.value.occlusion;
		writeUv(values, props, PBR_UV_MATRIX, PBR_UV_OFFSET, PBR_UV_SCROLL);
	}
	if (key.pbrMaps) {
		const strength = floatOf(props.aoMapIntensity, 1.0);
		if (!(strength >= 0.0 && strength <= 1.0)) {
			throw refuse("aoMapIntensity must be from 0 to 1; Void's occlusion strength is a unit value");
		}
		values[PBR_OCCLUSION_STRENGTH] = strength;
	}
	if (key.parallax) {
		const scale = floatOf(props.parallaxScale, 0.0);
		if (!(Number.isFinite(scale) && scale > 0.0)) {
			throw refuse("parallaxScale must be a finite number above 0");
		}
		values[MATERIAL_PARALLAX] = scale;
		const steps = props.parallaxSteps === null ? 0 : (props.parallaxSteps as () => int32)();
		if (steps < 0 || steps > 255) {
			throw refuse("parallaxSteps must be from 0 to 255, where 0 is Void's 24");
		}
		values[PBR_PARALLAX_STEPS] = steps as float32;
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
		if (props.flipbook !== null) { writeFlipbook(values, base, (props.flipbook as () => Flipbook)()); }
		if (props.distanceFade !== null) {
			writeFade(values, base, (props.distanceFade as () => DistanceFade)());
		}
		if (props.colorKey !== null) { writeColorKey(values, base, (props.colorKey as () => Color)()); }
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
