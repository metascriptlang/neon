import { requestFrame, frameNow } from "../animation/frame";
import { Easing, EasingFunction, bezier } from "pulse/src/easing";
import { MotionPolicy } from "pulse/src/policy";
import { createSpring, position, springByDuration } from "pulse/src/spring";
import { AnimatedValue, delay, timing } from "pulse/src/value";
import { neonClock } from "./neon";

when (js && !server) {
	import { animateDomLayout } from "../platform/browser/layoutAnimation";
}

export type LayoutAnimationType = "spring" | "linear" | "easeInEaseOut" | "easeIn" | "easeOut" | "keyboard";
export type LayoutAnimationProperty = "opacity" | "scaleX" | "scaleY" | "scaleXY";

export interface LayoutAnimationAnim {
	type?: LayoutAnimationType | null;
	property?: LayoutAnimationProperty | null;
	duration?: number | null;
	delay?: number | null;
	springDamping?: number | null;
	initialVelocity?: number | null;
}

export interface LayoutAnimationConfig {
	duration: number;
	create?: LayoutAnimationAnim | null;
	update?: LayoutAnimationAnim | null;
	delete?: LayoutAnimationAnim | null;
}

export interface LayoutPhase {
	duration: number;
	delay: number;
	curve: EasingFunction;
	property: LayoutAnimationProperty;
}

export interface LayoutAnimationPlan {
	update: LayoutPhase | null;
	create: LayoutPhase | null;
}

let pending: LayoutAnimationConfig | null = null;

function springCurve(duration: number, damping: number, velocity: number): EasingFunction {
	const simulation = createSpring(springByDuration(duration, damping), 0, 1, velocity);
	return (t: number): number => t >= 1 ? 1 : simulation.position(t * duration);
}

function curveFor(anim: LayoutAnimationAnim, duration: number): EasingFunction {
	const type = anim.type ?? "easeInEaseOut";
	return match (type) {
		"linear" => Easing.linear,
		"easeIn" => bezier(0.42, 0, 1, 1),
		"easeOut" => bezier(0, 0, 0.58, 1),
		"keyboard" => bezier(0.17, 0.59, 0.4, 0.77),
		"spring" => springCurve(duration, anim.springDamping ?? 0.5, anim.initialVelocity ?? 0),
		_ => bezier(0.42, 0, 0.58, 1),
	};
}

function phase(anim: LayoutAnimationAnim | null, duration: number): LayoutPhase | null {
	if (anim === null || anim === undefined) { return null; }
	const a = anim as LayoutAnimationAnim;
	const length = a.duration ?? duration;
	return {
		duration: length,
		delay: a.delay ?? 0,
		curve: curveFor(a, length),
		property: a.property ?? "opacity",
	};
}

export function layoutPlan(config: LayoutAnimationConfig): LayoutAnimationPlan {
	return { update: phase(config.update, config.duration), create: phase(config.create, config.duration) };
}

export function takeLayoutAnimation(): LayoutAnimationPlan | null {
	const config = pending;
	pending = null;
	if (config === null) { return null; }
	return layoutPlan(config as LayoutAnimationConfig);
}

// Every field spelled out: a nested literal's absent fields read `undefined` on JS
// (compiler card 2026-10-06-js-optional-fields-through-nullable-constructor.md).
function anim(type: LayoutAnimationType, property: LayoutAnimationProperty | null, springDamping: number | null): LayoutAnimationAnim {
	return { type, property, duration: null, delay: null, springDamping, initialVelocity: null };
}

function createConfig(duration: number, type: LayoutAnimationType, property: LayoutAnimationProperty): LayoutAnimationConfig {
	return {
		duration,
		create: anim(type, property, null),
		update: anim(type, null, null),
		delete: anim(type, property, null),
	};
}

export class LayoutAnimation {
	// RN fires onAnimationDidEnd from a race timer at duration + 17 ms.
	static configureNext(
		config: LayoutAnimationConfig,
		onAnimationDidEnd: (() => void) | null = null,
		onAnimationDidFail: (() => void) | null = null,
	): void {
		pending = config;
		when (js && !server) { animateDomLayout(layoutPlan(config)); }
		if (onAnimationDidEnd === null) { return; }
		const done = onAnimationDidEnd as () => void;
		const due = frameNow() + config.duration + 17;
		const wait = (time: number): void => {
			if (frameNow() >= due) {
				done();
				return;
			}
			requestFrame(wait);
		};
		requestFrame(wait);
	}

	static create(
		duration: number,
		type: LayoutAnimationType = "easeInEaseOut",
		property: LayoutAnimationProperty = "opacity",
	): LayoutAnimationConfig {
		return createConfig(duration, type, property);
	}

	static easeInEaseOut(onAnimationDidEnd: (() => void) | null = null): void {
		LayoutAnimation.configureNext(createConfig(300, "easeInEaseOut", "opacity"), onAnimationDidEnd);
	}

	static linear(onAnimationDidEnd: (() => void) | null = null): void {
		LayoutAnimation.configureNext(createConfig(500, "linear", "opacity"), onAnimationDidEnd);
	}

	static spring(onAnimationDidEnd: (() => void) | null = null): void {
		LayoutAnimation.configureNext(LayoutAnimationPresets.spring, onAnimationDidEnd);
	}
}

export class LayoutAnimationPresets {
	static easeInEaseOut: LayoutAnimationConfig = createConfig(300, "easeInEaseOut", "opacity");
	static linear: LayoutAnimationConfig = createConfig(500, "linear", "opacity");
	static spring: LayoutAnimationConfig = {
		duration: 700,
		create: anim("linear", "opacity", null),
		update: anim("spring", null, 0.4),
		delete: anim("linear", "opacity", null),
	};
}

export function runLayoutTween(
	phaseOf: LayoutPhase,
	step: (progress: number) => void,
	finished: () => void,
): void {
	const progress = new AnimatedValue(0, neonClock(), new MotionPolicy());
	progress.subscribe(step);
	step(0);
	const tween = timing(1, { duration: phaseOf.duration, easing: phaseOf.curve });
	progress.animate(delay(phaseOf.delay, tween), (done: boolean): void => {
		if (done) { finished(); }
	});
}
