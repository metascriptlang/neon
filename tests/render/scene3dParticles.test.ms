import { accessor, createSignal } from "../../src/core/signal";
import { flush, resetErrorHalt } from "../../src/core/runtime";
import { createRoot } from "../../src/core/owner";
import { element } from "../../src/macros/ui/element";
import { Show } from "../../src/macros/ui/flow";
import { HostNode, mockNode, mockHost, render } from "../../src/render/host";
import { Void } from "../../src/components/primitives";
import { Scene3DHandle } from "../../src/components/scene3d/core";
import { Scene3D } from "../../src/components/scene3d/scene";
import { Particles } from "../../src/components/scene3d/particles";
import { DrawContext, MaterialId, NO_MATERIAL, addMaterial, releaseMaterial } from "../../../void/src/void3d/draw";
import { Material, MaterialKind } from "../../../void/src/void3d/material";
import { Program, VertexLayout } from "../../../void/src/void3d/gpu3d";
import { ParticleSystemAsset, ParticleEffect, defaults } from "../../../void/src/particles/asset";
import { NodeId3D } from "../../../void/src/void3d/scene";
import { useManualFrames, setFrameDriver, framePending } from "../../src/animation/frame";

function particleMaterial(context: DrawContext): MaterialId {
	const made = addMaterial(context, Material.ofKind(Program.Particle, MaterialKind.Add));
	if (!made.ok) { throw new Error("fixture: addMaterial: " + made.error.toString()); }
	return made.value;
}

function system(maxParticles: int32): ParticleSystemAsset {
	const base = ParticleSystemAsset.defaults();
	return { ...base, main: { ...base.main, maxParticles: maxParticles } };
}

function effectOf(capacities: int32[]): ParticleEffect {
	let systems: Vec<ParticleSystemAsset> = [];
	for (const capacity of capacities) { systems.push(system(capacity)); }
	return { systems: systems };
}

test "Particles stream each system of the effect, with no GPU buffer before a frame, and free them on unmount" {
	const refs: Scene3DHandle[] = [];
	const nodes: NodeId3D[] = [];
	let material = NO_MATERIAL;
	const [shown, setShown] = createSignal(true);
	const [capacity, setCapacity] = createSignal<int32>(64);
	render(element(<Void>
		<Scene3D ref={(value: Scene3DHandle): void => { refs.push(value); material = particleMaterial(value.context); }}>
			{Show({ when: accessor(() => shown()), children: element(
				<Particles effect={effectOf([capacity(), 32])} material={material}
					ref={(value: NodeId3D): void => { nodes.push(value); }} />
			) })}
		</Scene3D>
	</Void>), mockHost(), mockNode("root") as unknown as HostNode);
	const handle = refs[0];
	const baseline = handle.context.liveMeshes();
	const streamOf = (s: int32): int32 => {
		const row = handle.scene.nodes[nodes[0].index].children[s];
		return handle.scene.meshes[handle.scene.nodes[row].payload].mesh.index;
	};
	assert handle.scene.nodes[nodes[0].index].children.length === 2, "one stream node per system";
	assert handle.context.meshes[streamOf(0)].layout === VertexLayout.Particle, "without frames a system streams Particle points";
	assert handle.context.meshes[streamOf(0)].instanceCapacity === 64 && handle.context.meshes[streamOf(0)].instanceBuffer === 0, "capacity is maxParticles, no buffer yet";
	assert handle.context.meshes[streamOf(1)].instanceCapacity === 32, "each system has its own capacity";
	setCapacity(128);
	flush();
	assert handle.scene.nodes[nodes[0].index].children.length === 2, "a new effect replaces the streams, it does not add to them";
	assert handle.context.meshes[streamOf(0)].instanceCapacity === 128 && handle.context.liveMeshes() === baseline, "the new capacity, the same live mesh count";
	setShown(false);
	flush();
	assert !handle.scene.isLive(nodes[0]) && handle.context.liveMeshes() === baseline - 2, "unmount frees the node and its streams";
	const released = releaseMaterial(handle.context, material);
	assert released.ok;
}

test "Particles refuse an effect Void refuses, naming the error" {
	let message = "";
	createRoot((dispose: () => void): void => {
		try {
			element(<Void><Scene3D ref={(value: Scene3DHandle): void => {}}>
				<Particles effect={effectOf([0])} material={NO_MATERIAL} />
			</Scene3D></Void>)(mockHost(), mockNode("root") as unknown as HostNode, null);
		} catch (error) { message = error.toString(); } finally { dispose(); resetErrorHalt(); }
	});
	assert message.includes("Particles") && message.includes("NoCapacity"), "names the system error: " + message;
}

test "a playing Particles keeps the area clock ticking, pause and unmount let it sleep, and a stopped one never wakes it" {
	const frames = useManualFrames();
	let handle: Scene3DHandle | null = null;
	let material = NO_MATERIAL;
	const [shown, setShown] = createSignal(true);
	const [paused, setPaused] = createSignal(false);
	const [playing, setPlaying] = createSignal(true);
	const dispose = render(element(<Void>
		<Scene3D ref={(value: Scene3DHandle): void => { handle = value; material = particleMaterial(value.context); }}>
			{Show({ when: accessor(() => shown()), children: element(
				<Particles effect={effectOf([16])} material={material} paused={paused()} playing={playing()} />
			) })}
		</Scene3D>
	</Void>), mockHost(), mockNode("root") as unknown as HostNode);
	try {
		assert framePending(), "a playing effect ticks on the area clock";
		frames.advance(16);
		assert framePending(), "and keeps ticking while it plays";
		setPaused(true);
		flush();
		assert !framePending(), "a paused effect asks for no frames";
		setPaused(false);
		flush();
		assert framePending(), "resuming ticks again";
		setShown(false);
		flush();
		assert !framePending(), "nothing left to play, nothing scheduled";
		setPlaying(false);
		setShown(true);
		flush();
		assert !framePending(), "a stopped effect with no particles does not wake the clock";
	} finally {
		setShown(false);
		flush();
		releaseMaterial((handle as Scene3DHandle).context, material);
		dispose();
		setFrameDriver(null);
	}
}
