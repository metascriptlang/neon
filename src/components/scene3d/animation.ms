import { Accessor, createSignal } from "../../core/signal";
import { createEffect, createRenderEffect } from "../../core/effect";
import { Cleanup } from "../../core/types";
import { onCleanup } from "../../core/cleanup";
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
import { NodeScope, mountOwned, requireScene } from "./core";

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
