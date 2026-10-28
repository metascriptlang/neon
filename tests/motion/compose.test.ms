import { ManualClock } from "../../src/motion/clock";
import {
	MotionClip,
	MotionDocument,
	MotionPlacement,
	MotionSlotMapping,
	MotionTrack,
	MotionValue,
	ValueKind,
	colorValue,
	linearKeyframe,
	numberValue,
	validate,
} from "../../src/motion/document";
import { MotionBinding, MotionPlayer, motionOptions } from "../../src/motion/player";

function near(a: float64, b: float64): boolean {
	return Math.abs(a - b) <= 1e-6;
}

function ramp(slot: string, property: string, from: float64, to: float64, duration: float64): MotionTrack {
	return {
		slot,
		property,
		kind: ValueKind.Number,
		keyframes: [linearKeyframe("a", 0, from), linearKeyframe("b", duration, to)],
	};
}

function clip(id: string, duration: float64, tracks: MotionTrack[], placements: MotionPlacement[]): MotionClip {
	return { id, duration, tracks, placements };
}

function place(child: string, start: float64, rate: float64, slots: MotionSlotMapping[]): MotionPlacement {
	return { clip: child, start, rate, slots };
}

function map(from: string, to: string): MotionSlotMapping {
	return { from, to };
}

function document(clips: MotionClip[]): MotionDocument {
	return { version: 1, root: clips[0].id, clips };
}

class Target {
	name: string;
	writes: float64[] = [];
	current: float64 = -1;

	constructor(name: string) {
		this.name = name;
	}
}

class Recorder {
	targets: Target[] = [];

	bind(slot: string, property: string): MotionBinding {
		const target = new Target(slot + "." + property);
		this.targets.push(target);
		return {
			slot,
			property,
			write: (value: MotionValue): void => {
				target.writes.push(value.number);
				target.current = value.number;
			},
			read: (): MotionValue => numberValue(target.current),
		};
	}

	find(name: string): Target {
		for (const target of this.targets) {
			if (target.name === name) { return target; }
		}
		throw new Error("no target " + name);
	}

	value(name: string): float64 {
		const target = this.find(name);
		return target.writes[target.writes.length - 1];
	}

	count(name: string): int32 {
		return this.find(name).writes.length;
	}
}

function paused(doc: MotionDocument, bindings: MotionBinding[]): MotionPlayer {
	const clock = new ManualClock();
	return new MotionPlayer(doc, bindings, { ...motionOptions(clock.clock), paused: true });
}

function refusal(action: () => void): string {
	try { action(); } catch (e) { return e.message; }
	return "";
}

test "two instances of one clip write their own targets through their slot mappings" {
	const doc = document([
		clip("main", 400, [], [
			place("fade", 0, 1, [map("item", "a")]),
			place("fade", 200, 1, [map("item", "b")]),
		]),
		clip("fade", 100, [ramp("item", "opacity", 0, 1, 100)], []),
	]);
	const rec = new Recorder();
	const player = paused(doc, [rec.bind("a", "opacity"), rec.bind("b", "opacity")]);
	player.seek(50);
	assert near(rec.value("a.opacity"), 0.5) && rec.count("b.opacity") === 0;
	player.seek(250);
	assert near(rec.value("a.opacity"), 1) && near(rec.value("b.opacity"), 0.5);
	const missing = refusal((): void => { paused(doc, [new Recorder().bind("a", "opacity")]); });
	assert missing === "motion: no binding for track b.opacity", missing;
}

test "slot mappings compose through two levels, and an unmapped slot keeps its name" {
	const doc = document([
		clip("main", 400, [], [
			place("pair", 0, 1, [map("left", "a"), map("right", "b")]),
			place("pair", 200, 1, [map("left", "c")]),
		]),
		clip("pair", 200, [], [
			place("dot", 0, 1, [map("dot", "left")]),
			place("dot", 100, 1, [map("dot", "right")]),
		]),
		clip("dot", 100, [ramp("dot", "x", 0, 100, 100)], []),
	]);
	const rec = new Recorder();
	const player = paused(doc, [rec.bind("a", "x"), rec.bind("b", "x"), rec.bind("c", "x"), rec.bind("right", "x")]);
	player.seek(150);
	assert near(rec.value("a.x"), 100) && near(rec.value("b.x"), 50);
	assert rec.count("c.x") === 0 && rec.count("right.x") === 0;
	player.seek(350);
	assert near(rec.value("c.x"), 100) && near(rec.value("right.x"), 50);
}

test "start and rate compose through nesting: child time is (parent time - start) * rate" {
	const doc = document([
		clip("main", 1000, [], [place("mid", 200, 4, [])]),
		clip("mid", 400, [], [place("leaf", 100, 0.5, [])]),
		clip("leaf", 100, [ramp("box", "x", 0, 100, 100)], []),
	]);
	const rec = new Recorder();
	const player = paused(doc, [rec.bind("box", "x")]);
	player.seek(250);
	assert near(rec.value("box.x"), 50), "leaf window is [225, 275] in root time at rate 2";
	player.seek(275);
	assert near(rec.value("box.x"), 100);
	player.seek(600);
	assert near(rec.value("box.x"), 100), "after its window a child holds its end value";
}

test "a child before its window writes nothing until it has rendered, then holds its first value" {
	const doc = document([
		clip("main", 1000, [], [place("leaf", 500, 1, [])]),
		clip("leaf", 100, [ramp("box", "x", 10, 20, 100)], []),
	]);
	const rec = new Recorder();
	const player = paused(doc, [rec.bind("box", "x")]);
	player.seek(200);
	assert rec.count("box.x") === 0, "GSAP does not render a child the playhead has not reached";
	player.seek(550);
	assert near(rec.value("box.x"), 15);
	player.seek(200);
	assert near(rec.value("box.x"), 10), "once rendered, a child before its start shows its first value";
	player.revert();
	const count = rec.count("box.x");
	player.seek(200);
	assert rec.count("box.x") === count, "revert forgets that the child rendered";
}

function contention(): MotionDocument {
	return document([
		clip("main", 1000, [], [
			place("a", 0, 1, []),
			place("d", 50, 1, []),
			place("b", 300, 1, []),
			place("c", 700, 1, []),
		]),
		clip("a", 400, [ramp("box", "x", 0, 400, 400)], []),
		clip("d", 50, [ramp("box", "x", 2000, 2050, 50)], []),
		clip("b", 200, [ramp("box", "x", 1000, 1200, 200)], []),
		clip("c", 100, [ramp("box", "x", 5000, 5100, 100)], []),
	]);
}

test "two writers of one property: the later-starting one wins while active" {
	const rec = new Recorder();
	const player = paused(contention(), [rec.bind("box", "x")]);
	player.seek(75);
	assert near(rec.value("box.x"), 2025), "d starts after a";
	player.seek(200);
	assert near(rec.value("box.x"), 200), "an ended writer never beats an active one";
	player.seek(300);
	assert near(rec.value("box.x"), 1000), "at b's start both cover, and b starts later";
	player.seek(350);
	assert near(rec.value("box.x"), 1050);
	player.seek(450);
	assert near(rec.value("box.x"), 1150);
	player.seek(650);
	assert near(rec.value("box.x"), 1200), "between writers the last one to end holds";
	player.seek(900);
	assert near(rec.value("box.x"), 5100);
}

test "when no writer covers a time, the one that ended last holds, not the one that started last" {
	const doc = document([
		clip("main", 1000, [], [place("long", 0, 1, []), place("short", 100, 1, [])]),
		clip("long", 400, [ramp("box", "x", 0, 400, 400)], []),
		clip("short", 100, [ramp("box", "x", 1000, 1100, 100)], []),
	]);
	const rec = new Recorder();
	const player = paused(doc, [rec.bind("box", "x")]);
	player.seek(500);
	assert near(rec.value("box.x"), 400);
}

test "a scrub gives the same value at a time whichever direction it arrives from" {
	const times: float64[] = [0, 75, 200, 300, 350, 400, 450, 500, 650, 700, 750, 900, 1000];
	const forward: float64[] = [];
	const rec = new Recorder();
	const player = paused(contention(), [rec.bind("box", "x")]);
	for (const time of times) {
		player.seek(time);
		forward.push(rec.value("box.x"));
	}
	for (let i: int32 = times.length - 1; i >= 0; i -= 1) {
		player.seek(times[i]);
		assert near(rec.value("box.x"), forward[i]), "backward at " + times[i].toString();
	}
	player.seek(900);
	player.seek(650);
	assert near(rec.value("box.x"), 1200), "not c's first value, as a GSAP backward pass would write";
}

test "writers of one property with different value kinds are refused" {
	const doc = document([
		clip("main", 1000, [ramp("box", "fill", 0, 1, 1000)], [place("tint", 0, 1, [])]),
		clip("tint", 100, [{
			slot: "box",
			property: "fill",
			kind: ValueKind.Color,
			keyframes: [{ ...linearKeyframe("a", 0, 0), value: colorValue(1, 0, 0, 1) }],
		}], []),
	]);
	const message = refusal((): void => { paused(doc, [new Recorder().bind("box", "fill")]); });
	assert message === "motion: tracks of different kinds write box.fill", message;
}

test "the root duration is authoritative: a placement outside its parent's duration is refused" {
	const doc = document([
		clip("main", 1000, [], [place("mid", 600, 1, [])]),
		clip("mid", 400, [], [place("leaf", 300, 1, [])]),
		clip("leaf", 100, [ramp("box", "x", 0, 1, 100)], []),
	]);
	validate(doc);
	const rec = new Recorder();
	assert paused(doc, [rec.bind("box", "x")]).duration === 1000;
	doc.clips[0].placements[0].start = 601;
	assert refusal((): void => { validate(doc); }) === "motion: placement of clip mid must lie inside the duration of clip main";
	doc.clips[0].placements[0].start = 600;
	doc.clips[1].placements[0].rate = 0.5;
	assert refusal((): void => { validate(doc); }) === "motion: placement of clip leaf must lie inside the duration of clip mid";
	doc.clips[1].placements[0].rate = 1;
	doc.clips[1].placements[0].start = -1;
	assert refusal((): void => { validate(doc); }).startsWith("motion: placement of clip leaf");
}
