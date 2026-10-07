// RN's Easing module (Libraries/Animated/Easing.js, bezier.js), ported member by
// member. A class of statics rather than RN's object of functions: a default
// argument (`Easing.back()`, `Easing.elastic()`) is lost when the function is
// called through a field value (compiler card
// 2026-10-07-default-parameter-lost-through-a-function-value.md).

export type EasingFunction = (t: number) => number;

const NEWTON_ITERATIONS: int32 = 4;
const NEWTON_MIN_SLOPE = 0.001;
const SUBDIVISION_PRECISION = 0.0000001;
const SUBDIVISION_MAX_ITERATIONS: int32 = 10;
const SPLINE_TABLE_SIZE: int32 = 11;
const SAMPLE_STEP_SIZE = 0.1;

function coefficientA(a1: number, a2: number): number { return 1.0 - 3.0 * a2 + 3.0 * a1; }
function coefficientB(a1: number, a2: number): number { return 3.0 * a2 - 6.0 * a1; }
function coefficientC(a1: number): number { return 3.0 * a1; }

function calcBezier(t: number, a1: number, a2: number): number {
	return ((coefficientA(a1, a2) * t + coefficientB(a1, a2)) * t + coefficientC(a1)) * t;
}

function bezierSlope(t: number, a1: number, a2: number): number {
	return 3.0 * coefficientA(a1, a2) * t * t + 2.0 * coefficientB(a1, a2) * t + coefficientC(a1);
}

function binarySubdivide(x: number, lowStart: number, highStart: number, x1: number, x2: number): number {
	let low = lowStart;
	let high = highStart;
	let currentT = 0.0;
	let currentX = 0.0;
	let i: int32 = 0;
	do {
		currentT = low + (high - low) / 2.0;
		currentX = calcBezier(currentT, x1, x2) - x;
		if (currentX > 0.0) { high = currentT; } else { low = currentT; }
		i += 1;
	} while (Math.abs(currentX) > SUBDIVISION_PRECISION && i < SUBDIVISION_MAX_ITERATIONS);
	return currentT;
}

function newtonRaphson(x: number, guess: number, x1: number, x2: number): number {
	let t = guess;
	for (let i: int32 = 0; i < NEWTON_ITERATIONS; i += 1) {
		const slope = bezierSlope(t, x1, x2);
		if (slope === 0.0) { return t; }
		t -= (calcBezier(t, x1, x2) - x) / slope;
	}
	return t;
}

export function bezier(x1: number, y1: number, x2: number, y2: number): EasingFunction {
	if (!(x1 >= 0 && x1 <= 1 && x2 >= 0 && x2 <= 1)) {
		throw new Error("bezier x values must be in [0, 1] range");
	}
	const samples: number[] = [];
	for (let i: int32 = 0; i < SPLINE_TABLE_SIZE; i += 1) {
		samples.push(calcBezier((i as number) * SAMPLE_STEP_SIZE, x1, x2));
	}
	const tForX = (x: number): number => {
		let intervalStart = 0.0;
		let current: int32 = 1;
		const last = SPLINE_TABLE_SIZE - 1;
		while (current !== last && samples[current] <= x) {
			intervalStart += SAMPLE_STEP_SIZE;
			current += 1;
		}
		current -= 1;
		const dist = (x - samples[current]) / (samples[current + 1] - samples[current]);
		const guess = intervalStart + dist * SAMPLE_STEP_SIZE;
		const slope = bezierSlope(guess, x1, x2);
		if (slope >= NEWTON_MIN_SLOPE) { return newtonRaphson(x, guess, x1, x2); }
		if (slope === 0.0) { return guess; }
		return binarySubdivide(x, intervalStart, intervalStart + SAMPLE_STEP_SIZE, x1, x2);
	};
	return (x: number): number => {
		if (x1 === y1 && x2 === y2) { return x; }
		if (x === 0) { return 0; }
		if (x === 1) { return 1; }
		return calcBezier(tForX(x), y1, y2);
	};
}

let easeCurve: EasingFunction | null = null;

function step0Curve(n: number): number { return n > 0 ? 1 : 0; }
function step1Curve(n: number): number { return n >= 1 ? 1 : 0; }
function linearCurve(t: number): number { return t; }

function easeOnce(t: number): number {
	if (easeCurve === null) { easeCurve = bezier(0.42, 0, 1, 1); }
	return (easeCurve as EasingFunction)(t);
}

function quadCurve(t: number): number { return t * t; }
function cubicCurve(t: number): number { return t * t * t; }
function sinCurve(t: number): number { return 1 - Math.cos((t * Math.PI) / 2); }
function circleCurve(t: number): number { return 1 - Math.sqrt(1 - t * t); }
function expCurve(t: number): number { return Math.pow(2, 10 * (t - 1)); }

function bounceCurve(t: number): number {
	if (t < 1 / 2.75) { return 7.5625 * t * t; }
	if (t < 2 / 2.75) {
		const t2 = t - 1.5 / 2.75;
		return 7.5625 * t2 * t2 + 0.75;
	}
	if (t < 2.5 / 2.75) {
		const t2 = t - 2.25 / 2.75;
		return 7.5625 * t2 * t2 + 0.9375;
	}
	const t2 = t - 2.625 / 2.75;
	return 7.5625 * t2 * t2 + 0.984375;
}

// An optional easing with its default. A function rather than an inline
// ternary: a ternary arm reading a static closure field, stored into a class
// field, corrupts the static on C (compiler card
// 2026-10-07-ternary-of-static-closure-into-field-corrupts-the-static.md).
export function easingOr(easing: EasingFunction | null, fallback: EasingFunction): EasingFunction {
	if (easing !== null && easing !== undefined) { return easing as EasingFunction; }
	return fallback;
}

// The parameterless curves are function-valued static fields, not static
// methods: a static method read as a value (`Easing.in(Easing.quad)`) breaks
// on both backends (compiler handover card, row "a static method read as a
// value", sighting 2026-10-07).
export class Easing {
	static step0: EasingFunction = step0Curve;
	static step1: EasingFunction = step1Curve;
	static linear: EasingFunction = linearCurve;
	static ease: EasingFunction = easeOnce;
	static quad: EasingFunction = quadCurve;
	static cubic: EasingFunction = cubicCurve;
	static sin: EasingFunction = sinCurve;
	static circle: EasingFunction = circleCurve;
	static exp: EasingFunction = expCurve;
	static bounce: EasingFunction = bounceCurve;

	static poly(n: number): EasingFunction {
		return (t: number): number => Math.pow(t, n);
	}

	static elastic(bounciness: number = 1): EasingFunction {
		const p = bounciness * Math.PI;
		return (t: number): number => 1 - Math.pow(Math.cos((t * Math.PI) / 2), 3) * Math.cos(t * p);
	}

	static back(s: number = 1.70158): EasingFunction {
		return (t: number): number => t * t * ((s + 1) * t - s);
	}

	static bezier(x1: number, y1: number, x2: number, y2: number): EasingFunction {
		return bezier(x1, y1, x2, y2);
	}

	static in(easing: EasingFunction): EasingFunction { return easing; }

	static out(easing: EasingFunction): EasingFunction {
		return (t: number): number => 1 - easing(1 - t);
	}

	static inOut(easing: EasingFunction): EasingFunction {
		return (t: number): number => {
			if (t < 0.5) { return easing(t * 2) / 2; }
			return 1 - easing((1 - t) * 2) / 2;
		};
	}
}
