import { bezier } from "../animation/easing";
import { MotionColor, MotionKeyframe, MotionTrack, MotionValue, ValueKind, colorValue, numberValue } from "./document";

function clamp01(x: float64): float64 {
	return Math.min(Math.max(x, 0), 1);
}

function expandChannel(x: float64): float64 {
	if (x >= 0.04045) { return Math.pow((x + 0.055) / 1.055, 2.4); }
	return x / 12.92;
}

function compressChannel(x: float64): float64 {
	if (x >= 0.0031308) { return 1.055 * Math.pow(x, 1 / 2.4) - 0.055; }
	return 12.92 * x;
}

struct Oklab {
	l: float64;
	a: float64;
	b: float64;
	alpha: float64;
}

function toOklab(color: MotionColor): Oklab {
	const r = expandChannel(color.r);
	const g = expandChannel(color.g);
	const b = expandChannel(color.b);
	const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
	const m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
	const s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
	return {
		l: 0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s,
		a: 1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s,
		b: 0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s,
		alpha: color.a,
	};
}

function fromOklab(lab: Oklab): MotionColor {
	const l = Math.pow(lab.l + 0.3963377774 * lab.a + 0.2158037573 * lab.b, 3);
	const m = Math.pow(lab.l - 0.1055613458 * lab.a - 0.0638541728 * lab.b, 3);
	const s = Math.pow(lab.l - 0.0894841775 * lab.a - 1.291485548 * lab.b, 3);
	return {
		r: clamp01(compressChannel(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s)),
		g: clamp01(compressChannel(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s)),
		b: clamp01(compressChannel(-0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s)),
		a: clamp01(lab.alpha),
	};
}

function mix(left: float64, right: float64, progression: float64): float64 {
	return (1 - progression) * left + progression * right;
}

export function interpolate(left: MotionValue, right: MotionValue, progression: float64): MotionValue {
	if (left.kind !== right.kind) { throw new Error("motion: cannot interpolate a number with a colour"); }
	if (left.kind === ValueKind.Number) {
		return numberValue(left.number + progression * (right.number - left.number));
	}
	const from = toOklab(left.color);
	const to = toOklab(right.color);
	const c = fromOklab({
		l: mix(from.l, to.l, progression),
		a: mix(from.a, to.a, progression),
		b: mix(from.b, to.b, progression),
		alpha: mix(from.alpha, to.alpha, progression),
	});
	return colorValue(c.r, c.g, c.b, c.a);
}

function between(left: MotionKeyframe, right: MotionKeyframe, time: float64): MotionValue {
	if (!left.connectedRight) { return left.value; }
	const local = (time - left.time) / (right.time - left.time);
	const curve = bezier(left.handles.rightX, left.handles.rightY, right.handles.leftX, right.handles.leftY);
	return interpolate(left.value, right.value, curve(local));
}

export function sampleTrack(track: MotionTrack, time: float64): MotionValue {
	const keyframes = track.keyframes;
	if (keyframes.length === 0) { throw new Error("motion: cannot sample a track with no keyframes"); }
	if (time < keyframes[0].time) { return keyframes[0].value; }
	let index: int32 = 0;
	while (index < keyframes.length - 1 && keyframes[index + 1].time <= time) { index += 1; }
	if (index === keyframes.length - 1) { return keyframes[index].value; }
	return between(keyframes[index], keyframes[index + 1], time);
}
