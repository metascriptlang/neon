import {
	DecayConfig,
	DecaySimulation,
	createDecay,
	decayConfig,
	isDone,
	position,
	velocity,
} from "../../src/motion/decay";

function near(actual: float64, expected: float64, tolerance: float64): boolean {
	return Math.abs(actual - expected) <= tolerance;
}

function throws(run: () => void): string {
	let message = "";
	try { run(); } catch (e) { message = e.message; }
	return message;
}

function highest(decay: DecaySimulation, untilMs: int32): float64 {
	let top = decay.position(0);
	for (let ms: int32 = 0; ms <= untilMs; ms += 10) {
		top = Math.max(top, decay.position(ms as float64));
	}
	return top;
}

test "velocity decays exponentially and position is its integral" {
	const decay = createDecay(decayConfig(), 0, 2000);
	assert near(decay.position(500), 951.625819640404, 1e-6);
	assert near(decay.velocity(500), 1809.6748360719191, 1e-6);
	assert decay.velocity(0) === 2000;
	assert decay.position(0) === 0;
}

test "position moves at the velocity it reports, whatever the sampling step" {
	const decay = createDecay(decayConfig(), 10, -1500);
	for (let ms: int32 = 1000; ms <= 20000; ms += 1000) {
		const t = ms as float64;
		const slope = (decay.position(t + 0.5) - decay.position(t - 0.5)) / 0.001;
		assert near(slope, decay.velocity(t), 1e-3 * Math.abs(decay.velocity(t)) + 1e-6);
	}
	let walked = 10.0;
	for (let step: int32 = 0; step < 100; step++) {
		const t = (step * 10) as float64;
		walked += (decay.position(t + 10) - decay.position(t));
	}
	assert near(walked, decay.position(1000), 1e-9);
}

test "decay stops when the velocity falls under the threshold and then holds still" {
	const decay = createDecay(decayConfig(), 0, 2000);
	const stopSeconds = Math.log(2000) / 0.2;
	assert !decay.isDone(0);
	assert !decay.isDone(stopSeconds * 1000 - 10);
	assert decay.isDone(stopSeconds * 1000 + 10);
	assert decay.position(stopSeconds * 1000 + 10) === decay.position(600000);
	assert decay.velocity(stopSeconds * 1000 + 10) === 0;
	assert decay.velocity(stopSeconds * 1000 - 10) > 0.9;
}

test "a velocity under the threshold is done at once and leaves the value where it is" {
	const decay = createDecay(decayConfig(), 42, 0.5);
	assert decay.isDone(0);
	assert decay.position(5000) === 42;
}

test "velocityFactor scales the distance travelled" {
	const plain = createDecay(decayConfig(), 0, 800);
	const doubled = createDecay({ ...decayConfig(), velocityFactor: 2 }, 0, 800);
	assert near(doubled.position(700), 2 * plain.position(700), 1e-9);
}

test "a clamp stops the decay at the bound it runs into" {
	const config: DecayConfig = { ...decayConfig(), clampMin: -300, clampMax: 500 };
	const up = createDecay(config, 0, 2000);
	const reachSeconds = -Math.log(1 - 500 * 0.2 / 2000) / 0.2;
	assert near(reachSeconds, 0.2564664719377527, 1e-12);
	assert !up.isDone(reachSeconds * 1000 - 1);
	assert up.position(reachSeconds * 1000 - 1) < 500;
	assert up.isDone(reachSeconds * 1000 + 1);
	assert up.position(reachSeconds * 1000 + 1) === 500;
	assert up.velocity(reachSeconds * 1000 + 1) === 0;
	const down = createDecay(config, 0, -4000);
	assert down.position(60000) === -300;
	const pastIt = createDecay(config, 700, 100);
	assert pastIt.isDone(0);
	assert pastIt.position(0) === 500;
	const spent = createDecay(config, 0, 30);
	assert spent.isDone(30000 * 1000);
	assert spent.position(100000) > 0 && spent.position(100000) < 500;
}

test "a rubber band lets the value past the clamp and pulls it back to the bound" {
	const config: DecayConfig = { ...decayConfig(), clampMin: -300, clampMax: 500, rubberBand: true };
	const decay = createDecay(config, 0, 2000);
	assert near(decay.position(500), 919.931222041629, 0.05);
	assert near(decay.velocity(500), 1557.7173994147224, 0.05);
	assert near(decay.position(1000), 1553.1464724762423, 0.1);
	assert near(highest(decay, 60000) - 500, 1828.276222574374, 0.1);
	assert near(decay.position(54000), 500.1, 0.1);
	assert !decay.isDone(54000);
	assert decay.isDone(54200);
	assert decay.position(54200) === 500;
	assert decay.velocity(54200) === 0;
}

test "a rubber band starting outside the clamp is pulled to the nearest bound" {
	const config: DecayConfig = { ...decayConfig(), clampMin: 0, clampMax: 100, rubberBand: true };
	const decay = createDecay(config, 160, 0);
	assert decay.position(0) === 160;
	assert decay.position(1000) < 160 && decay.position(1000) > 100;
	assert decay.isDone(60000);
	assert decay.position(60000) === 100;
}

test "a rubber band that never leaves the clamp behaves like plain decay" {
	const config: DecayConfig = { ...decayConfig(), clampMin: 0, clampMax: 100000, rubberBand: true };
	const decay = createDecay(config, 0, 2000);
	const plain = createDecay(decayConfig(), 0, 2000);
	assert near(decay.position(3000), plain.position(3000), 1e-9);
}

test "an invalid config fails loud and names the field" {
	const good = decayConfig();
	assert throws(() => { createDecay({ ...good, deceleration: 1 }, 0, 1); }).startsWith("motion: decay deceleration");
	assert throws(() => { createDecay({ ...good, deceleration: NaN }, 0, 1); }).startsWith("motion: decay deceleration");
	assert throws(() => { createDecay({ ...good, velocityFactor: 0 }, 0, 1); }).startsWith("motion: decay velocityFactor");
	assert throws(() => { createDecay({ ...good, velocityThreshold: -1 }, 0, 1); }).startsWith("motion: decay velocityThreshold");
	assert throws(() => { createDecay({ ...good, clampMin: 1 }, 0, 1); }).startsWith("motion: decay clamp");
	assert throws(() => { createDecay({ ...good, clampMin: 5, clampMax: 1 }, 0, 1); }).startsWith("motion: decay clampMin");
	assert throws(() => { createDecay({ ...good, rubberBand: true }, 0, 1); }).startsWith("motion: decay rubberBand");
	assert throws(() => { createDecay(good, Infinity, 1); }).startsWith("motion: decay from");
	assert throws(() => { createDecay(good, 0, 1).position(NaN); }).startsWith("motion: decay time");
}
