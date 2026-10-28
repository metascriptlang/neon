import { ManualClock } from "../../src/motion/clock";
import { MotionDocument, MotionValue, ValueKind, linearKeyframe, numberValue } from "../../src/motion/document";
import { MotionBinding, MotionOptions, MotionPlayer, motionOptions } from "../../src/motion/player";

function near(a: float64, b: float64): boolean {
	return Math.abs(a - b) <= 1e-6;
}

function rampDocument(): MotionDocument {
	return {
		version: 1,
		root: "main",
		clips: [
			{
				id: "main",
				duration: 1000,
				tracks: [
					{
						slot: "box",
						property: "x",
						kind: ValueKind.Number,
						keyframes: [linearKeyframe("a", 0, 0), linearKeyframe("b", 1000, 100)],
					},
				],
				placements: [],
			},
		],
	};
}

class Probe {
	writes: float64[] = [];
	initial: float64 = 7;
	current: float64 = 7;

	binding(withRead: boolean): MotionBinding {
		return {
			slot: "box",
			property: "x",
			write: (value: MotionValue): void => {
				this.writes.push(value.number);
				this.current = value.number;
			},
			read: withRead ? (): MotionValue => numberValue(this.current) : null,
		};
	}

	last(): float64 {
		return this.writes[this.writes.length - 1];
	}
}

class Events {
	log: string[] = [];

	attach(player: MotionPlayer): void {
		player.onStart = (): void => { this.log.push("start"); };
		player.onUpdate = (): void => { this.log.push("update"); };
		player.onRepeat = (): void => { this.log.push("repeat"); };
		player.onComplete = (): void => { this.log.push("complete"); };
		player.onReverseComplete = (): void => { this.log.push("reverseComplete"); };
	}

	count(name: string): int32 {
		let total: int32 = 0;
		for (const entry of this.log) {
			if (entry === name) { total += 1; }
		}
		return total;
	}
}

class Rig {
	clock: ManualClock = new ManualClock();
	probe: Probe = new Probe();
	events: Events = new Events();
	player: MotionPlayer;

	constructor(configure: (options: MotionOptions) => MotionOptions, withRead: boolean = true) {
		const options = configure(motionOptions(this.clock.clock));
		this.player = new MotionPlayer(rampDocument(), [this.probe.binding(withRead)], options);
		this.events.attach(this.player);
	}
}

function plain(): Rig {
	return new Rig((options: MotionOptions): MotionOptions => options);
}

function refusal(action: () => void): string {
	try { action(); } catch (e) { return e.message; }
	return "";
}

function construction(configure: (options: MotionOptions) => MotionOptions): string {
	const clock = new ManualClock();
	return refusal((): void => {
		new MotionPlayer(rampDocument(), [new Probe().binding(true)], configure(motionOptions(clock.clock)));
	});
}

test "a playing player advances by the clock delta and writes the sampled value" {
	const rig = plain();
	assert rig.clock.pending() === 1;
	assert rig.probe.writes.length === 0, "nothing is written before the first frame";
	rig.clock.advance(250);
	assert near(rig.probe.last(), 25);
	assert near(rig.player.time, 250) && near(rig.player.progress, 0.25);
	rig.clock.advance(250);
	assert near(rig.probe.last(), 50);
	assert rig.clock.pending() === 1, "one frame is requested at a time";
}

test "a player created paused holds no frame and writes nothing until played" {
	const rig = new Rig((options: MotionOptions): MotionOptions => ({ ...options, paused: true }));
	assert rig.player.paused && rig.clock.pending() === 0;
	rig.clock.advance(500);
	assert rig.probe.writes.length === 0 && rig.player.time === 0;
	rig.player.play();
	assert rig.clock.pending() === 1 && !rig.player.paused;
	rig.clock.advance(100);
	assert near(rig.probe.last(), 10);
}

test "pause holds the playhead and the frame request; resume continues without the paused span" {
	const rig = plain();
	rig.clock.advance(300);
	rig.player.pause();
	assert rig.clock.pending() === 0 && rig.player.paused;
	rig.clock.advance(5000);
	assert near(rig.probe.last(), 30) && rig.probe.writes.length === 1;
	rig.player.resume();
	assert rig.clock.pending() === 1;
	rig.clock.advance(100);
	assert near(rig.probe.last(), 40);
}

test "pause at a time seeks first, suppressing events by default" {
	const rig = plain();
	rig.player.pause(600);
	assert near(rig.probe.last(), 60) && rig.player.paused && rig.events.log.length === 0;
}

test "a delay holds the first value back, and onStart fires when the playhead leaves zero" {
	const rig = new Rig((options: MotionOptions): MotionOptions => ({ ...options, delay: 200 }));
	rig.clock.advance(100);
	assert rig.probe.writes.length === 0 && rig.events.log.length === 0 && !rig.player.isActive;
	rig.clock.advance(100);
	assert rig.probe.writes.length === 1 && rig.probe.last() === 0, "the start value is written when the delay ends";
	assert rig.events.count("start") === 0 && rig.player.isActive;
	rig.clock.advance(100);
	assert near(rig.probe.last(), 10);
	assert rig.events.count("start") === 1 && rig.events.count("update") === 2;
	rig.clock.advance(100);
	assert rig.events.count("start") === 1;
}

test "repeat plays the clip again; a boundary belongs to the iteration that ends there" {
	const rig = new Rig((options: MotionOptions): MotionOptions => ({ ...options, repeat: 2 }));
	assert rig.player.totalDuration === 3000;
	rig.clock.advance(1000);
	assert near(rig.probe.last(), 100) && rig.player.iteration === 1 && rig.events.count("repeat") === 0;
	rig.clock.advance(1);
	assert near(rig.probe.last(), 0.1) && rig.player.iteration === 2 && rig.events.count("repeat") === 1;
	rig.clock.advance(999);
	assert near(rig.probe.last(), 100) && rig.player.iteration === 2;
	rig.clock.advance(500);
	assert near(rig.probe.last(), 50) && rig.player.iteration === 3 && rig.events.count("repeat") === 2;
	assert near(rig.player.totalProgress, 2500.0 / 3000.0);
	rig.clock.advance(500);
	assert near(rig.probe.last(), 100) && rig.events.count("complete") === 1;
	assert rig.player.totalProgress === 1 && rig.clock.pending() === 0;
	rig.clock.advance(1000);
	assert rig.events.count("complete") === 1 && rig.events.count("repeat") === 2;
}

test "repeatDelay holds the last value of the iteration and writes nothing" {
	const rig = new Rig((options: MotionOptions): MotionOptions => ({ ...options, repeat: 1, repeatDelay: 500 }));
	assert rig.player.totalDuration === 2500;
	rig.clock.advance(1000);
	assert near(rig.probe.last(), 100);
	const before = rig.probe.writes.length;
	rig.clock.advance(250);
	rig.clock.advance(250);
	assert rig.probe.writes.length === before, "the gap writes nothing";
	rig.clock.advance(100);
	assert near(rig.probe.last(), 10) && rig.player.iteration === 2 && rig.events.count("repeat") === 1;
	rig.clock.advance(900);
	assert near(rig.probe.last(), 100) && rig.events.count("complete") === 1;
}

test "repeatDelay is ignored when the clip does not repeat" {
	const rig = new Rig((options: MotionOptions): MotionOptions => ({ ...options, repeatDelay: 500 }));
	assert rig.player.totalDuration === 1000;
}

test "yoyo plays odd iterations backwards and ends at the start value" {
	const rig = new Rig((options: MotionOptions): MotionOptions => ({ ...options, repeat: 1, yoyo: true }));
	rig.clock.advance(1000);
	assert near(rig.probe.last(), 100);
	rig.clock.advance(250);
	assert near(rig.probe.last(), 75) && near(rig.player.progress, 0.75);
	rig.clock.advance(250);
	assert near(rig.probe.last(), 50);
	rig.clock.advance(500);
	assert near(rig.probe.last(), 0) && rig.events.count("complete") === 1 && rig.clock.pending() === 0;
}

test "repeat -1 never completes and keeps one frame pending" {
	const rig = new Rig((options: MotionOptions): MotionOptions => ({ ...options, repeat: -1 }));
	rig.clock.advance(5500);
	assert near(rig.probe.last(), 50) && rig.player.iteration === 6;
	assert rig.clock.pending() === 1 && rig.events.count("complete") === 0;
}

test "reverse plays backwards from the current time and completes at zero" {
	const rig = plain();
	rig.clock.advance(600);
	rig.player.reverse();
	assert rig.player.reversed && rig.clock.pending() === 1;
	rig.clock.advance(200);
	assert near(rig.probe.last(), 40);
	rig.clock.advance(1000);
	assert near(rig.probe.last(), 0) && rig.events.count("reverseComplete") === 1;
	assert rig.events.count("complete") === 0 && rig.clock.pending() === 0;
	assert rig.player.progress === 0;
}

test "reverse from a time seeks there first; zero means the end, as GSAP reads it" {
	const rig = new Rig((options: MotionOptions): MotionOptions => ({ ...options, paused: true }));
	rig.player.reverse(400);
	assert near(rig.probe.last(), 40);
	rig.clock.advance(100);
	assert near(rig.probe.last(), 30);
	rig.player.reverse(0);
	assert near(rig.probe.last(), 100);
}

test "play after reverse plays forwards again" {
	const rig = plain();
	rig.clock.advance(500);
	rig.player.reverse();
	rig.clock.advance(100);
	rig.player.play();
	assert !rig.player.reversed && rig.player.timeScale === 1;
	rig.clock.advance(100);
	assert near(rig.probe.last(), 50);
}

test "timeScale multiplies the clock delta, and a negative one reverses" {
	const rig = new Rig((options: MotionOptions): MotionOptions => ({ ...options, timeScale: 2 }));
	rig.clock.advance(250);
	assert near(rig.probe.last(), 50);
	rig.player.setTimeScale(0.5);
	rig.clock.advance(200);
	assert near(rig.probe.last(), 60);
	rig.player.setTimeScale(-1);
	assert rig.player.reversed;
	rig.clock.advance(100);
	assert near(rig.probe.last(), 50);
}

test "a zero or non-finite timeScale is refused, in the options and in the setter" {
	assert construction((options: MotionOptions): MotionOptions => ({ ...options, timeScale: 0 })) === "motion: timeScale must be finite and not zero";
	assert construction((options: MotionOptions): MotionOptions => ({ ...options, timeScale: Infinity })).startsWith("motion: ");
	const rig = plain();
	assert refusal((): void => { rig.player.setTimeScale(0); }).startsWith("motion: ");
	assert refusal((): void => { rig.player.setTimeScale(NaN); }).startsWith("motion: ");
	assert rig.player.timeScale === 1;
}

test "invalid delay, repeat and repeatDelay are refused before a frame is requested" {
	assert construction((options: MotionOptions): MotionOptions => ({ ...options, delay: -1 })).startsWith("motion: ");
	assert construction((options: MotionOptions): MotionOptions => ({ ...options, delay: NaN })).startsWith("motion: ");
	assert construction((options: MotionOptions): MotionOptions => ({ ...options, repeat: -2 })).startsWith("motion: ");
	assert construction((options: MotionOptions): MotionOptions => ({ ...options, repeatDelay: -1 })).startsWith("motion: ");
	const clock = new ManualClock();
	refusal((): void => {
		new MotionPlayer(rampDocument(), [new Probe().binding(true)], { ...motionOptions(clock.clock), delay: -1 });
	});
	assert clock.pending() === 0;
}

test "seek writes the value and suppresses events unless asked" {
	const rig = plain();
	rig.player.seek(500);
	assert near(rig.probe.last(), 50) && rig.events.log.length === 0;
	assert near(rig.player.totalTime, 500);
	rig.player.seek(600, false);
	assert near(rig.probe.last(), 60) && rig.events.count("update") === 1;
}

test "seeking to the end without suppression completes, and back to zero reverse-completes" {
	const rig = new Rig((options: MotionOptions): MotionOptions => ({ ...options, paused: true }));
	rig.player.seek(0, false);
	assert rig.events.count("reverseComplete") === 0, "zero to zero is not a reverse completion";
	rig.player.seek(1000, false);
	assert rig.events.count("complete") === 1 && rig.events.count("start") === 1;
	rig.player.seek(0, false);
	assert rig.events.count("reverseComplete") === 1 && near(rig.probe.last(), 0);
}

test "seeking a playing player to the end releases its frame, and seeking back resumes it" {
	const rig = plain();
	rig.player.seek(1000);
	assert rig.clock.pending() === 0 && near(rig.probe.last(), 100);
	rig.player.seek(500);
	assert rig.clock.pending() === 1;
	rig.clock.advance(100);
	assert near(rig.probe.last(), 60);
}

test "a finished player holds no frame, play at the end does not restart, restart does" {
	const rig = plain();
	rig.clock.advance(1000);
	assert rig.events.count("complete") === 1 && rig.clock.pending() === 0;
	rig.player.play();
	assert rig.clock.pending() === 0;
	rig.player.restart();
	assert rig.clock.pending() === 1 && rig.events.count("complete") === 1;
	assert near(rig.probe.last(), 0) && rig.events.count("update") === 1, "restart suppresses events by default";
	rig.clock.advance(1000);
	assert rig.events.count("complete") === 2;
}

test "restart with the delay seeks before it, restart without skips it" {
	const rig = new Rig((options: MotionOptions): MotionOptions => ({ ...options, delay: 300 }));
	rig.clock.advance(800);
	assert near(rig.probe.last(), 50);
	rig.player.restart(true);
	rig.clock.advance(300);
	assert near(rig.probe.last(), 0), "the delay is waited again";
	rig.clock.advance(100);
	assert near(rig.probe.last(), 10);
	rig.player.restart();
	rig.clock.advance(100);
	assert near(rig.probe.last(), 10), "no delay";
}

test "progress and totalProgress setters seek, and fire events unless suppressed" {
	const rig = new Rig((options: MotionOptions): MotionOptions => ({ ...options, repeat: 1, yoyo: true, paused: true }));
	rig.player.setProgress(0.25);
	assert near(rig.probe.last(), 25) && rig.events.count("update") === 1;
	rig.player.setTotalProgress(0.75, true);
	assert near(rig.probe.last(), 50) && near(rig.player.progress, 0.5) && rig.events.count("update") === 1;
	rig.player.setTotalProgress(0.625, true);
	assert near(rig.probe.last(), 75) && rig.player.iteration === 2;
	rig.player.setProgress(0.2, true);
	assert near(rig.player.progress, 0.2) && near(rig.player.totalTime, 1800), "yoyo mirrors the time in an odd iteration";
}

test "time and totalTime setters seek inside the iteration and over all iterations" {
	const rig = new Rig((options: MotionOptions): MotionOptions => ({ ...options, repeat: 2, paused: true }));
	rig.player.setTotalTime(1500, true);
	assert near(rig.player.time, 500) && rig.player.iteration === 2;
	rig.player.setTime(250, true);
	assert near(rig.player.totalTime, 1250) && near(rig.probe.last(), 25);
	rig.player.setTime(1000, true);
	assert near(rig.player.totalTime, 2000) && near(rig.probe.last(), 100);
}

test "two players of one document on one clock share nothing but the clock" {
	const clock = new ManualClock();
	const left = new Probe();
	const right = new Probe();
	const a = new MotionPlayer(rampDocument(), [left.binding(true)], motionOptions(clock.clock));
	const b = new MotionPlayer(rampDocument(), [right.binding(true)], { ...motionOptions(clock.clock), timeScale: 2 });
	assert clock.pending() === 2;
	clock.advance(200);
	assert near(left.last(), 20) && near(right.last(), 40);
	a.pause();
	clock.advance(100);
	assert near(left.last(), 20) && near(right.last(), 60) && clock.pending() === 1;
	b.seek(0);
	assert near(right.last(), 0) && near(left.last(), 20) && a.paused && !b.paused;
	a.dispose();
	clock.advance(100);
	assert near(right.last(), 20);
	b.finish();
	assert near(right.last(), 100) && b.totalProgress === 1;
}

test "finish goes to the end in the current direction, with events" {
	const rig = plain();
	rig.clock.advance(300);
	rig.player.finish();
	assert near(rig.probe.last(), 100) && rig.events.count("complete") === 1 && rig.clock.pending() === 0;
	rig.player.seek(400);
	rig.player.reverse();
	rig.player.finish();
	assert near(rig.probe.last(), 0) && rig.events.count("reverseComplete") === 1 && rig.clock.pending() === 0;
}

test "finish with repeats goes to the last iteration's end" {
	const rig = new Rig((options: MotionOptions): MotionOptions => ({ ...options, repeat: 2, yoyo: true }));
	rig.player.finish();
	assert near(rig.probe.last(), 100) && rig.player.iteration === 3 && rig.events.count("complete") === 1;
}

test "cancel keeps the current value, releases the frame, and a later play revives" {
	const rig = plain();
	rig.clock.advance(200);
	rig.player.cancel();
	assert rig.player.cancelled && rig.player.paused && rig.clock.pending() === 0;
	rig.clock.advance(1000);
	assert near(rig.probe.last(), 20) && rig.probe.writes.length === 1;
	assert rig.events.count("complete") === 0 && rig.events.count("reverseComplete") === 0;
	rig.player.play();
	assert !rig.player.cancelled && rig.clock.pending() === 1;
	rig.clock.advance(100);
	assert near(rig.probe.last(), 30);
}

test "revert writes the value read at the first render, then holds" {
	const rig = plain();
	rig.clock.advance(500);
	assert near(rig.probe.last(), 50);
	rig.player.revert();
	assert rig.probe.last() === 7 && rig.clock.pending() === 0 && rig.player.cancelled;
	assert rig.player.totalTime === 0 && rig.player.time === 0;
	const count = rig.probe.writes.length;
	rig.clock.advance(500);
	assert rig.probe.writes.length === count;
	rig.probe.current = 3;
	rig.player.play();
	rig.clock.advance(100);
	rig.player.revert();
	assert rig.probe.last() === 3, "a later render reads again";
}

test "revert before any render writes nothing" {
	const rig = new Rig((options: MotionOptions): MotionOptions => ({ ...options, paused: true }));
	rig.player.revert();
	assert rig.probe.writes.length === 0 && rig.clock.pending() === 0;
}

test "revert without a read on a binding refuses and changes nothing" {
	const rig = new Rig((options: MotionOptions): MotionOptions => options, false);
	rig.clock.advance(500);
	assert refusal((): void => { rig.player.revert(); }) === "motion: cannot revert: binding box.x has no read";
	assert !rig.player.paused && rig.clock.pending() === 1 && rig.probe.writes.length === 1;
}

test "dispose releases the frame and refuses every later call" {
	const rig = plain();
	rig.clock.advance(100);
	rig.player.dispose();
	assert rig.player.disposed && rig.clock.pending() === 0;
	const message = "motion: player is disposed";
	assert refusal((): void => { rig.player.play(); }) === message;
	assert refusal((): void => { rig.player.pause(); }) === message;
	assert refusal((): void => { rig.player.resume(); }) === message;
	assert refusal((): void => { rig.player.reverse(); }) === message;
	assert refusal((): void => { rig.player.seek(0); }) === message;
	assert refusal((): void => { rig.player.restart(); }) === message;
	assert refusal((): void => { rig.player.finish(); }) === message;
	assert refusal((): void => { rig.player.cancel(); }) === message;
	assert refusal((): void => { rig.player.revert(); }) === message;
	assert refusal((): void => { rig.player.setProgress(0.5); }) === message;
	assert refusal((): void => { rig.player.setTimeScale(2); }) === message;
	assert refusal((): void => { rig.player.dispose(); }) === message;
	assert refusal((): void => { rig.player.progress; }) === message;
	assert rig.clock.pending() === 0;
	rig.clock.advance(1000);
	assert rig.probe.writes.length === 1;
}

test "a write that disposes the player causes no further write" {
	const clock = new ManualClock();
	const doc = rampDocument();
	doc.clips[0].tracks.push({
		slot: "box",
		property: "y",
		kind: ValueKind.Number,
		keyframes: [linearKeyframe("a", 0, 0), linearKeyframe("b", 1000, 10)],
	});
	let player: MotionPlayer | null = null;
	let xWrites = 0;
	let yWrites = 0;
	const bindings: MotionBinding[] = [
		{
			slot: "box",
			property: "x",
			write: (value: MotionValue): void => {
				xWrites += 1;
				if (player !== null) { player.dispose(); }
			},
			read: null,
		},
		{ slot: "box", property: "y", write: (value: MotionValue): void => { yWrites += 1; }, read: null },
	];
	player = new MotionPlayer(doc, bindings, motionOptions(clock.clock));
	clock.advance(100);
	assert xWrites === 1 && yWrites === 0 && clock.pending() === 0;
	clock.advance(100);
	assert xWrites === 1 && yWrites === 0;
}

test "a listener that disposes the player stops the rest of the frame" {
	const rig = plain();
	rig.player.onUpdate = (): void => { rig.player.dispose(); };
	rig.player.onComplete = (): void => { rig.events.log.push("complete"); };
	rig.clock.advance(1000);
	assert rig.player.disposed && rig.events.count("complete") === 0 && rig.clock.pending() === 0;
}

test "a listener that pauses stops the frame; one that seeks wins over the rest of its render" {
	const rig = plain();
	rig.player.onUpdate = (): void => { rig.player.pause(); };
	rig.clock.advance(100);
	assert rig.player.paused && rig.clock.pending() === 0;
	const other = plain();
	other.player.onStart = (): void => { other.player.seek(900); };
	other.clock.advance(100);
	assert near(other.probe.last(), 90) && other.probe.writes.length === 1;
}

test "bindings are checked before any write or frame request" {
	const clock = new ManualClock();
	const probe = new Probe();
	const good = probe.binding(true);
	const other: MotionBinding = { slot: "box", property: "y", write: (value: MotionValue): void => {}, read: null };
	const checks: MotionBinding[][] = [[], [good, good], [good, other]];
	const expected: string[] = [
		"motion: no binding for track box.x",
		"motion: duplicate binding for box.x",
		"motion: binding box.y has no track",
	];
	for (let i: int32 = 0; i < checks.length; i += 1) {
		const message = refusal((): void => {
			new MotionPlayer(rampDocument(), checks[i], motionOptions(clock.clock));
		});
		assert message === expected[i], message;
	}
	assert probe.writes.length === 0 && clock.pending() === 0;
}

test "an invalid document is refused by validation, and a composed root is refused for now" {
	const clock = new ManualClock();
	const invalid = { ...rampDocument(), version: 2 };
	const invalidMessage = refusal((): void => {
		new MotionPlayer(invalid, [new Probe().binding(true)], motionOptions(clock.clock));
	});
	assert invalidMessage === "motion: unsupported version 2";
	const composed = rampDocument();
	composed.clips.push({ id: "leaf", duration: 100, tracks: [], placements: [] });
	composed.clips[0].placements.push({ clip: "leaf", start: 0, rate: 1, slots: [] });
	const composedMessage = refusal((): void => {
		new MotionPlayer(composed, [new Probe().binding(true)], motionOptions(clock.clock));
	});
	assert composedMessage === "motion: composition is not supported yet";
	assert clock.pending() === 0;
}

test "isActive is true only while the playhead moves inside the clip" {
	const rig = plain();
	assert !rig.player.isActive, "nothing has rendered yet";
	rig.clock.advance(100);
	assert rig.player.isActive;
	rig.player.pause();
	assert !rig.player.isActive;
	rig.player.resume();
	assert rig.player.isActive;
	rig.clock.advance(2000);
	assert !rig.player.isActive;
}
