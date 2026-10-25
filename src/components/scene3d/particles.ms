import { Accessor, untrack } from "../../core/signal";
import { createRenderEffect } from "../../core/effect";
import { Cleanup } from "../../core/types";
import { Host, HostNode, NeonNode } from "../../render/hostTypes";
import { useVoidClock } from "../../render/voidClock";
import { vec3 } from "../../../../void/src/math/math3d";
import { VertexLayout } from "../../../../void/src/void3d/gpu3d";
import { GpuMesh, MeshId, MaterialId, addMesh, streamMesh, writeStream, releaseMesh } from "../../../../void/src/void3d/draw";
import { ParticleEffect } from "../../../../void/src/particles/asset";
import { EffectInstance, create, playEffect, stopEffect, isAlive, updateEffect } from "../../../../void/src/particles/effect";
import {
	ParticleWriter3D, writeParticles, writeParticlePoints, PARTICLE_INSTANCE_STRIDE, PARTICLE_VISUAL_INSTANCE_STRIDE,
} from "../../../../void/src/void3d/particleWriter";
import { AtlasTile } from "../../../../void/src/void3d/billboard";
import { NodeId3D, Transform3D, addGroup, addMeshNode, setMaterialOf, remove, worldOf } from "../../../../void/src/void3d/scene";
import { CameraView } from "../../../../void/src/void3d/camera";
import { NodeProps, SceneState, mountOwned, requireScene, localOf, bindNode, ownNode, mountNodeChildren, onBeforeRefresh } from "./core";

export interface ParticlesProps extends NodeProps {
	effect: Accessor<ParticleEffect>;
	material: Accessor<MaterialId>;
	frames?: Accessor<Vec<AtlasTile>> | null;
	playing?: Accessor<boolean> | null;
	paused?: Accessor<boolean> | null;
	speed?: Accessor<float64> | null;
	seed?: Accessor<uint32> | null;
}

interface SystemDraw {
	node: NodeId3D;
	stream: MeshId;
	instances: Vec<float32>;
}

const DEFAULT_SEED: uint32 = 2463534242;

function instanced(effect: ParticleEffect, seed: uint32): EffectInstance {
	const made = EffectInstance.create(effect, seed);
	if (!made.ok) {
		throw new Error("Particles: EffectInstance.create failed: " + made.error.kind.toString() + " in system "
			+ made.error.system.toString() + ", " + made.error.cause.toString());
	}
	return made.value;
}

function drawSystems(state: SceneState, group: NodeId3D, effect: EffectInstance, material: MaterialId, visual: boolean): SystemDraw[] {
	const scene = state.handle.scene;
	const context = state.handle.context;
	const layout = visual ? VertexLayout.ParticleVisual : VertexLayout.Particle;
	const stride = visual ? PARTICLE_VISUAL_INSTANCE_STRIDE : PARTICLE_INSTANCE_STRIDE;
	const draws: SystemDraw[] = [];
	for (const sys of effect.systems) {
		const added = addMesh(context, GpuMesh.streamMesh(sys.capacity, 0, 0, layout));
		if (!added.ok) { throw new Error("Particles: addMesh failed: " + added.error.toString()); }
		const placed = addMeshNode(scene, group, Transform3D.identity(), added.value, material);
		const released = releaseMesh(context, added.value);
		if (!placed.ok) { throw new Error("Particles: addMeshNode failed: " + placed.error.toString()); }
		if (!released.ok) { throw new Error("Particles: releaseMesh failed: " + released.error.toString()); }
		draws.push({ node: placed.value, stream: added.value, instances: new Array(sys.capacity * stride) });
	}
	return draws;
}

export function Particles(props: ParticlesProps): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		const scope = requireScene("Particles");
		mountOwned((): void => {
			const state = scope.state;
			const scene = state.handle.scene;
			const context = state.handle.context;
			const local = localOf(props);
			const visual = props.frames !== null;
			const readFrames = (): Vec<AtlasTile> => (props.frames as () => Vec<AtlasTile>)();
			const readSeed = (): uint32 => props.seed === null ? DEFAULT_SEED : (props.seed as () => uint32)();
			const readPlaying = (): boolean => props.playing === null ? true : (props.playing as () => boolean)();
			const readPaused = (): boolean => props.paused === null ? false : (props.paused as () => boolean)();
			const readSpeed = (): float64 => props.speed === null ? 1.0 : (props.speed as () => float64)();
			const group = addGroup(scene, scope.parent, local);
			ownNode(state, group);
			let effect = instanced(untrack(() => props.effect()), untrack(readSeed));
			let material = untrack(() => props.material());
			let draws = drawSystems(state, group, effect, material, visual);
			let frames: Vec<AtlasTile> = visual ? untrack(readFrames) : [];
			let playing = untrack(readPlaying);
			let paused = untrack(readPaused);
			let speed = untrack(readSpeed);
			// Play waits for the frame hook, which knows the group's world pose.
			let playDue = playing;
			let writer = ParticleWriter3D.create();
			const busy = (): boolean => playDue || (!paused && effect.isAlive());
			let awake = busy();
			let stale = true;
			let unspentSeconds: float64 = 0.0;
			const wakeClock = useVoidClock((): boolean => awake && !paused, (seconds: float64): void => { unspentSeconds += seconds; });
			wakeClock();
			const redraw = (): void => {
				stale = true;
				state.invalidate();
			};
			const wake = (): void => {
				if (!awake && busy()) {
					awake = true;
					unspentSeconds = 0.0;
					state.invalidate();
				}
				wakeClock();
			};
			createRenderEffect<[ParticleEffect, uint32]>(
				(prev: [ParticleEffect, uint32] | null): [ParticleEffect, uint32] => [props.effect(), readSeed()],
				(value: [ParticleEffect, uint32], prev: [ParticleEffect, uint32] | null): Cleanup | null => {
					if (prev === null) { return null; }
					const next = instanced(value[0], value[1]);
					for (const draw of draws) {
						if (scene.isLive(draw.node)) { const removed = remove(scene, draw.node); }
					}
					effect = next;
					draws = drawSystems(state, group, effect, material, visual);
					playDue = playing;
					redraw();
					wake();
					return null;
				},
			);
			createRenderEffect<[boolean, boolean, float64]>(
				(prev: [boolean, boolean, float64] | null): [boolean, boolean, float64] => [readPlaying(), readPaused(), readSpeed()],
				(value: [boolean, boolean, float64], prev: [boolean, boolean, float64] | null): Cleanup | null => {
					if (prev === null) { return null; }
					if (!(value[2] >= 0.0)) { throw new Error("Particles: speed must be zero or positive, got " + value[2].toString()); }
					if (value[0] && !playing) { playDue = true; }
					if (!value[0] && playing) {
						playDue = false;
						stopEffect(effect, false);
					}
					playing = value[0];
					paused = value[1];
					speed = value[2];
					wake();
					return null;
				},
			);
			if (visual) {
				createRenderEffect<Vec<AtlasTile>>(
					(prev: Vec<AtlasTile> | null): Vec<AtlasTile> => readFrames(),
					(value: Vec<AtlasTile>, prev: Vec<AtlasTile> | null): Cleanup | null => {
						frames = value;
						redraw();
						return null;
					},
				);
			}
			createRenderEffect<MaterialId>(
				(prev: MaterialId | null): MaterialId => props.material(),
				(value: MaterialId, prev: MaterialId | null): Cleanup | null => {
					if (value !== material) {
						for (const draw of draws) {
							const changed = setMaterialOf(scene, draw.node, value);
							if (!changed.ok) { throw new Error("Particles: setMaterialOf failed: " + changed.error.toString()); }
						}
						material = value;
						state.invalidate();
					}
					return null;
				},
			);
			onBeforeRefresh(state, (view: CameraView): void => {
				if (!awake && !stale) { return; }
				stale = false;
				const world = worldOf(scene, group);
				if (!world.ok) { return; }
				if (playDue) {
					playEffect(effect, world.value);
					playDue = false;
				}
				if (!paused) {
					const updated = updateEffect(effect, unspentSeconds * speed, world.value);
					if (!updated.ok) { throw new Error("Particles: updateEffect failed: " + updated.error.toString()); }
				}
				unspentSeconds = 0.0;
				for (let s = 0; s < draws.length; s++) {
					const draw = draws[s];
					const written = visual
						? writeParticles(writer, effect.systems[s], frames, view.eye, view.basis.forward, vec3(0.0, 0.0, 0.0), draw.instances)
						: writeParticlePoints(writer, effect.systems[s], view.eye, view.basis.forward, draw.instances);
					if (!written.ok) { throw new Error("Particles: writing system " + s.toString() + " failed: " + written.error.toString()); }
					const streamed = writeStream(context, draw.stream, draw.instances, written.value);
					if (!streamed.ok) { throw new Error("Particles: writeStream failed: " + streamed.error.toString()); }
				}
				if (!busy()) {
					awake = false;
					wakeClock();
				}
			});
			bindNode(state, group, props, local);
			mountNodeChildren(scope, group, props, host, parent, before);
		});
	};
}
