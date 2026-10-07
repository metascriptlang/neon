import { parsePathData, geometryText, geometryBounds, formatNumber } from "../../../src/components/svg/pathData";

function absolute(d: string): string {
	return geometryText(parsePathData(d));
}

function same(d: string, expected: string): string {
	const got = absolute(d);
	return got === expected ? "" : d + " => " + got;
}

test "absolute and relative lines, H/V and closepath" {
	assert same("M10 20 L30 40", "M 10 20 L 30 40") === "", same("M10 20 L30 40", "M 10 20 L 30 40");
	assert same("m10 20 l5 5 h10 v-5 z", "M 10 20 L 15 25 L 25 25 L 25 20 Z") === "", same("m10 20 l5 5 h10 v-5 z", "M 10 20 L 15 25 L 25 25 L 25 20 Z");
	assert same("M10 20 H30 V40 h-5 v-5", "M 10 20 L 30 20 L 30 40 L 25 40 L 25 35") === "", same("M10 20 H30 V40 h-5 v-5", "M 10 20 L 30 20 L 30 40 L 25 40 L 25 35");
	assert same("M10 10 L20 10 Z l5 5", "M 10 10 L 20 10 Z L 15 15") === "", same("M10 10 L20 10 Z l5 5", "M 10 10 L 20 10 Z L 15 15");
}

test "pairs after a moveto are implicit linetos, relative after a relative moveto" {
	assert same("M0 0 10 10 20 0", "M 0 0 L 10 10 L 20 0") === "", same("M0 0 10 10 20 0", "M 0 0 L 10 10 L 20 0");
	assert same("m1 1 2 2", "M 1 1 L 3 3") === "", same("m1 1 2 2", "M 1 1 L 3 3");
	assert same("M1 1 m2 2 3 3", "M 1 1 M 3 3 L 6 6") === "", same("M1 1 m2 2 3 3", "M 1 1 M 3 3 L 6 6");
	assert same("M0 0 L1 1 2 2 3 3", "M 0 0 L 1 1 L 2 2 L 3 3") === "", same("M0 0 L1 1 2 2 3 3", "M 0 0 L 1 1 L 2 2 L 3 3");
}

test "compact number syntax: signs, leading dots, exponents and commas" {
	assert same("M.5-1.5.5.25L1e1-2", "M 0.5 -1.5 L 0.5 0.25 L 10 -2") === "", same("M.5-1.5.5.25L1e1-2", "M 0.5 -1.5 L 0.5 0.25 L 10 -2");
	assert same("M 1,2 L 3 , 4", "M 1 2 L 3 4") === "", same("M 1,2 L 3 , 4", "M 1 2 L 3 4");
	assert same("M1.5e-1 2E+1", "M 0.15 20") === "", same("M1.5e-1 2E+1", "M 0.15 20");
}

test "smooth cubics reflect the previous control point, or start at the pen" {
	assert same("M0 0 C10 0 20 10 20 20 S30 40 40 40", "M 0 0 C 10 0 20 10 20 20 C 20 30 30 40 40 40") === "", same("M0 0 C10 0 20 10 20 20 S30 40 40 40", "M 0 0 C 10 0 20 10 20 20 C 20 30 30 40 40 40");
	assert same("M0 0 S10 10 20 0", "M 0 0 C 0 0 10 10 20 0") === "", same("M0 0 S10 10 20 0", "M 0 0 C 0 0 10 10 20 0");
	assert same("M0 0 c10 0 20 10 20 20 s10 20 20 20", "M 0 0 C 10 0 20 10 20 20 C 20 30 30 40 40 40") === "", same("M0 0 c10 0 20 10 20 20 s10 20 20 20", "M 0 0 C 10 0 20 10 20 20 C 20 30 30 40 40 40");
}

test "quadratics and smooth quadratics" {
	assert same("M0 0 Q10 10 20 0 T40 0", "M 0 0 Q 10 10 20 0 Q 30 -10 40 0") === "", same("M0 0 Q10 10 20 0 T40 0", "M 0 0 Q 10 10 20 0 Q 30 -10 40 0");
	assert same("M0 0 q10 10 20 0 t20 0", "M 0 0 Q 10 10 20 0 Q 30 -10 40 0") === "", same("M0 0 q10 10 20 0 t20 0", "M 0 0 Q 10 10 20 0 Q 30 -10 40 0");
	assert same("M0 0 T10 10", "M 0 0 Q 0 0 10 10") === "", same("M0 0 T10 10", "M 0 0 Q 0 0 10 10");
	assert same("M0 0 C1 1 2 2 3 3 T10 10", "M 0 0 C 1 1 2 2 3 3 Q 3 3 10 10") === "", same("M0 0 C1 1 2 2 3 3 T10 10", "M 0 0 C 1 1 2 2 3 3 Q 3 3 10 10");
}

test "an arc becomes one cubic per quarter turn (F.6.5)" {
	const half = "M 0 0 C 0 -5.5228 4.4772 -10 10 -10 C 15.5228 -10 20 -5.5228 20 0";
	assert same("M0 0 A10 10 0 0 1 20 0", half) === "", same("M0 0 A10 10 0 0 1 20 0", half);
	// Sweep 0 takes the other side.
	assert same("M0 0 A10 10 0 0 0 20 0", "M 0 0 C 0 5.5228 4.4772 10 10 10 C 15.5228 10 20 5.5228 20 0") === "", same("M0 0 A10 10 0 0 0 20 0", "M 0 0 C 0 5.5228 4.4772 10 10 10 C 15.5228 10 20 5.5228 20 0");
	// Radii too small to reach are scaled up (F.6.6).
	assert same("M0 0 A1 1 0 0 1 20 0", half) === "", same("M0 0 A1 1 0 0 1 20 0", half);
	// Flags need no separator.
	assert same("M0 0a10 10 0 0120 0", half) === "", same("M0 0a10 10 0 0120 0", half);
	// A quarter arc is one cubic.
	assert same("M10 0 A10 10 0 0 1 0 10", "M 10 0 C 10 5.5228 5.5228 10 0 10") === "", same("M10 0 A10 10 0 0 1 0 10", "M 10 0 C 10 5.5228 5.5228 10 0 10");
}

test "large-arc picks the long way round; rotation turns the ellipse" {
	assert same("M10 0 A10 10 0 1 1 0 10", "M 10 0 C 15.5228 0 20 4.4772 20 10 C 20 15.5228 15.5228 20 10 20 C 4.4772 20 0 15.5228 0 10") === "", same("M10 0 A10 10 0 1 1 0 10", "M 10 0 C 15.5228 0 20 4.4772 20 10 C 20 15.5228 15.5228 20 10 20 C 4.4772 20 0 15.5228 0 10");
	assert same("M0 0 A20 10 90 0 1 0 40", "M 0 0 C 5.5228 0 10 8.9543 10 20 C 10 31.0457 5.5228 40 0 40") === "", same("M0 0 A20 10 90 0 1 0 40", "M 0 0 C 5.5228 0 10 8.9543 10 20 C 10 31.0457 5.5228 40 0 40");
}

test "a zero radius is a line and a zero-length arc is dropped" {
	assert same("M0 0 A0 10 0 0 1 20 0", "M 0 0 L 20 0") === "", same("M0 0 A0 10 0 0 1 20 0", "M 0 0 L 20 0");
	assert same("M5 5 A10 10 0 0 1 5 5 L6 6", "M 5 5 L 6 6") === "", same("M5 5 A10 10 0 0 1 5 5 L6 6", "M 5 5 L 6 6");
}

test "data renders up to the first error" {
	assert same("M10 10 L20", "M 10 10") === "", same("M10 10 L20", "M 10 10");
	assert same("L10 10", "") === "", same("L10 10", "");
	assert same("M10 10 X 5", "M 10 10") === "", same("M10 10 X 5", "M 10 10");
	assert same("M10 10 A10 10 0 2 1 0 0", "M 10 10") === "", same("M10 10 A10 10 0 2 1 0 0", "M 10 10");
	assert same("  ", "") === "", same("  ", "");
}

test "bounds are exact for curves" {
	const b = geometryBounds(parsePathData("M0 0 A10 10 0 0 1 20 0"));
	assert formatNumber(b.minX) === "0" && formatNumber(b.maxX) === "20", "x";
	assert formatNumber(b.minY) === "-10" && formatNumber(b.maxY) === "0", "y " + formatNumber(b.minY);
	const q = geometryBounds(parsePathData("M0 0 Q10 20 20 0"));
	assert formatNumber(q.maxY) === "10", "quad peak " + formatNumber(q.maxY);
	assert geometryBounds(parsePathData("")).empty, "empty";
}

test "numbers print the same on every backend" {
	assert formatNumber(1.0 / 3.0) === "0.3333";
	assert formatNumber(-0.00001) === "0";
	assert formatNumber(2.5) === "2.5";
	assert formatNumber(-12.25) === "-12.25";
	assert formatNumber(100) === "100";
	assert formatNumber(0.0001) === "0.0001";
}
