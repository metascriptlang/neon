// Particles emit only while mounted and playing, ask for frames only while particles live or
// emit, sleep when idle, and give their stream buffer back on unmount.
//   msc run tests/device/scene3dParticles.ms
import { createSignal, accessor } from "../../src/core/signal";
import { flush } from "../../src/core/runtime";
import { element } from "../../src/macros/ui/element";
import { Show } from "../../src/macros/ui/flow";
import { useManualFrames } from "../../src/animation/frame";
import { HostNode, MockNode, mockNode, mockHost, render, mockAreaHub } from "../../src/render/host";
import { Void } from "../../src/components/primitives";
import { Scene3DHandle } from "../../src/components/scene3d/core";
import { Scene3D } from "../../src/components/scene3d/scene";
import { Camera3D } from "../../src/components/scene3d/camera";
import { Particles } from "../../src/components/scene3d/particles";
import { ParticleSystemAsset, ParticleEffect, defaults } from "../../../void/src/particles/asset";
import { constantCurve } from "../../../void/src/particles/curve";
import { NodeId3D } from "../../../void/src/void3d/scene";
import { MaterialId, addMaterial, releaseMaterial } from "../../../void/src/void3d/draw";
import { Material, MaterialKind } from "../../../void/src/void3d/material";
import { Program } from "../../../void/src/void3d/gpu3d";
import { vec3 } from "../../../void/src/math/math3d";
import { gfxSetup, fbWidth, fbHeight } from "../../../void/src/host/gpu";
import { beginScreenPass } from "../../../void/src/gpu/target";
import { endPass, commit, liveBuffers } from "../../../void/src/gpu/door";

@include("../../../void/src/host/bridge.h");
extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;

const clock = useManualFrames();
const root: MockNode = mockNode("root");
let handle: Scene3DHandle = null as unknown as Scene3DHandle;
let material: MaterialId = { store: 0, index: 0, generation: 0 };
let cleanup: (() => void) | null = null;
let frames: int32 = 0;
let stage: int32 = 0;
let quiet: int32 = 0;
let peak: int32 = 0;
let base: int32 = 0;
let withStream: int32 = 0;
let running: int32 = 0;
let stoppedAt: int32 = -1;
let last: int32 = 0;
const nodes: NodeId3D[] = [];
const [active, setActive] = createSignal(true);
const [shown, setShown] = createSignal(true);

function fail(message: string): void {
	console.log("FAIL Particles device: stage " + stage.toString() + " frame " + frames.toString() + ": " + message);
	process.exit(1);
}

function oneShot(): ParticleEffect {
	const base = ParticleSystemAsset.defaults();
	return { systems: [{
		...base,
		main: { ...base.main, duration: 0.5, loop: false, startLifetime: constantCurve(0.25), maxParticles: 64 },
		emission: { ...base.emission, rateOverTime: constantCurve(40.0) },
	}] };
}

function requests(): int32 {
	let n: int32 = 0;
	for (const a of root.children[0].attrs) {
		if (a.name === "frameRequested") { n += 1; }
	}
	return n;
}

function liveCount(): int32 {
	const row = handle.scene.nodes[handle.scene.nodes[nodes[0].index].children[0]].payload;
	return handle.context.meshes[handle.scene.meshes[row].mesh.index].instanceCount;
}

function init(): void {
	gfxSetup();
	base = liveBuffers();
	cleanup = render(element(<Void>
		<Scene3D ref={(value: Scene3DHandle): void => {
			handle = value;
			const made = addMaterial(value.context, Material.ofKind(Program.Particle, MaterialKind.Add));
			if (!made.ok) { fail("material"); return; }
			material = made.value;
		}}>
			<Camera3D active={true} position={vec3(0.0, 0.0, 5.0)} />
			{Show({ when: accessor(() => shown()), children: element(
				<Particles effect={oneShot()} material={material} playing={active()}
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

// Stages: 0 a one-shot emits then sleeps; 1 reactivation restarts it; 2 deactivation mid-emission
// stops spawning and sleeps once the last particle dies; 3 unmount returns the stream buffer.
function frame(): void {
	const before = requests();
	clock.advance(16.0);
	drawFrame();
	const asked = requests() > before;
	frames += 1;
	if (frames > 600) { fail("did not settle"); return; }
	if (stage === 3) {
		if (liveBuffers() !== withStream - 1) { fail("unmount kept the stream buffer: " + liveBuffers().toString() + " vs " + withStream.toString()); return; }
		if (!releaseMaterial(handle.context, material).ok) { fail("material lease"); return; }
		const dispose = cleanup;
		if (dispose !== null) { dispose(); }
		if (!handle.context.closed || liveBuffers() !== base) { fail("terminal buffers " + liveBuffers().toString()); return; }
		console.log("PASS Particles device: " + frames.toString() + " frames, peak " + peak.toString() + " particles, sleeps when idle, restart, stop, buffers back to " + base.toString());
		process.exit(0);
	}
	const count = liveCount();
	if (stage === 2 && stoppedAt >= 0 && count > last) { fail("a stopped emitter spawned"); return; }
	last = count;
	peak = Math.max(peak, count);
	if (asked) {
		quiet = 0;
		if (stage === 2 && stoppedAt < 0) {
			running += 1;
			if (running === 10) {
				if (count === 0) { fail("restart emitted nothing by frame 10"); return; }
				setActive(false);
				flush();
				stoppedAt = frames;
			}
		}
		return;
	}
	quiet += 1;
	if (count !== 0) { fail("slept with " + count.toString() + " particles alive"); return; }
	if (quiet < 3) { return; }
	if (stage === 0 || stage === 1) {
		if (peak === 0) { fail("emitted nothing before sleeping"); return; }
		withStream = liveBuffers();
		peak = 0;
		setActive(false);
		flush();
		if (requests() !== before) { fail("deactivating an idle emitter woke it"); return; }
		setActive(true);
		flush();
		if (requests() === before) { fail("reactivation did not wake the emitter"); return; }
		stage += 1;
		return;
	}
	if (stoppedAt < 0 || frames - stoppedAt > 30) { fail("deactivation did not let the emitter sleep soon: " + (frames - stoppedAt).toString()); return; }
	setShown(false);
	flush();
	stage = 3;
}

voidRun(320, 240, init, frame);
