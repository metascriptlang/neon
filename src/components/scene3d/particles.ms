import { Accessor, untrack } from "../../core/signal";
import { createRenderEffect } from "../../core/effect";
import { Cleanup } from "../../core/types";
import { Host, HostNode, NeonNode } from "../../render/hostTypes";
import { frameNow } from "../../animation/frame";
import { VertexLayout } from "../../../../void/src/void3d/gpu3d";
import { GpuMesh, MeshId, MaterialId, addMesh, streamMesh, writeStream, releaseMesh } from "../../../../void/src/void3d/draw";
import {
	ParticleEmitter, EmitterState, Turbulence, constant, create, isActive, clearParticles, updateEmitter,
	writeSortedInstances, writeVisualInstances, PARTICLE_INSTANCE_STRIDE, PARTICLE_VISUAL_INSTANCE_STRIDE,
} from "../../../../void/src/void3d/particles";
import { ParticleVisualFrame } from "../../../../void/src/void3d/particleVisual";
import { Anchor } from "../../../../void/src/void3d/billboard";
import { addMeshNode, setMeshOf, setMaterialOf, worldOf } from "../../../../void/src/void3d/scene";
import { CameraView } from "../../../../void/src/void3d/camera";
import { NodeProps, SceneState, mountOwned, requireScene, localOf, bindNode, ownNode, mountNodeChildren, onBeforeRefresh } from "./core";

export interface ParticleVisualSettings {
	frames: Vec<ParticleVisualFrame>;
	anchor: Anchor;
}

export interface ParticlesProps extends NodeProps {
	settings: Accessor<EmitterState>;
	material: Accessor<MaterialId>;
	noise?: Accessor<Turbulence> | null;
	visual?: Accessor<ParticleVisualSettings> | null;
	active?: Accessor<boolean> | null;
	seed?: Accessor<uint32> | null;
}

const DEFAULT_SEED: uint32 = 2463534242;

// The emitter's clock in seconds; the shared area clock replaces this one function.
function sceneSeconds(): float64 {
	return frameNow() / 1000.0;
}

function streamOf(state: SceneState, capacity: int32, layout: VertexLayout): MeshId {
	const added = addMesh(state.handle.context, GpuMesh.streamMesh(capacity, 0, 0, layout));
	if (!added.ok) { throw new Error("Particles: addMesh failed: " + added.error.toString()); }
	return added.value;
}

function emitted(settings: EmitterState, noise: Turbulence | null, active: boolean): EmitterState {
	const shaped: EmitterState = noise === null ? settings : { ...settings, turbulence: noise as Turbulence };
	const quiet: EmitterState = active ? shaped : { ...shaped, emitRate: constant(0.0), bursts: [] };
	return quiet;
}

export function Particles(props: ParticlesProps): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		const scope = requireScene("Particles");
		mountOwned((): void => {
			const state = scope.state;
			const scene = state.handle.scene;
			const context = state.handle.context;
			const local = localOf(props);
			const visual = props.visual !== null;
			const layout = visual ? VertexLayout.ParticleVisual : VertexLayout.Particle;
			const stride = visual ? PARTICLE_VISUAL_INSTANCE_STRIDE : PARTICLE_INSTANCE_STRIDE;
			const readSeed = (): uint32 => props.seed === null ? DEFAULT_SEED : (props.seed as () => uint32)();
			const readNoise = (): Turbulence | null => props.noise === null ? null : (props.noise as () => Turbulence)();
			const readActive = (): boolean => props.active === null ? true : (props.active as () => boolean)();
			let active = untrack(readActive);
			let seed = untrack(readSeed);
			const made = ParticleEmitter.create(emitted(untrack(() => props.settings()), untrack(readNoise), active), seed);
			if (!made.ok) { throw new Error("Particles: ParticleEmitter.create failed: " + made.error.toString()); }
			let emitter = made.value;
			let instances: Vec<float32> = new Array(emitter.capacity * stride);
			let material = untrack(() => props.material());
			let stream = streamOf(state, emitter.capacity, layout);
			const added = addMeshNode(scene, scope.parent, local, stream, material);
			const released = releaseMesh(context, stream);
			if (!added.ok) { throw new Error("Particles: addMeshNode failed: " + added.error.toString()); }
			if (!released.ok) { throw new Error("Particles: releaseMesh failed: " + released.error.toString()); }
			const node = added.value;
			ownNode(state, node);
			let visualSettings: ParticleVisualSettings | null = null;
			let awake = true;
			let last: float64 = -1.0;
			const wake = (): void => {
				if (awake || !(emitter.count > 0 || (active && emitter.isActive()))) { return; }
				awake = true;
				last = -1.0;
				state.invalidate();
			};
			createRenderEffect<[EmitterState, Turbulence | null, boolean, uint32]>(
				(prev: [EmitterState, Turbulence | null, boolean, uint32] | null): [EmitterState, Turbulence | null, boolean, uint32] =>
					[props.settings(), readNoise(), readActive(), readSeed()],
				(value: [EmitterState, Turbulence | null, boolean, uint32], prev: [EmitterState, Turbulence | null, boolean, uint32] | null): Cleanup | null => {
					if (prev === null) { return null; }
					const next = emitted(value[0], value[1], value[2]);
					if (!(next.globalLife > 0.0)) { throw new Error("Particles: settings.globalLife must be positive"); }
					const restarted = value[2] && !active && emitter.count === 0 && !emitter.isActive();
					active = value[2];
					if (value[3] !== seed || next.maxParts !== emitter.capacity) {
						const remade = ParticleEmitter.create(next, value[3]);
						if (!remade.ok) { throw new Error("Particles: ParticleEmitter.create failed: " + remade.error.toString()); }
						if (remade.value.capacity !== emitter.capacity) {
							const resized = streamOf(state, remade.value.capacity, layout);
							const swapped = setMeshOf(scene, node, resized);
							const releasedStream = releaseMesh(context, resized);
							if (!swapped.ok) { throw new Error("Particles: setMeshOf failed: " + swapped.error.toString()); }
							if (!releasedStream.ok) { throw new Error("Particles: releaseMesh failed: " + releasedStream.error.toString()); }
							stream = resized;
							instances = new Array(remade.value.capacity * stride);
						}
						emitter = remade.value;
						seed = value[3];
					} else {
						emitter.state = next;
						if (restarted) { clearParticles(emitter); }
					}
					wake();
					return null;
				},
			);
			if (visual) {
				createRenderEffect<ParticleVisualSettings>(
					(prev: ParticleVisualSettings | null): ParticleVisualSettings => (props.visual as () => ParticleVisualSettings)(),
					(value: ParticleVisualSettings, prev: ParticleVisualSettings | null): Cleanup | null => {
						visualSettings = value;
						state.invalidate();
						return null;
					},
				);
			}
			createRenderEffect<MaterialId>(
				(prev: MaterialId | null): MaterialId => props.material(),
				(value: MaterialId, prev: MaterialId | null): Cleanup | null => {
					if (value !== material) {
						const changed = setMaterialOf(scene, node, value);
						if (!changed.ok) { throw new Error("Particles: setMaterialOf failed: " + changed.error.toString()); }
						material = value;
						state.invalidate();
					}
					return null;
				},
			);
			onBeforeRefresh(state, (view: CameraView): void => {
				if (!awake) { return; }
				const world = worldOf(scene, node);
				if (!world.ok) { return; }
				const now = sceneSeconds();
				const step = last < 0.0 ? 0.0 : Math.max(0.0, now - last);
				last = now;
				const updated = updateEmitter(emitter, step, world.value);
				if (!updated.ok) { throw new Error("Particles: updateEmitter failed: " + updated.error.toString()); }
				const look = visualSettings;
				const written = look === null
					? writeSortedInstances(emitter, world.value, view.viewProj, instances)
					: writeVisualInstances(emitter, world.value, view.viewProj, (look as ParticleVisualSettings).frames, (look as ParticleVisualSettings).anchor, instances);
				if (!written.ok) { throw new Error("Particles: writing instances failed: " + written.error.toString()); }
				const streamed = writeStream(context, stream, instances, written.value);
				if (!streamed.ok) { throw new Error("Particles: writeStream failed: " + streamed.error.toString()); }
				if (emitter.count > 0 || (active && emitter.isActive())) {
					state.invalidate();
				} else {
					awake = false;
				}
			});
			bindNode(state, node, props, local);
			mountNodeChildren(scope, node, props, host, parent, before);
		});
	};
}
