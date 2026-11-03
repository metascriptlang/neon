#define _USE_MATH_DEFINES
#include <cmath>
#include <string>
#include "../../src/platform/windows/layerCurve.h"
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
