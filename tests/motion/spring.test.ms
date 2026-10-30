import {
	SpringConfig,
	SpringKind,
	createSpring,
	isDone,
	position,
	retarget,
	springByDuration,
	springByStiffness,
	velocity,
} from "../../src/motion/spring";

function near(actual: float64, expected: float64, tolerance: float64): boolean {
	return Math.abs(actual - expected) <= tolerance;
}

function maxPosition(config: SpringConfig, from: float64, to: float64, velocityPerSecond: float64): float64 {
	const spring = createSpring(config, from, to, velocityPerSecond);
	let highest = from;
	for (let ms: int32 = 0; ms <= 4000; ms += 2) {
		highest = Math.max(highest, spring.position(ms as float64));
	}
	return highest;
}

function throws(run: () => void): string {
	let message = "";
	try { run(); } catch (e) { message = e.message; }
	return message;
}

test "an under-damped spring overshoots, then settles on the target" {
	const spring = createSpring(springByStiffness(100, 10, 1), 0, 1);
	assert spring.kind === SpringKind.UnderDamped;
	assert maxPosition(springByStiffness(100, 10, 1), 0, 1, 0) > 1.1, "overshoot";
	assert spring.position(20000) === 1;
}

test "a critically damped spring never overshoots" {
	const config = springByStiffness(900, 120, 4);
	assert createSpring(config, 0, 1).kind === SpringKind.CriticallyDamped;
	assert maxPosition(config, 0, 1, 0) <= 1;
}

test "an over-damped spring never overshoots and is slower than the critical one" {
	const over = springByStiffness(100, 40, 1);
	const critical = springByStiffness(100, 20, 1);
	assert createSpring(over, 0, 1).kind === SpringKind.OverDamped;
	assert maxPosition(over, 0, 1, 0) <= 1;
	assert createSpring(over, 0, 1).position(300) < createSpring(critical, 0, 1).position(300);
}

test "positions and velocities match an RK4 integration of the same spring" {
	const under = createSpring(springByStiffness(100, 10, 1), 0, 1);
	assert near(under.position(100), 1 - 0.6597001533916963, 1e-7);
	assert near(under.velocity(100), 5.33507195114691, 1e-6);
	const critical = createSpring(springByStiffness(900, 120, 4), 0, 1);
	assert near(critical.position(100), 1 - 0.5578254003710775, 1e-7);
	assert near(critical.velocity(100), 5.020428603339669, 1e-6);
	const over = createSpring(springByStiffness(100, 40, 1), 0, 1);
	assert near(over.position(100), 1 - 0.8222634239018236, 1e-7);
	assert near(over.velocity(100), 2.139091302602838, 1e-6);
	const flung = createSpring(springByStiffness(100, 40, 1), 0, 1, 50);
	assert near(flung.position(300), 1 + 0.16381548508193738, 1e-7);
	assert near(flung.velocity(300), -0.43829270500163314, 1e-6);
	const fast = createSpring(springByStiffness(100, 10, 1), 0, 1, 300);
	assert near(fast.position(100), 1 + 15.34551570004915, 1e-6);
	assert near(fast.velocity(100), 43.19295943425196, 1e-5);
}

test "the duration family resolves the stiffness the reference finds and then follows it" {
	const spring = createSpring(springByDuration(550, 0.75, 4), 0, 1);
	assert near(spring.stiffness, 1566.650390625, 1e-6);
	assert near(spring.position(200), 1 + 0.015368642101489647, 1e-7);
	assert near(spring.velocity(200), 0.7685536206426039, 1e-6);
	const critical = createSpring(springByDuration(300, 1, 1), 0, 2);
	assert near(critical.stiffness, 755.37109375, 1e-6);
	assert near(critical.position(150), 2 - 0.16599584241925502, 1e-7);
	assert near(critical.velocity(150), 3.6716239337876697, 1e-6);
}

test "a duration of zero is already at the target" {
	const spring = createSpring(springByDuration(0, 0.5, 1), 3, 9);
	assert spring.position(0) === 9;
	assert spring.isDone(0);
}

test "sampling at one step equals sampling ten steps, and re-launching on the same target continues" {
	const spring = createSpring(springByStiffness(100, 10, 1), 0, 1, 20);
	let continued = spring;
	for (let step: int32 = 1; step <= 10; step++) {
		continued = continued.retarget(10, 1);
	}
	assert near(continued.position(0), spring.position(100), 1e-9);
	assert near(continued.velocity(0), spring.velocity(100), 1e-9);
	assert near(continued.position(50), spring.position(150), 1e-9);
}

test "rest is detected, and a rested spring sits on the target with no velocity" {
	const spring = createSpring(springByStiffness(100, 10, 1), 0, 1);
	assert !spring.isDone(0);
	assert !spring.isDone(500);
	assert spring.isDone(5000);
	assert spring.position(5000) === 1;
	assert spring.velocity(5000) === 0;
	let rested = false;
	for (let ms: int32 = 0; ms <= 8000; ms += 5) {
		const done = spring.isDone(ms as float64);
		assert !(rested && !done), "once done, always done";
		rested = done;
	}
	assert createSpring(springByStiffness(100, 10, 1), 4, 4).isDone(0);
}

test "a gesture velocity toward the target is the starting velocity, away from it is dropped" {
	const config = springByStiffness(100, 10, 1);
	assert near(createSpring(config, 0, 1, 7).velocity(0), 7, 1e-12);
	assert createSpring(config, 0, 1, -7).velocity(0) === 0;
	assert near(createSpring(config, 1, 0, -7).velocity(0), -7, 1e-12);
}

test "overshoot clamping stops at the first crossing of the target" {
	const config: SpringConfig = { ...springByStiffness(100, 10, 1), overshootClamping: true };
	const spring = createSpring(config, 0, 1);
	const crossing = 2 * Math.PI / 3 / (5 * Math.sqrt(3));
	assert near(spring.crossSeconds, crossing, 1e-9);
	assert maxPosition(config, 0, 1, 0) <= 1;
	assert !spring.isDone(crossing * 1000 - 1);
	assert spring.position(crossing * 1000 - 1) < 1;
	assert spring.isDone(crossing * 1000 + 1);
	assert spring.position(crossing * 1000 + 1) === 1;
	assert maxPosition(springByStiffness(100, 10, 1), 0, 1, 0) > 1;
}

test "a clamp raises the damping so the bounce stays inside it" {
	const unclamped = springByDuration(500, 0.3, 1);
	const clamped: SpringConfig = { ...unclamped, clampMax: 110 };
	assert maxPosition(unclamped, 0, 100, 0) > 110;
	assert maxPosition(clamped, 0, 100, 0) <= 110;
	assert createSpring(clamped, 0, 100).zeta > 0.3;
}

test "retarget keeps position and velocity of the moving spring" {
	const spring = createSpring(springByStiffness(100, 10, 1), 0, 1);
	const moved = spring.retarget(100, 3);
	assert near(moved.position(0), spring.position(100), 1e-12);
	assert near(moved.velocity(0), spring.velocity(100), 1e-12);
	assert moved.to === 3;
	assert moved.velocity(1) > 5, "the carried velocity points at the new target";
	assert moved.isDone(20000);
	assert moved.position(20000) === 3;
}

test "retarget against the carried velocity keeps it and turns around smoothly" {
	const spring = createSpring(springByStiffness(100, 10, 1), 0, 1);
	const reversed = spring.retarget(100, -1);
	assert near(reversed.velocity(0), spring.velocity(100), 1e-12);
	assert reversed.velocity(0) > 5;
	assert reversed.position(20) > reversed.position(0), "it keeps moving away before it turns";
	assert reversed.position(20000) === -1;
}

test "retarget of a finished spring starts from rest on the old target" {
	const spring = createSpring(springByStiffness(100, 10, 1), 0, 1);
	const next = spring.retarget(20000, 5);
	assert next.position(0) === 1;
	assert next.velocity(0) === 0;
	assert next.to === 5;
}

test "an invalid config or input fails loud and names the field" {
	const good = springByStiffness(100, 10, 1);
	assert throws(() => { createSpring({ ...good, mass: 0 }, 0, 1); }) === "motion: spring mass must be finite and greater than zero, got 0";
	assert throws(() => { createSpring({ ...good, stiffness: -1 }, 0, 1); }).startsWith("motion: spring stiffness");
	assert throws(() => { createSpring({ ...good, damping: -2 }, 0, 1); }).startsWith("motion: spring damping");
	assert throws(() => { createSpring({ ...good, mass: Infinity }, 0, 1); }).startsWith("motion: spring mass");
	assert throws(() => { createSpring({ ...good, energyThreshold: 0 }, 0, 1); }).startsWith("motion: spring energyThreshold");
	assert throws(() => { createSpring(springByDuration(-5, 1, 1), 0, 1); }).startsWith("motion: spring durationMs");
	assert throws(() => { createSpring(springByDuration(500, 0, 1), 0, 1); }).startsWith("motion: spring dampingRatio");
	assert throws(() => { createSpring({ ...good, clampMin: 5, clampMax: 1 }, 0, 1); }).startsWith("motion: spring clampMin");
	assert throws(() => { createSpring(good, NaN, 1); }).startsWith("motion: spring from");
	assert throws(() => { createSpring(good, 0, 1, Infinity); }).startsWith("motion: spring velocity");
	assert throws(() => { createSpring(good, 0, 1).position(NaN); }).startsWith("motion: spring time");
}
