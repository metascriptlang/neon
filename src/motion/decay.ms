export struct DecayConfig {
	deceleration: float64;
	velocityFactor: float64;
	velocityThreshold: float64;
	clampMin: float64 | null;
	clampMax: float64 | null;
	rubberBand: boolean;
	rubberBandFactor: float64;
}

export struct DecaySimulation {
	config: DecayConfig;
	from: float64;
	initialVelocityPerSecond: float64;
	decayPerSecond: float64;
	endSeconds: float64;
	snapsToBound: boolean;
	bound: float64;
	rubberStartSeconds: float64;
	rubberOffset: float64;
	rubberDecayCoefficient: float64;
	rubberSpringCoefficient: float64;
}

const SLOPE_FACTOR = 0.1;
const RUBBER_BAND_SETTLE_DISTANCE = 0.1;
const PEAK_REFINE_STEPS = 80;

export function decayConfig(): DecayConfig {
	return {
		deceleration: 0.998,
		velocityFactor: 1,
		velocityThreshold: 1,
		clampMin: null,
		clampMax: null,
		rubberBand: false,
		rubberBandFactor: 0.6,
	};
}

function requireFinite(value: float64, name: string): void {
	if (!Number.isFinite(value)) {
		throw new Error("motion: decay " + name + " must be finite, got " + value);
	}
}

function validate(config: DecayConfig): void {
	requireFinite(config.deceleration, "deceleration");
	if (config.deceleration <= 0 || config.deceleration >= 1) {
		throw new Error("motion: decay deceleration must be between 0 and 1, got " + config.deceleration);
	}
	requireFinite(config.velocityFactor, "velocityFactor");
	if (config.velocityFactor <= 0) {
		throw new Error("motion: decay velocityFactor must be greater than zero, got " + config.velocityFactor);
	}
	requireFinite(config.velocityThreshold, "velocityThreshold");
	if (config.velocityThreshold <= 0) {
		throw new Error("motion: decay velocityThreshold must be greater than zero, got " + config.velocityThreshold);
	}
	if ((config.clampMin === null) !== (config.clampMax === null)) {
		throw new Error("motion: decay clamp needs both clampMin and clampMax");
	}
	if (config.clampMin !== null && config.clampMax !== null) {
		requireFinite(config.clampMin, "clampMin");
		requireFinite(config.clampMax, "clampMax");
		if (config.clampMin > config.clampMax) {
			throw new Error("motion: decay clampMin must not exceed clampMax");
		}
	}
	if (config.rubberBand) {
		if (config.clampMin === null) {
			throw new Error("motion: decay rubberBand needs a clamp");
		}
		requireFinite(config.rubberBandFactor, "rubberBandFactor");
		if (config.rubberBandFactor <= 0) {
			throw new Error("motion: decay rubberBandFactor must be greater than zero, got " + config.rubberBandFactor);
		}
	}
}

function rigidPosition(this d: DecaySimulation, seconds: float64): float64 {
	return d.from + d.config.velocityFactor * d.initialVelocityPerSecond *
		(1 - Math.exp(-d.decayPerSecond * seconds)) / d.decayPerSecond;
}

function rigidVelocity(this d: DecaySimulation, seconds: float64): float64 {
	return d.initialVelocityPerSecond * Math.exp(-d.decayPerSecond * seconds);
}

function rubberOffsetAt(this d: DecaySimulation, seconds: float64): float64 {
	const kappa = d.decayPerSecond;
	const beta = d.rubberSpringCoefficient;
	const start = d.rubberStartSeconds;
	const forcing = d.rubberDecayCoefficient;
	if (Math.abs(beta - kappa) <= 1e-9) {
		const carried = d.rubberOffset * Math.exp(kappa * start);
		return (carried + forcing * (seconds - start)) * Math.exp(-kappa * seconds);
	}
	const particular = forcing / (beta - kappa);
	const homogeneous = (d.rubberOffset - particular * Math.exp(-kappa * start)) * Math.exp(beta * start);
	return particular * Math.exp(-kappa * seconds) + homogeneous * Math.exp(-beta * seconds);
}

function rubberPeakSeconds(this d: DecaySimulation): float64 {
	const kappa = d.decayPerSecond;
	const beta = d.rubberSpringCoefficient;
	const start = d.rubberStartSeconds;
	const forcing = d.rubberDecayCoefficient;
	if (Math.abs(beta - kappa) <= 1e-9) {
		if (forcing === 0) {
			return start;
		}
		const carried = d.rubberOffset * Math.exp(kappa * start);
		return Math.max(start, start + 1 / kappa - carried / forcing);
	}
	const particular = forcing / (beta - kappa);
	if (particular === 0) {
		return start;
	}
	const homogeneous = (d.rubberOffset - particular * Math.exp(-kappa * start)) * Math.exp(beta * start);
	const ratio = -beta * homogeneous / (kappa * particular);
	if (ratio <= 0) {
		return start;
	}
	return Math.max(start, Math.log(ratio) / (beta - kappa));
}

export function createDecay(
	config: DecayConfig,
	from: float64,
	velocityPerSecond: float64,
): DecaySimulation {
	validate(config);
	requireFinite(from, "from");
	requireFinite(velocityPerSecond, "velocity");
	const decayPerSecond = (1 - config.deceleration) * SLOPE_FACTOR * 1000;
	const thresholdSeconds = Math.abs(velocityPerSecond) <= config.velocityThreshold
		? 0
		: Math.log(Math.abs(velocityPerSecond) / config.velocityThreshold) / decayPerSecond;
	let simulation: DecaySimulation = {
		config,
		from,
		initialVelocityPerSecond: velocityPerSecond,
		decayPerSecond,
		endSeconds: thresholdSeconds,
		snapsToBound: false,
		bound: from,
		rubberStartSeconds: Infinity,
		rubberOffset: 0,
		rubberDecayCoefficient: 0,
		rubberSpringCoefficient: 0,
	};
	if (config.clampMin === null || config.clampMax === null) {
		return simulation;
	}
	const clampMin: float64 = config.clampMin;
	const clampMax: float64 = config.clampMax;
	const outside = from < clampMin || from > clampMax;
	const nearest = Math.abs(from - clampMin) < Math.abs(from - clampMax) ? clampMin : clampMax;
	const heading = velocityPerSecond > 0 ? clampMax : clampMin;
	let reachSeconds = Infinity;
	if (velocityPerSecond !== 0) {
		const beyondHeading = velocityPerSecond > 0 ? from >= heading : from <= heading;
		if (beyondHeading) {
			reachSeconds = 0;
		} else {
			const fraction = (heading - from) * decayPerSecond /
				(config.velocityFactor * velocityPerSecond);
			if (fraction < 1) {
				reachSeconds = -Math.log(1 - fraction) / decayPerSecond;
			}
		}
	}
	if (!config.rubberBand) {
		if (reachSeconds <= thresholdSeconds) {
			simulation.endSeconds = reachSeconds;
			simulation.snapsToBound = true;
			simulation.bound = heading;
		}
		return simulation;
	}
	const springStart = outside ? 0 : reachSeconds;
	if (springStart >= thresholdSeconds && !outside) {
		return simulation;
	}
	const bound = outside ? nearest : heading;
	simulation.bound = bound;
	simulation.rubberStartSeconds = springStart;
	simulation.rubberOffset = outside ? from - bound : 0;
	simulation.rubberDecayCoefficient = config.velocityFactor * velocityPerSecond;
	simulation.rubberSpringCoefficient = config.velocityFactor * config.rubberBandFactor;
	const peakSeconds = simulation.rubberPeakSeconds();
	if (Math.abs(simulation.rubberOffsetAt(peakSeconds)) <= RUBBER_BAND_SETTLE_DISTANCE &&
		Math.abs(simulation.rubberOffset) <= RUBBER_BAND_SETTLE_DISTANCE) {
		simulation.endSeconds = Math.max(thresholdSeconds, springStart);
		return simulation;
	}
	let high = peakSeconds + 1;
	while (Math.abs(simulation.rubberOffsetAt(high)) > RUBBER_BAND_SETTLE_DISTANCE) {
		high = peakSeconds + (high - peakSeconds) * 2;
	}
	let low = peakSeconds;
	for (let step: int32 = 0; step < PEAK_REFINE_STEPS; step++) {
		const middle = (low + high) / 2;
		if (Math.abs(simulation.rubberOffsetAt(middle)) > RUBBER_BAND_SETTLE_DISTANCE) {
			low = middle;
		} else {
			high = middle;
		}
	}
	simulation.endSeconds = high;
	simulation.snapsToBound = true;
	return simulation;
}

function requireTime(tMs: float64): float64 {
	requireFinite(tMs, "time");
	return Math.max(tMs, 0) / 1000;
}

export function isDone(this d: DecaySimulation, tMs: float64): boolean {
	return requireTime(tMs) >= d.endSeconds;
}

export function position(this d: DecaySimulation, tMs: float64): float64 {
	const seconds = requireTime(tMs);
	if (seconds >= d.endSeconds && d.snapsToBound) {
		return d.bound;
	}
	const at = Math.min(seconds, d.endSeconds);
	return at >= d.rubberStartSeconds ? d.bound + d.rubberOffsetAt(at) : d.rigidPosition(at);
}

export function velocity(this d: DecaySimulation, tMs: float64): float64 {
	const seconds = requireTime(tMs);
	if (seconds >= d.endSeconds) {
		return 0;
	}
	if (seconds >= d.rubberStartSeconds) {
		return d.rigidVelocity(seconds) -
			d.config.rubberBandFactor * d.rubberOffsetAt(seconds);
	}
	return d.rigidVelocity(seconds);
}
