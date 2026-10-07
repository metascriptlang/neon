// RN Libraries/Animated/__tests__/Interpolation-test.js, ported: an
// interpolation over a value set by hand, read at each input.

import { Easing } from "../../src/animation/easing";
import { AnimatedValue, InterpolationConfig, StringInterpolationConfig } from "../../src/animation/nodes";

function numeric(config: InterpolationConfig): (input: number) => number {
	const v = new AnimatedValue(0);
	const node = v.interpolate(config);
	return (input: number): number => {
		v.setValue(input);
		return node.peek();
	};
}

function text(config: StringInterpolationConfig): (input: number) => string {
	const v = new AnimatedValue(0);
	const node = v.interpolateString(config);
	return (input: number): string => {
		v.setValue(input);
		return node.peek();
	};
}

function close(a: number, b: number): boolean {
	return Math.abs(a - b) < 0.005;
}

function throws(run: () => void): boolean {
	try { run(); } catch (e) { return true; }
	return false;
}

test "defaults, output range, input range" {
	const i = numeric({ inputRange: [0, 1], outputRange: [0, 1] });
	assert i(0) === 0 && i(0.5) === 0.5 && i(0.8) === 0.8 && i(1) === 1;
	const o = numeric({ inputRange: [0, 1], outputRange: [100, 200] });
	assert o(0) === 100 && o(0.5) === 150 && o(0.8) === 180 && o(1) === 200;
	const r = numeric({ inputRange: [100, 200], outputRange: [0, 1] });
	assert r(100) === 0 && r(150) === 0.5 && r(180) === 0.8 && r(200) === 1;
}

test "a non-monotonic input range throws, a non-monotonic output range does not" {
	const v = new AnimatedValue(0);
	assert throws((): void => { v.interpolate({ inputRange: [0, 2, 1], outputRange: [0, 1, 2] }); });
	assert !throws((): void => { v.interpolate({ inputRange: [0, 1, 2], outputRange: [0, 3, 1] }); });
}

test "empty input and output segments" {
	const i = numeric({ inputRange: [0, 10, 10], outputRange: [1, 2, 3], extrapolate: "extend" });
	assert i(0) === 1 && i(5) === 1.5 && i(10) === 2 && i(10.1) === 3 && i(15) === 3;
	const o = numeric({ inputRange: [1, 2, 3], outputRange: [0, 10, 10], extrapolate: "extend" });
	assert o(0) === -10 && o(1.5) === 5 && o(2) === 10 && o(2.5) === 10 && o(3) === 10 && o(4) === 10;
}

test "easing and extrapolation" {
	const e = numeric({ inputRange: [0, 1], outputRange: [0, 1], easing: Easing.quad });
	assert e(0) === 0 && e(0.5) === 0.25 && close(e(0.9), 0.81) && e(1) === 1;
	const extend = numeric({ inputRange: [0, 1], outputRange: [0, 1], extrapolate: "extend", easing: Easing.quad });
	assert extend(-2) === 4 && extend(2) === 4;
	const clamp = numeric({ inputRange: [0, 1], outputRange: [0, 1], extrapolate: "clamp", easing: Easing.quad });
	assert clamp(-2) === 0 && clamp(2) === 1;
	const identity = numeric({ inputRange: [0, 1], outputRange: [0, 1], extrapolate: "identity", easing: Easing.quad });
	assert identity(-2) === -2 && identity(2) === 2;
	const leftOnly = numeric({ inputRange: [0, 1], outputRange: [0, 1], extrapolateLeft: "clamp" });
	assert leftOnly(-2) === 0 && leftOnly(2) === 2;
}

test "keyframes with and without extrapolation" {
	const k = numeric({ inputRange: [0, 10, 100, 1000], outputRange: [0, 5, 50, 500] });
	assert k(-5) === -2.5 && k(0) === 0 && k(5) === 2.5 && k(10) === 5 && k(50) === 25;
	assert k(100) === 50 && k(500) === 250 && k(1000) === 500 && k(2000) === 1000;
	const c = numeric({ inputRange: [0, 1, 2], outputRange: [0.2, 1, 0.2], extrapolate: "clamp" });
	assert close(c(5), 0.2);
}

test "infinite ranges" {
	const v = new AnimatedValue(0);
	assert throws((): void => { v.interpolate({ inputRange: [-Infinity, Infinity], outputRange: [0, 1] }); });
	assert !throws((): void => { v.interpolate({ inputRange: [-Infinity, 0, Infinity], outputRange: [1, 2, 3] }); });
	const neg = numeric({ inputRange: [-Infinity, 0], outputRange: [-Infinity, 0], easing: Easing.quad, extrapolate: "identity" });
	assert neg(-Infinity) === -Infinity && close(neg(-100), -10000) && close(neg(-10), -100) && close(neg(0), 0);
	assert close(neg(1), 1) && close(neg(100), 100);
	const pos = numeric({ inputRange: [5, Infinity], outputRange: [5, Infinity], easing: Easing.quad, extrapolate: "identity" });
	assert close(pos(-100), -100) && close(pos(-10), -10) && close(pos(0), 0) && close(pos(5), 5);
	assert close(pos(6), 6) && close(pos(10), 30) && close(pos(100), 5 + 95 * 95) && pos(Infinity) === Infinity;
}

test "colors interpolate to rgba" {
	const rgba = text({ inputRange: [0, 1], outputRange: ["rgba(0, 100, 200, 0)", "rgba(50, 150, 250, 0.4)"] });
	assert rgba(0) === "rgba(0, 100, 200, 0)", rgba(0);
	assert rgba(0.5) === "rgba(25, 125, 225, 0.2)", rgba(0.5);
	assert rgba(1) === "rgba(50, 150, 250, 0.4)", rgba(1);
	const short = text({ inputRange: [0, 1], outputRange: ["#024", "#9BF"] });
	assert short(0) === "rgba(0, 34, 68, 1)" && short(0.5) === "rgba(77, 111, 162, 1)" && short(1) === "rgba(153, 187, 255, 1)", short(0.5);
	const long = text({ inputRange: [0, 1], outputRange: ["#FF9500", "#87FC70"] });
	assert long(0) === "rgba(255, 149, 0, 1)" && long(0.5) === "rgba(195, 201, 56, 1)" && long(1) === "rgba(135, 252, 112, 1)", long(0.5);
	const mixed = text({ inputRange: [0, 1], outputRange: ["rgba(100, 120, 140, .4)", "#87FC70"] });
	assert mixed(0) === "rgba(100, 120, 140, 0.4)" && mixed(0.5) === "rgba(118, 186, 126, 0.7)", mixed(0.5);
	const named = text({ inputRange: [0, 1, 2], outputRange: ["rgba(0, 100, 200, 0)", "rgb(50, 150, 250)", "red"] });
	assert named(0.5) === "rgba(25, 125, 225, 0.5)" && named(1.5) === "rgba(153, 75, 125, 1)" && named(2) === "rgba(255, 0, 0, 1)", named(1.5);
	const alpha = text({ inputRange: [0, 1], outputRange: ["rgba(0, 0, 0, 0)", "rgba(0, 0, 0, 1)"] });
	assert alpha(1e-12) === "rgba(0, 0, 0, 0)" && alpha(2.0 / 3.0) === "rgba(0, 0, 0, 0.667)", alpha(2.0 / 3.0);
}

test "numbers inside strings keep their text" {
	const deg = text({ inputRange: [0, 1], outputRange: ["-100.5deg", "100deg"] });
	assert deg(0) === "-100.5deg" && deg(0.5) === "-0.25deg" && deg(1) === "100deg", deg(0.5);
	const foo = text({ inputRange: [0, 1], outputRange: ["-10foo", "10foo"] });
	assert foo(0) === "-10foo" && foo(0.5) === "0foo", foo(0.5);
	const path = text({ inputRange: [0, 1], outputRange: ["M20,20L20,80L80,80L80,20Z", "M40,40L33,60L60,60L65,40Z"] });
	assert path(0) === "M20,20L20,80L80,80L80,20Z" && path(0.5) === "M30,30L26.5,70L70,70L72.5,30Z", path(0.5);
	const v = new AnimatedValue(0);
	assert throws((): void => { v.interpolateString({ inputRange: [0, 1], outputRange: ["20deg", "30rad"] }); });
}

test "an interpolation of an interpolation chains" {
	const v = new AnimatedValue(0);
	const half = v.interpolate({ inputRange: [0, 2], outputRange: [0, 1] });
	const pct = half.interpolate({ inputRange: [0, 1], outputRange: [0, 100] });
	v.setValue(1);
	assert pct.peek() === 50;
}
