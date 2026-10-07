import { NeonNode } from "../render/hostTypes";
import { NeonEvent } from "../render/event";
import {
	View as PlainView,
	ViewProps,
	Text as PlainText,
	TextProps,
	ScrollView as PlainScrollView,
	ScrollViewProps,
} from "../components/primitives";
import { Image as PlainImage, ImageProps } from "../components/image";
import {
	Animation,
	EndCallback,
	EndResult,
	TimingAnimation,
	SpringAnimation,
	DecayAnimation,
} from "./animation";
import { EasingFunction } from "./easing";
import {
	AnimatedNode,
	AnimatedValue,
	AnimatedValueXY,
	AnimatedAddition,
	AnimatedSubtraction,
	AnimatedMultiplication,
	AnimatedDivision,
	AnimatedModulo,
	AnimatedDiffClamp,
	ValueXYInit,
} from "./nodes";

export class CompositeAnimation {
	constructor() {}
	start(callback: EndCallback | null = null): void {}
	stop(): void {}
	reset(): void {}
}

function finish(callback: EndCallback | null, result: EndResult): void {
	if (callback !== null) { (callback as EndCallback)(result); }
}

function combine(callback: EndCallback | null, onComplete: EndCallback | null): EndCallback | null {
	if (onComplete === null || onComplete === undefined) { return callback; }
	const done = onComplete as EndCallback;
	if (callback === null) { return done; }
	const user = callback as EndCallback;
	return (result: EndResult): void => {
		done(result);
		user(result);
	};
}

// RN starts and stops an Animation at most once: build a fresh one per start.
class ValueAnimation extends CompositeAnimation {
	value: AnimatedValue;
	target: number;
	node: AnimatedNode | null;
	make: (toValue: number) => Animation;
	onComplete: EndCallback | null;

	constructor(
		value: AnimatedValue,
		target: number,
		node: AnimatedNode | null,
		make: (toValue: number) => Animation,
		onComplete: EndCallback | null,
	) {
		super();
		this.value = value;
		this.target = target;
		this.node = node;
		this.make = make;
		this.onComplete = onComplete;
	}

	start(callback: EndCallback | null = null): void {
		const done = combine(callback, this.onComplete);
		this.value.stopTracking();
		const node = this.node;
		if (node === null) {
			this.value.animate(this.make(this.target), done);
		} else {
			this.value.track(node as AnimatedNode, this.make, done);
		}
	}

	stop(): void {
		this.value.stopAnimation();
	}

	reset(): void {
		this.value.resetAnimation();
	}
}

class SequenceAnimation extends CompositeAnimation {
	animations: CompositeAnimation[];
	current: int32 = 0;

	constructor(animations: CompositeAnimation[]) {
		super();
		this.animations = animations;
	}

	start(callback: EndCallback | null = null): void {
		if (this.animations.length === 0) {
			finish(callback, { finished: true });
			return;
		}
		const onComplete = (result: EndResult): void => {
			if (!result.finished) {
				finish(callback, result);
				return;
			}
			this.current += 1;
			if (this.current === this.animations.length) {
				this.current = 0;
				finish(callback, result);
				return;
			}
			this.animations[this.current].start(onComplete);
		};
		this.animations[this.current].start(onComplete);
	}

	stop(): void {
		if (this.current < this.animations.length) { this.animations[this.current].stop(); }
	}

	reset(): void {
		for (let i: int32 = 0; i < this.animations.length; i += 1) {
			if (i <= this.current) { this.animations[i].reset(); }
		}
		this.current = 0;
	}
}

export interface ParallelConfig {
	stopTogether?: boolean | null;
}

class ParallelAnimation extends CompositeAnimation {
	animations: (CompositeAnimation | null)[];
	stopTogether: boolean;
	doneCount: int32 = 0;
	ended: boolean[] = [];

	constructor(animations: (CompositeAnimation | null)[], stopTogether: boolean) {
		super();
		this.animations = animations;
		this.stopTogether = stopTogether;
		for (let i: int32 = 0; i < animations.length; i += 1) { this.ended.push(false); }
	}

	start(callback: EndCallback | null = null): void {
		if (this.doneCount === this.animations.length) {
			finish(callback, { finished: true });
			return;
		}
		for (let i: int32 = 0; i < this.animations.length; i += 1) {
			const index = i;
			const ended = (result: EndResult): void => {
				this.ended[index] = true;
				this.doneCount += 1;
				if (this.doneCount === this.animations.length) {
					this.doneCount = 0;
					finish(callback, result);
					return;
				}
				if (!result.finished && this.stopTogether) { this.stop(); }
			};
			const animation = this.animations[i];
			if (animation === null) {
				ended({ finished: true });
			} else {
				(animation as CompositeAnimation).start(ended);
			}
		}
	}

	stop(): void {
		for (let i: int32 = 0; i < this.animations.length; i += 1) {
			const animation = this.animations[i];
			if (!this.ended[i] && animation !== null) { (animation as CompositeAnimation).stop(); }
			this.ended[i] = true;
		}
	}

	reset(): void {
		for (let i: int32 = 0; i < this.animations.length; i += 1) {
			const animation = this.animations[i];
			if (animation !== null) { (animation as CompositeAnimation).reset(); }
			this.ended[i] = false;
		}
		this.doneCount = 0;
	}
}

export interface LoopAnimationConfig {
	iterations?: number | null;
	resetBeforeIteration?: boolean | null;
}

class LoopAnimation extends CompositeAnimation {
	animation: CompositeAnimation;
	iterations: number;
	resetBeforeIteration: boolean;
	isFinished: boolean = false;
	iterationsSoFar: number = 0;

	constructor(animation: CompositeAnimation, iterations: number, resetBeforeIteration: boolean) {
		super();
		this.animation = animation;
		this.iterations = iterations;
		this.resetBeforeIteration = resetBeforeIteration;
	}

	start(callback: EndCallback | null = null): void {
		const restart = (result: EndResult): void => {
			if (this.isFinished || this.iterationsSoFar === this.iterations || !result.finished) {
				finish(callback, result);
				return;
			}
			this.iterationsSoFar += 1;
			if (this.resetBeforeIteration) { this.animation.reset(); }
			this.animation.start(restart);
		};
		if (this.iterations === 0) {
			finish(callback, { finished: true });
			return;
		}
		restart({ finished: true });
	}

	stop(): void {
		this.isFinished = true;
		this.animation.stop();
	}

	reset(): void {
		this.iterationsSoFar = 0;
		this.isFinished = false;
		this.animation.reset();
	}
}

// RN's `toValue: number | AnimatedNode` is split: WORKAROUND.md N4.
export interface TimingConfig {
	toValue: number;
	toNode?: AnimatedNode | null;
	duration?: number | null;
	easing?: EasingFunction | null;
	delay?: number | null;
	useNativeDriver?: boolean | null;
	isInteraction?: boolean | null;
	onComplete?: EndCallback | null;
}

export interface TimingXYConfig {
	toValue: ValueXYInit;
	duration?: number | null;
	easing?: EasingFunction | null;
	delay?: number | null;
	useNativeDriver?: boolean | null;
	onComplete?: EndCallback | null;
}

export interface SpringConfig {
	toValue: number;
	toNode?: AnimatedNode | null;
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

export interface SpringXYConfig {
	toValue: ValueXYInit;
	velocity?: ValueXYInit | null;
	bounciness?: number | null;
	speed?: number | null;
	tension?: number | null;
	friction?: number | null;
	stiffness?: number | null;
	damping?: number | null;
	mass?: number | null;
	overshootClamping?: boolean | null;
	delay?: number | null;
	useNativeDriver?: boolean | null;
	onComplete?: EndCallback | null;
}

export interface DecayConfig {
	velocity: number;
	deceleration?: number | null;
	useNativeDriver?: boolean | null;
	isInteraction?: boolean | null;
	onComplete?: EndCallback | null;
}

export interface DecayXYConfig {
	velocity: ValueXYInit;
	deceleration?: number | null;
	useNativeDriver?: boolean | null;
	onComplete?: EndCallback | null;
}

function nodeOf(node: AnimatedNode | null): AnimatedNode | null {
	if (node === null || node === undefined) { return null; }
	return node;
}

function timingAnimation(value: AnimatedValue, config: TimingConfig): CompositeAnimation {
	const make = (toValue: number): Animation => new TimingAnimation({
		toValue,
		duration: config.duration,
		easing: config.easing,
		delay: config.delay,
	});
	return new ValueAnimation(value, config.toValue, nodeOf(config.toNode), make, config.onComplete ?? null);
}

function springAnimation(value: AnimatedValue, config: SpringConfig): CompositeAnimation {
	const make = (toValue: number): Animation => new SpringAnimation({
		toValue,
		overshootClamping: config.overshootClamping,
		restDisplacementThreshold: config.restDisplacementThreshold,
		restSpeedThreshold: config.restSpeedThreshold,
		velocity: config.velocity,
		bounciness: config.bounciness,
		speed: config.speed,
		tension: config.tension,
		friction: config.friction,
		stiffness: config.stiffness,
		damping: config.damping,
		mass: config.mass,
		delay: config.delay,
	});
	return new ValueAnimation(value, config.toValue, nodeOf(config.toNode), make, config.onComplete ?? null);
}

function decayAnimation(value: AnimatedValue, config: DecayConfig): CompositeAnimation {
	const make = (toValue: number): Animation => new DecayAnimation({
		velocity: config.velocity,
		deceleration: config.deceleration,
	});
	return new ValueAnimation(value, 0, null, make, config.onComplete ?? null);
}

function delayAnimation(time: number): CompositeAnimation {
	return timingAnimation(new AnimatedValue(0), { toValue: 0, delay: time, duration: 0 });
}

export interface EventMapping {
	x?: AnimatedValue | null;
	y?: AnimatedValue | null;
	width?: AnimatedValue | null;
	height?: AnimatedValue | null;
	contentWidth?: AnimatedValue | null;
	contentHeight?: AnimatedValue | null;
}

export interface EventConfig {
	listener?: ((e: NeonEvent) => void) | null;
	useNativeDriver?: boolean | null;
}

function drive(target: AnimatedValue | null, value: number): void {
	if (target !== null && target !== undefined) { (target as AnimatedValue).setValue(value); }
}

function eventHandler(mapping: EventMapping, config: EventConfig): (e: NeonEvent) => void {
	const listener = config.listener;
	return (e: NeonEvent): void => {
		drive(mapping.x, e.x);
		drive(mapping.y, e.y);
		drive(mapping.width, e.width);
		drive(mapping.height, e.height);
		drive(mapping.contentWidth, e.contentWidth);
		drive(mapping.contentHeight, e.contentHeight);
		if (listener !== null && listener !== undefined) { (listener as (e: NeonEvent) => void)(e); }
	};
}

export class Animated {
	static View: (props: ViewProps) => NeonNode = PlainView;
	static Text: (props: TextProps) => NeonNode = PlainText;
	static Image: (props: ImageProps) => NeonNode = PlainImage;
	static ScrollView: (props: ScrollViewProps) => NeonNode = PlainScrollView;

	static Value(value: number = 0): AnimatedValue {
		return new AnimatedValue(value);
	}

	static ValueXY(value: ValueXYInit = { x: 0, y: 0 }): AnimatedValueXY {
		return new AnimatedValueXY(value);
	}

	static timing(value: AnimatedValue, config: TimingConfig): CompositeAnimation {
		return timingAnimation(value, config);
	}

	static timingXY(value: AnimatedValueXY, config: TimingXYConfig): CompositeAnimation {
		const shared = { duration: config.duration, easing: config.easing, delay: config.delay };
		const x = timingAnimation(value.x, { toValue: config.toValue.x, duration: shared.duration, easing: shared.easing, delay: shared.delay });
		const y = timingAnimation(value.y, { toValue: config.toValue.y, duration: shared.duration, easing: shared.easing, delay: shared.delay });
		return new ParallelAnimation([x, y], false);
	}

	static spring(value: AnimatedValue, config: SpringConfig): CompositeAnimation {
		return springAnimation(value, config);
	}

	static springXY(value: AnimatedValueXY, config: SpringXYConfig): CompositeAnimation {
		const v = config.velocity;
		const vx = v !== null && v !== undefined ? (v as ValueXYInit).x : 0;
		const vy = v !== null && v !== undefined ? (v as ValueXYInit).y : 0;
		const x = springAnimation(value.x, {
			toValue: config.toValue.x, velocity: vx, bounciness: config.bounciness, speed: config.speed,
			tension: config.tension, friction: config.friction, stiffness: config.stiffness,
			damping: config.damping, mass: config.mass, overshootClamping: config.overshootClamping, delay: config.delay,
		});
		const y = springAnimation(value.y, {
			toValue: config.toValue.y, velocity: vy, bounciness: config.bounciness, speed: config.speed,
			tension: config.tension, friction: config.friction, stiffness: config.stiffness,
			damping: config.damping, mass: config.mass, overshootClamping: config.overshootClamping, delay: config.delay,
		});
		return new ParallelAnimation([x, y], false);
	}

	static decay(value: AnimatedValue, config: DecayConfig): CompositeAnimation {
		return decayAnimation(value, config);
	}

	static decayXY(value: AnimatedValueXY, config: DecayXYConfig): CompositeAnimation {
		const x = decayAnimation(value.x, { velocity: config.velocity.x, deceleration: config.deceleration });
		const y = decayAnimation(value.y, { velocity: config.velocity.y, deceleration: config.deceleration });
		return new ParallelAnimation([x, y], false);
	}

	static delay(time: number): CompositeAnimation {
		return delayAnimation(time);
	}

	static sequence(animations: CompositeAnimation[]): CompositeAnimation {
		return new SequenceAnimation(animations);
	}

	static parallel(animations: (CompositeAnimation | null)[], config: ParallelConfig = {}): CompositeAnimation {
		return new ParallelAnimation(animations, config.stopTogether ?? true);
	}

	static stagger(time: number, animations: CompositeAnimation[]): CompositeAnimation {
		const staged: (CompositeAnimation | null)[] = [];
		for (let i: int32 = 0; i < animations.length; i += 1) {
			staged.push(new SequenceAnimation([delayAnimation(time * (i as number)), animations[i]]));
		}
		return new ParallelAnimation(staged, true);
	}

	static loop(animation: CompositeAnimation, config: LoopAnimationConfig = {}): CompositeAnimation {
		return new LoopAnimation(animation, config.iterations ?? -1, config.resetBeforeIteration ?? true);
	}

	// Node operands only: WORKAROUND.md N4.
	static add(a: AnimatedNode, b: AnimatedNode): AnimatedNode {
		return new AnimatedAddition(a, b);
	}

	static subtract(a: AnimatedNode, b: AnimatedNode): AnimatedNode {
		return new AnimatedSubtraction(a, b);
	}

	static multiply(a: AnimatedNode, b: AnimatedNode): AnimatedNode {
		return new AnimatedMultiplication(a, b);
	}

	static divide(a: AnimatedNode, b: AnimatedNode): AnimatedNode {
		return new AnimatedDivision(a, b);
	}

	static modulo(a: AnimatedNode, modulus: number): AnimatedNode {
		return new AnimatedModulo(a, modulus);
	}

	static diffClamp(a: AnimatedNode, min: number, max: number): AnimatedNode {
		return new AnimatedDiffClamp(a, min, max);
	}

	static event(mapping: EventMapping, config: EventConfig = {}): (e: NeonEvent) => void {
		return eventHandler(mapping, config);
	}

	static forkEvent(
		event: ((e: NeonEvent) => void) | null,
		listener: (e: NeonEvent) => void,
	): (e: NeonEvent) => void {
		if (event === null) { return listener; }
		const first = event as (e: NeonEvent) => void;
		return (e: NeonEvent): void => {
			first(e);
			listener(e);
		};
	}

	static unforkEvent(event: ((e: NeonEvent) => void) | null, listener: (e: NeonEvent) => void): void {}
}

export function useAnimatedValue(initial: number = 0): AnimatedValue {
	return new AnimatedValue(initial);
}
