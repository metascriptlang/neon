// A Decal mounts, writes its block, swaps its material and gives everything back on the GPU.
//   msc run tests/device/scene3dDecal.ms
// Exits 0 once frames prepared and drew with a decal over a floor, a value change wrote the block in
// place, afterToneMap and a new map each swapped the material and released the old one, position
// moved the node, and unmount gave every GPU object back.

import { createSignal, accessor } from "../../src/core/signal";
import { flush } from "../../src/core/runtime";
import { useManualFrames } from "../../src/animation/frame";
import { element } from "../../src/macros/ui/element";
import { Show } from "../../src/macros/ui/flow";
import { Host, HostNode, NeonNode } from "../../src/render/hostTypes";
import { MockNode, mockNode, mockHost, render, mockAreaHub } from "../../src/render/host";
import { Void } from "../../src/components/primitives";
import { Scene3D, Scene3DHandle, Mesh, Camera3D, Decal, DecalNormalFade } from "../../src/components/scene3d";
import { NodeId3D } from "../../../void/src/void3d/scene";
import { MeshData, Rgba, addQuad } from "../../../void/src/void3d/meshData";
import { Phase } from "../../../void/src/void3d/material";
import {
	Program, DECAL_COLOR, DECAL_FADE_START, DECAL_FADE_END, DECAL_FADE_POWER, DECAL_EMISSIVE, DECAL_CENTERED,
	DECAL_GAMMA_CORRECT, DECAL_AUTO_ALPHA, DECAL_TONE_MAPPED, DECAL_NORMAL_FADE_START, DECAL_NORMAL_FADE_END,
	DECAL_NORMAL_FADE,
} from "../../../void/src/void3d/gpu3d";
import { TextureId, NO_TEXTURE } from "../../../void/src/void3d/texture";
import { MaterialId, addTexture, releaseTexture } from "../../../void/src/void3d/draw";
import { FilterMode, Wrap } from "../../../void/src/gpu/state";
import { Color, rgba } from "../../../void/src/void2d/types";
import { vec3 } from "../../../void/src/math/math3d";
import { gfxSetup, fbWidth, fbHeight } from "../../../void/src/sokol/gpu";
import { beginScreenPass } from "../../../void/src/gpu/target";
import { endPass, commit, liveImages, liveViews } from "../../../void/src/gpu/door";

@include("../../../void/src/sokol/bridge.h");
extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;

const clock = useManualFrames();
let handle: Scene3DHandle = null as unknown as Scene3DHandle;
let root: MockNode = mockNode("root");
let cleanup: (() => void) | null = null;
let frames: int32 = 0;
let baseImages: int32 = 0;
let baseViews: int32 = 0;
let mapA: TextureId = NO_TEXTURE;
let mapB: TextureId = NO_TEXTURE;
let node: NodeId3D | null = null;
let previous: MaterialId | null = null;
const [color, setColor] = createSignal<Color>(rgba(0.5, 0.25, 0.75, 0.5));
const [fadeEnd, setFadeEnd] = createSignal<float32>(0.75);
const [after, setAfter] = createSignal<boolean>(false);
const [second, setSecond] = createSignal<boolean>(false);
const [at, setAt] = createSignal(vec3(1.0, 0.0, 0.0));
const [on, setOn] = createSignal<boolean>(true);

function fail(message: string): void {
	console.log("FAIL Scene3D decal device:", message);
	process.exit(1);
}

function floor(): MeshData {
	let data = MeshData.empty();
	const white: Rgba = { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 };
	const added = addQuad(data,
		vec3(-3.0, 0.0, 3.0), vec3(3.0, 0.0, 3.0), vec3(3.0, 0.0, -3.0), vec3(-3.0, 0.0, -3.0),
		vec3(0.0, 1.0, 0.0), white);
	if (!added.ok) { fail("floor"); }
	return data;
}

const ground = floor();

function texture(pixel: uint32): TextureId {
	const made = addTexture(handle.context, { pixels: [pixel], width: 1, height: 1, filter: FilterMode.Nearest, wrap: Wrap.Clamp });
	if (!made.ok) { fail("texture"); return NO_TEXTURE; }
	return made.value;
}

function materialOf(): MaterialId {
	const id = node as NodeId3D;
	return handle.scene.meshes[handle.scene.nodes[id.index].payload].material;
}

function value(material: MaterialId, offset: int32): float32 {
	return handle.context.uniforms.values[handle.context.materials[material.index].uniforms.offset + offset];
}

const painted: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
	Decal({
		map: accessor((): TextureId => second() ? mapB : mapA),
		color: accessor((): Color => color()),
		fadeStart: accessor((): float32 => 0.25),
		fadeEnd: accessor((): float32 => fadeEnd()),
		fadePower: accessor((): float32 => 2.0),
		emissive: accessor((): float32 => 0.5),
		normalFade: accessor((): DecalNormalFade => ({ start: 0.25, end: 0.5 })),
		afterToneMap: accessor((): boolean => after()),
		position: accessor(() => at()),
		scale: accessor(() => vec3(2.0, 2.0, 2.0)),
		ref: (id: NodeId3D): void => { node = id; },
	})(host, parent, before);
};

function init(): void {
	gfxSetup();
	baseImages = liveImages(); baseViews = liveViews();
	cleanup = render(element(<Void><Scene3D ref={(scene: Scene3DHandle): void => {
		handle = scene;
		mapA = texture(0xFFFFFFFF);
		mapB = texture(0xFF0000FF);
	}}>
		<Camera3D active={true} position={vec3(0.0, 3.0, 5.0)} />
		<Mesh geometry={ground} />
		{Show({ when: accessor(() => on()), children: painted })}
	</Scene3D></Void>), mockHost(), root as unknown as HostNode);
}

function checkFirst(): boolean {
	const material = materialOf();
	const used = handle.context.materials[material.index];
	if (used.program.program !== Program.Decal || used.phase !== Phase.Decal) { fail("decal program in the Decal phase"); return false; }
	if (value(material, DECAL_COLOR) !== 0.5 || value(material, DECAL_COLOR + 1) !== 0.25 ||
		value(material, DECAL_COLOR + 2) !== 0.75 || value(material, DECAL_COLOR + 3) !== 0.5) { fail("color block"); return false; }
	if (value(material, DECAL_FADE_START) !== 0.25 || value(material, DECAL_FADE_END) !== 0.75 ||
		value(material, DECAL_FADE_POWER) !== 2.0 || value(material, DECAL_EMISSIVE) !== 0.5) { fail("fade and emissive block"); return false; }
	if (value(material, DECAL_NORMAL_FADE) !== 1.0 || value(material, DECAL_NORMAL_FADE_START) !== 0.25 ||
		value(material, DECAL_NORMAL_FADE_END) !== 0.5) { fail("normal fade block"); return false; }
	if (value(material, DECAL_CENTERED) !== 1.0 || value(material, DECAL_GAMMA_CORRECT) !== 0.0 ||
		value(material, DECAL_AUTO_ALPHA) !== 1.0 || value(material, DECAL_TONE_MAPPED) !== 1.0) { fail("flags block"); return false; }
	if (used.texture.index !== mapA.index) { fail("map is the material texture"); return false; }
	if (handle.scene.nodes[(node as NodeId3D).index].local.scale.z !== 2.0) { fail("scale places the box"); return false; }
	previous = material;
	return true;
}

function frame(): void {
	clock.advance(16.0);
	const layers = mockAreaHub(root.children[0]).layers();
	if (layers.length !== 1) { fail("one Scene3D layer"); return; }
	layers[0].prepare(fbWidth(), fbHeight());
	beginScreenPass({ x: 0.1, y: 0.1, z: 0.1, w: 1.0 });
	layers[0].draw();
	endPass(); commit();
	const context = handle.context;
	if (frames === 0) {
		if (!checkFirst()) { return; }
		setColor(rgba(0.5, 1.0, 0.25, 1.0)); setFadeEnd(0.5); flush();
	} else if (frames === 1) {
		const material = materialOf();
		if (material !== previous) { fail("a value change keeps the material"); return; }
		if (value(material, DECAL_COLOR + 1) !== 1.0 || value(material, DECAL_FADE_END) !== 0.5) { fail("values written in place"); return; }
		setAfter(true); flush();
	} else if (frames === 2) {
		const material = materialOf();
		if (material === previous || context.hasMaterial(previous as MaterialId)) { fail("afterToneMap swaps and releases the old material"); return; }
		if (context.materials[material.index].phase !== Phase.DecalAfterToneMap || value(material, DECAL_TONE_MAPPED) !== 0.0) { fail("after-tone-map phase and flag"); return; }
		if (value(material, DECAL_COLOR + 1) !== 1.0) { fail("values carry to the new material"); return; }
		previous = material;
		setSecond(true); flush();
	} else if (frames === 3) {
		const material = materialOf();
		if (material === previous || context.hasMaterial(previous as MaterialId)) { fail("a new map swaps and releases the old material"); return; }
		if (context.materials[material.index].texture.index !== mapB.index) { fail("the new map is the material texture"); return; }
		previous = material;
		setAt(vec3(0.0, 4.0, 0.0)); flush();
	} else if (frames === 4) {
		if (handle.scene.nodes[(node as NodeId3D).index].local.position.y !== 4.0) { fail("position moves the node"); return; }
		setOn(false); flush();
	} else {
		if (handle.scene.isLive(node as NodeId3D) || context.hasMaterial(previous as MaterialId)) { fail("unmount removes the node and the material"); return; }
		if (!releaseTexture(context, mapA).ok || !releaseTexture(context, mapB).ok) { fail("release textures"); return; }
		const renderer = handle.renderer;
		const dispose = cleanup;
		if (dispose !== null) { dispose(); }
		if (!renderer.closed || !context.closed || liveImages() !== baseImages || liveViews() !== baseViews) {
			fail("GPU objects outlive the Scene3D"); return;
		}
		console.log("PASS Scene3D decal device: 6 frames, block values, in-place write, pass and map swaps, unmount, closed GPU resources");
		process.exit(0);
	}
	frames += 1;
}

voidRun(320, 240, init, frame);
