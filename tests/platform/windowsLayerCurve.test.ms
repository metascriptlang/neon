@include("./windowsLayerCurve.h");
@compile("./windowsLayerCurve.cpp");

extern function wlcBuild(
	keyTimes: Readonly<Span<float64>>,
	values: Readonly<Span<float64>>,
	durationMs: float64,
	repeatCount: float64,
	autoreverses: int32,
	startMs: float64,
	offsetMs: float64,
	speed: float64,
): void;
extern function wlcAccepted(): int32;
extern function wlcRefusal(): cstring;
extern function wlcSample(seconds: float64): float64;

function near(a: float64, b: float64): boolean { return Math.abs(a - b) < 1e-4; }

function build(repeatCount: float64, autoreverses: boolean, startMs: float64, offsetMs: float64): void {
	const keyTimes: float64[] = [0, 0.5, 1];
	const values: float64[] = [0, 0.5, 1];
	wlcBuild(keyTimes, values, 1000, repeatCount, autoreverses ? 1 : 0, startMs, offsetMs, 1);
}

function refusal(): string {
	return wlcAccepted() === 1 ? "" : String(wlcRefusal());
}

test "a forever repeat hands DirectComposition a repeat after its last segment that replays one whole period" {
	build(Infinity, false, 0, 250);
	assert refusal() === "", `${refusal()}`;
	assert near(wlcSample(0), 0.25), wlcSample(0).toString();
	assert near(wlcSample(0.5), 0.75), wlcSample(0.5).toString();
	assert near(wlcSample(1.5), 0.75), wlcSample(1.5).toString();
	assert near(wlcSample(3.6), 0.85), wlcSample(3.6).toString();
}

test "a forever autoreversing repeat plays forward then back in every later period" {
	build(Infinity, true, 0, 0);
	assert refusal() === "", `${refusal()}`;
	assert near(wlcSample(0.25), 0.25) && near(wlcSample(1.25), 0.75), wlcSample(1.25).toString();
	assert near(wlcSample(4.5), 0.5) && near(wlcSample(5.75), 0.25), wlcSample(5.75).toString();
}

test "a start in the past samples into the curve instead of an offset before its beginning" {
	build(1, false, -200, 0);
	assert refusal() === "", `${refusal()}`;
	assert near(wlcSample(0), 0.2), wlcSample(0).toString();
	assert near(wlcSample(0.5), 0.7), wlcSample(0.5).toString();
	assert near(wlcSample(0.9), 1), wlcSample(0.9).toString();
}

test "a delayed finite run holds its first value, then ends on its last" {
	build(2, false, 300, 0);
	assert refusal() === "", `${refusal()}`;
	assert near(wlcSample(0.1), 0) && near(wlcSample(0.8), 0.5), wlcSample(0.8).toString();
	assert near(wlcSample(1.8), 0.5) && near(wlcSample(5), 1), wlcSample(5).toString();
}
