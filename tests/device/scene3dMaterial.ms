import { Accessor, accessor, createSignal } from "../../src/core/signal";
import { flush } from "../../src/core/runtime";
import { element } from "../../src/macros/ui/element";
import { Host, HostNode, mockNode, mockHost, render } from "../../src/render/host";
import { NeonNode } from "../../src/render/hostTypes";
import { Void } from "../../src/components/primitives";
import { Scene3D, Scene3DHandle, Mesh, createMaterial } from "../../src/components/scene3d";
import { MeshData, addBox } from "../../../void/src/void3d/meshData";
import { DrawContext, MaterialId, addTexture, releaseTexture } from "../../../void/src/void3d/draw";
import {
	UNLIT_MATERIAL_COLOR, MOVING_UV_SCROLL, EMISSIVE_STRENGTH, movingBase, emissiveBase,
} from "../../../void/src/void3d/gpu3d";
import { TextureId, NO_TEXTURE } from "../../../void/src/void3d/texture";
import { FilterMode, Wrap } from "../../../void/src/gpu/state";
import { Color, Vec2, rgba } from "../../../void/src/void2d/types";
import { vec3 } from "../../../void/src/math/math3d";
import { gfxSetup } from "../../../void/src/sokol/gpu";
import { beginScreenPass } from "../../../void/src/gpu/target";
import { endPass, commit } from "../../../void/src/gpu/door";

@include("../../../void/src/sokol/bridge.h");
extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;

let handle: Scene3DHandle = null as unknown as Scene3DHandle;
let cleanup: (() => void) | null = null;
let frames: int32 = 0;
let first = NO_TEXTURE;
let second = NO_TEXTURE;
const unlit: Accessor<MaterialId>[] = [];
const glowing: Accessor<MaterialId>[] = [];
const [color, setColor] = createSignal<Color>(rgba(1.0, 1.0, 1.0, 1.0));
const [which, setWhich] = createSignal(0);
const [scroll, setScroll] = createSignal<Vec2>({ x: 0.0, y: 0.0 });
const [intensity, setIntensity] = createSignal<float32>(1.0);

function fail(message: string): void {
	console.log("FAIL createMaterial device:", message);
	process.exit(1);
}

function uniformAt(material: MaterialId, at: int32): float32 {
	const context = handle.context;
	const block = context.materials[material.index].uniforms;
	return context.uniforms.values[block.offset + at];
}

function whiteTexture(context: DrawContext): TextureId {
	const made = addTexture(context, {
		pixels: [0xFFFFFFFF], width: 1, height: 1, filter: FilterMode.Nearest, wrap: Wrap.Repeat,
	});
	if (!made.ok) { fail("addTexture: " + made.error.toString()); unreachable; }
	return made.value;
}

function cube(): MeshData {
	let data = MeshData.empty();
	const made = addBox(data, { base: vec3(0.0, 0.0, 0.0), size: vec3(1.0, 1.0, 1.0), yaw: 0.0, tilt: 0.0,
		color: { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 } });
	if (!made.ok) { fail("addBox"); unreachable; }
	return data;
}

const shape = cube();

const painted: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
	const plain = createMaterial({
		unlit: accessor((): boolean => true),
		texture: accessor((): TextureId => which() === 0 ? first : second),
		color: accessor((): Color => color()),
		uvScroll: accessor((): Vec2 => scroll()),
	});
	unlit.push(plain);
	const glow = createMaterial({
		texture: accessor((): TextureId => first),
		emissiveTexture: accessor((): TextureId => second),
		emissive: accessor((): Color => rgba(1.0, 0.5, 0.0, 1.0)),
		emissiveIntensity: accessor((): float32 => intensity()),
	});
	glowing.push(glow);
	element(<>
		<Mesh geometry={shape} material={plain()} />
		<Mesh geometry={shape} material={glow()} position={vec3(2.0, 0.0, 0.0)} />
	</>)(host, parent, before);
};

function init(): void {
	gfxSetup();
	cleanup = render(element(<Void><Scene3D ref={(value: Scene3DHandle): void => {
		handle = value;
		first = whiteTexture(value.context);
		second = whiteTexture(value.context);
	}}>{painted}</Scene3D></Void>), mockHost(), mockNode("root") as unknown as HostNode);
}

function frame(): void {
	const context = handle.context;
	if (frames === 0) {
		const material = unlit[0]();
		if (context.materials[material.index].texture !== first) { fail("unlit texture"); return; }
		if (!context.materials[material.index].program.uvTransform) { fail("uvScroll keys a uv transform"); return; }
		setColor(rgba(0.25, 0.5, 0.75, 1.0));
		setScroll({ x: 0.5, y: 0.0 });
		setIntensity(3.0);
		flush();
		if (unlit[0]() !== material) { fail("a value change made a new material"); return; }
		if (uniformAt(material, UNLIT_MATERIAL_COLOR + 2) !== 0.75) { fail("unlit colour in place"); return; }
		const key = context.materials[material.index].program;
		if (uniformAt(material, movingBase(key) + MOVING_UV_SCROLL) !== 0.5) { fail("uv scroll in place"); return; }
		const glow = glowing[0]();
		const glowKey = context.materials[glow.index].program;
		if (!glowKey.emissive) { fail("emissiveTexture keys emissive"); return; }
		if (uniformAt(glow, emissiveBase(glowKey) + EMISSIVE_STRENGTH) !== 3.0) { fail("emissive strength in place"); return; }
	}
	if (frames === 1) {
		const material = unlit[0]();
		setWhich(1);
		flush();
		const next = unlit[0]();
		if (next === material || context.hasMaterial(material)) { fail("a texture change swaps and releases"); return; }
		if (context.materials[next.index].texture !== second) { fail("new texture"); return; }
		if (uniformAt(next, UNLIT_MATERIAL_COLOR + 1) !== 0.5) { fail("values carry to the new material"); return; }
		if (context.texturePins[first.index] !== 1) { fail("first texture pinned by the glow material only"); return; }
	}
	beginScreenPass({ x: 0.02, y: 0.04, z: 0.1, w: 1.0 });
	endPass(); commit();
	frames += 1;
	if (frames === 3) {
		if (!releaseTexture(context, first).ok || !releaseTexture(context, second).ok) { fail("release textures"); return; }
		const dispose = cleanup;
		if (dispose !== null) { dispose(); }
		if (!context.closed) { fail("context left open"); return; }
		console.log("PASS createMaterial device: unlit colour, uv scroll and emissive strength written in place; texture change swaps and releases");
		process.exit(0);
	}
}

voidRun(320, 240, init, frame);
