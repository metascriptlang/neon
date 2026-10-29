import { Rgba, parseColor } from "../../../src/components/svg/color";

function rgbaOf(text: string): Rgba {
	const r = parseColor(text);
	if (!r.ok) { throw new Error(text + " does not parse"); }
	return r.value;
}

test "hsl converts by the CSS Color 4 algorithm" {
	const red = rgbaOf("hsl(0, 100%, 50%)");
	assert red.r === 255 && red.g === 0 && red.b === 0 && red.a === 1.0, "hsl red";
	const blue = rgbaOf("hsl(240,100%,50%)");
	assert blue.r === 0 && blue.g === 0 && blue.b === 255, "hsl blue";
}

test "hsla carries alpha and rounds channels like rgb()" {
	const c = rgbaOf("hsla(120,100%,25%,0.5)");
	assert c.r === 0 && c.g === 128 && c.b === 0 && c.a === 0.5, "dark green at half alpha";
}

test "hsl wraps the hue and clamps saturation and lightness" {
	const wrapped = rgbaOf("hsl(-120deg, 100%, 50%)");
	assert wrapped.r === 0 && wrapped.g === 0 && wrapped.b === 255, "-120 wraps to 240";
	const over = rgbaOf("hsl(0, 150%, 50%)");
	assert over.r === 255 && over.g === 0 && over.b === 0, "saturation clamps to 100%";
}

test "a malformed hsl is refused" {
	assert !parseColor("hsl(0, 100, 50%)").ok, "saturation needs a percent sign";
	assert !parseColor("hsl(abc, 100%, 50%)").ok, "hue must be a number";
	assert !parseColor("hsl(0, 100%)").ok, "too few arguments";
}
