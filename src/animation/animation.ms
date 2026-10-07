// The driver half of RN's Animated (Libraries/Animated/animations/*.js): an
// Animation moves one number from where a value is towards a target, one
// frame at a time, and reports once when it ends. Every animation here is
// JS-driven in RN's terms: it runs on Neon's frame loop and writes the value
// through its signal, so `useNativeDriver` is accepted and has no effect.

import { requestFrame, cancelFrame, frameNow } from "./frame";
import { Easing, EasingFunction, easingOr } from "./easing";

export interface EndResult {
	finished: boolean;
}

export type EndCallback = (result: EndResult) => void;

export class Animation {
	active: boolean = false;
	onEnd: EndCallback | null = null;
	frame: int32 = -1;
	delayFrame: int32 = -1;

	constructor() {}

	start(
		fromValue: number,
		onUpdate: (value: number) => void,
		onEnd: EndCallback | null,
		previous: Animation | null,
	): void {
		this.begin(onEnd);
	}

	// RN's `super.start(...)`; a subclass calls this by name because
	// `super.method()` fails on both backends (compiler card
	// 2026-10-07-super-method-call-fails-on-c-and-js.md).
	begin(onEnd: EndCallback | null): void {
		this.onEnd = onEnd;
		this.active = true;
	}

	stop(): void {
		this.active = false;
		this.cancelFrames();
		this.notifyEnd(false);
	}

	cancelFrames(): void {
		if (this.frame >= 0) { cancelFrame(this.frame); }
		if (this.delayFrame >= 0) { cancelFrame(this.delayFrame); }
		this.frame = -1;
		this.delayFrame = -1;
	}

	notifyEnd(finished: boolean): void {
		const callback = this.onEnd;
		this.onEnd = null;
		this.active = false;
		if (callback !== null) { (callback as EndCallback)({ finished }); }
	}

	// RN starts a delayed animation from a `setTimeout`; Neon waits on the frame
	// clock instead, so a manual clock in a test drives the delay too.
	afterDelay(delay: number, run: () => void): void {
		if (delay <= 0) {
			run();
			return;
		}
		const due = frameNow() + delay;
		const wait = (time: number): void => {
			this.delayFrame = -1;
			if (!this.active) { return; }
			if (frameNow() >= due) {
				run();
				return;
			}
			this.delayFrame = requestFrame(wait);
		};
		this.delayFrame = requestFrame(wait);
	}
}

export interface TimingAnimationConfig {
	toValue: number;
	duration?: number | null;
	easing?: EasingFunction | null;
	delay?: number | null;
	useNativeDriver?: boolean | null;
	isInteraction?: boolean | null;
	onComplete?: EndCallback | null;
}

let easeInOutCurve: EasingFunction | null = null;

function defaultTimingEasing(): EasingFunction {
	if (easeInOutCurve === null) { easeInOutCurve = Easing.inOut(Easing.ease); }
	return easeInOutCurve as EasingFunction;
}

export class TimingAnimation extends Animation {
	startTime: number = 0;
	fromValue: number = 0;
	toValue: number;
	duration: number;
	delay: number;
	easing: EasingFunction;
	update: (value: number) => void = (value: number): void => {};

	constructor(config: TimingAnimationConfig) {
		super();
		this.toValue = config.toValue;
		this.easing = easingOr(config.easing, defaultTimingEasing());
		this.duration = config.duration ?? 500;
		this.delay = config.delay ?? 0;
	}

	// RN `__getNativeAnimationConfig().frames`: the eased progress sampled at 60 Hz.
	frames(): number[] {
		const frameDuration = 1000.0 / 60.0;
		const out: number[] = [];
		const count = Math.round(this.duration / frameDuration);
		for (let frame = 0; frame < count; frame += 1) {
			out.push(this.easing(frame / count));
		}
		out.push(this.easing(1));
		return out;
	}

	start(
		fromValue: number,
		onUpdate: (value: number) => void,
		onEnd: EndCallback | null,
		previous: Animation | null,
	): void {
		this.begin(onEnd);
		this.fromValue = fromValue;
		this.update = onUpdate;
		this.afterDelay(this.delay, (): void => {
			this.startTime = frameNow();
			if (this.duration === 0) {
				this.update(this.toValue);
				this.notifyEnd(true);
			} else {
				this.frame = requestFrame((time: number): void => { this.onFrame(); });
			}
		});
	}

	onFrame(): void {
		this.frame = -1;
		const now = frameNow();
		if (now >= this.startTime + this.duration) {
			this.update(this.fromValue + this.easing(1) * (this.toValue - this.fromValue));
			this.notifyEnd(true);
			return;
		}
		const progress = this.easing((now - this.startTime) / this.duration);
		this.update(this.fromValue + progress * (this.toValue - this.fromValue));
		if (this.active) {
			this.frame = requestFrame((time: number): void => { this.onFrame(); });
		}
	}
}

export interface SpringAnimationConfig {
	toValue: number;
	overshootClamping?: boolean | null;
	restDisplacementThreshold?: number | null;
	restSpeedThreshold?: number | null;
	velocity?: number | null;
	bounciness?: number | null;
	speed?: number | null;
	tension?: number | null;
	friction?: number | null;
	stiffness?: number | null;
	damping?: number | null;
	mass?: number | null;
	delay?: number | null;
	useNativeDriver?: boolean | null;
	isInteraction?: boolean | null;
	onComplete?: EndCallback | null;
}

export interface SpringParameters {
	stiffness: number;
	damping: number;
}

function stiffnessFromOrigami(value: number): number { return (value - 30) * 3.62 + 194; }
function dampingFromOrigami(value: number): number { return (value - 8) * 3 + 25; }

// RN SpringConfig.js.
export function fromOrigamiTensionAndFriction(tension: number, friction: number): SpringParameters {
	return { stiffness: stiffnessFromOrigami(tension), damping: dampingFromOrigami(friction) };
}

function normalize(value: number, startValue: number, endValue: number): number {
	return (value - startValue) / (endValue - startValue);
}

function projectNormal(n: number, start: number, end: number): number {
	return start + n * (end - start);
}

function linearInterpolation(t: number, start: number, end: number): number {
	return t * end + (1 - t) * start;
}

function quadraticOutInterpolation(t: number, start: number, end: number): number {
	return linearInterpolation(2 * t - t * t, start, end);
}

function b3Friction1(x: number): number {
	return 0.0007 * Math.pow(x, 3) - 0.031 * Math.pow(x, 2) + 0.64 * x + 1.28;
}

function b3Friction2(x: number): number {
	return 0.000044 * Math.pow(x, 3) - 0.006 * Math.pow(x, 2) + 0.36 * x + 2;
}

function b3Friction3(x: number): number {
	return 0.00000045 * Math.pow(x, 3) - 0.000332 * Math.pow(x, 2) + 0.1078 * x + 5.84;
}

function b3Nobounce(tension: number): number {
	if (tension <= 18) { return b3Friction1(tension); }
	if (tension <= 44) { return b3Friction2(tension); }
	return b3Friction3(tension);
}

export function fromBouncinessAndSpeed(bounciness: number, speed: number): SpringParameters {
	let b = normalize(bounciness / 1.7, 0, 20);
	b = projectNormal(b, 0, 0.8);
	const s = normalize(speed / 1.7, 0, 20);
	const bouncyTension = projectNormal(s, 0.5, 200);
	const bouncyFriction = quadraticOutInterpolation(b, b3Nobounce(bouncyTension), 0.01);
	return { stiffness: stiffnessFromOrigami(bouncyTension), damping: dampingFromOrigami(bouncyFriction) };
}

const ABSENT = -1.0e300;

// An absent optional number reads as `undefined` on JS and `null` on C; `??`
// folds both (WORKAROUND.md L4 describes the same absence gap).
function present(value: number | null): boolean {
	return (value ?? ABSENT) !== ABSENT;
}

export class SpringAnimation extends Animation {
	overshootClamping: boolean;
	restDisplacementThreshold: number;
	restSpeedThreshold: number;
	initialVelocity: number;
	lastVelocity: number;
	startPosition: number = 0;
	lastPosition: number = 0;
	toValue: number;
	stiffness: number;
	damping: number;
	mass: number;
	delay: number;
	lastTime: number = 0;
	frameTime: number = 0;
	update: (value: number) => void = (value: number): void => {};

	constructor(config: SpringAnimationConfig) {
		super();
		this.overshootClamping = config.overshootClamping ?? false;
		this.restDisplacementThreshold = config.restDisplacementThreshold ?? 0.001;
		this.restSpeedThreshold = config.restSpeedThreshold ?? 0.001;
		this.initialVelocity = config.velocity ?? 0;
		this.lastVelocity = config.velocity ?? 0;
		this.toValue = config.toValue;
		this.delay = config.delay ?? 0;
		const physical = present(config.stiffness) || present(config.damping) || present(config.mass);
		const bouncy = present(config.bounciness) || present(config.speed);
		const origami = present(config.tension) || present(config.friction);
		if ((physical && (bouncy || origami)) || (bouncy && origami)) {
			throw new Error("You can define one of bounciness/speed, tension/friction, or stiffness/damping/mass, but not more than one");
		}
		if (physical) {
			this.stiffness = config.stiffness ?? 100;
			this.damping = config.damping ?? 10;
			this.mass = config.mass ?? 1;
		} else if (bouncy) {
			const p = fromBouncinessAndSpeed(config.bounciness ?? 8, config.speed ?? 12);
			this.stiffness = p.stiffness;
			this.damping = p.damping;
			this.mass = 1;
		} else {
			const p = fromOrigamiTensionAndFriction(config.tension ?? 40, config.friction ?? 7);
			this.stiffness = p.stiffness;
			this.damping = p.damping;
			this.mass = 1;
		}
		if (!(this.stiffness > 0)) { throw new Error("Stiffness value must be greater than 0"); }
		if (!(this.damping > 0)) { throw new Error("Damping value must be greater than 0"); }
		if (!(this.mass > 0)) { throw new Error("Mass value must be greater than 0"); }
	}

	start(
		fromValue: number,
		onUpdate: (value: number) => void,
		onEnd: EndCallback | null,
		previous: Animation | null,
	): void {
		this.begin(onEnd);
		this.startPosition = fromValue;
		this.lastPosition = fromValue;
		this.update = onUpdate;
		this.lastTime = frameNow();
		this.frameTime = 0.0;
		if (previous !== null && previous instanceof SpringAnimation) {
			const before = previous as SpringAnimation;
			this.lastPosition = before.lastPosition;
			this.lastVelocity = before.lastVelocity;
			this.initialVelocity = this.lastVelocity;
			this.lastTime = before.lastTime;
		}
		this.afterDelay(this.delay, (): void => { this.onFrame(); });
	}

	// RN's closed-form damped harmonic oscillator, the model CASpringAnimation uses.
	onFrame(): void {
		this.frame = -1;
		const maxSteps = 64;
		let now = frameNow();
		if (now > this.lastTime + maxSteps) { now = this.lastTime + maxSteps; }
		const deltaTime = (now - this.lastTime) / 1000;
		this.frameTime += deltaTime;
		const c = this.damping;
		const m = this.mass;
		const k = this.stiffness;
		const v0 = -this.initialVelocity;
		const zeta = c / (2 * Math.sqrt(k * m));
		const omega0 = Math.sqrt(k / m);
		const omega1 = omega0 * Math.sqrt(1.0 - zeta * zeta);
		const x0 = this.toValue - this.startPosition;
		let position = 0.0;
		let velocity = 0.0;
		const t = this.frameTime;
		if (zeta < 1) {
			const envelope = Math.exp(-zeta * omega0 * t);
			position = this.toValue - envelope * (((v0 + zeta * omega0 * x0) / omega1) * Math.sin(omega1 * t) + x0 * Math.cos(omega1 * t));
			velocity = zeta * omega0 * envelope * ((Math.sin(omega1 * t) * (v0 + zeta * omega0 * x0)) / omega1 + x0 * Math.cos(omega1 * t))
				- envelope * (Math.cos(omega1 * t) * (v0 + zeta * omega0 * x0) - omega1 * x0 * Math.sin(omega1 * t));
		} else {
			const envelope = Math.exp(-omega0 * t);
			position = this.toValue - envelope * (x0 + (v0 + omega0 * x0) * t);
			velocity = envelope * (v0 * (t * omega0 - 1) + t * x0 * (omega0 * omega0));
		}
		this.lastTime = now;
		this.lastPosition = position;
		this.lastVelocity = velocity;
		this.update(position);
		if (!this.active) { return; }
		let overshooting = false;
		if (this.overshootClamping && this.stiffness !== 0) {
			overshooting = this.startPosition < this.toValue ? position > this.toValue : position < this.toValue;
		}
		const resting = Math.abs(velocity) <= this.restSpeedThreshold;
		let settled = true;
		if (this.stiffness !== 0) { settled = Math.abs(this.toValue - position) <= this.restDisplacementThreshold; }
		if (overshooting || (resting && settled)) {
			if (this.stiffness !== 0) {
				this.lastPosition = this.toValue;
				this.lastVelocity = 0;
				this.update(this.toValue);
			}
			this.notifyEnd(true);
			return;
		}
		this.frame = requestFrame((time: number): void => { this.onFrame(); });
	}
}

export interface DecayAnimationConfig {
	velocity: number;
	deceleration?: number | null;
	useNativeDriver?: boolean | null;
	isInteraction?: boolean | null;
	onComplete?: EndCallback | null;
}

export class DecayAnimation extends Animation {
	startTime: number = 0;
	lastValue: number = 0;
	fromValue: number = 0;
	deceleration: number;
	velocity: number;
	update: (value: number) => void = (value: number): void => {};

	constructor(config: DecayAnimationConfig) {
		super();
		this.deceleration = config.deceleration ?? 0.998;
		this.velocity = config.velocity;
	}

	start(
		fromValue: number,
		onUpdate: (value: number) => void,
		onEnd: EndCallback | null,
		previous: Animation | null,
	): void {
		this.begin(onEnd);
		this.lastValue = fromValue;
		this.fromValue = fromValue;
		this.update = onUpdate;
		this.startTime = frameNow();
		this.frame = requestFrame((time: number): void => { this.onFrame(); });
	}

	onFrame(): void {
		this.frame = -1;
		const now = frameNow();
		const value = this.fromValue + (this.velocity / (1 - this.deceleration))
			* (1 - Math.exp(-(1 - this.deceleration) * (now - this.startTime)));
		this.update(value);
		if (Math.abs(this.lastValue - value) < 0.1) {
			this.notifyEnd(true);
			return;
		}
		this.lastValue = value;
		if (this.active) {
			this.frame = requestFrame((time: number): void => { this.onFrame(); });
		}
	}
}
