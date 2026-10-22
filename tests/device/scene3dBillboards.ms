// Billboards own their instance buffer on the GPU: growth, replace, remount and unmount.
//   msc run tests/device/scene3dBillboards.ms
import { createSignal, accessor } from "../../src/core/signal";
import { flush } from "../../src/core/runtime";
import { element } from "../../src/macros/ui/element";
import { Show } from "../../src/macros/ui/flow";
import { HostNode, MockNode, mockNode, mockHost, render, mockAreaHub } from "../../src/render/host";
import { Void } from "../../src/components/primitives";
import { Scene3D, Scene3DHandle, Billboards, Camera3D } from "../../src/components/scene3d";
import { BillboardInstance, ANCHOR_CENTER } from "../../../void/src/void3d/billboard";
import { NodeId3D } from "../../../void/src/void3d/scene";
import { DrawContext, MaterialId, addMaterial, releaseMaterial, addTexture, releaseTexture, reserveUniforms, writeUniforms } from "../../../void/src/void3d/draw";
import { Material, MaterialKind } from "../../../void/src/void3d/material";
import { Program, BILLBOARD_UNIFORM_SLOT, BILLBOARD_UNIFORM_LENGTH } from "../../../void/src/void3d/gpu3d";
import { FilterMode, Wrap } from "../../../void/src/gpu/state";
import { vec3 } from "../../../void/src/math/math3d";
import { gfxSetup, fbWidth, fbHeight } from "../../../void/src/sokol/gpu";
import { beginScreenPass } from "../../../void/src/gpu/target";
import { endPass, commit, liveBuffers } from "../../../void/src/gpu/door";

@include("../../../void/src/sokol/bridge.h");
extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;

const root: MockNode = mockNode("root");
let handle: Scene3DHandle = null as unknown as Scene3DHandle;
let material: MaterialId = { store: 0, index: 0, generation: 0 };
let cleanup: (() => void) | null = null;
let frames: int32 = 0;
let base: int32 = 0;
let steady: int32 = 0;
const nodes: NodeId3D[] = [];
const [list, setList] = createSignal<BillboardInstance[]>([instance(-1.0), instance(1.0)]);
const [shown, setShown] = createSignal(true);

function fail(message: string): void {
	console.log("FAIL Billboards device:", message);
	process.exit(1);
}

function instance(x: float32): BillboardInstance {
	return {
		position: vec3(x, 0.0, 0.0), width: 0.5, height: 0.5, anchor: ANCHOR_CENTER,
		tile: { u: 0.0, v: 0.0, u2: 1.0, v2: 1.0 },
		color: { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 },
	};
}

function billboardMaterial(context: DrawContext): MaterialId {
	const texels: Vec<uint32> = [0xFFFFFFFF];
	const texture = addTexture(context, { pixels: texels, width: 1, height: 1, filter: FilterMode.Nearest, wrap: Wrap.Clamp });
	if (!texture.ok) { fail("texture"); unreachable; }
	const block = reserveUniforms(context, BILLBOARD_UNIFORM_SLOT, BILLBOARD_UNIFORM_LENGTH);
	if (!block.ok) { fail("uniform block"); unreachable; }
	const uniforms: Vec<float32> = [1.0, 1.0, 1.0, 1.0, 4.0, 0.0, 0.25, 0.0];
	if (!writeUniforms(context, block.value, uniforms).ok) { fail("uniform write"); }
	const made = addMaterial(context, { ...Material.ofKind(Program.Billboard, MaterialKind.Alpha), texture: texture.value, uniforms: block.value });
	if (!made.ok) { fail("material " + made.error.toString()); unreachable; }
	if (!releaseTexture(context, texture.value).ok) { fail("texture lease"); }
	return made.value;
}

function shownBuffer(): uint32 {
	const row = handle.scene.nodes[nodes[nodes.length - 1].index].payload;
	return handle.context.meshes[handle.scene.meshes[row].mesh.index].instanceBuffer;
}

function shownCount(): int32 {
	const row = handle.scene.nodes[nodes[nodes.length - 1].index].payload;
	return handle.context.meshes[handle.scene.meshes[row].mesh.index].instanceCount;
}

function init(): void {
	gfxSetup();
	base = liveBuffers();
	cleanup = render(element(<Void>
		<Scene3D ref={(value: Scene3DHandle): void => { handle = value; material = billboardMaterial(value.context); }}>
			<Camera3D active={true} position={vec3(0.0, 0.0, 5.0)} />
			{Show({ when: accessor(() => shown()), children: element(
				<Billboards instances={list()} material={material}
					ref={(value: NodeId3D): void => { nodes.push(value); }} />
			) })}
		</Scene3D>
	</Void>), mockHost(), root as unknown as HostNode);
}

function drawFrame(): void {
	const layers = mockAreaHub(root.children[0]).layers();
	for (const layer of layers) { layer.prepare(fbWidth(), fbHeight()); }
	beginScreenPass({ x: 0.0, y: 0.0, z: 0.0, w: 1.0 });
	for (const layer of layers) { layer.draw(); }
	endPass();
	commit();
}

function frame(): void {
	drawFrame();
	const parked = frames === 6 || frames === 7;
	const buffer: uint32 = parked ? 0 : shownBuffer();
	const count: int32 = parked ? 0 : shownCount();
	if (frames === 0) {
		if (buffer === 0 || count !== 2) { fail("first frame uploads 2 instances: " + count.toString()); return; }
		steady = liveBuffers();
		setList([instance(-2.0), instance(2.0)]);
		flush();
	}
	if (frames === 1) {
		if (count !== 2 || liveBuffers() !== steady) { fail("same count updates in place"); return; }
		setList([instance(-2.0), instance(-1.0), instance(0.0), instance(1.0), instance(2.0)]);
		flush();
	}
	if (frames === 2) {
		if (count !== 5 || liveBuffers() !== steady) { fail("growth replaces the buffer without a leak: " + liveBuffers().toString() + " vs " + steady.toString()); return; }
		setList([]);
		flush();
	}
	if (frames === 3) {
		if (count !== 0 || buffer === 0 || liveBuffers() !== steady) { fail("an empty list keeps the buffer and draws nothing"); return; }
		setList([instance(0.0)]);
		flush();
	}
	if (frames === 4) {
		if (count !== 1 || liveBuffers() !== steady) { fail("refill reuses the buffer"); return; }
	}
	if (frames === 5) {
		setShown(false);
		flush();
		if (liveBuffers() !== steady - 1) { fail("unmount destroys the buffer: " + liveBuffers().toString() + " vs " + steady.toString()); return; }
	}
	if (frames === 7) {
		setShown(true);
		flush();
	}
	if (frames === 8) {
		if (count !== 1 || liveBuffers() !== steady) { fail("remount owns exactly one buffer again"); return; }
	}
	frames += 1;
	if (frames === 10) {
		if (!releaseMaterial(handle.context, material).ok) { fail("material lease"); return; }
		const dispose = cleanup;
		if (dispose !== null) { dispose(); }
		if (!handle.context.closed || liveBuffers() !== base) { fail("terminal buffers " + liveBuffers().toString() + " vs " + base.toString()); return; }
		console.log("PASS Billboards device: grow, replace, empty, remount, unmount; buffers back to " + base.toString());
		process.exit(0);
	}
}

voidRun(320, 240, init, frame);
