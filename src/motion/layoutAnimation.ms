import { requestFrame, frameNow } from "../animation/frame";
import { Easing, EasingFunction, bezier } from "pulse/src/easing";
import { createSpring, position, springByDuration } from "pulse/src/spring";
import { AnimatedValue, delay, timing } from "pulse/src/value";
import { hostMotionPolicy, neonClock } from "./neon";

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
	css: string | null;
	property: LayoutAnimationProperty;
}

export interface LayoutAnimationPlan {
	update: LayoutPhase | null;
	create: LayoutPhase | null;
	delete: LayoutPhase | null;
}

let pending: LayoutAnimationConfig | null = null;

function springCurve(duration: number, damping: number, velocity: number): EasingFunction {
	const simulation = createSpring(springByDuration(duration, damping), 0, 1, velocity);
	return (t: number): number => t >= 1 ? 1 : simulation.position(t * duration);
}

function bezierPoints(type: LayoutAnimationType): number[] | null {
	return match (type) {
		"linear" => [0, 0, 1, 1],
		"easeIn" => [0.42, 0, 1, 1],
		"easeOut" => [0, 0, 0.58, 1],
		"keyboard" => [0.17, 0.59, 0.4, 0.77],
		"spring" => null,
		_ => [0.42, 0, 0.58, 1],
	};
}

function curveFor(anim: LayoutAnimationAnim, duration: number): EasingFunction {
	const type: LayoutAnimationType = anim.type ?? "easeInEaseOut";
	if (type === "linear") { return Easing.linear; }
	const points = bezierPoints(type);
	if (points === null) { return springCurve(duration, anim.springDamping ?? 0.5, anim.initialVelocity ?? 0); }
	const p = points as number[];
	return bezier(p[0], p[1], p[2], p[3]);
}

function cssEasing(anim: LayoutAnimationAnim): string | null {
	const points = bezierPoints(anim.type ?? "easeInEaseOut");
	return points === null ? null : `cubic-bezier(${(points as number[]).join(", ")})`;
}

function phase(anim: LayoutAnimationAnim | null, duration: number): LayoutPhase | null {
	if (anim === null || anim === undefined) { return null; }
	const a = anim as LayoutAnimationAnim;
	const length = a.duration ?? duration;
	return {
		duration: length,
		delay: a.delay ?? 0,
		curve: curveFor(a, length),
		css: cssEasing(a),
		property: a.property ?? "opacity",
	};
}

function absent<T>(value: T | null | undefined): boolean {
	return value === null || value === undefined;
}

function animUnparsed(anim: LayoutAnimationAnim | null | undefined, withProperty: boolean): boolean {
	if (absent(anim)) { return false; }
	const a = anim as LayoutAnimationAnim;
	return absent(a.type) || (withProperty && absent(a.property));
}

function unparsed(config: LayoutAnimationConfig): boolean {
	return animUnparsed(config.create, true) || animUnparsed(config.update, false) ||
		animUnparsed(config.delete, true);
}

export function layoutPlan(config: LayoutAnimationConfig): LayoutAnimationPlan {
	return {
		update: phase(config.update, config.duration),
		create: phase(config.create, config.duration),
		delete: phase(config.delete, config.duration),
	};
}

export function armedLayoutAnimation(): LayoutAnimationPlan | null {
	const config = pending;
	return config === null ? null : layoutPlan(config as LayoutAnimationConfig);
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
		if (unparsed(config)) {
			if (onAnimationDidFail !== null) { (onAnimationDidFail as () => void)(); }
		} else {
			when (js && !server) {
				animateDomLayout(layoutPlan(config));
			} else {
				pending = config;
			}
		}
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
	const progress = new AnimatedValue(0, neonClock(), hostMotionPolicy());
	progress.subscribe(step);
	step(0);
	const tween = timing(1, { duration: phaseOf.duration, easing: phaseOf.curve });
	progress.animate(delay(phaseOf.delay, tween), (done: boolean): void => {
		if (done) { finished(); }
	});
}
