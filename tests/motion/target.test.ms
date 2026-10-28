import { Easing } from "../../src/animation/easing";
import { ManualClock } from "../../src/motion/clock";
import {
	MotionDocument,
	MotionTrack,
	MotionValue,
	ValueKind,
	colorValue,
	linearKeyframe,
	numberValue,
} from "../../src/motion/document";
import { MotionBinding, MotionOptions, MotionPlayer, motionOptions } from "../../src/motion/player";
import { MotionPolicy } from "../../src/motion/policy";
import { Composition, MotionTarget } from "../../src/motion/target";
import { AnimatedValue, decay, timing } from "../../src/motion/value";
import { decayConfig } from "../../src/motion/decay";

function near(a: float64, b: float64): boolean {
	return Math.abs(a - b) <= 1e-6;
}

function refusal(action: () => void): string {
	try { action(); } catch (e) { return e.message; }
	return "";
}

function ramp(property: string, from: float64, to: float64): MotionTrack {
	return {
		slot: "box",
		property,
		kind: ValueKind.Number,
		keyframes: [linearKeyframe("a", 0, from), linearKeyframe("b", 1000, to)],
	};
}

function document(tracks: MotionTrack[], duration: float64 = 1000): MotionDocument {
	return {
		version: 1,
		root: "main",
		clips: [{ id: "main", duration, tracks, placements: [], labels: [] }],
	};
}

class Write {
	writer: string;
	value: float64;

	constructor(writer: string, value: float64) {
		this.writer = writer;
		this.value = value;
	}
}

class Sink {
	target: MotionTarget = new MotionTarget();
	writes: Write[] = [];

	binding(writer: string, property: string = "x", identified: boolean = true): MotionBinding {
		return {
			slot: "box",
			property,
			write: (value: MotionValue): void => {
				this.writes.push(new Write(writer, value.number));
			},
			read: null,
			target: identified ? this.target : null,
		};
	}

	last(): Write {
		return this.writes[this.writes.length - 1];
	}

	writersAfter(index: int32): string[] {
		const names: string[] = [];
		for (let i = index; i < this.writes.length; i += 1) {
			if (!names.includes(this.writes[i].writer)) { names.push(this.writes[i].writer); }
		}
		return names;
	}
}

function options(clock: ManualClock, composition: Composition): MotionOptions {
	return { ...motionOptions(clock.clock), composition };
}

function player(
	clock: ManualClock,
	tracks: MotionTrack[],
	bindings: MotionBinding[],
	composition: Composition = Composition.Replace,
	duration: float64 = 1000,
): MotionPlayer {
	return new MotionPlayer(document(tracks, duration), bindings, options(clock, composition));
}

test "replace hands a target to the newer player mid-flight with no jump back" {
	const clock = new ManualClock();
	const sink = new Sink();
	player(clock, [ramp("x", 0, 100)], [sink.binding("older")]);
	clock.advance(500);
	assert near(sink.last().value, 50);
	const newer = player(clock, [ramp("x", 300, 400)], [sink.binding("newer")]);
	clock.advance(100);
	const handover = sink.writes.length - 1;
	assert sink.last().writer === "newer" && near(sink.last().value, 310);
	clock.advance(900);
	const after = sink.writersAfter(handover);
	assert after.length === 1 && after[0] === "newer";
	assert near(sink.last().value, 400);
	assert !newer.cancelled;
}

test "an older player that holds no target is cancelled without completing" {
	const clock = new ManualClock();
	const sink = new Sink();
	const older = player(clock, [ramp("x", 0, 100)], [sink.binding("older")]);
	let completed: int32 = 0;
	older.onComplete = (): void => { completed += 1; };
	clock.advance(500);
	player(clock, [ramp("x", 300, 400)], [sink.binding("newer")]);
	clock.advance(100);
	assert older.cancelled && older.paused;
	assert sink.target.writers === 1;
	clock.advance(1000);
	assert completed === 0;
	assert near(older.time, 600);
}

test "replacing one property leaves the older player's other properties running" {
	const clock = new ManualClock();
	const sink = new Sink();
	const other = new Sink();
	const older = player(
		clock,
		[ramp("x", 0, 100), ramp("y", 0, 10)],
		[sink.binding("older"), other.binding("older", "y")],
	);
	clock.advance(500);
	player(clock, [ramp("x", 300, 400)], [sink.binding("newer")]);
	clock.advance(100);
	const handover = sink.writes.length - 1;
	clock.advance(200);
	assert !older.cancelled;
	assert sink.writersAfter(handover).length === 1 && sink.last().writer === "newer";
	assert other.last().writer === "older" && near(other.last().value, 8);
	clock.advance(300);
	assert near(other.last().value, 10);
}

test "blend sums two numeric players and settles on the newer end" {
	const clock = new ManualClock();
	const sink = new Sink();
	player(clock, [ramp("x", 0, 100)], [sink.binding("a")], Composition.Blend);
	clock.advance(500);
	assert near(sink.last().value, 50);
	const half: MotionTrack = {
		slot: "box",
		property: "x",
		kind: ValueKind.Number,
		keyframes: [linearKeyframe("a", 0, 0), linearKeyframe("b", 500, 10)],
	};
	player(clock, [half], [sink.binding("b")], Composition.Blend, 500);
	clock.advance(100);
	assert near(sink.last().value, 60);
	clock.advance(100);
	const scale: float64 = -11.25;
	assert near(sink.last().value, 10 + (70 - 100) + (4 - 10) * scale);
	clock.advance(200);
	assert near(sink.last().value, 10 + (90 - 100) + (8 - 10) * scale);
	clock.advance(100);
	assert near(sink.last().value, 10);
	assert sink.target.writers === 0;
}

test "blend of two animated values follows the additive model" {
	const clock = new ManualClock();
	const target = new MotionTarget();
	const policy = new MotionPolicy();
	const a = new AnimatedValue(0, clock.clock, policy, target, Composition.Blend);
	const b = new AnimatedValue(0, clock.clock, policy, target, Composition.Blend);
	a.animate(timing(100, { duration: 1000, easing: Easing.linear }));
	clock.advance(500);
	assert near(a.get(), 50);
	b.animate(timing(10, { duration: 1000, easing: Easing.linear }));
	assert near(b.get(), 50);
	clock.advance(250);
	assert near(b.get(), 10 + (75 - 100) + (77.5 - 10));
	clock.advance(250);
	assert near(b.get(), 55) && !a.isAnimating();
	clock.advance(500);
	assert near(b.get(), 10) && target.writers === 0;
}

test "blend composes colour per channel" {
	const target = new MotionTarget();
	const first = target.claim(
		Composition.Blend,
		colorValue(0, 0, 0, 1),
		colorValue(1, 0, 0, 1),
		"fill",
		null,
		(): void => {},
	);
	const out = target.blended(first, colorValue(0.5, 0, 0, 1), "fill");
	assert near(out.color.r, 0.5) && near(out.color.a, 1);
	assert refusal((): void => {
		const ignore = (): void => {};
		target.claim(Composition.Blend, numberValue(0), numberValue(1), "fill", null, ignore);
	}) === "motion: fill blends a number with a colour";
}

test "blend refuses an animated value without a fixed end" {
	const clock = new ManualClock();
	const target = new MotionTarget();
	const value = new AnimatedValue(0, clock.clock, new MotionPolicy(), target, Composition.Blend);
	assert refusal((): void => { value.animate(decay(decayConfig(), 100)); }) ===
		"motion: a blended animation needs a fixed end; decay and reversing repeat have none";
}

test "none keeps last write wins and cancels nobody" {
	const clock = new ManualClock();
	const sink = new Sink();
	const first = player(clock, [ramp("x", 0, 100)], [sink.binding("first")], Composition.None);
	clock.advance(500);
	const second = player(clock, [ramp("x", 300, 400)], [sink.binding("second")], Composition.None);
	clock.advance(100);
	const frame = sink.writes.slice(sink.writes.length - 2);
	assert frame[0].writer === "first" && frame[1].writer === "second";
	assert !first.cancelled && !second.cancelled && sink.target.writers === 0;
}

test "writers without a target identity keep last write wins" {
	const clock = new ManualClock();
	const sink = new Sink();
	const first = player(clock, [ramp("x", 0, 100)], [sink.binding("first", "x", false)]);
	clock.advance(500);
	player(clock, [ramp("x", 300, 400)], [sink.binding("second", "x", false)]);
	clock.advance(100);
	const frame = sink.writes.slice(sink.writes.length - 2);
	assert frame[0].writer === "first" && near(frame[0].value, 60);
	assert frame[1].writer === "second" && !first.cancelled;
}

test "dispose and completion release the target" {
	const clock = new ManualClock();
	const sink = new Sink();
	const older = player(clock, [ramp("x", 0, 100)], [sink.binding("older")]);
	clock.advance(500);
	assert sink.target.writers === 1;
	older.dispose();
	assert sink.target.writers === 0;
	const newer = player(clock, [ramp("x", 300, 400)], [sink.binding("newer")]);
	clock.advance(100);
	assert sink.last().writer === "newer" && !newer.cancelled;
	clock.advance(1000);
	assert sink.target.writers === 0;
}

test "two bindings of one player cannot share a target" {
	const clock = new ManualClock();
	const sink = new Sink();
	assert refusal((): void => {
		const tracks = [ramp("x", 0, 1), ramp("y", 0, 1)];
		player(clock, tracks, [sink.binding("p"), sink.binding("p", "y")]);
	}) === "motion: bindings box.y and another share one target";
}

test "a player and an animated value replace each other on one target" {
	const clock = new ManualClock();
	const sink = new Sink();
	const older = player(clock, [ramp("x", 0, 100)], [sink.binding("player")]);
	clock.advance(500);
	const value = new AnimatedValue(50, clock.clock, new MotionPolicy(), sink.target);
	const seen: float64[] = [];
	value.subscribe((next: float64): void => { seen.push(next); });
	let ended = "";
	const onEnd = (finished: boolean): void => { ended = finished ? "finished" : "cancelled"; };
	value.animate(timing(0, { duration: 1000, easing: Easing.linear }), onEnd);
	assert older.cancelled;
	clock.advance(100);
	assert near(value.get(), 45);
	player(clock, [ramp("x", 300, 400)], [sink.binding("later")]);
	clock.advance(100);
	assert ended === "cancelled" && !value.isAnimating() && near(value.get(), 40);
	assert sink.last().writer === "later";
}

test "set on a replacing value stops the player that holds the target" {
	const clock = new ManualClock();
	const sink = new Sink();
	const older = player(clock, [ramp("x", 0, 100)], [sink.binding("player")]);
	clock.advance(500);
	const value = new AnimatedValue(0, clock.clock, new MotionPolicy(), sink.target);
	value.set(7);
	assert older.cancelled && sink.target.writers === 0 && value.get() === 7;
}
