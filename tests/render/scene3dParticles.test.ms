import { accessor, createSignal } from "../../src/core/signal";
import { flush, resetErrorHalt } from "../../src/core/runtime";
import { createRoot } from "../../src/core/owner";
import { element } from "../../src/macros/ui/element";
import { Show } from "../../src/macros/ui/flow";
import { HostNode, mockNode, mockHost, render } from "../../src/render/host";
import { Void } from "../../src/components/primitives";
import { Scene3D, Scene3DHandle, Particles } from "../../src/components/scene3d";
import { DrawContext, MaterialId, NO_MATERIAL, addMaterial, releaseMaterial } from "../../../void/src/void3d/draw";
import { Material, MaterialKind } from "../../../void/src/void3d/material";
import { Program, VertexLayout } from "../../../void/src/void3d/gpu3d";
import { EmitterState, defaults } from "../../../void/src/void3d/particles";
import { NodeId3D } from "../../../void/src/void3d/scene";
import { useManualFrames, setFrameDriver, framePending } from "../../src/animation/frame";

function particleMaterial(context: DrawContext): MaterialId {
	const made = addMaterial(context, Material.ofKind(Program.Particle, MaterialKind.Add));
	if (!made.ok) { throw new Error("fixture: addMaterial: " + made.error.toString()); }
	return made.value;
}

function settings(maxParts: int32): EmitterState {
	return { ...EmitterState.defaults(), maxParts: maxParts };
}

test "Particles mount a stream that has no GPU buffer before a frame and free it on unmount" {
	const refs: Scene3DHandle[] = [];
	const nodes: NodeId3D[] = [];
	let material = NO_MATERIAL;
	const [shown, setShown] = createSignal(true);
	const [capacity, setCapacity] = createSignal<int32>(64);
	render(element(<Void>
		<Scene3D ref={(value: Scene3DHandle): void => { refs.push(value); material = particleMaterial(value.context); }}>
			{Show({ when: accessor(() => shown()), children: element(
				<Particles settings={settings(capacity())} material={material}
					ref={(value: NodeId3D): void => { nodes.push(value); }} />
			) })}
		</Scene3D>
	</Void>), mockHost(), mockNode("root") as unknown as HostNode);
	const handle = refs[0];
	const baseline = handle.context.liveMeshes();
	const meshOf = (): int32 => handle.scene.meshes[handle.scene.nodes[nodes[0].index].payload].mesh.index;
	assert handle.context.meshes[meshOf()].layout === VertexLayout.Particle, "a plain emitter streams Particle instances";
	assert handle.context.meshes[meshOf()].instanceCapacity === 64 && handle.context.meshes[meshOf()].instanceBuffer === 0, "capacity is maxParts, no buffer yet";
	setCapacity(128);
	flush();
	assert handle.context.meshes[meshOf()].instanceCapacity === 128 && handle.context.liveMeshes() === baseline, "a new capacity replaces the stream";
	setShown(false);
	flush();
	assert !handle.scene.isLive(nodes[0]) && handle.context.liveMeshes() === baseline - 1, "unmount frees the node and its stream";
	const released = releaseMaterial(handle.context, material);
	assert released.ok;
}

test "Particles refuse settings the emitter refuses, naming the error" {
	let message = "";
	createRoot((dispose: () => void): void => {
		try {
			element(<Void><Scene3D ref={(value: Scene3DHandle): void => {}}>
				<Particles settings={settings(0)} material={NO_MATERIAL} />
			</Scene3D></Void>)(mockHost(), mockNode("root") as unknown as HostNode, null);
		} catch (error) { message = error.toString(); } finally { dispose(); resetErrorHalt(); }
	});
	assert message.includes("Particles") && message.includes("NoCapacity"), "names the emitter error: " + message;
}

test "an emitting Particles keeps the area clock ticking and its unmount lets the clock sleep" {
	const frames = useManualFrames();
	let handle: Scene3DHandle | null = null;
	let material = NO_MATERIAL;
	const [shown, setShown] = createSignal(true);
	const dispose = render(element(<Void>
		<Scene3D ref={(value: Scene3DHandle): void => { handle = value; material = particleMaterial(value.context); }}>
			{Show({ when: accessor(() => shown()), children: element(<Particles settings={settings(16)} material={material} />) })}
		</Scene3D>
	</Void>), mockHost(), mockNode("root") as unknown as HostNode);
	try {
		assert framePending(), "an emitter ticks on the area clock";
		frames.advance(16);
		assert framePending(), "and keeps ticking while it emits";
		setShown(false);
		flush();
		assert !framePending(), "nothing left to emit, nothing scheduled";
	} finally {
		setShown(false);
		flush();
		releaseMaterial((handle as Scene3DHandle).context, material);
		dispose();
		setFrameDriver(null);
	}
}
