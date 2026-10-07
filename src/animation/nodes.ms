// The value half of RN's Animated (Libraries/Animated/nodes/*.js) on Neon's
// signals. An AnimatedValue is a signal; reading `get()` inside a style
// subscribes that one style to it, so a frame updates exactly the properties
// that read the value and nothing re-renders. Derived nodes (interpolate, add,
// multiply, diffClamp, …) recompute from their parents on read, so they track
// through to the same signals.

import { Signal, Accessor, accessor, untrack } from "../core/signal";
import { createEffect } from "../core/effect";
import { createRoot } from "../core/owner";
import { Dispose } from "../core/types";
import { Easing, EasingFunction, easingOr } from "./easing";
import { Animation, EndCallback, EndResult } from "./animation";

export interface ValueState {
	value: number;
}

export type ValueListener = (state: ValueState) => void;

export type ExtrapolateType = "extend" | "identity" | "clamp";

export interface InterpolationConfig {
	inputRange: number[];
	outputRange: number[];
	easing?: EasingFunction | null;
	extrapolate?: ExtrapolateType | null;
	extrapolateLeft?: ExtrapolateType | null;
	extrapolateRight?: ExtrapolateType | null;
}

export interface StringInterpolationConfig {
	inputRange: number[];
	outputRange: string[];
	easing?: EasingFunction | null;
	extrapolate?: ExtrapolateType | null;
	extrapolateLeft?: ExtrapolateType | null;
	extrapolateRight?: ExtrapolateType | null;
}

interface ListenerEntry {
	id: string;
	callback: ValueListener;
	dispose: Dispose | null;
}

interface DerivedListener {
	node: AnimatedNode;
	entry: ListenerEntry;
}

let nextListenerId: int32 = 1;

function listenerId(): string {
	const id = nextListenerId;
	nextListenerId += 1;
	return id.toString();
}

// The listeners of derived nodes. AnimatedNode itself holds no field: a base
// class with a field whose method constructs a subclass (`interpolate`) breaks
// the build (compiler card
// 2026-10-07-base-class-method-returning-a-later-subclass-breaks-fields.md).
let derivedListeners: DerivedListener[] = [];

function disposeEntry(entry: ListenerEntry): void {
	if (entry.dispose !== null) { (entry.dispose as Dispose)(); }
}

export class AnimatedNode {
	constructor() {}

	// The tracked read: inside a style, a memo or an effect it subscribes.
	get(): number {
		return 0;
	}

	// The untracked read (RN `__getValue`).
	peek(): number {
		return untrack((): number => this.get());
	}

	__getValue(): number {
		return this.peek();
	}

	accessor(): Accessor<number> {
		return accessor((): number => this.get());
	}

	interpolate(config: InterpolationConfig): AnimatedInterpolation {
		return new AnimatedInterpolation(this, config);
	}

	interpolateString(config: StringInterpolationConfig): AnimatedStringInterpolation {
		return new AnimatedStringInterpolation(this, config);
	}

	// A derived node has no setter to hook, so a listener is an effect that
	// watches the computed value and reports each change after the first read.
	addListener(callback: ValueListener): string {
		const id = listenerId();
		let primed = false;
		const dispose = createRoot((d: Dispose): Dispose => {
			createEffect((): void => {
				const value = this.get();
				if (!primed) {
					primed = true;
					return;
				}
				untrack((): void => { callback({ value }); });
			});
			return d;
		});
		derivedListeners.push({ node: this, entry: { id, callback, dispose } });
		return id;
	}

	removeListener(id: string): void {
		const kept: DerivedListener[] = [];
		for (const l of derivedListeners) {
			if (l.node === this && l.entry.id === id) { disposeEntry(l.entry); } else { kept.push(l); }
		}
		derivedListeners = kept;
	}

	removeAllListeners(): void {
		const kept: DerivedListener[] = [];
		for (const l of derivedListeners) {
			if (l.node === this) { disposeEntry(l.entry); } else { kept.push(l); }
		}
		derivedListeners = kept;
	}
}

export class AnimatedValue extends AnimatedNode {
	listeners: ListenerEntry[] = [];
	value: number;
	offset: number = 0;
	startingValue: number;
	signal: Signal<number>;
	animation: Animation | null = null;
	tracking: Dispose | null = null;

	constructor(value: number = 0) {
		super();
		this.value = value;
		this.startingValue = value;
		this.signal = new Signal<number>(value);
	}

	get(): number {
		return this.signal.get();
	}

	peek(): number {
		return this.value + this.offset;
	}

	addListener(callback: ValueListener): string {
		const id = listenerId();
		this.listeners.push({ id, callback, dispose: null });
		return id;
	}

	removeListener(id: string): void {
		const kept: ListenerEntry[] = [];
		for (const entry of this.listeners) {
			if (entry.id !== id) { kept.push(entry); }
		}
		this.listeners = kept;
	}

	removeAllListeners(): void {
		this.listeners = [];
	}

	setValue(value: number): void {
		const running = this.animation;
		if (running !== null) {
			this.animation = null;
			(running as Animation).stop();
		}
		this.updateValue(value);
	}

	setOffset(offset: number): void {
		this.offset = offset;
		this.publish();
	}

	flattenOffset(): void {
		this.value += this.offset;
		this.offset = 0;
		this.publish();
	}

	extractOffset(): void {
		this.offset += this.value;
		this.value = 0;
		this.publish();
	}

	stopAnimation(callback: ((value: number) => void) | null = null): void {
		this.stopTracking();
		const running = this.animation;
		this.animation = null;
		if (running !== null) { (running as Animation).stop(); }
		if (callback !== null) { (callback as (value: number) => void)(this.peek()); }
	}

	resetAnimation(callback: ((value: number) => void) | null = null): void {
		this.stopAnimation(callback);
		this.value = this.startingValue;
		this.publish();
	}

	animate(animation: Animation, callback: EndCallback | null): void {
		const previous = this.animation;
		if (previous !== null) { (previous as Animation).stop(); }
		this.animation = animation;
		animation.start(
			this.value,
			(value: number): void => { this.updateValue(value); },
			(result: EndResult): void => {
				if (this.animation === animation) { this.animation = null; }
				if (callback !== null) { (callback as EndCallback)(result); }
			},
			previous,
		);
	}

	stopTracking(): void {
		const t = this.tracking;
		this.tracking = null;
		if (t !== null) { (t as Dispose)(); }
	}

	// RN AnimatedTracking: every change of `target` restarts `make(target)` on
	// this value, beginning with the target's current value.
	track(target: AnimatedNode, make: (toValue: number) => Animation, callback: EndCallback | null): void {
		this.stopTracking();
		this.tracking = createRoot((d: Dispose): Dispose => {
			createEffect((): void => {
				const toValue = target.get();
				untrack((): void => { this.animate(make(toValue), callback); });
			});
			return d;
		});
	}

	updateValue(value: number): void {
		this.value = value;
		this.publish();
	}

	publish(): void {
		const current = this.value + this.offset;
		this.signal.set(current);
		if (this.listeners.length === 0) { return; }
		const snapshot = this.listeners;
		for (const entry of snapshot) { entry.callback({ value: current }); }
	}

	toJSON(): number {
		return this.peek();
	}
}

export class AnimatedAddition extends AnimatedNode {
	a: AnimatedNode;
	b: AnimatedNode;
	constructor(a: AnimatedNode, b: AnimatedNode) {
		super();
		this.a = a;
		this.b = b;
	}
	get(): number { return this.a.get() + this.b.get(); }
}

export class AnimatedSubtraction extends AnimatedNode {
	a: AnimatedNode;
	b: AnimatedNode;
	constructor(a: AnimatedNode, b: AnimatedNode) {
		super();
		this.a = a;
		this.b = b;
	}
	get(): number { return this.a.get() - this.b.get(); }
}

export class AnimatedMultiplication extends AnimatedNode {
	a: AnimatedNode;
	b: AnimatedNode;
	constructor(a: AnimatedNode, b: AnimatedNode) {
		super();
		this.a = a;
		this.b = b;
	}
	get(): number { return this.a.get() * this.b.get(); }
}

export class AnimatedDivision extends AnimatedNode {
	a: AnimatedNode;
	b: AnimatedNode;
	warned: boolean = false;
	constructor(a: AnimatedNode, b: AnimatedNode) {
		super();
		this.a = a;
		this.b = b;
		if (this.b.peek() === 0) { console.log("Detected potential division by zero in AnimatedDivision"); }
	}
	get(): number {
		const a = this.a.get();
		const b = this.b.get();
		if (b === 0) {
			if (!this.warned) {
				console.log("Detected division by zero in AnimatedDivision");
				this.warned = true;
			}
			return 0;
		}
		this.warned = false;
		return a / b;
	}
}

export class AnimatedModulo extends AnimatedNode {
	a: AnimatedNode;
	modulus: number;
	constructor(a: AnimatedNode, modulus: number) {
		super();
		this.a = a;
		this.modulus = modulus;
	}
	get(): number {
		return ((this.a.get() % this.modulus) + this.modulus) % this.modulus;
	}
}

// RN's diffClamp folds every input change into a clamped running value. Reads
// are idempotent per input value here, because several readers (a style and a
// listener) read once per change where RN reads once.
export class AnimatedDiffClamp extends AnimatedNode {
	a: AnimatedNode;
	min: number;
	max: number;
	current: number;
	lastInput: number;
	constructor(a: AnimatedNode, min: number, max: number) {
		super();
		this.a = a;
		this.min = min;
		this.max = max;
		this.lastInput = a.peek();
		this.current = this.lastInput;
	}
	get(): number {
		const input = this.a.get();
		if (input === this.lastInput) { return this.current; }
		const diff = input - this.lastInput;
		this.lastInput = input;
		this.current = Math.min(Math.max(this.current + diff, this.min), this.max);
		return this.current;
	}
}

function extrapolateSide(side: ExtrapolateType | null, both: ExtrapolateType | null): ExtrapolateType {
	if (side !== null && side !== undefined) { return side as ExtrapolateType; }
	if (both !== null && both !== undefined) { return both as ExtrapolateType; }
	return "extend";
}

// RN AnimatedInterpolation.js `interpolate`.
export function interpolateSegment(
	input: number,
	inputMin: number,
	inputMax: number,
	outputMin: number,
	outputMax: number,
	easing: EasingFunction,
	extrapolateLeft: ExtrapolateType,
	extrapolateRight: ExtrapolateType,
): number {
	let result = input;
	if (result < inputMin) {
		if (extrapolateLeft === "identity") { return result; }
		if (extrapolateLeft === "clamp") { result = inputMin; }
	}
	if (result > inputMax) {
		if (extrapolateRight === "identity") { return result; }
		if (extrapolateRight === "clamp") { result = inputMax; }
	}
	if (outputMin === outputMax) { return outputMin; }
	if (inputMin === inputMax) {
		if (input <= inputMin) { return outputMin; }
		return outputMax;
	}
	if (inputMin === -Infinity) {
		result = -result;
	} else if (inputMax === Infinity) {
		result = result - inputMin;
	} else {
		result = (result - inputMin) / (inputMax - inputMin);
	}
	result = easing(result);
	if (outputMin === -Infinity) {
		result = -result;
	} else if (outputMax === Infinity) {
		result = result + outputMin;
	} else {
		result = result * (outputMax - outputMin) + outputMin;
	}
	return result;
}

function findRange(input: number, inputRange: number[]): int32 {
	let i: int32 = 1;
	while (i < inputRange.length - 1) {
		if (inputRange[i] >= input) { break; }
		i += 1;
	}
	return i - 1;
}

function checkRanges(inputRange: number[], outputLength: int32, outputInfinite: boolean): void {
	if (inputRange.length < 2) { throw new Error("inputRange must have at least 2 elements"); }
	if (outputLength < 2) { throw new Error("outputRange must have at least 2 elements"); }
	if (inputRange.length === 2 && inputRange[0] === -Infinity && inputRange[1] === Infinity) {
		throw new Error("inputRange cannot be ]-infinity;+infinity[");
	}
	if (outputInfinite) { throw new Error("outputRange cannot be ]-infinity;+infinity["); }
	for (let i: int32 = 1; i < inputRange.length; i += 1) {
		if (!(inputRange[i] >= inputRange[i - 1])) {
			throw new Error("inputRange must be monotonically non-decreasing");
		}
	}
	if (inputRange.length !== outputLength) {
		throw new Error(`inputRange (${inputRange.length}) and outputRange (${outputLength}) must have the same length`);
	}
}

export class NumericInterpolation {
	inputRange: number[];
	outputRange: number[];
	easing: EasingFunction;
	left: ExtrapolateType;
	right: ExtrapolateType;

	constructor(config: InterpolationConfig) {
		const out = config.outputRange;
		checkRanges(config.inputRange, out.length, out.length === 2 && out[0] === -Infinity && out[1] === Infinity);
		this.inputRange = config.inputRange;
		this.outputRange = out;
		this.easing = easingOr(config.easing, Easing.linear);
		this.left = extrapolateSide(config.extrapolateLeft, config.extrapolate);
		this.right = extrapolateSide(config.extrapolateRight, config.extrapolate);
	}

	at(input: number): number {
		const range = findRange(input, this.inputRange);
		return interpolateSegment(
			input,
			this.inputRange[range],
			this.inputRange[range + 1],
			this.outputRange[range],
			this.outputRange[range + 1],
			this.easing,
			this.left,
			this.right,
		);
	}
}

export class AnimatedInterpolation extends AnimatedNode {
	parent: AnimatedNode;
	curve: NumericInterpolation;

	constructor(parent: AnimatedNode, config: InterpolationConfig) {
		super();
		this.parent = parent;
		this.curve = new NumericInterpolation(config);
	}

	get(): number {
		return this.curve.at(this.parent.get());
	}
}

// ---- string outputs: colors and numbers inside text ("90deg", SVG paths) ----

interface StringShape {
	isColor: boolean;
	numbers: number[];
	texts: string[];
}

function digitCode(code: int32): boolean {
	return code >= 48 && code <= 57;
}

function hexDigit(code: int32): int32 {
	if (code >= 48 && code <= 57) { return code - 48; }
	if (code >= 97 && code <= 102) { return code - 87; }
	if (code >= 65 && code <= 70) { return code - 55; }
	return -1;
}

const NAMED_COLORS: string[][] = [
	["transparent", "0,0,0,0"],
	["black", "0,0,0,1"],
	["white", "255,255,255,1"],
	["red", "255,0,0,1"],
	["green", "0,128,0,1"],
	["blue", "0,0,255,1"],
	["yellow", "255,255,0,1"],
	["orange", "255,165,0,1"],
	["purple", "128,0,128,1"],
	["gray", "128,128,128,1"],
	["grey", "128,128,128,1"],
];

// Reads the numbers out of a string the way RN's numericComponentRegex does:
// `[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?`, keeping the text between them.
function splitNumbers(input: string): StringShape {
	const numbers: number[] = [];
	const texts: string[] = [];
	let text = "";
	let i: int32 = 0;
	while (i < input.length) {
		let j = i;
		const c = input.charCodeAt(j);
		if (c === 43 || c === 45) { j += 1; }
		const startDigits = j;
		while (j < input.length && digitCode(input.charCodeAt(j))) { j += 1; }
		let digits = j - startDigits;
		if (j < input.length && input.charCodeAt(j) === 46) {
			const afterDot = j + 1;
			let k = afterDot;
			while (k < input.length && digitCode(input.charCodeAt(k))) { k += 1; }
			if (digits > 0 || k > afterDot) {
				digits += k - afterDot;
				j = k;
			}
		}
		if (digits === 0) {
			text += input.charAt(i);
			i += 1;
			continue;
		}
		if (j < input.length && (input.charCodeAt(j) === 101 || input.charCodeAt(j) === 69)) {
			let k = j + 1;
			if (k < input.length && (input.charCodeAt(k) === 43 || input.charCodeAt(k) === 45)) { k += 1; }
			const expStart = k;
			while (k < input.length && digitCode(input.charCodeAt(k))) { k += 1; }
			if (k > expStart) { j = k; }
		}
		texts.push(text);
		text = "";
		numbers.push(parseFloat(input.substring(i, j)));
		i = j;
	}
	texts.push(text);
	return { isColor: false, numbers, texts };
}

function colorShape(r: number, g: number, b: number, a: number): StringShape {
	return { isColor: true, numbers: [r, g, b, a], texts: [] };
}

function parseColor(input: string): StringShape | null {
	const s = input.trim();
	if (s.length > 1 && s.charAt(0) === "#") {
		const body = s.substring(1, s.length);
		const n = body.length;
		if (n === 3 || n === 4 || n === 6 || n === 8) {
			const vals: int32[] = [];
			const step: int32 = n <= 4 ? 1 : 2;
			for (let i: int32 = 0; i < n; i += step) {
				let v: int32 = 0;
				for (let k: int32 = 0; k < step; k += 1) {
					const d = hexDigit(body.charCodeAt(i + k));
					if (d < 0) { return null; }
					v = v * 16 + d;
				}
				vals.push(step === 1 ? v * 17 : v);
			}
			const alpha = vals.length === 4 ? (vals[3] as number) / 255 : 1;
			return colorShape(vals[0] as number, vals[1] as number, vals[2] as number, alpha);
		}
		return null;
	}
	if (s.startsWith("rgba(") || s.startsWith("rgb(")) {
		const inner = splitNumbers(s);
		if (inner.numbers.length === 3) { return colorShape(inner.numbers[0], inner.numbers[1], inner.numbers[2], 1); }
		if (inner.numbers.length === 4) { return colorShape(inner.numbers[0], inner.numbers[1], inner.numbers[2], inner.numbers[3]); }
		return null;
	}
	for (const row of NAMED_COLORS) {
		if (row[0] === s) {
			const parts = row[1].split(",");
			return colorShape(parseFloat(parts[0]), parseFloat(parts[1]), parseFloat(parts[2]), parseFloat(parts[3]));
		}
	}
	return null;
}

function stringShape(input: string): StringShape {
	const color = parseColor(input);
	if (color !== null) { return color as StringShape; }
	const shape = splitNumbers(input);
	if (shape.numbers.length === 0) {
		throw new Error("outputRange must contain color or value with numeric component");
	}
	return shape;
}

function formatNumber(n: number): string {
	if (n === Math.round(n) && Math.abs(n) < 1e15) { return Math.round(n).toString(); }
	return n.toString();
}

export class AnimatedStringInterpolation {
	parent: AnimatedNode;
	shape: StringShape;
	curves: NumericInterpolation[] = [];

	constructor(parent: AnimatedNode, config: StringInterpolationConfig) {
		this.parent = parent;
		if (config.outputRange.length < 2) { throw new Error("Bad output range"); }
		const shapes: StringShape[] = [];
		for (const out of config.outputRange) { shapes.push(stringShape(out)); }
		this.shape = shapes[0];
		for (const s of shapes) {
			if (s.isColor !== this.shape.isColor) {
				throw new Error("All elements of output range should either be a color or a string with numeric components");
			}
			if (s.numbers.length !== this.shape.numbers.length) {
				throw new Error("All elements of output range should have the same number of components");
			}
			if (!s.isColor) {
				for (let i: int32 = 0; i < s.texts.length; i += 1) {
					if (s.texts[i] !== this.shape.texts[i]) {
						throw new Error("All elements of output range should have the same non-numeric components");
					}
				}
			}
		}
		for (let i: int32 = 0; i < this.shape.numbers.length; i += 1) {
			const outputs: number[] = [];
			for (const s of shapes) { outputs.push(s.numbers[i]); }
			this.curves.push(new NumericInterpolation({
				inputRange: config.inputRange,
				outputRange: outputs,
				easing: config.easing,
				extrapolate: config.extrapolate,
				extrapolateLeft: config.extrapolateLeft,
				extrapolateRight: config.extrapolateRight,
			}));
		}
	}

	at(input: number): string {
		if (this.shape.isColor) {
			const r = Math.round(this.curves[0].at(input));
			const g = Math.round(this.curves[1].at(input));
			const b = Math.round(this.curves[2].at(input));
			const a = Math.round(this.curves[3].at(input) * 1000) / 1000;
			return `rgba(${formatNumber(r)}, ${formatNumber(g)}, ${formatNumber(b)}, ${formatNumber(a)})`;
		}
		let out = "";
		for (let i: int32 = 0; i < this.curves.length; i += 1) {
			out += this.shape.texts[i];
			out += formatNumber(this.curves[i].at(input));
		}
		out += this.shape.texts[this.curves.length];
		return out;
	}

	get(): string {
		return this.at(this.parent.get());
	}

	peek(): string {
		return untrack((): string => this.get());
	}

	__getValue(): string {
		return this.peek();
	}

	accessor(): Accessor<string> {
		return accessor((): string => this.get());
	}
}

export interface ValueXYInit {
	x: number;
	y: number;
}

export interface LayoutXY {
	left: number;
	top: number;
}

export class AnimatedValueXY {
	x: AnimatedValue;
	y: AnimatedValue;
	listenerPairs: string[][] = [];

	constructor(value: ValueXYInit = { x: 0, y: 0 }) {
		this.x = new AnimatedValue(value.x);
		this.y = new AnimatedValue(value.y);
	}

	setValue(value: ValueXYInit): void {
		this.x.setValue(value.x);
		this.y.setValue(value.y);
	}

	setOffset(offset: ValueXYInit): void {
		this.x.setOffset(offset.x);
		this.y.setOffset(offset.y);
	}

	flattenOffset(): void {
		this.x.flattenOffset();
		this.y.flattenOffset();
	}

	extractOffset(): void {
		this.x.extractOffset();
		this.y.extractOffset();
	}

	get(): ValueXYInit {
		return { x: this.x.get(), y: this.y.get() };
	}

	peek(): ValueXYInit {
		return { x: this.x.peek(), y: this.y.peek() };
	}

	__getValue(): ValueXYInit {
		return this.peek();
	}

	stopAnimation(callback: ((value: ValueXYInit) => void) | null = null): void {
		this.x.stopAnimation();
		this.y.stopAnimation();
		if (callback !== null) { (callback as (value: ValueXYInit) => void)(this.peek()); }
	}

	resetAnimation(callback: ((value: ValueXYInit) => void) | null = null): void {
		this.x.resetAnimation();
		this.y.resetAnimation();
		if (callback !== null) { (callback as (value: ValueXYInit) => void)(this.peek()); }
	}

	addListener(callback: (value: ValueXYInit) => void): string {
		const id = listenerId();
		const report = (state: ValueState): void => { callback(this.peek()); };
		this.listenerPairs.push([id, this.x.addListener(report), this.y.addListener(report)]);
		return id;
	}

	removeListener(id: string): void {
		const kept: string[][] = [];
		for (const pair of this.listenerPairs) {
			if (pair[0] === id) {
				this.x.removeListener(pair[1]);
				this.y.removeListener(pair[2]);
			} else {
				kept.push(pair);
			}
		}
		this.listenerPairs = kept;
	}

	removeAllListeners(): void {
		this.x.removeAllListeners();
		this.y.removeAllListeners();
		this.listenerPairs = [];
	}

	// RN returns `{ left: x, top: y }` of AnimatedValues for a style spread;
	// Neon's style reads numbers, tracked here.
	getLayout(): LayoutXY {
		return { left: this.x.get(), top: this.y.get() };
	}

	// RN returns `[{ translateX: x }, { translateY: y }]`; Neon's transform is
	// the CSS string, tracked here.
	getTranslateTransform(): string {
		return `translateX(${this.x.get()}px) translateY(${this.y.get()}px)`;
	}
}
