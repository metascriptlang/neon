import { Easing } from "../../src/animation/easing";
import { ManualClock } from "../../src/motion/clock";
import {
	createDecay,
	decayConfig,
	isDone as decayIsDone,
	position as decayPosition,
} from "../../src/motion/decay";
import { MotionPolicy, ReduceMotion } from "../../src/motion/policy";
import { createSpring, position, springByStiffness, velocity } from "../../src/motion/spring";
import {
	AnimatedValue,
	AnimationSpec,
	decay,
	delay,
	repeat,
	sequence,
	spring,
	timing,
} from "../../src/motion/value";

function near(actual: float64, expected: float64, tolerance: float64): boolean {
	return Math.abs(actual - expected) <= tolerance;
}

function throws(run: () => void): string {
	let message = "";
	try { run(); } catch (e) { message = e.message; }
	return message;
}

class Ends {
	finished: int32 = 0;
	cancelled: int32 = 0;
	handler: (finished: boolean) => void;

	constructor() {
		this.handler = (finished: boolean): void => {
			if (finished) { this.finished += 1; } else { this.cancelled += 1; }
		};
	}
}

function linear(to: float64, duration: float64): AnimationSpec {
	return timing(to, { duration, easing: Easing.linear });
}

test "set is immediate, notifies once and skips an unchanged value" {
	const clock = new ManualClock();
	const value = new AnimatedValue(3, clock.clock, new MotionPolicy());
	const seen: float64[] = [];
	value.subscribe((v: float64): void => { seen.push(v); });
	assert value.get() === 3;
	value.set(8);
	assert value.get() === 8;
	value.set(8);
	assert seen.length === 1 && seen[0] === 8;
	assert !value.isAnimating();
	assert clock.pending() === 0;
}

test "a linear timing reaches each fraction of its duration" {
	const clock = new ManualClock();
	const value = new AnimatedValue(0, clock.clock, new MotionPolicy());
	const ends = new Ends();
	value.animate(linear(100, 100), ends.handler);
	assert value.get() === 0, "the first frame is the start";
	assert value.isAnimating();
	assert clock.pending() === 1;
	clock.advance(25);
	assert value.get() === 25;
	clock.advance(25);
	assert value.get() === 50;
	assert ends.finished === 0;
	clock.advance(50);
	assert value.get() === 100;
	assert ends.finished === 1 && ends.cancelled === 0;
	assert !value.isAnimating();
	assert clock.pending() === 0;
	clock.advance(50);
	assert ends.finished === 1;
}

test "a timing defaults to 300 ms of Easing.inOut(Easing.quad)" {
	const clock = new ManualClock();
	const value = new AnimatedValue(0, clock.clock, new MotionPolicy());
	value.animate(timing(100));
	clock.advance(75);
	assert near(value.get(), 12.5, 1e-12);
	clock.advance(75);
	assert near(value.get(), 50, 1e-12);
	clock.advance(75);
	assert near(value.get(), 87.5, 1e-12);
	clock.advance(75);
	assert value.get() === 100;
	assert !value.isAnimating();
}

test "animating to the value already held ends at once, finished" {
	const clock = new ManualClock();
	const value = new AnimatedValue(5, clock.clock, new MotionPolicy());
	const ends = new Ends();
	value.animate(linear(5, 100), ends.handler);
	assert ends.finished === 1;
	assert !value.isAnimating();
	assert clock.pending() === 0;
}

test "set during an animation stops it and reports it unfinished once" {
	const clock = new ManualClock();
	const value = new AnimatedValue(0, clock.clock, new MotionPolicy());
	const ends = new Ends();
	value.animate(linear(100, 100), ends.handler);
	clock.advance(40);
	value.set(7);
	assert value.get() === 7;
	assert ends.cancelled === 1 && ends.finished === 0;
	assert clock.pending() === 0;
	clock.advance(100);
	assert value.get() === 7;
	assert ends.cancelled === 1 && ends.finished === 0;
}

test "a new animation interrupts the running one, which ends unfinished once" {
	const clock = new ManualClock();
	const value = new AnimatedValue(0, clock.clock, new MotionPolicy());
	const first = new Ends();
	const second = new Ends();
	value.animate(linear(100, 100), first.handler);
	clock.advance(50);
	value.animate(linear(0, 100), second.handler);
	assert first.cancelled === 1 && first.finished === 0;
	clock.advance(50);
	assert value.get() === 25;
	clock.advance(50);
	assert value.get() === 0;
	assert second.finished === 1 && second.cancelled === 0;
	assert first.cancelled === 1 && first.finished === 0;
	assert clock.pending() === 0;
}

test "a timing over a running timing to the same target keeps its timeline" {
	const clock = new ManualClock();
	const value = new AnimatedValue(0, clock.clock, new MotionPolicy());
	value.animate(linear(100, 100));
	clock.advance(40);
	value.animate(linear(100, 100));
	clock.advance(20);
	assert value.get() === 60;
	clock.advance(40);
	assert value.get() === 100;
	assert !value.isAnimating();
}

test "cancel holds the value, ends unfinished and releases the frame" {
	const clock = new ManualClock();
	const value = new AnimatedValue(0, clock.clock, new MotionPolicy());
	const ends = new Ends();
	const seen: float64[] = [];
	value.animate(linear(100, 100), ends.handler);
	clock.advance(30);
	value.subscribe((v: float64): void => { seen.push(v); });
	value.cancel();
	assert value.get() === 30;
	assert ends.cancelled === 1 && ends.finished === 0;
	assert seen.length === 0, "cancel does not change the value";
	assert !value.isAnimating();
	assert clock.pending() === 0;
	value.cancel();
	assert ends.cancelled === 1;
}

test "a spring retargeted mid-flight keeps its position and velocity" {
	const clock = new ManualClock();
	const config = springByStiffness(100, 10, 1);
	const value = new AnimatedValue(0, clock.clock, new MotionPolicy());
	value.animate(spring(1, config));
	clock.advance(100);
	const reference = createSpring(config, 0, 1);
	assert near(value.get(), reference.position(100), 1e-12);
	const x = value.get();
	const v = value.velocity();
	assert near(v, reference.velocity(100), 1e-12);
	value.animate(spring(3, config));
	assert near(value.get(), x, 1e-12);
	assert near(value.velocity(), v, 1e-12);
	clock.advance(10);
	const carried = createSpring(config, x, 3, v);
	assert near(value.get(), carried.position(10), 1e-12);
	assert near(value.velocity(), carried.velocity(10), 1e-12);
	clock.advance(20000);
	assert value.get() === 3;
	assert value.velocity() === 0;
}

test "a spring interrupting a wrapped spring carries the inner spring's velocity" {
	const clock = new ManualClock();
	const config = springByStiffness(100, 10, 1);
	const value = new AnimatedValue(0, clock.clock, new MotionPolicy());
	value.animate(repeat(delay(10, spring(1, config)), 2));
	clock.advance(10);
	clock.advance(100);
	const v = value.velocity();
	assert near(v, createSpring(config, 0, 1).velocity(100), 1e-12);
	value.animate(spring(5, config));
	assert near(value.velocity(), v, 1e-12);
}

test "the same spring started again on the same target continues" {
	const clock = new ManualClock();
	const config = springByStiffness(100, 10, 1);
	const value = new AnimatedValue(0, clock.clock, new MotionPolicy());
	value.animate(spring(1, config));
	clock.advance(100);
	value.animate(spring(1, config));
	clock.advance(50);
	assert near(value.get(), createSpring(config, 0, 1).position(150), 1e-12);
}

test "a spring after a timing starts from rest, plus its own velocity" {
	const clock = new ManualClock();
	const config = springByStiffness(100, 10, 1);
	const value = new AnimatedValue(0, clock.clock, new MotionPolicy());
	value.animate(linear(100, 100));
	clock.advance(50);
	value.animate(spring(200, config));
	assert value.velocity() === 0;
	value.animate(spring(300, config, 40));
	assert near(value.velocity(), 40, 1e-12);
}

test "a decay follows the decay simulation from the current value" {
	const clock = new ManualClock();
	const value = new AnimatedValue(10, clock.clock, new MotionPolicy());
	const ends = new Ends();
	value.animate(decay(decayConfig(), 2000), ends.handler);
	const reference = createDecay(decayConfig(), 10, 2000);
	clock.advance(100);
	assert near(value.get(), reference.decayPosition(100), 1e-12);
	assert value.velocity() > 0;
	assert !reference.decayIsDone(30000);
	for (let i: int32 = 0; i < 1000; i++) { clock.advance(50); }
	assert ends.finished === 1;
	assert near(value.get(), reference.decayPosition(50000), 1e-12);
}

test "a sequence starts each step on the frame the step before it ends" {
	const clock = new ManualClock();
	const value = new AnimatedValue(0, clock.clock, new MotionPolicy());
	const ends = new Ends();
	value.animate(sequence(linear(100, 100), linear(0, 50)), ends.handler);
	clock.advance(50);
	assert value.get() === 50;
	clock.advance(50);
	assert value.get() === 100;
	assert value.isAnimating();
	clock.advance(25);
	assert value.get() === 50;
	clock.advance(25);
	assert value.get() === 0;
	assert ends.finished === 1 && ends.cancelled === 0;
	assert clock.pending() === 0;
}

test "a delay holds the value, then starts its animation" {
	const clock = new ManualClock();
	const value = new AnimatedValue(0, clock.clock, new MotionPolicy());
	const ends = new Ends();
	value.animate(delay(40, linear(100, 100)), ends.handler);
	clock.advance(39);
	assert value.get() === 0;
	clock.advance(1);
	assert value.get() === 0;
	clock.advance(50);
	assert value.get() === 50;
	clock.advance(50);
	assert value.get() === 100;
	assert ends.finished === 1;
}

test "a delay keeps the interrupted animation moving until it starts" {
	const clock = new ManualClock();
	const value = new AnimatedValue(0, clock.clock, new MotionPolicy());
	const first = new Ends();
	value.animate(linear(100, 100), first.handler);
	clock.advance(50);
	value.animate(delay(40, linear(0, 100)));
	assert first.cancelled === 1;
	clock.advance(20);
	assert value.get() === 70;
	clock.advance(20);
	assert value.get() === 70, "the delayed step starts from the last frame's value";
	clock.advance(50);
	assert value.get() === 35;
	assert first.finished === 0, "the interrupted animation never reports again";
}

test "a repeat restarts from the start value on the frame it ends" {
	const clock = new ManualClock();
	const value = new AnimatedValue(0, clock.clock, new MotionPolicy());
	const ends = new Ends();
	value.animate(repeat(linear(100, 100), 3), ends.handler);
	clock.advance(100);
	assert value.get() === 100;
	assert value.isAnimating();
	clock.advance(50);
	assert value.get() === 50;
	clock.advance(50);
	assert value.get() === 100;
	clock.advance(100);
	assert value.get() === 100;
	assert ends.finished === 1 && ends.cancelled === 0;
	assert clock.pending() === 0;
}

test "a reverse repeat alternates its direction" {
	const clock = new ManualClock();
	const value = new AnimatedValue(0, clock.clock, new MotionPolicy());
	const ends = new Ends();
	value.animate(repeat(linear(100, 100), 3, true), ends.handler);
	clock.advance(50);
	assert value.get() === 50;
	clock.advance(50);
	assert value.get() === 100;
	clock.advance(25);
	assert value.get() === 75;
	clock.advance(75);
	assert value.get() === 0;
	clock.advance(30);
	assert value.get() === 30;
	clock.advance(70);
	assert value.get() === 100;
	assert ends.finished === 1;
}

test "a repeat of -1 runs until it is cancelled" {
	const clock = new ManualClock();
	const value = new AnimatedValue(0, clock.clock, new MotionPolicy());
	const ends = new Ends();
	value.animate(repeat(linear(100, 100), -1, true), ends.handler);
	for (let i: int32 = 0; i < 100; i++) { clock.advance(25); }
	assert value.isAnimating();
	assert value.get() === 100, "the 25th pass ends on the target";
	value.cancel();
	assert ends.cancelled === 1 && ends.finished === 0;
	assert clock.pending() === 0;
}

test "reduced motion: a timing or a spring jumps to its target and ends finished" {
	const clock = new ManualClock();
	const policy = new MotionPolicy(true);
	const value = new AnimatedValue(0, clock.clock, policy);
	const ends = new Ends();
	const seen: float64[] = [];
	value.subscribe((v: float64): void => { seen.push(v); });
	value.animate(linear(100, 100), ends.handler);
	assert value.get() === 100;
	assert ends.finished === 1;
	assert seen.length === 1 && seen[0] === 100;
	assert clock.pending() === 0;
	value.animate(spring(-4, springByStiffness(100, 10, 1)), ends.handler);
	assert value.get() === -4;
	assert ends.finished === 2;
	assert clock.pending() === 0;
}

test "reduced motion: a decay stays put, or moves into its clamp" {
	const clock = new ManualClock();
	const value = new AnimatedValue(50, clock.clock, new MotionPolicy(true));
	const ends = new Ends();
	value.animate(decay(decayConfig(), 3000), ends.handler);
	assert value.get() === 50;
	assert ends.finished === 1;
	value.set(500);
	value.animate(decay({ ...decayConfig(), clampMin: 0, clampMax: 100 }, 3000), ends.handler);
	assert value.get() === 100;
	assert ends.finished === 2;
	assert clock.pending() === 0;
}

test "Never overrides a reduced policy and Always overrides a full one" {
	const clock = new ManualClock();
	const reduced = new AnimatedValue(0, clock.clock, new MotionPolicy(true));
	reduced.animate({ ...linear(100, 100), reduceMotion: ReduceMotion.Never });
	clock.advance(50);
	assert reduced.get() === 50;
	const full = new AnimatedValue(0, clock.clock, new MotionPolicy(false));
	full.animate({ ...linear(100, 100), reduceMotion: ReduceMotion.Always });
	assert full.get() === 100;
}

test "the policy is read when an animation starts" {
	const clock = new ManualClock();
	const policy = new MotionPolicy();
	const value = new AnimatedValue(0, clock.clock, policy);
	value.animate(linear(100, 100));
	policy.reducedMotion = true;
	clock.advance(50);
	assert value.get() === 50;
	value.animate(linear(0, 100));
	assert value.get() === 0;
}

test "reduced motion: a sequence skips to its last step, a delay does not wait" {
	const clock = new ManualClock();
	const value = new AnimatedValue(0, clock.clock, new MotionPolicy(true));
	const ends = new Ends();
	value.animate(sequence(linear(100, 100), linear(30, 100)), ends.handler);
	assert value.get() === 30;
	assert ends.finished === 1;
	value.animate(delay(500, linear(60, 100)), ends.handler);
	assert value.get() === 60;
	assert ends.finished === 2;
	assert clock.pending() === 0;
}

test "reduced motion: an inner Never step of a sequence still plays" {
	const clock = new ManualClock();
	const value = new AnimatedValue(0, clock.clock, new MotionPolicy(true));
	const ends = new Ends();
	const kept: AnimationSpec = { ...linear(100, 100), reduceMotion: ReduceMotion.Never };
	value.animate(sequence(kept, linear(30, 100)), ends.handler);
	clock.advance(50);
	assert value.get() === 50;
	clock.advance(50);
	assert value.get() === 100;
	clock.advance(1);
	assert value.get() === 30;
	assert ends.finished === 1;
}

test "reduced motion: a repeat that would return to its start stays there" {
	const clock = new ManualClock();
	const value = new AnimatedValue(0, clock.clock, new MotionPolicy(true));
	const ends = new Ends();
	value.animate(repeat(linear(100, 100), 2, true), ends.handler);
	assert value.get() === 0;
	assert ends.finished === 1;
	value.animate(repeat(linear(100, 100), -1, true), ends.handler);
	assert value.get() === 0;
	assert ends.finished === 2;
	value.animate(repeat(linear(100, 100), 3, true), ends.handler);
	assert value.get() === 100;
	assert ends.finished === 3;
	value.set(0);
	value.animate(repeat(linear(100, 100), -1), ends.handler);
	assert value.get() === 100;
	assert ends.finished === 4;
	assert clock.pending() === 0;
}

test "dispose ends the animation unfinished, never notifies and refuses later calls" {
	const clock = new ManualClock();
	const value = new AnimatedValue(0, clock.clock, new MotionPolicy());
	const ends = new Ends();
	const seen: float64[] = [];
	value.subscribe((v: float64): void => { seen.push(v); });
	value.animate(linear(100, 100), ends.handler);
	clock.advance(10);
	const before = seen.length;
	value.dispose();
	assert ends.cancelled === 1 && ends.finished === 0;
	assert clock.pending() === 0;
	clock.advance(100);
	assert seen.length === before;
	assert throws(() => { value.get(); }).startsWith("motion: ");
	assert throws(() => { value.set(1); }).startsWith("motion: ");
	assert throws(() => { value.animate(linear(1, 1)); }).startsWith("motion: ");
	assert throws(() => { value.dispose(); }).startsWith("motion: ");
}

test "an unsubscribed listener hears nothing more" {
	const clock = new ManualClock();
	const value = new AnimatedValue(0, clock.clock, new MotionPolicy());
	let heard = 0;
	const stop = value.subscribe((v: float64): void => { heard += 1; });
	value.set(1);
	stop();
	stop();
	value.set(2);
	assert heard === 1;
}

test "a listener may stop the animation it is hearing" {
	const clock = new ManualClock();
	const value = new AnimatedValue(0, clock.clock, new MotionPolicy());
	const ends = new Ends();
	value.subscribe((v: float64): void => { if (v >= 50) { value.cancel(); } });
	value.animate(linear(100, 100), ends.handler);
	clock.advance(50);
	assert value.get() === 50;
	assert ends.cancelled === 1 && ends.finished === 0;
	assert clock.pending() === 0;
}

test "invalid specs fail loud" {
	assert throws(() => { timing(1, { duration: -1 }); }).startsWith("motion: timing duration");
	assert throws(() => { timing(NaN); }).startsWith("motion: timing to");
	assert throws(() => { delay(-5, timing(1)); }).startsWith("motion: delay");
	assert throws(() => { sequence(); }).startsWith("motion: sequence");
	assert throws(() => { spring(1, springByStiffness(100, -1, 1)); }).startsWith("motion: spring");
	const clock = new ManualClock();
	const value = new AnimatedValue(0, clock.clock, new MotionPolicy());
	assert throws(() => { value.set(NaN); }).startsWith("motion: ");
}
