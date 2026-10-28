import { MotionValue, ValueKind, colorValue, numberValue } from "./document";

export enum Composition {
	Replace,
	Blend,
	None,
}

export class TargetClaim {
	composition: Composition;
	end: MotionValue;
	scale: float64[];
	delta: MotionValue;
	onReplaced: () => void;

	constructor(
		composition: Composition,
		end: MotionValue,
		scale: float64[],
		delta: MotionValue,
		onReplaced: () => void,
	) {
		this.composition = composition;
		this.end = end;
		this.scale = scale;
		this.delta = delta;
		this.onReplaced = onReplaced;
	}
}

function fail(message: string): never {
	throw new Error("motion: " + message);
}

function channels(value: MotionValue): float64[] {
	if (value.kind === ValueKind.Number) { return [value.number]; }
	return [value.color.r, value.color.g, value.color.b, value.color.a];
}

function fromChannels(kind: ValueKind, parts: float64[]): MotionValue {
	if (kind === ValueKind.Number) { return numberValue(parts[0]); }
	return colorValue(parts[0], parts[1], parts[2], parts[3]);
}

function sameKind(a: MotionValue, b: MotionValue, label: string): void {
	if (a.kind !== b.kind) { fail(label + " blends a number with a colour"); }
}

function plus(a: MotionValue, b: MotionValue, label: string): MotionValue {
	sameKind(a, b, label);
	const left = channels(a);
	const right = channels(b);
	const out: float64[] = [];
	for (let i: int32 = 0; i < left.length; i += 1) { out.push(left[i] + right[i]); }
	return fromChannels(a.kind, out);
}

function scaledDelta(
	value: MotionValue,
	end: MotionValue,
	scale: float64[],
	label: string,
): MotionValue {
	sameKind(value, end, label);
	const current = channels(value);
	const last = channels(end);
	const out: float64[] = [];
	for (let i: int32 = 0; i < current.length; i += 1) { out.push((current[i] - last[i]) * scale[i]); }
	return fromChannels(value.kind, out);
}

export class MotionTarget {
	private claims: TargetClaim[] = [];
	private base: MotionValue = numberValue(0);

	get writers(): int32 {
		return this.claims.length;
	}

	blendFrom(previous: TargetClaim | null, fallback: MotionValue, label: string): MotionValue {
		if (this.claims.length === 0 || this.claims[0].composition !== Composition.Blend) {
			return fallback;
		}
		return previous === null ? this.base : plus(this.base, previous.delta, label);
	}

	claim(
		composition: Composition,
		start: MotionValue,
		end: MotionValue,
		label: string,
		previous: TargetClaim | null,
		onReplaced: () => void,
	): TargetClaim {
		if (composition === Composition.None) {
			fail(label + " composes with None and claims no target");
		}
		if (composition === Composition.Replace) {
			const claim = new TargetClaim(composition, end, [1], numberValue(0), onReplaced);
			this.replaceAll(claim, previous);
			return claim;
		}
		const from = this.blendFrom(previous, start, label);
		sameKind(from, end, label);
		sameKind(start, end, label);
		const towards = channels(from);
		const own = channels(start);
		const last = channels(end);
		const scale: float64[] = [];
		for (let i: int32 = 0; i < last.length; i += 1) {
			if (own[i] !== last[i]) {
				scale.push((towards[i] - last[i]) / (own[i] - last[i]));
			} else if (towards[i] !== last[i]) {
				fail(label + " starts where it ends and cannot join a blend in flight");
			} else {
				scale.push(1);
			}
		}
		const delta = scaledDelta(start, end, scale, label);
		const claim = new TargetClaim(composition, end, scale, delta, onReplaced);
		if (this.claims.length > 0 && this.claims[0].composition === Composition.Replace) {
			this.replaceAll(claim, previous);
		} else {
			this.drop(previous);
			this.claims.push(claim);
		}
		this.base = end;
		return claim;
	}

	blended(claim: TargetClaim, value: MotionValue, label: string): MotionValue {
		claim.delta = scaledDelta(value, claim.end, claim.scale, label);
		let out = this.base;
		for (const other of this.claims) { out = plus(out, other.delta, label); }
		return out;
	}

	release(claim: TargetClaim): void {
		this.drop(claim);
	}

	private drop(claim: TargetClaim | null): void {
		if (claim === null) { return; }
		this.claims = this.claims.filter((other: TargetClaim): boolean => other !== claim);
	}

	private replaceAll(claim: TargetClaim, previous: TargetClaim | null): void {
		const older = this.claims.filter((other: TargetClaim): boolean => other !== previous);
		this.claims = [claim];
		for (const other of older) { other.onReplaced(); }
	}
}
