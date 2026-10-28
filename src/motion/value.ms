import { Easing, EasingFunction, easingOr } from "../animation/easing";
import { Clock } from "./clock";
import {
	DecayConfig,
	DecaySimulation,
	createDecay,
	decayConfig,
	isDone as decayIsDone,
	position as decayPosition,
	velocity as decayVelocity,
} from "./decay";
import { numberValue } from "./document";
import { MotionPolicy, ReduceMotion, shouldReduce } from "./policy";
import {
	SpringConfig,
	SpringSimulation,
	createSpring,
	isDone as springIsDone,
	position as springPosition,
	springByStiffness,
	velocity as springVelocity,
} from "./spring";
import { Composition, MotionTarget, TargetClaim } from "./target";

export enum AnimationKind {
	Timing,
	Spring,
	Decay,
	Sequence,
	Delay,
	Repeat,
}

export struct AnimationSpec {
	kind: AnimationKind;
	to: float64;
	durationMs: float64;
	easing: EasingFunction;
	spring: SpringConfig;
	decay: DecayConfig;
	velocityPerSecond: float64;
	count: int32;
	reverse: boolean;
	children: AnimationSpec[];
	reduceMotion: ReduceMotion | null;
}

export interface TimingOptions {
	duration?: float64;
	easing?: EasingFunction;
}

function requireFinite(value: float64, what: string): void {
	if (!Number.isFinite(value)) {
		throw new Error("motion: " + what + " must be finite, got " + value);
	}
}

function baseSpec(kind: AnimationKind): AnimationSpec {
	return {
		kind,
		to: 0,
		durationMs: 0,
		easing: Easing.linear,
		spring: springByStiffness(),
		decay: decayConfig(),
		velocityPerSecond: 0,
		count: 1,
		reverse: false,
		children: [],
		reduceMotion: null,
	};
}

export function timing(to: float64, options: TimingOptions = {}): AnimationSpec {
	requireFinite(to, "timing to");
	const duration: float64 = options.duration ?? 300;
	requireFinite(duration, "timing duration");
	if (duration < 0) {
		throw new Error("motion: timing duration can't be negative, got " + duration);
	}
	return {
		...baseSpec(AnimationKind.Timing),
		to,
		durationMs: duration,
		easing: easingOr(options.easing, Easing.inOut(Easing.quad)),
	};
}

export function spring(
	to: float64,
	config: SpringConfig = springByStiffness(),
	velocityPerSecond: float64 = 0,
): AnimationSpec {
	createSpring(config, to, to, velocityPerSecond);
	return { ...baseSpec(AnimationKind.Spring), to, spring: config, velocityPerSecond };
}

export function decay(config: DecayConfig, velocityPerSecond: float64): AnimationSpec {
	createDecay(config, 0, velocityPerSecond);
	return { ...baseSpec(AnimationKind.Decay), decay: config, velocityPerSecond };
}

export function sequence(...specs: AnimationSpec[]): AnimationSpec {
	if (specs.length === 0) {
		throw new Error("motion: sequence needs at least one animation");
	}
	return { ...baseSpec(AnimationKind.Sequence), children: specs };
}

export function delay(ms: float64, spec: AnimationSpec): AnimationSpec {
	requireFinite(ms, "delay");
	if (ms < 0) {
		throw new Error("motion: delay can't be negative, got " + ms);
	}
	return { ...baseSpec(AnimationKind.Delay), durationMs: ms, children: [spec] };
}

export function repeat(
	spec: AnimationSpec,
	count: int32 = 2,
	reverse: boolean = false,
): AnimationSpec {
	return { ...baseSpec(AnimationKind.Repeat), count, reverse, children: [spec] };
}

function blendEnd(spec: AnimationSpec): float64 {
	const kind = spec.kind;
	if (kind === AnimationKind.Timing || kind === AnimationKind.Spring) { return spec.to; }
	if (kind === AnimationKind.Sequence) { return blendEnd(spec.children[spec.children.length - 1]); }
	if (kind === AnimationKind.Delay || (kind === AnimationKind.Repeat && !spec.reverse)) {
		return blendEnd(spec.children[0]);
	}
	throw new Error(
		"motion: a blended animation needs a fixed end; decay and reversing repeat have none",
	);
}

function sameSpringConfig(a: SpringConfig, b: SpringConfig): boolean {
	return a.useDuration === b.useDuration && a.mass === b.mass &&
		a.stiffness === b.stiffness && a.damping === b.damping &&
		a.durationMs === b.durationMs && a.dampingRatio === b.dampingRatio &&
		a.energyThreshold === b.energyThreshold &&
		a.overshootClamping === b.overshootClamping &&
		a.clampMin === b.clampMin && a.clampMax === b.clampMax;
}

class Run {
	spec: AnimationSpec;
	children: Run[] = [];
	reduce: boolean = false;
	reduceSet: boolean = false;
	settled: boolean = false;
	finished: boolean = false;
	to: float64;
	current: float64 = 0;
	velocityPerSecond: float64 = 0;
	startTime: float64 = 0;
	startValue: float64 = 0;
	springSimulation: SpringSimulation | null = null;
	decaySimulation: DecaySimulation | null = null;
	index: int32 = 0;
	reps: int32 = 0;
	begun: boolean = false;
	previous: Run | null = null;

	constructor(spec: AnimationSpec, policy: MotionPolicy) {
		this.spec = spec;
		this.to = spec.to;
		if (spec.reduceMotion !== null) {
			this.reduce = shouldReduce(spec.reduceMotion, policy);
			this.reduceSet = true;
		}
		for (const child of spec.children) {
			this.children.push(new Run(child, policy));
		}
	}

	inherit(child: Run): void {
		if (!child.reduceSet) {
			child.reduce = this.reduce;
			child.reduceSet = true;
		}
	}

	handoffVelocity(): float64 {
		if (this.finished) {
			return 0;
		}
		return match (this.spec.kind) {
			AnimationKind.Timing => 0,
			AnimationKind.Spring | AnimationKind.Decay => this.velocityPerSecond,
			AnimationKind.Sequence => this.children[this.index].handoffVelocity(),
			AnimationKind.Repeat => this.children[0].handoffVelocity(),
			AnimationKind.Delay => this.delayHandoffVelocity(),
		};
	}

	delayHandoffVelocity(): float64 {
		if (this.begun) {
			return this.children[0].handoffVelocity();
		}
		const previous = this.previous;
		return previous === null ? 0 : previous.handoffVelocity();
	}

	start(value: float64, now: float64, previous: Run | null): void {
		this.finished = false;
		this.settled = false;
		match (this.spec.kind) {
			AnimationKind.Timing => this.startTiming(value, now, previous),
			AnimationKind.Spring => this.startSpring(value, now, previous),
			AnimationKind.Decay => this.startDecay(value, now),
			AnimationKind.Sequence => this.startSequence(value, now, previous),
			AnimationKind.Delay => this.startDelay(value, now, previous),
			AnimationKind.Repeat => this.startRepeat(value, now, previous),
		};
	}

	continues(previous: Run): boolean {
		return !previous.finished && previous.spec.kind === this.spec.kind &&
			previous.to === this.to;
	}

	startTiming(value: float64, now: float64, previous: Run | null): void {
		this.current = value;
		if (this.reduce) {
			this.current = this.to;
			this.settled = true;
			return;
		}
		if (previous !== null && this.continues(previous)) {
			this.startTime = previous.startTime;
			this.startValue = previous.startValue;
			return;
		}
		this.startTime = now;
		this.startValue = value;
	}

	startSpring(value: float64, now: float64, previous: Run | null): void {
		this.current = value;
		if (this.reduce) {
			this.current = this.to;
			this.settled = true;
			return;
		}
		if (previous !== null && this.continues(previous) && previous.springSimulation !== null &&
			sameSpringConfig(previous.spec.spring, this.spec.spring)) {
			this.springSimulation = previous.springSimulation;
			this.startTime = previous.startTime;
			this.velocityPerSecond = previous.velocityPerSecond;
			return;
		}
		const carried = previous === null ? 0 : previous.handoffVelocity();
		const simulation = createSpring(
			this.spec.spring,
			value,
			this.to,
			carried + this.spec.velocityPerSecond,
		);
		this.springSimulation = simulation;
		this.startTime = now;
		this.velocityPerSecond = simulation.springVelocity(0);
	}

	startDecay(value: float64, now: float64): void {
		this.current = value;
		if (this.reduce) {
			const config = this.spec.decay;
			if (config.clampMin !== null && value < config.clampMin) {
				this.current = config.clampMin;
			} else if (config.clampMax !== null && value > config.clampMax) {
				this.current = config.clampMax;
			}
			this.settled = true;
			return;
		}
		this.decaySimulation = createDecay(this.spec.decay, value, this.spec.velocityPerSecond);
		this.startTime = now;
		this.velocityPerSecond = this.spec.velocityPerSecond;
	}

	nextUnreduced(from: int32): int32 {
		let index = from;
		while (index < this.children.length - 1 && this.children[index].reduce) {
			index += 1;
		}
		return index;
	}

	startSequence(value: float64, now: float64, previous: Run | null): void {
		for (const child of this.children) {
			this.inherit(child);
		}
		this.index = this.nextUnreduced(0);
		this.current = value;
		this.children[this.index].start(value, now, previous);
	}

	startDelay(value: float64, now: float64, previous: Run | null): void {
		this.startTime = now;
		this.begun = false;
		this.current = value;
		this.previous = previous;
		this.inherit(this.children[0]);
	}

	startRepeat(value: float64, now: float64, previous: Run | null): void {
		this.startValue = value;
		this.reps = 0;
		this.current = value;
		const child = this.children[0];
		this.inherit(child);
		const evenOrEndless = this.spec.count <= 0 || this.spec.count % 2 === 0;
		if (this.reduce && this.spec.reverse && evenOrEndless) {
			this.settled = true;
			return;
		}
		child.start(value, now, previous);
	}

	frame(now: float64): boolean {
		if (this.settled) {
			this.finished = true;
			return true;
		}
		const done = match (this.spec.kind) {
			AnimationKind.Timing => this.frameTiming(now),
			AnimationKind.Spring => this.frameSpring(now),
			AnimationKind.Decay => this.frameDecay(now),
			AnimationKind.Sequence => this.frameSequence(now),
			AnimationKind.Delay => this.frameDelay(now),
			AnimationKind.Repeat => this.frameRepeat(now),
		};
		this.finished = done;
		return done;
	}

	frameTiming(now: float64): boolean {
		let runtime = now - this.startTime;
		if (runtime < 0) {
			this.startTime = now;
			runtime = 0;
		}
		if (runtime >= this.spec.durationMs) {
			this.current = this.to;
			return true;
		}
		const progress = this.spec.easing(runtime / this.spec.durationMs);
		this.current = this.startValue + (this.to - this.startValue) * progress;
		return false;
	}

	frameSpring(now: float64): boolean {
		const simulation = this.springSimulation;
		if (simulation === null) {
			throw new Error("motion: a spring frame ran before the spring started");
		}
		const elapsed = now - this.startTime;
		this.current = simulation.springPosition(elapsed);
		this.velocityPerSecond = simulation.springVelocity(elapsed);
		return simulation.springIsDone(elapsed);
	}

	frameDecay(now: float64): boolean {
		const simulation = this.decaySimulation;
		if (simulation === null) {
			throw new Error("motion: a decay frame ran before the decay started");
		}
		const elapsed = now - this.startTime;
		this.current = simulation.decayPosition(elapsed);
		this.velocityPerSecond = simulation.decayVelocity(elapsed);
		return simulation.decayIsDone(elapsed);
	}

	frameSequence(now: float64): boolean {
		const child = this.children[this.index];
		const done = child.frame(now);
		this.current = child.current;
		if (!done) {
			return false;
		}
		this.index = this.nextUnreduced(this.index + 1);
		if (this.index < this.children.length) {
			this.children[this.index].start(child.current, now, child);
			return false;
		}
		this.index = this.children.length - 1;
		return true;
	}

	frameDelay(now: float64): boolean {
		const child = this.children[0];
		if (now - this.startTime >= this.spec.durationMs || this.reduce) {
			if (!this.begun) {
				child.start(this.current, now, this.previous);
				this.previous = null;
				this.begun = true;
			}
			const done = child.frame(now);
			this.current = child.current;
			return done;
		}
		const previous = this.previous;
		if (previous !== null) {
			const done = previous.finished || previous.frame(now);
			this.current = previous.current;
			if (done) {
				this.previous = null;
			}
		}
		return false;
	}

	frameRepeat(now: float64): boolean {
		const child = this.children[0];
		const done = child.frame(now);
		this.current = child.current;
		if (!done) {
			return false;
		}
		this.reps += 1;
		if (this.reduce || (this.spec.count > 0 && this.reps >= this.spec.count)) {
			return true;
		}
		const startValue = this.spec.reverse ? child.current : this.startValue;
		if (this.spec.reverse) {
			child.to = this.startValue;
			this.startValue = startValue;
		}
		child.start(startValue, now, null);
		return false;
	}
}

class Listener {
	callback: (value: float64) => void;
	live: boolean = true;

	constructor(callback: (value: float64) => void) {
		this.callback = callback;
	}
}

const LABEL = "an animated value";

export class AnimatedValue {
	private value: float64;
	private clock: Clock;
	private policy: MotionPolicy;
	private running: Run | null = null;
	private onEnd: ((finished: boolean) => void) | null = null;
	private frameId: int32 = 0;
	private listeners: Listener[] = [];
	private isDisposed: boolean = false;
	private target: MotionTarget | null;
	private composition: Composition;
	private claim: TargetClaim | null = null;

	constructor(
		value: float64,
		clock: Clock,
		policy: MotionPolicy,
		target: MotionTarget | null = null,
		composition: Composition = Composition.Replace,
	) {
		requireFinite(value, "an animated value");
		this.value = value;
		this.clock = clock;
		this.policy = policy;
		this.target = composition === Composition.None ? null : target;
		this.composition = composition;
	}

	get disposed(): boolean {
		return this.isDisposed;
	}

	get(): float64 {
		this.requireAlive();
		return this.value;
	}

	velocity(): float64 {
		this.requireAlive();
		const running = this.running;
		return running === null ? 0 : running.handoffVelocity();
	}

	isAnimating(): boolean {
		this.requireAlive();
		return this.running !== null;
	}

	set(value: float64): void {
		this.requireAlive();
		requireFinite(value, "an animated value");
		this.interrupt();
		const target = this.target;
		if (target === null) {
			this.write(value);
			return;
		}
		const previous = this.claim;
		const start = this.composition === Composition.Blend
			? target.blendFrom(previous, numberValue(value), LABEL)
			: numberValue(value);
		this.claim = target.claim(
			this.composition,
			start,
			numberValue(value),
			LABEL,
			previous,
			this.onReplaced(),
		);
		const out = this.output(value);
		this.release();
		this.write(out);
	}

	cancel(): void {
		this.requireAlive();
		this.interrupt();
		this.release();
	}

	animate(spec: AnimationSpec, onEnd: ((finished: boolean) => void) | null = null): void {
		this.requireAlive();
		const blend = this.target !== null && this.composition === Composition.Blend;
		const end = blend ? blendEnd(spec) : spec.to;
		const previous = this.interrupt();
		const target = this.target;
		const start = target === null || !blend
			? this.value
			: target.blendFrom(this.claim, numberValue(this.value), LABEL).number;
		const leaf = spec.kind === AnimationKind.Timing || spec.kind === AnimationKind.Spring;
		if (leaf && !blend && spec.to === start) {
			this.release();
			if (onEnd !== null) { onEnd(true); }
			return;
		}
		const run = new Run(spec, this.policy);
		if (!run.reduceSet) {
			run.reduce = shouldReduce(ReduceMotion.System, this.policy);
			run.reduceSet = true;
		}
		const now = this.clock.now();
		run.start(start, now, previous);
		if (target !== null) {
			this.claim = target.claim(
				this.composition,
				numberValue(start),
				numberValue(end),
				LABEL,
				this.claim,
				this.onReplaced(),
			);
		}
		this.running = run;
		this.onEnd = onEnd;
		this.step(run, now);
	}

	subscribe(callback: (value: float64) => void): () => void {
		this.requireAlive();
		const listener = new Listener(callback);
		this.listeners.push(listener);
		return (): void => {
			listener.live = false;
			this.listeners = this.listeners.filter(
				(other: Listener): boolean => other !== listener,
			);
		};
	}

	dispose(): void {
		this.requireAlive();
		this.isDisposed = true;
		for (const listener of this.listeners) {
			listener.live = false;
		}
		this.listeners = [];
		this.interrupt();
		this.release();
	}

	private requireAlive(): void {
		if (this.isDisposed) {
			throw new Error("motion: an AnimatedValue is used after dispose");
		}
	}

	private interrupt(): Run | null {
		const running = this.running;
		if (running === null) {
			return null;
		}
		this.running = null;
		if (this.frameId !== 0) {
			this.clock.cancel(this.frameId);
			this.frameId = 0;
		}
		const onEnd = this.onEnd;
		this.onEnd = null;
		if (onEnd !== null) { onEnd(false); }
		return running;
	}

	private onReplaced(): () => void {
		return (): void => {
			this.claim = null;
			this.interrupt();
		};
	}

	private release(): void {
		const claim = this.claim;
		const target = this.target;
		this.claim = null;
		if (claim !== null && target !== null) { target.release(claim); }
	}

	private output(value: float64): float64 {
		const claim = this.claim;
		const target = this.target;
		if (claim === null || target === null || this.composition !== Composition.Blend) {
			return value;
		}
		return target.blended(claim, numberValue(value), LABEL).number;
	}

	private write(value: float64): void {
		if (value === this.value) {
			return;
		}
		this.value = value;
		for (const listener of this.listeners.slice(0)) {
			if (listener.live) { listener.callback(value); }
		}
	}

	private step(run: Run, now: float64): void {
		const done = run.frame(now);
		this.write(this.output(run.current));
		if (this.running !== run) {
			return;
		}
		if (done) {
			this.running = null;
			this.release();
			const onEnd = this.onEnd;
			this.onEnd = null;
			if (onEnd !== null) { onEnd(true); }
			return;
		}
		this.frameId = this.clock.request((time: float64): void => {
			this.frameId = 0;
			this.step(run, time);
		});
	}
}
