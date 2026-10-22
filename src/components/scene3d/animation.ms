import { Accessor, Setter, createSignal } from "../../core/signal";
import { createEffect, createRenderEffect } from "../../core/effect";
import { Cleanup } from "../../core/types";
import { onCleanup } from "../../core/cleanup";
import { useContext } from "../../render/context";
import { useVoidClock } from "../../render/voidClock";
import { Host, HostNode, NeonNode } from "../../render/hostTypes";
import { MeshId } from "../../../../void/src/void3d/draw";
import {
	AnimationClock,
	ObjectAnimation as VoidObjectAnimation,
	MeshFrameAnimation as VoidMeshFrameAnimation,
	Interpolation,
	forFrames,
	isPlaying,
	isFinished,
	update,
	setFrame,
	bindTracks,
	syncPose,
	forMeshes,
	closeMeshFrames,
	bindMeshFrames,
	syncMeshFrame,
	isClosed,
} from "../../../../void/src/void3d/animation";
import { GltfData, GltfAnimation } from "../../../../void/src/void3d/gltf";
import { GltfPose, bind, samplePose, stageTrsChild } from "../../../../void/src/void3d/gltfPose";
import {
	AnimationCompose, AnimationRestTarget, AnimationChildSample, create, stageSmoothCompose,
} from "../../../../void/src/void3d/animationCompose";
import {
	Scene3D as VoidScene3D, NodeId3D, Transform3D, setLocal, isLive,
} from "../../../../void/src/void3d/scene";
import { NodeScope, mountOwned, requireScene } from "./core";
import { GltfMount, GltfScope, gltfScope } from "./gltf";

export interface FrameClockProps {
	paused?: Accessor<boolean> | null;
	speed?: Accessor<float64> | null;
	looping?: Accessor<boolean> | null;
	frame?: Accessor<float64> | null;
}

export interface ObjectAnimationProps extends FrameClockProps {
	animation: Accessor<VoidObjectAnimation>;
}

export interface MeshFrameAnimationProps extends FrameClockProps {
	target: Accessor<string>;
	meshes: Accessor<Vec<MeshId>>;
	fps: Accessor<float64>;
}

interface ClockRun {
	read: () => AnimationClock | null;
	write: (clock: AnimationClock) => void;
	sync: () => boolean;
}

interface ObjectRun {
	animation: VoidObjectAnimation;
}

function progressing(clock: AnimationClock): boolean {
	if (clock.frameCount <= 1 || !clock.isPlaying()) { return false; }
	return clock.speed < 0.0 ? clock.frame > 0.0 : !clock.isFinished();
}

// The props' paused/speed/looping/frame drive the run's AnimationClock on the area clock; the
// returned `bound` applies them to a freshly bound run and writes its first pose.
function frameClock(tag: string, props: FrameClockProps, scope: NodeScope, run: ClockRun): () => void {
	let paused: boolean | null = null;
	let speed: float64 | null = null;
	let looping: boolean | null = null;
	let frame: float64 | null = null;
	let failure: Error | null = null;
	let stalled = false;
	let ticks: int32 = 0;
	const [tick, setTick] = createSignal<int32>(0);
	const sync = (): void => {
		if (run.sync()) { scope.state.invalidate(); }
	};
	const apply = (seek: boolean): void => {
		const current = run.read();
		if (current === null) { return; }
		let clock = current;
		if (paused !== null) { clock.pause = paused as boolean; }
		if (speed !== null) { clock.speed = speed as float64; }
		if (looping !== null) { clock.loop = looping as boolean; }
		if (seek && frame !== null) {
			const at = setFrame(clock, frame as float64);
			if (!at.ok) { throw new Error(tag + ": frame must be finite"); }
		}
		run.write(clock);
	};
	const wake = useVoidClock(
		(): boolean => {
			const clock = run.read();
			return !stalled && clock !== null && progressing(clock);
		},
		(seconds: float64): void => {
			const current = run.read();
			if (current === null) { return; }
			let clock = current;
			const moved = update(clock, seconds);
			if (!moved.ok) {
				stalled = true;
				failure = new Error(tag + ": update failed: " + moved.error.toString());
			} else {
				run.write(clock);
				if (!moved.value) { return; }
			}
			ticks += 1;
			setTick(ticks);
		},
	);
	createRenderEffect<int32>(
		(prev: int32 | null): int32 => tick(),
		(value: int32, prev: int32 | null): Cleanup | null => {
			const failed = failure;
			if (failed !== null) {
				failure = null;
				throw failed;
			}
			if (run.read() === null) { return null; }
			stalled = true;
			sync();
			stalled = false;
			wake();
			return null;
		},
	);
	createRenderEffect<[boolean | null, float64 | null, boolean | null]>(
		(prev: [boolean | null, float64 | null, boolean | null] | null):
			[boolean | null, float64 | null, boolean | null] => [
			props.paused === null ? null : (props.paused as () => boolean)(),
			props.speed === null ? null : (props.speed as () => float64)(),
			props.looping === null ? null : (props.looping as () => boolean)(),
		],
		(value: [boolean | null, float64 | null, boolean | null],
			prev: [boolean | null, float64 | null, boolean | null] | null): Cleanup | null => {
			const nextSpeed = value[1];
			if (nextSpeed !== null && !Number.isFinite(nextSpeed as float64)) {
				throw new Error(tag + ": speed must be finite");
			}
			paused = value[0];
			speed = nextSpeed;
			looping = value[2];
			apply(false);
			wake();
			return null;
		},
	);
	if (props.frame !== null) {
		const seek = props.frame as () => float64;
		createRenderEffect<float64>(
			(prev: float64 | null): float64 => seek(),
			(value: float64, prev: float64 | null): Cleanup | null => {
				frame = value;
				if (run.read() === null) { return null; }
				apply(true);
				sync();
				wake();
				return null;
			},
		);
	}
	return (): void => {
		stalled = false;
		apply(true);
		sync();
		wake();
	};
}

export function ObjectAnimation(props: ObjectAnimationProps): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		const scope = requireScene("ObjectAnimation");
		mountOwned((): void => {
			const scene = scope.state.handle.scene;
			let run: ObjectRun | null = null;
			const bound = frameClock("ObjectAnimation", props, scope, {
				read: (): AnimationClock | null => run === null ? null : (run as ObjectRun).animation.clock,
				write: (clock: AnimationClock): void => {
					const current = run;
					if (current !== null) { current.animation.clock = clock; }
				},
				sync: (): boolean => {
					const current = run;
					if (current === null) { return false; }
					const written = syncPose(current.animation, scene);
					if (!written.ok) {
						throw new Error("ObjectAnimation: syncPose failed: " + written.error.toString());
					}
					return written.value > 0;
				},
			});
			createEffect<VoidObjectAnimation>(
				(prev: VoidObjectAnimation | null): VoidObjectAnimation => props.animation(),
				(value: VoidObjectAnimation, prev: VoidObjectAnimation | null): Cleanup | null => {
					let next = value;
					const checked = AnimationClock.forFrames(
						next.clock.frameCount, next.clock.sampling, next.clock.interpolation,
					);
					if (!checked.ok) {
						throw new Error("ObjectAnimation: invalid clock: " + checked.error.toString());
					}
					if (!Number.isFinite(next.clock.frame) || !Number.isFinite(next.clock.speed)) {
						throw new Error("ObjectAnimation: frame and speed must be finite");
					}
					if (next.keys.length !== next.tracks.length * (next.clock.frameCount as int64)) {
						throw new Error("ObjectAnimation: invalid track length");
					}
					const tracked = bindTracks(next, scene, scope.parent);
					if (!tracked.ok) {
						throw new Error("ObjectAnimation: bindTracks failed: " + tracked.error.toString());
					}
					run = { animation: next };
					bound();
					return null;
				},
			);
		});
	};
}

export function MeshFrameAnimation(props: MeshFrameAnimationProps): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		const scope = requireScene("MeshFrameAnimation");
		mountOwned((): void => {
			const scene = scope.state.handle.scene;
			const context = scope.state.handle.context;
			let run: VoidMeshFrameAnimation | null = null;
			const close = (): void => {
				const current = run;
				run = null;
				if (current !== null && !current.isClosed() && !context.closed) { closeMeshFrames(current); }
			};
			onCleanup(close);
			const bound = frameClock("MeshFrameAnimation", props, scope, {
				read: (): AnimationClock | null => run === null ? null : (run as VoidMeshFrameAnimation).clock,
				write: (clock: AnimationClock): void => {
					const current = run;
					if (current !== null) { current.clock = clock; }
				},
				sync: (): boolean => {
					const current = run;
					if (current === null) { return false; }
					const swapped = syncMeshFrame(current, scene);
					if (!swapped.ok) {
						throw new Error("MeshFrameAnimation: syncMeshFrame failed: " + swapped.error.toString());
					}
					return swapped.value > 0;
				},
			});
			createEffect<[string, Vec<MeshId>, float64]>(
				(prev: [string, Vec<MeshId>, float64] | null): [string, Vec<MeshId>, float64] => [
					props.target(), props.meshes(), props.fps(),
				],
				(value: [string, Vec<MeshId>, float64], prev: [string, Vec<MeshId>, float64] | null): Cleanup | null => {
					const clock = AnimationClock.forFrames(value[1].length as int32, value[2], Interpolation.Step);
					if (!clock.ok) {
						throw new Error("MeshFrameAnimation: invalid meshes or fps: " + clock.error.toString());
					}
					const made = VoidMeshFrameAnimation.forMeshes(context, clock.value, value[0], value[1]);
					if (!made.ok) {
						throw new Error("MeshFrameAnimation: forMeshes failed: " + made.error.toString());
					}
					const next = made.value;
					const target = bindMeshFrames(next, scene, scope.parent);
					if (!target.ok) {
						closeMeshFrames(next);
						throw new Error("MeshFrameAnimation: bindMeshFrames failed: " + target.error.toString());
					}
					close();
					run = next;
					bound();
					return null;
				},
			);
		});
	};
}

export interface ClipHandle {
	play: () => void;
	pause: () => void;
	stop: () => void;
	setWeight: (weight: float64) => void;
	crossfade: (to: ClipHandle, ms: float64) => void;
}

export interface ClipProps {
	name: Accessor<string>;
	playing?: Accessor<boolean> | null;
	speed?: Accessor<float64> | null;
	loop?: Accessor<boolean> | null;
	weight?: Accessor<float64> | null;
	fadeMs?: Accessor<float64> | null;
	time?: Accessor<float64> | null;
	ref?: ((handle: ClipHandle) => void) | null;
}

interface ClipRun {
	handle: ClipHandle;
	pose: GltfPose | null;
	duration: float64;
	seconds: float64;
	playing: boolean;
	enabled: boolean;
	speed: float64;
	loop: boolean;
	weight: float64;
	current: float64;
	fadeSeconds: float64;
	wake: () => void;
}

// The clips under one Gltf share its nodes: each frame they compose into one pose, in the
// first clip effect of the flush that sees the new tick.
interface ClipMixer {
	scope: GltfScope;
	runs: ClipRun[];
	nodes: Vec<NodeId3D>;
	targets: Vec<AnimationRestTarget>;
	compose: AnimationCompose;
	posed: boolean;
	mixed: boolean;
	ticks: int32;
	committed: int32;
	failedBy: ClipRun | null;
	tick: Accessor<int32>;
	setTick: Setter<int32>;
}

const mixers: ClipMixer[] = [];

function refuseUnmounted(): void { throw new Error("Clip: the handle is not mounted yet"); }

const NO_CLIP_HANDLE: ClipHandle = {
	play: refuseUnmounted,
	pause: refuseUnmounted,
	stop: refuseUnmounted,
	setWeight: (weight: float64): void => { refuseUnmounted(); },
	crossfade: (to: ClipHandle, ms: float64): void => { refuseUnmounted(); },
};

function mixerOf(scope: GltfScope): ClipMixer {
	for (const mixer of mixers) {
		if (mixer.scope === scope) { return mixer; }
	}
	const empty = AnimationCompose.create([]);
	if (!empty.ok) { throw new Error("Clip: AnimationCompose.create failed: " + empty.error.toString()); }
	const [tick, setTick] = createSignal<int32>(0, { ownedWrite: true });
	const mixer: ClipMixer = {
		scope, runs: [], nodes: [], targets: [], compose: empty.value, posed: false, mixed: false,
		ticks: 0, committed: -1, failedBy: null, tick, setTick,
	};
	mixers.push(mixer);
	return mixer;
}

function bump(mixer: ClipMixer): void {
	mixer.ticks += 1;
	mixer.setTick(mixer.ticks);
}

function targetWeight(run: ClipRun): float64 {
	return run.enabled ? run.weight : 0.0;
}

function clipActive(mixer: ClipMixer, run: ClipRun): boolean {
	if (mixer.failedBy !== null || run.pose === null) { return false; }
	const target = targetWeight(run);
	if (run.current !== target) { return true; }
	if (target <= 0.0 || !run.playing || run.speed === 0.0 || run.duration <= 0.0) { return false; }
	return run.loop || (run.speed > 0.0 ? run.seconds < run.duration : run.seconds > 0.0);
}

function placed(run: ClipRun, seconds: float64): float64 {
	if (run.duration <= 0.0) { return 0.0; }
	if (run.loop) {
		const wrapped = seconds % run.duration;
		return wrapped < 0.0 ? wrapped + run.duration : wrapped;
	}
	return Math.min(Math.max(seconds, 0.0), run.duration);
}

function settleWeight(run: ClipRun): void {
	if (run.fadeSeconds <= 0.0) { run.current = targetWeight(run); }
}

function advanceClip(run: ClipRun, seconds: float64): void {
	const target = targetWeight(run);
	if (run.current !== target) {
		const step = run.fadeSeconds <= 0.0 ? 1.0e300 : seconds / run.fadeSeconds;
		run.current = run.current < target ? Math.min(target, run.current + step) : Math.max(target, run.current - step);
	}
	if (run.playing && run.enabled) { run.seconds = placed(run, run.seconds + seconds * run.speed); }
}

function restOf(data: GltfData, source: int32): Transform3D {
	const local = data.nodes[source].local;
	return { position: local.position, rotation: local.rotation, scale: local.scale };
}

function writeRest(mixer: ClipMixer, scene: VoidScene3D, targets: Vec<AnimationRestTarget>): void {
	if (scene.closed) { return; }
	for (const target of targets) {
		const node = mixer.nodes[target.sourceNode];
		if (scene.isLive(node)) { setLocal(scene, node, target.rest); }
	}
}

function retarget(mixer: ClipMixer, scene: VoidScene3D, data: GltfData | null, nodes: Vec<NodeId3D>): void {
	writeRest(mixer, scene, mixer.targets);
	mixer.nodes = nodes;
	let targets: Vec<AnimationRestTarget> = [];
	if (data !== null) {
		for (const run of mixer.runs) {
			const pose = run.pose;
			if (pose === null) { continue; }
			for (const track of pose.tracks) {
				let known = track.sourceNode >= nodes.length;
				for (const target of targets) {
					if (target.sourceNode === track.sourceNode) { known = true; }
				}
				if (!known) { targets.push({ sourceNode: track.sourceNode, rest: restOf(data as GltfData, track.sourceNode) }); }
			}
		}
	}
	const compose = AnimationCompose.create(targets);
	if (!compose.ok) { throw new Error("Clip: AnimationCompose.create failed: " + compose.error.toString()); }
	mixer.targets = targets;
	mixer.compose = compose.value;
	mixer.posed = false;
	mixer.mixed = false;
}

// Weights below a total of one leave the rest pose that share, as three.js' mixer does.
function commitMixer(mixer: ClipMixer, scene: VoidScene3D): boolean {
	let contributing: ClipRun[] = [];
	let total: float64 = 0.0;
	for (const run of mixer.runs) {
		if (run.pose !== null && run.current > 0.0) {
			contributing.push(run);
			total += run.current;
		}
	}
	if (contributing.length === 0) {
		if (!mixer.posed) { return false; }
		writeRest(mixer, scene, mixer.targets);
		mixer.posed = false;
		return true;
	}
	mixer.posed = true;
	if (contributing.length === 1 && contributing[0].current === 1.0) {
		if (mixer.mixed) { writeRest(mixer, scene, mixer.targets); }
		mixer.mixed = false;
		const sampled = (contributing[0].pose as GltfPose).samplePose(contributing[0].seconds);
		if (!sampled.ok) { throw new Error("Clip: samplePose failed: " + sampled.error.toString()); }
		return true;
	}
	let blend: AnimationChildSample = { seconds: 0.0, samples: [] };
	let gathered: float64 = Math.max(0.0, 1.0 - total);
	for (const run of contributing) {
		const child = (run.pose as GltfPose).stageTrsChild(mixer.targets, run.seconds);
		if (!child.ok) { throw new Error("Clip: stageTrsChild failed: " + child.error.toString()); }
		gathered += run.current;
		const staged = stageSmoothCompose(mixer.compose, blend, child.value, (run.current / gathered) as float32);
		if (!staged.ok) { throw new Error("Clip: stageSmoothCompose failed: " + staged.error.toString()); }
		blend = { seconds: 0.0, samples: mixer.compose.output };
	}
	for (let i = 0; i < mixer.targets.length; i++) {
		setLocal(scene, mixer.nodes[mixer.targets[i].sourceNode], mixer.compose.output[i].value);
	}
	mixer.mixed = true;
	return true;
}

function durationOf(clip: GltfAnimation): float64 {
	let longest: float64 = 0.0;
	for (const track of clip.tracks) {
		const times = track.curve.times;
		if (times.length > 0) { longest = Math.max(longest, times[times.length - 1] as float64); }
	}
	return longest;
}

function checkedWeight(weight: float64): float64 {
	if (!Number.isFinite(weight) || weight < 0.0) { throw new Error("Clip: weight must be finite and nonnegative"); }
	return weight;
}

function checkedFade(ms: float64): float64 {
	if (!Number.isFinite(ms) || ms < 0.0) { throw new Error("Clip: fadeMs must be finite and nonnegative"); }
	return ms / 1000.0;
}

function runOf(mixer: ClipMixer, handle: ClipHandle): ClipRun {
	for (const run of mixer.runs) {
		if (run.handle === handle) { return run; }
	}
	throw new Error("Clip: crossfade to a clip of another Gltf");
}

// One glTF animation by name, played on the nodes of the enclosing Gltf. Props and the handle
// write the same state, so the last write wins.
export function Clip(props: ClipProps): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		const scope = requireScene("Clip");
		const owner = useContext(gltfScope);
		if (owner === null) { throw new Error("Clip: mount inside Gltf"); }
		mountOwned((): void => {
			const scene = scope.state.handle.scene;
			const mixer = mixerOf(owner as GltfScope);
			const run: ClipRun = {
				handle: NO_CLIP_HANDLE, pose: null, duration: 0.0, seconds: 0.0, playing: true, enabled: true,
				speed: 1.0, loop: true, weight: 1.0, current: 1.0, fadeSeconds: 0.0, wake: (): void => {},
			};
			const touched = (): void => { bump(mixer); run.wake(); };
			run.handle = {
				play: (): void => { run.playing = true; run.enabled = true; settleWeight(run); touched(); },
				pause: (): void => { run.playing = false; touched(); },
				stop: (): void => {
					run.playing = false; run.enabled = false; run.seconds = 0.0; run.current = 0.0; touched();
				},
				setWeight: (weight: float64): void => { run.weight = checkedWeight(weight); settleWeight(run); touched(); },
				crossfade: (to: ClipHandle, ms: float64): void => {
					const next = runOf(mixer, to);
					const seconds = checkedFade(ms);
					run.fadeSeconds = seconds;
					next.fadeSeconds = seconds;
					run.weight = 0.0;
					next.weight = 1.0;
					next.playing = true;
					next.enabled = true;
					settleWeight(run);
					settleWeight(next);
					touched();
					next.wake();
				},
			};
			mixer.runs.push(run);
			run.wake = useVoidClock(
				(): boolean => clipActive(mixer, run),
				(seconds: float64): void => { advanceClip(run, seconds); bump(mixer); },
			);
			onCleanup((): void => {
				mixer.runs.splice(mixer.runs.indexOf(run), 1);
				if (mixer.failedBy === run) { mixer.failedBy = null; }
				const mount = owner.mount();
				retarget(mixer, scene, mount === null ? null : (mount as GltfMount).data, mixer.nodes);
				if (mixer.runs.length === 0) {
					writeRest(mixer, scene, mixer.targets);
					mixers.splice(mixers.indexOf(mixer), 1);
				} else {
					bump(mixer);
				}
				scope.state.invalidate();
			});
			createRenderEffect<int32>(
				(prev: int32 | null): int32 => mixer.tick(),
				(value: int32, prev: int32 | null): Cleanup | null => {
					if (mixer.failedBy === run) { mixer.failedBy = null; mixer.committed = -1; }
					if (mixer.failedBy !== null || mixer.committed === value) { return null; }
					mixer.committed = value;
					try {
						if (commitMixer(mixer, scene)) { scope.state.invalidate(); }
					} catch (error) {
						mixer.failedBy = run;
						throw error;
					}
					for (const other of mixer.runs) { other.wake(); }
					return null;
				},
			);
			createRenderEffect<[boolean, float64, boolean]>(
				(prev: [boolean, float64, boolean] | null): [boolean, float64, boolean] => [
					props.playing === null ? true : (props.playing as () => boolean)(),
					props.speed === null ? 1.0 : (props.speed as () => float64)(),
					props.loop === null ? true : (props.loop as () => boolean)(),
				],
				(value: [boolean, float64, boolean], prev: [boolean, float64, boolean] | null): Cleanup | null => {
					if (!Number.isFinite(value[1])) { throw new Error("Clip: speed must be finite"); }
					if (value[0]) { run.enabled = true; settleWeight(run); }
					run.playing = value[0];
					run.speed = value[1];
					run.loop = value[2];
					run.seconds = placed(run, run.seconds);
					touched();
					return null;
				},
			);
			createRenderEffect<[float64, float64]>(
				(prev: [float64, float64] | null): [float64, float64] => [
					props.weight === null ? 1.0 : (props.weight as () => float64)(),
					props.fadeMs === null ? 0.0 : (props.fadeMs as () => float64)(),
				],
				(value: [float64, float64], prev: [float64, float64] | null): Cleanup | null => {
					run.weight = checkedWeight(value[0]);
					run.fadeSeconds = checkedFade(value[1]);
					if (prev === null) { run.current = targetWeight(run); }
					settleWeight(run);
					touched();
					return null;
				},
			);
			if (props.time !== null) {
				const time = props.time as () => float64;
				createRenderEffect<float64>(
					(prev: float64 | null): float64 => time(),
					(value: float64, prev: float64 | null): Cleanup | null => {
						if (!Number.isFinite(value)) { throw new Error("Clip: time must be finite"); }
						run.seconds = placed(run, value);
						touched();
						return null;
					},
				);
			}
			createEffect<[GltfMount | null, string]>(
				(prev: [GltfMount | null, string] | null): [GltfMount | null, string] => [owner.mount(), props.name()],
				(value: [GltfMount | null, string], prev: [GltfMount | null, string] | null): Cleanup | null => {
					const mount = value[0];
					if (mount === null) { return null; }
					const data = (mount as GltfMount).data;
					let found: GltfAnimation | null = null;
					for (const clip of data.animations) {
						if (clip.name === value[1]) { found = clip; break; }
					}
					if (found === null) { throw new Error("Clip: the Gltf has no animation named \"" + value[1] + "\""); }
					const clip = found as GltfAnimation;
					const bound = GltfPose.bind(scene, (mount as GltfMount).nodes, clip.tracks);
					if (!bound.ok) { throw new Error("Clip: GltfPose.bind failed: " + bound.error.toString()); }
					run.pose = bound.value;
					run.duration = durationOf(clip);
					run.seconds = props.time === null ? 0.0 : placed(run, (props.time as () => float64)());
					retarget(mixer, scene, data, (mount as GltfMount).nodes);
					touched();
					return null;
				},
			);
			if (props.ref !== null) { (props.ref as (handle: ClipHandle) => void)(run.handle); }
		});
	};
}
