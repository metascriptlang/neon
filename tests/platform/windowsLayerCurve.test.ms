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
extern function wlcBuildUnsizedTransform(
	keyTimes: Readonly<Span<float64>>,
	values: Readonly<Span<float64>>,
	durationMs: float64,
): void;
extern function wlcShownScaleX(seconds: float64): float64;
extern function wlcShownRotationDegrees(seconds: float64): float64;
extern function wlvReset(pixelWidth: float32, pixelHeight: float32, dpiScale: float32): void;
extern function wlvPlace(pixelWidth: float32, pixelHeight: float32, dpiScale: float32): void;
extern function wlvSetOpacity(opacity: float32): void;
extern function wlvSetTransform(scaleX: float32, scaleY: float32, translateX: float32, translateY: float32): void;
extern function wlvWrite(property: int32, values: Readonly<Span<float64>>): void;
extern function wlvHand(property: int32, keyTimes: Readonly<Span<float64>>, values: Readonly<Span<float64>>, durationMs: float64): void;
extern function wlvRelease(property: int32): void;
extern function wlvShownOpacity(seconds: float64): float64;
extern function wlvShownMatrix(element: int32, seconds: float64): float64;

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

function spin(degrees: float64): void {
	const keyTimes: float64[] = [0, 1];
	const values: float64[] = [1, 1, 0, 0, 0, 1, 1, 0, 0, degrees];
	wlcBuildUnsizedTransform(keyTimes, values, 1000);
}

test "a quarter turn between two keys keeps its scale through the turn" {
	spin(90);
	assert wlcShownScaleX(0.5) > 0.9998, wlcShownScaleX(0.5).toString();
	assert Math.abs(wlcShownRotationDegrees(0.5) - 45) < 0.01, wlcShownRotationDegrees(0.5).toString();
}

test "a whole turn between two keys turns through every angle instead of holding still" {
	spin(360);
	assert Math.abs(wlcShownRotationDegrees(0.25) - 90) < 0.01, wlcShownRotationDegrees(0.25).toString();
	assert Math.abs(Math.abs(wlcShownRotationDegrees(0.5)) - 180) < 0.01, wlcShownRotationDegrees(0.5).toString();
	assert wlcShownScaleX(0.6) > 0.9998, wlcShownScaleX(0.6).toString();
}

const OPACITY: int32 = 0;
const TRANSFORM: int32 = 1;

function handGrowAndSlide(): void {
	const keyTimes: float64[] = [0, 1];
	const end: float64[] = [2, 2, 100, 0, 0];
	wlvWrite(TRANSFORM, end);
	const values: float64[] = [1, 1, 0, 0, 0, 2, 2, 100, 0, 0];
	wlvHand(TRANSFORM, keyTimes, values, 1000);
}

function shownAt(seconds: float64): string {
	const parts: string[] = [];
	for (let i: int32 = 0; i < 6; i += 1) {
		parts.push(wlvShownMatrix(i, seconds).toString());
	}
	return parts.join(" ");
}

function shows(seconds: float64, m11: float64, dx: float64, dy: float64): boolean {
	return near(wlvShownMatrix(0, seconds), m11) && near(wlvShownMatrix(3, seconds), m11) &&
		near(wlvShownMatrix(4, seconds), dx) && near(wlvShownMatrix(5, seconds), dy);
}

test "a frame write during a handed transform keeps it running about the new centre" {
	wlvReset(100, 50, 1);
	handGrowAndSlide();
	wlvPlace(200, 80, 1);
	assert shows(0.5, 1.5, 100 + 50 - 100 * 1.5, 40 - 40 * 1.5), shownAt(0.5);
}

test "a DPI rescale during a handed transform keeps it running, its translation in the new scale" {
	wlvReset(100, 50, 1);
	handGrowAndSlide();
	wlvPlace(200, 100, 2);
	assert shows(0.5, 1.5, 100 + 50 * 2 - 100 * 1.5, 50 - 50 * 1.5), shownAt(0.5);
}

test "a static transform write during a handed transform waits for the track's release" {
	wlvReset(100, 50, 1);
	handGrowAndSlide();
	wlvSetTransform(1, 1, 10, 0);
	assert shows(0.5, 1.5, 50 + 50 - 50 * 1.5, 25 - 25 * 1.5), shownAt(0.5);
	wlvRelease(TRANSFORM);
	assert shows(0.5, 1, 10, 0), shownAt(0.5);
}

test "a static opacity write during a handed opacity track leaves it running, and shows on release" {
	wlvReset(100, 50, 1);
	const end: float64[] = [1];
	wlvWrite(OPACITY, end);
	const keyTimes: float64[] = [0, 1];
	const values: float64[] = [0, 1];
	wlvHand(OPACITY, keyTimes, values, 1000);
	wlvSetOpacity(0.3);
	assert near(wlvShownOpacity(0.5), 0.5), wlvShownOpacity(0.5).toString();
	wlvPlace(200, 80, 2);
	assert near(wlvShownOpacity(0.5), 0.5), wlvShownOpacity(0.5).toString();
	wlvRelease(OPACITY);
	assert Math.abs(wlvShownOpacity(0.5) - 0.3) < 1e-6, wlvShownOpacity(0.5).toString();
}
