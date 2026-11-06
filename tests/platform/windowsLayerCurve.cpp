#define _USE_MATH_DEFINES
#include <cmath>
#include <string>
#include "../../src/platform/windows/viewLayer.h"
#include "windowsLayerCurve.h"

static Curve g_curve;
static std::string g_refusal;

void wlcBuild(const double *keyTimes, int64_t keyCount, const double *values, int64_t valueCount,
	double durationMs, double repeatCount, int32_t autoreverses, double startMs, double offsetMs, double speed) {
	std::vector<double> column(values, values + valueCount);
	g_curve = curveOf(periodOf(keyTimes, keyCount, column, durationMs, autoreverses != 0), repeatCount, startMs, offsetMs, speed);
}

int32_t wlcAccepted(void) {
	double previous = -INFINITY;
	for (const CurveSegment &segment : g_curve.segments) {
		if (!std::isfinite(segment.begin) || !std::isfinite(segment.value) || !std::isfinite(segment.slope)) {
			g_refusal = "AddCubic: a coefficient or offset is not finite";
			return 0;
		}
		if (segment.begin <= previous) {
			g_refusal = "AddCubic: beginOffset " + std::to_string(segment.begin) + " is not after " + std::to_string(previous);
			return 0;
		}
		previous = segment.begin;
	}
	if (g_curve.segments.empty()) {
		g_refusal = g_curve.repeats ? "AddRepeat: the first segment" : "End: the first segment";
		return 0;
	}
	double last = g_curve.repeats ? g_curve.repeatBegin : g_curve.endSeconds;
	if (!std::isfinite(last) || last <= previous) {
		g_refusal = std::string(g_curve.repeats ? "AddRepeat" : "End") + ": offset " + std::to_string(last) +
			" is not after the last segment's " + std::to_string(previous);
		return 0;
	}
	if (g_curve.repeats && !(g_curve.repeatSeconds > 0 && std::isfinite(g_curve.repeatSeconds))) {
		g_refusal = "AddRepeat: durationToRepeat is not a positive finite duration";
		return 0;
	}
	g_refusal.clear();
	return 1;
}

const char *wlcRefusal(void) { return g_refusal.c_str(); }

static double sampled(const Curve &curve, double seconds);

double wlcSample(double seconds) { return sampled(g_curve, seconds); }

static Curve g_matrix[6];

void wlcBuildUnsizedTransform(const double *keyTimes, int64_t keyCount, const double *values, int64_t valueCount,
	double durationMs) {
	(void)valueCount;
	transformCurves(keyTimes, keyCount, values, durationMs, 1, false, 0, 0, 1,
		[](const double *at, float m[6]) {
			double radians = at[4] * M_PI / 180.0;
			m[0] = (float)(at[0] * std::cos(radians));
			m[1] = (float)(at[0] * std::sin(radians));
			m[2] = (float)(-at[1] * std::sin(radians));
			m[3] = (float)(at[1] * std::cos(radians));
			m[4] = (float)at[2];
			m[5] = (float)at[3];
		},
		g_matrix);
}

double wlcShownScaleX(double seconds) { return std::hypot(sampled(g_matrix[0], seconds), sampled(g_matrix[1], seconds)); }

double wlcShownRotationDegrees(double seconds) {
	return std::atan2(sampled(g_matrix[1], seconds), sampled(g_matrix[0], seconds)) * 180.0 / M_PI;
}

static double sampled(const Curve &curve, double seconds) {
	if (curve.repeats && seconds >= curve.repeatBegin) {
		seconds = curve.repeatBegin - curve.repeatSeconds + std::fmod(seconds - curve.repeatBegin, curve.repeatSeconds);
	} else if (!curve.repeats && seconds >= curve.endSeconds) {
		return curve.endValue;
	}
	const CurveSegment *at = nullptr;
	for (const CurveSegment &segment : curve.segments) {
		if (segment.begin <= seconds) at = &segment;
	}
	if (!at) return NAN;
	return at->value + at->slope * (seconds - at->begin);
}

// DirectComposition's rule for one property: a static set replaces the animation that drove it.
struct MockVisual : IVisual {
	float before[6] = {1, 0, 0, 1, 0, 0}, motion[6] = {1, 0, 0, 1, 0, 0}, after[6] = {1, 0, 0, 1, 0, 0};
	bool motionAnimated = false;
	Curve motionCurves[6];
	float opacity = 1;
	bool opacityAnimated = false;
	Curve opacityCurve;

	void InsertAt(IVisual *, int32_t) override {}
	void Remove(IVisual *) override {}
	void Size(float, float) override {}
	void Offset(float, float) override {}
	void CornerRadius(float) override {}
	void ClipsChildren(bool) override {}
	void Brush(Color) override {}
	void Content(IDrawingSurface *) override {}
	void Opacity(float value) override {
		opacity = value;
		opacityAnimated = false;
	}
	void TransformMatrix(const float m[6]) override {
		const float identity[6] = {1, 0, 0, 1, 0, 0};
		FramedTransform(identity, identity);
		MotionTransform(m);
	}
	void FramedTransform(const float b[6], const float a[6]) override {
		for (int i = 0; i < 6; i++) {
			before[i] = b[i];
			after[i] = a[i];
		}
	}
	void MotionTransform(const float m[6]) override {
		for (int i = 0; i < 6; i++) motion[i] = m[i];
		motionAnimated = false;
	}
	void AnimatedOpacity(const Curve &curve, double lagMs) override {
		(void)lagMs;
		opacityCurve = curve;
		opacityAnimated = true;
	}
	void AnimatedTransform(const Curve curves[6], double lagMs) override {
		(void)lagMs;
		for (int i = 0; i < 6; i++) motionCurves[i] = curves[i];
		motionAnimated = true;
	}

	static void product(const double a[6], const double b[6], double out[6]) {
		double m[6] = {a[0] * b[0] + a[1] * b[2], a[0] * b[1] + a[1] * b[3], a[2] * b[0] + a[3] * b[2],
			a[2] * b[1] + a[3] * b[3], a[4] * b[0] + a[5] * b[2] + b[4], a[4] * b[1] + a[5] * b[3] + b[5]};
		for (int i = 0; i < 6; i++) out[i] = m[i];
	}

	double shownMatrix(int element, double seconds) const {
		double b[6], m[6], a[6], shown[6];
		for (int i = 0; i < 6; i++) {
			b[i] = before[i];
			m[i] = motionAnimated ? sampled(motionCurves[i], seconds) : motion[i];
			a[i] = after[i];
		}
		product(b, m, shown);
		product(shown, a, shown);
		return shown[element];
	}
};

static MockVisual g_visual;
static ViewLayer g_layer;

void wlvReset(float pixelWidth, float pixelHeight, float dpiScale) {
	g_visual = MockVisual();
	g_layer = ViewLayer();
	placeLayer(&g_visual, g_layer, pixelWidth, pixelHeight, dpiScale);
}

void wlvPlace(float pixelWidth, float pixelHeight, float dpiScale) { placeLayer(&g_visual, g_layer, pixelWidth, pixelHeight, dpiScale); }

void wlvSetOpacity(float opacity) { setLayerOpacity(&g_visual, g_layer, opacity); }

void wlvSetTransform(float scaleX, float scaleY, float translateX, float translateY) {
	setLayerTransform(&g_visual, g_layer, scaleX, scaleY, translateX, translateY);
}

void wlvWrite(int32_t property, const double *values, int64_t count) {
	(void)count;
	writeLayer(&g_visual, g_layer, property, values);
}

void wlvHand(int32_t property, const double *keyTimes, int64_t keyCount, const double *values, int64_t valueCount, double durationMs) {
	(void)valueCount;
	handLayer(&g_visual, g_layer, property, keyTimes, keyCount, values, durationMs, 1, false, 0, 0, 1, 0);
}

void wlvRelease(int32_t property) { releaseLayer(&g_visual, g_layer, property); }

double wlvShownOpacity(double seconds) {
	return g_visual.opacityAnimated ? sampled(g_visual.opacityCurve, seconds) : g_visual.opacity;
}

double wlvShownMatrix(int32_t element, double seconds) { return g_visual.shownMatrix(element, seconds); }
