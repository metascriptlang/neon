import { requestFrame, frameNow } from "./frame";
import { Easing, EasingFunction, bezier } from "./easing";

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
	cssCurve: string;
	property: LayoutAnimationProperty;
}

export interface LayoutAnimationPlan {
	update: LayoutPhase | null;
	create: LayoutPhase | null;
}

let pending: LayoutAnimationConfig | null = null;
let listeners: ((plan: LayoutAnimationPlan) => void)[] = [];

// RN Android's SpringInterpolator for `type: "spring"`; keep the formula as is.
function springCurve(damping: number): EasingFunction {
	const factor = damping > 0 ? damping : 0.5;
	return (t: number): number => {
		if (t >= 1) { return 1; }
		return 1 + Math.pow(2, -10 * t) * Math.sin(((t - factor / 4) * (2 * Math.PI)) / factor);
	};
}

function curveFor(anim: LayoutAnimationAnim): EasingFunction {
	const type = anim.type ?? "easeInEaseOut";
	return match (type) {
		"linear" => Easing.linear,
		"easeIn" => bezier(0.42, 0, 1, 1),
		"easeOut" => bezier(0, 0, 0.58, 1),
		"keyboard" => bezier(0.17, 0.59, 0.4, 0.77),
		"spring" => springCurve(anim.springDamping ?? 0.5),
		_ => bezier(0.42, 0, 0.58, 1),
	};
}

function cssCurveFor(anim: LayoutAnimationAnim): string {
	const type = anim.type ?? "easeInEaseOut";
	return match (type) {
		"linear" => "linear",
		"easeIn" => "cubic-bezier(0.42, 0, 1, 1)",
		"easeOut" => "cubic-bezier(0, 0, 0.58, 1)",
		"keyboard" => "cubic-bezier(0.17, 0.59, 0.4, 0.77)",
		"spring" => "cubic-bezier(0.5, 1.6, 0.4, 0.8)",
		_ => "cubic-bezier(0.42, 0, 0.58, 1)",
	};
}

function phase(anim: LayoutAnimationAnim | null, duration: number): LayoutPhase | null {
	if (anim === null || anim === undefined) { return null; }
	const a = anim as LayoutAnimationAnim;
	return {
		duration: a.duration ?? duration,
		delay: a.delay ?? 0,
		curve: curveFor(a),
		cssCurve: cssCurveFor(a),
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

export function onConfigureNext(listener: (plan: LayoutAnimationPlan) => void): void {
	listeners.push(listener);
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
		const plan = layoutPlan(config);
		for (const listener of listeners) { listener(plan); }
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
	const start = frameNow() + phaseOf.delay;
	const tick = (time: number): void => {
		const now = frameNow();
		if (now < start) {
			requestFrame(tick);
			return;
		}
		const linear = phaseOf.duration <= 0 ? 1 : Math.min(1, (now - start) / phaseOf.duration);
		step(linear >= 1 ? 1 : phaseOf.curve(linear));
		if (linear >= 1) {
			finished();
			return;
		}
		requestFrame(tick);
	};
	step(0);
	requestFrame(tick);
}
