import {
	MotionKeyframe,
	MotionTrack,
	ValueKind,
	colorValue,
	linearKeyframe,
	numberValue,
} from "../../src/motion/document";
import { interpolate, sampleTrack } from "../../src/motion/evaluate";

function near(a: float64, b: float64, tolerance: float64): boolean {
	return Math.abs(a - b) <= tolerance;
}

function numbers(keyframes: MotionKeyframe[]): MotionTrack {
	return { slot: "box", property: "x", kind: ValueKind.Number, keyframes };
}

function at(track: MotionTrack, time: float64): float64 {
	return sampleTrack(track, time).number;
}

function threw(track: MotionTrack): boolean {
	try { sampleTrack(track, 0); } catch (e) { return e.message.startsWith("motion: "); }
	return false;
}

test "before the first key the value is the first value, after the last the last" {
	const track = numbers([linearKeyframe("a", 100, 10), linearKeyframe("b", 200, 20)]);
	assert at(track, -50) === 10;
	assert at(track, 99.5) === 10;
	assert at(track, 200.5) === 20;
	assert at(track, 1e9) === 20;
}

test "a single keyframe is a constant" {
	const track = numbers([linearKeyframe("a", 100, 7)]);
	assert at(track, 0) === 7 && at(track, 100) === 7 && at(track, 500) === 7;
}

test "an exact keyframe time gives that keyframe's value" {
	const track = numbers([linearKeyframe("a", 0, 0), linearKeyframe("b", 100, 10), linearKeyframe("c", 300, 50)]);
	assert at(track, 0) === 0;
	assert at(track, 100) === 10;
	assert at(track, 300) === 50;
}

test "linear handles interpolate linearly between keys" {
	const track = numbers([linearKeyframe("a", 0, 0), linearKeyframe("b", 100, 10), linearKeyframe("c", 300, 50)]);
	assert near(at(track, 50), 5, 1e-4);
	assert near(at(track, 200), 30, 1e-4);
	assert near(at(track, 250), 40, 1e-4);
}

test "a keyframe that is not connected right holds its value until the next key" {
	const first = linearKeyframe("a", 0, 0);
	let held = { ...first, connectedRight: false };
	const track = numbers([held, linearKeyframe("b", 100, 10)]);
	assert at(track, 0) === 0;
	assert at(track, 50) === 0;
	assert at(track, 99.999) === 0;
	assert at(track, 100) === 10;
}

test "bezier handles shape the progression" {
	let left = linearKeyframe("a", 0, 0);
	let right = linearKeyframe("b", 100, 100);
	left = { ...left, handles: { leftX: 0, leftY: 0, rightX: 0.25, rightY: 0.1 } };
	right = { ...right, handles: { leftX: 0.25, leftY: 1, rightX: 0, rightY: 0 } };
	const track = numbers([left, right]);
	assert near(at(track, 50), 80.24, 0.1), "ease at the midpoint " + at(track, 50).toString();
	assert near(at(track, 0), 0, 1e-9);
	assert near(at(track, 100), 100, 1e-9);
}

test "a handle y outside [0, 1] overshoots" {
	let left = linearKeyframe("a", 0, 0);
	let right = linearKeyframe("b", 100, 100);
	left = { ...left, handles: { leftX: 0, leftY: 0, rightX: 0.3, rightY: 2 } };
	const track = numbers([left, right]);
	assert at(track, 30) > 100, at(track, 30).toString();
}

test "the second segment uses its own handles" {
	const a = linearKeyframe("a", 0, 0);
	let b = linearKeyframe("b", 100, 100);
	b = { ...b, handles: { leftX: 2.0 / 3.0, leftY: 2.0 / 3.0, rightX: 0.25, rightY: 0.1 } };
	let c = linearKeyframe("c", 200, 200);
	c = { ...c, handles: { leftX: 0.25, leftY: 1, rightX: 0, rightY: 0 } };
	const track = numbers([a, b, c]);
	assert near(at(track, 50), 50, 1e-3);
	assert near(at(track, 150), 100 + 80.24, 0.1);
}

test "sampling a track with no keyframes fails loud" {
	assert threw(numbers([]));
}

test "colours interpolate in Oklab, not per sRGB channel" {
	const mid = interpolate(colorValue(0, 0, 0, 0), colorValue(1, 1, 1, 1), 0.5);
	assert near(mid.color.r, 0.3885, 0.002), "r " + mid.color.r.toString();
	assert near(mid.color.g, mid.color.r, 1e-6) && near(mid.color.b, mid.color.r, 1e-6);
	assert near(mid.color.a, 0.5, 1e-9);
}

test "a colour track samples its endpoints and clamps outside the first and last key" {
	const red = colorValue(1, 0, 0, 1);
	const blue = colorValue(0, 0, 1, 1);
	const track: MotionTrack = {
		slot: "box",
		property: "fill",
		kind: ValueKind.Color,
		keyframes: [{ ...linearKeyframe("a", 0, 0), value: red }, { ...linearKeyframe("b", 100, 0), value: blue }],
	};
	assert sampleTrack(track, -10).color.r === 1;
	assert sampleTrack(track, 200).color.b === 1;
	const start = sampleTrack(track, 0).color;
	assert near(start.r, 1, 1e-6) && near(start.g, 0, 1e-6) && near(start.b, 0, 1e-6);
	const middle = sampleTrack(track, 50).color;
	assert middle.r > 0 && middle.b > 0 && middle.r < 1 && middle.b < 1;
	assert middle.a === 1;
}

test "a colour overshoot stays inside [0, 1]" {
	const over = interpolate(colorValue(1, 0, 0, 1), colorValue(0, 0, 1, 1), 1.5);
	assert over.color.r >= 0 && over.color.r <= 1 && over.color.g >= 0 && over.color.g <= 1;
	assert over.color.b >= 0 && over.color.b <= 1 && over.color.a === 1;
}

test "interpolating a number with a colour is refused" {
	let refused = false;
	try { interpolate(numberValue(1), colorValue(0, 0, 0, 1), 0.5); } catch (e) { refused = e.message.startsWith("motion: "); }
	assert refused;
}
