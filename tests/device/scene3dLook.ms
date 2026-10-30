// A Scene3D layer with hdr, bloom and a directional shadow submits frames on the GPU.
//   msc run tests/device/scene3dLook.ms
// Exits 0 once the layer drew with one caster and bloom mips, dropped the shadow map when
// castShadow turned off, and gave every GPU object back on unmount. Pixels are not checked.

import { createSignal } from "../../src/core/signal";
import { flush } from "../../src/core/runtime";
import { useManualFrames } from "../../src/animation/frame";
import { element } from "../../src/macros/ui/element";
import { HostNode, MockNode, mockNode, mockHost, render, mockAreaHub } from "../../src/render/host";
import { Void } from "../../src/components/primitives";
import { Scene3D, Scene3DHandle, Light, Mesh, Camera3D } from "../../src/components/scene3d";
import { LightKind } from "../../../void/src/void3d/scene";
import { MeshData, Rgba, empty, withUvs, addQuad, addTexturedQuad } from "../../../void/src/void3d/meshData";
import { Material, Phase, movingDefaults } from "../../../void/src/void3d/material";
import { Program, ProgramKey, MATERIAL_UNIFORM_SLOT, UNLIT_MATERIAL_COLOR, MOVING_UV_SCROLL, movingBase, withUvTransform } from "../../../void/src/void3d/gpu3d";
import { TextureId, NO_TEXTURE } from "../../../void/src/void3d/texture";
import { MeshId, MaterialId, NO_MESH, NO_MATERIAL, addMeshData, addMaterial, addTexture, releaseMesh, releaseMaterial, releaseTexture, reserveUniforms, writeUniforms } from "../../../void/src/void3d/draw";
import { RenderState, FilterMode, Wrap } from "../../../void/src/gpu/state";
import { BloomSettings, natural } from "../../../void/src/void3d/bloom";
import { vec3, quatBetween } from "../../../void/src/math/math3d";
import { gfxSetup, fbWidth, fbHeight } from "../../../void/src/host/gpu";
import { beginScreenPass } from "../../../void/src/gpu/target";
import { endPass, commit, liveImages, liveViews } from "../../../void/src/gpu/door";

@include("../../../void/src/host/bridge.h");
extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;

const clock = useManualFrames();
let handle: Scene3DHandle = null as unknown as Scene3DHandle;
let root: MockNode = mockNode("root");
let cleanup: (() => void) | null = null;
let frames: int32 = 0;
let baseImages: int32 = 0;
let baseViews: int32 = 0;
const [cast, setCast] = createSignal(true);

function fail(message: string): void {
	console.log("FAIL Scene3D look device:", message);
	process.exit(1);
}

function quad(half: float32, y: float32): MeshData {
	let data = MeshData.empty();
	const white: Rgba = { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 };
	const added = addQuad(data,
		vec3(-half, y, half), vec3(half, y, half), vec3(half, y, -half), vec3(-half, y, -half),
		vec3(0.0, 1.0, 0.0), white);
	if (!added.ok) { fail("quad"); }
	return data;
}

const floor = quad(3.0, 0.0);
const caster = quad(0.8, 1.0);
let scrollMesh: MeshId = NO_MESH;
let scrollMaterial: MaterialId = NO_MATERIAL;
let scrollTexture: TextureId = NO_TEXTURE;
let requests: int32 = 0;

function frameRequests(): int32 {
	let count: int32 = 0;
	for (const attr of root.children[0].attrs) {
		if (attr.name === "frameRequested") { count += 1; }
	}
	return count;
}

function scrolling(value: Scene3DHandle): void {
	const context = value.context;
	const texture = addTexture(context, { pixels: [0xFF0000FF, 0xFF00FF00], width: 2, height: 1, filter: FilterMode.Nearest, wrap: Wrap.Repeat });
	if (!texture.ok) { fail("scroll texture"); return; }
	scrollTexture = texture.value;
	const key = ProgramKey.of(Program.UnlitTextured).withUvTransform();
	let values = movingDefaults(key);
	for (let i = 0; i < 4; i++) { values[UNLIT_MATERIAL_COLOR + i] = 1.0; }
	values[movingBase(key) + MOVING_UV_SCROLL] = 0.5;
	const block = reserveUniforms(context, MATERIAL_UNIFORM_SLOT, values.length as int32);
	if (!block.ok || !writeUniforms(context, block.value, values).ok) { fail("scroll block"); return; }
	const material = addMaterial(context, {
		...Material.keyed(key, RenderState.defaults(), Phase.Opaque), uniforms: block.value, texture: texture.value,
	});
	if (!material.ok) { fail("scroll material"); return; }
	let data = MeshData.withUvs();
	const white: Rgba = { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 };
	const built = addTexturedQuad(data, vec3(-0.5, 2.0, 0.0), vec3(0.5, 2.0, 0.0), vec3(0.5, 3.0, 0.0),
		vec3(-0.5, 3.0, 0.0), vec3(0.0, 0.0, 1.0), white);
	if (!built.ok) { fail("scroll quad"); return; }
	const mesh = addMeshData(context, data);
	if (!mesh.ok) { fail("scroll mesh"); return; }
	scrollMesh = mesh.value;
	scrollMaterial = material.value;
}

function init(): void {
	gfxSetup();
	baseImages = liveImages(); baseViews = liveViews();
	cleanup = render(element(<Void><Scene3D hdr={true} bloom={BloomSettings.natural()} exposure={1.5}
		ambient={vec3(0.2, 0.2, 0.2)} ref={(value: Scene3DHandle): void => { handle = value; scrolling(value); }}>
		<Camera3D active={true} position={vec3(0.0, 4.0, 6.0)} />
		<Light kind={LightKind.Directional} castShadow={cast()} shadowMapSize={1024}
			rotation={quatBetween(vec3(0.0, 0.0, 1.0), vec3(0.0, -1.0, 0.0))} />
		<Mesh geometry={floor} receiveShadow={true} />
		<Mesh geometry={caster} castShadow={true} />
		<Mesh mesh={scrollMesh} material={scrollMaterial} />
	</Scene3D></Void>), mockHost(), root as unknown as HostNode);
}

function frame(): void {
	clock.advance(16.0);
	const layers = mockAreaHub(root.children[0]).layers();
	if (layers.length !== 1) { fail("one Scene3D layer"); return; }
	layers[0].prepare(fbWidth(), fbHeight());
	beginScreenPass({ x: 0.1, y: 0.1, z: 0.1, w: 1.0 });
	layers[0].draw();
	endPass(); commit();
	const renderer = handle.renderer;
	const toneMap = renderer.toneMap;
	if (toneMap === null || toneMap.bloom.mips.length === 0) { fail("hdr bloom mips"); return; }
	if (frames < 4) {
		const shadow = renderer.core.shadow;
		if (shadow === null || shadow.casterCount !== 1) { fail("one shadow caster"); return; }
	}
	if (frames > 0 && frameRequests() <= requests) { fail("a scrolling material keeps the area awake"); return; }
	requests = frameRequests();
	if (frames > 1 && !(renderer.core.readsTime && renderer.core.time > 0.0)) { fail("Scene3D feeds frame time to a scrolling material"); return; }
	if (frames === 4) { setCast(false); flush(); }
	if (frames > 4 && renderer.core.shadow !== null) { fail("castShadow off keeps the map"); return; }
	frames += 1;
	if (frames === 8) {
		const context = handle.context;
		if (!releaseMesh(context, scrollMesh).ok || !releaseMaterial(context, scrollMaterial).ok ||
			!releaseTexture(context, scrollTexture).ok) { fail("release scroll fixture"); return; }
		const dispose = cleanup;
		if (dispose !== null) { dispose(); }
		if (!renderer.closed || !handle.context.closed || liveImages() !== baseImages || liveViews() !== baseViews) {
			fail("GPU objects outlive the Scene3D"); return;
		}
		console.log("PASS Scene3D look device: 8 frames, hdr + bloom, 1 shadow caster, uv scroll time, shadow off, closed GPU resources");
		process.exit(0);
	}
}

voidRun(320, 240, init, frame);
