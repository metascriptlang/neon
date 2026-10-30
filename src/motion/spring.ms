export enum SpringKind {
	UnderDamped,
	CriticallyDamped,
	OverDamped,
}

export struct SpringConfig {
	useDuration: boolean;
	mass: float64;
	stiffness: float64;
	damping: float64;
	durationMs: float64;
	dampingRatio: float64;
	energyThreshold: float64;
	overshootClamping: boolean;
	clampMin: float64 | null;
	clampMax: float64 | null;
}

export struct SpringSimulation {
	config: SpringConfig;
	from: float64;
	to: float64;
	initialVelocityPerSecond: float64;
	stiffness: float64;
	zeta: float64;
	omega0: float64;
	initialEnergy: float64;
	kind: SpringKind;
	rate1: float64;
	rate2: float64;
	coefficient1: float64;
	coefficient2: float64;
	frequency: float64;
	crossSeconds: float64;
	instant: boolean;
}

const CRITICAL_ZETA_TOLERANCE = 1e-9;
const DURATION_PERCEPTUAL_COEFFICIENT = 1.5;
const MAX_SEARCH_STIFFNESS = 8e3;

export function springByStiffness(
	stiffness: float64 = 900,
	damping: float64 = 120,
	mass: float64 = 4,
): SpringConfig {
	return {
		useDuration: false,
		mass,
		stiffness,
		damping,
		durationMs: 0,
		dampingRatio: 0,
		energyThreshold: 6e-9,
		overshootClamping: false,
		clampMin: null,
		clampMax: null,
	};
}

export function springByDuration(
	durationMs: float64 = 550,
	dampingRatio: float64 = 1,
	mass: float64 = 4,
): SpringConfig {
	return {
		useDuration: true,
		mass,
		stiffness: 0,
		damping: 0,
		durationMs,
		dampingRatio,
		energyThreshold: 6e-9,
		overshootClamping: false,
		clampMin: null,
		clampMax: null,
	};
}

function requirePositive(value: float64, name: string): void {
	if (!Number.isFinite(value) || value <= 0) {
		throw new Error("motion: spring " + name + " must be finite and greater than zero, got " + value);
	}
}

function requireFinite(value: float64, name: string): void {
	if (!Number.isFinite(value)) {
		throw new Error("motion: spring " + name + " must be finite, got " + value);
	}
}

function validate(config: SpringConfig): void {
	requirePositive(config.mass, "mass");
	requirePositive(config.energyThreshold, "energyThreshold");
	if (config.useDuration) {
		requireFinite(config.durationMs, "durationMs");
		if (config.durationMs < 0) {
			throw new Error("motion: spring durationMs can't be negative, got " + config.durationMs);
		}
		requirePositive(config.dampingRatio, "dampingRatio");
	} else {
		requirePositive(config.stiffness, "stiffness");
		requirePositive(config.damping, "damping");
	}
	if (config.clampMin !== null) {
		requireFinite(config.clampMin, "clampMin");
	}
	if (config.clampMax !== null) {
		requireFinite(config.clampMax, "clampMax");
	}
	if (config.clampMin !== null && config.clampMax !== null && config.clampMin > config.clampMax) {
		throw new Error("motion: spring clampMin must not exceed clampMax");
	}
}

function energy(
	displacement: float64,
	velocityPerSecond: float64,
	stiffness: float64,
	mass: float64,
): float64 {
	return 0.5 * stiffness * displacement * displacement +
		0.5 * mass * velocityPerSecond * velocityPerSecond;
}

function energyFractionAtSettle(
	stiffness: float64,
	x0: float64,
	v0: float64,
	config: SpringConfig,
): float64 {
	const settlingSeconds = config.durationMs * DURATION_PERCEPTUAL_COEFFICIENT / 1000;
	const decayRate = Math.sqrt(stiffness / config.mass) * config.dampingRatio;
	const envelope = Math.exp(-decayRate * settlingSeconds);
	const slope = v0 + x0 * decayRate;
	const xAtSettle = (x0 + slope * settlingSeconds) * envelope;
	const vAtSettle = xAtSettle * -decayRate + slope * envelope;
	return energy(xAtSettle, vAtSettle, stiffness, config.mass) /
		energy(x0, v0, stiffness, config.mass);
}

function stiffnessForDuration(x0: float64, v0: float64, config: SpringConfig): float64 {
	const threshold = config.energyThreshold;
	const precision = threshold * 1e-3;
	let low = 2.220446049250313e-16;
	let high = MAX_SEARCH_STIFFNESS;
	const direction =
		energyFractionAtSettle(high, x0, v0, config) >= energyFractionAtSettle(low, x0, v0, config)
			? 1
			: -1;
	let current = (high + low) / 2;
	let remaining = 100;
	while (
		Math.abs(energyFractionAtSettle(current, x0, v0, config) - threshold) > precision &&
		remaining > 0
	) {
		remaining -= 1;
		if ((energyFractionAtSettle(current, x0, v0, config) - threshold) * direction < 0) {
			low = current;
		} else {
			high = current;
		}
		current = (low + high) / 2;
	}
	return current;
}

function zetaToMatchClamps(
	zeta: float64,
	x0: float64,
	to: float64,
	clampMin: float64 | null,
	clampMax: float64 | null,
): float64 {
	if (x0 === 0) {
		return zeta;
	}
	const startsAtOrBelow = x0 <= 0;
	const firstBound = startsAtOrBelow ? clampMin : clampMax;
	const secondBound = startsAtOrBelow ? clampMax : clampMin;
	let result = zeta;
	if (secondBound !== null) {
		const relative = Math.abs((secondBound - to) / x0);
		result = Math.max(result, relative > 0 ? Math.abs(Math.log(relative) / Math.PI) : 1);
	}
	if (firstBound !== null) {
		const relative = Math.abs((firstBound - to) / x0);
		result = Math.max(result, relative > 0 ? Math.abs(Math.log(relative) / (2 * Math.PI)) : 1);
	}
	return result;
}

function firstCrossSeconds(
	kind: SpringKind,
	rate1: float64,
	rate2: float64,
	coefficient1: float64,
	coefficient2: float64,
	frequency: float64,
): float64 {
	if (kind === SpringKind.UnderDamped) {
		const angle = Math.atan2(-coefficient1, coefficient2);
		return (angle > 0 ? angle : angle + Math.PI) / frequency;
	}
	if (kind === SpringKind.CriticallyDamped) {
		const root = coefficient2 === 0 ? -1 : -coefficient1 / coefficient2;
		return root > 0 ? root : Infinity;
	}
	const ratio = coefficient2 === 0 ? 0 : -coefficient1 / coefficient2;
	return ratio > 1 ? Math.log(ratio) / (rate2 - rate1) : Infinity;
}

function assemble(
	config: SpringConfig,
	stiffness: float64,
	zeta: float64,
	omega0: float64,
	initialEnergy: float64,
	from: float64,
	to: float64,
	velocityPerSecond: float64,
	instant: boolean,
): SpringSimulation {
	const x0 = from - to;
	let kind = SpringKind.UnderDamped;
	let rate1 = -zeta * omega0;
	let rate2: float64 = 0;
	let coefficient1 = x0;
	let coefficient2: float64 = 0;
	let frequency: float64 = 0;
	if (Math.abs(zeta - 1) <= CRITICAL_ZETA_TOLERANCE) {
		kind = SpringKind.CriticallyDamped;
		rate1 = -omega0;
		coefficient2 = velocityPerSecond - rate1 * x0;
	} else if (zeta < 1) {
		frequency = omega0 * Math.sqrt(1 - zeta * zeta);
		coefficient2 = (velocityPerSecond - rate1 * x0) / frequency;
	} else {
		kind = SpringKind.OverDamped;
		const spread = Math.sqrt(zeta * zeta - 1);
		rate1 = omega0 * (-zeta - spread);
		rate2 = omega0 * (-zeta + spread);
		coefficient2 = (velocityPerSecond - rate1 * x0) / (rate2 - rate1);
		coefficient1 = x0 - coefficient2;
	}
	let crossSeconds = Infinity;
	if (config.overshootClamping) {
		crossSeconds = x0 === 0
			? 0
			: firstCrossSeconds(kind, rate1, rate2, coefficient1, coefficient2, frequency);
	}
	return {
		config,
		from,
		to,
		initialVelocityPerSecond: velocityPerSecond,
		stiffness,
		zeta,
		omega0,
		initialEnergy,
		kind,
		rate1,
		rate2,
		coefficient1,
		coefficient2,
		frequency,
		crossSeconds,
		instant,
	};
}

function towardTarget(from: float64, to: float64, velocityPerSecond: float64): float64 {
	const away = (to > from && velocityPerSecond < 0) || (to < from && velocityPerSecond > 0);
	return away ? 0 : velocityPerSecond;
}

function startSpring(
	config: SpringConfig,
	from: float64,
	to: float64,
	v0: float64,
): SpringSimulation {
	const x0 = from - to;
	const instant = config.useDuration && config.durationMs === 0;
	let stiffness = config.stiffness;
	let zeta: float64 = 0;
	let omega0: float64 = 0;
	if (!instant && (x0 !== 0 || v0 !== 0)) {
		if (config.useDuration) {
			stiffness = stiffnessForDuration(x0, v0, config);
			zeta = config.dampingRatio;
		} else {
			zeta = config.damping / (2 * Math.sqrt(stiffness * config.mass));
		}
		omega0 = Math.sqrt(stiffness / config.mass);
		if (config.clampMin !== null || config.clampMax !== null) {
			zeta = zetaToMatchClamps(zeta, x0, to, config.clampMin, config.clampMax);
		}
	}
	const initialEnergy = energy(x0, v0, stiffness, config.mass);
	return assemble(config, stiffness, zeta, omega0, initialEnergy, from, to, v0, instant);
}

export function createSpring(
	config: SpringConfig,
	from: float64,
	to: float64,
	velocityPerSecond: float64 = 0,
): SpringSimulation {
	validate(config);
	requireFinite(from, "from");
	requireFinite(to, "to");
	requireFinite(velocityPerSecond, "velocity");
	return startSpring(config, from, to, towardTarget(from, to, velocityPerSecond));
}

function requireTime(tMs: float64): float64 {
	requireFinite(tMs, "time");
	return Math.max(tMs, 0) / 1000;
}

function displacementAt(this s: SpringSimulation, seconds: float64): float64 {
	if (s.kind === SpringKind.UnderDamped) {
		return Math.exp(s.rate1 * seconds) * (
			s.coefficient1 * Math.cos(s.frequency * seconds) +
				s.coefficient2 * Math.sin(s.frequency * seconds)
		);
	}
	if (s.kind === SpringKind.CriticallyDamped) {
		return (s.coefficient1 + s.coefficient2 * seconds) * Math.exp(s.rate1 * seconds);
	}
	return s.coefficient1 * Math.exp(s.rate1 * seconds) +
		s.coefficient2 * Math.exp(s.rate2 * seconds);
}

function rateAt(this s: SpringSimulation, seconds: float64): float64 {
	if (s.kind === SpringKind.UnderDamped) {
		const envelope = Math.exp(s.rate1 * seconds);
		const cosine = Math.cos(s.frequency * seconds);
		const sine = Math.sin(s.frequency * seconds);
		return envelope * (
			s.coefficient2 * s.frequency * cosine - s.coefficient1 * s.frequency * sine
		) + s.rate1 * envelope * (s.coefficient1 * cosine + s.coefficient2 * sine);
	}
	if (s.kind === SpringKind.CriticallyDamped) {
		const envelope = Math.exp(s.rate1 * seconds);
		return envelope * (s.coefficient2 + s.rate1 * (s.coefficient1 + s.coefficient2 * seconds));
	}
	return s.coefficient1 * s.rate1 * Math.exp(s.rate1 * seconds) +
		s.coefficient2 * s.rate2 * Math.exp(s.rate2 * seconds);
}

function doneAtSeconds(this s: SpringSimulation, seconds: float64): boolean {
	if (s.instant || s.initialEnergy === 0 || seconds >= s.crossSeconds) {
		return true;
	}
	const remaining =
		energy(s.displacementAt(seconds), s.rateAt(seconds), s.stiffness, s.config.mass);
	return remaining / s.initialEnergy <= s.config.energyThreshold;
}

export function isDone(this s: SpringSimulation, tMs: float64): boolean {
	return s.doneAtSeconds(requireTime(tMs));
}

export function position(this s: SpringSimulation, tMs: float64): float64 {
	const seconds = requireTime(tMs);
	return s.doneAtSeconds(seconds) ? s.to : s.to + s.displacementAt(seconds);
}

export function velocity(this s: SpringSimulation, tMs: float64): float64 {
	const seconds = requireTime(tMs);
	return s.doneAtSeconds(seconds) ? 0 : s.rateAt(seconds);
}

export function retarget(this s: SpringSimulation, tMs: float64, to: float64): SpringSimulation {
	requireFinite(to, "to");
	if (s.isDone(tMs)) {
		return createSpring(s.config, s.to, to, 0);
	}
	const x = s.position(tMs);
	const v = s.velocity(tMs);
	if (to === s.to) {
		return assemble(s.config, s.stiffness, s.zeta, s.omega0, s.initialEnergy, x, to, v, false);
	}
	return startSpring(s.config, x, to, v);
}
