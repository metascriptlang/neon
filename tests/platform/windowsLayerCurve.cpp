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

double wlcSample(double seconds) {
	if (g_curve.repeats && seconds >= g_curve.repeatBegin) {
		seconds = g_curve.repeatBegin - g_curve.repeatSeconds + std::fmod(seconds - g_curve.repeatBegin, g_curve.repeatSeconds);
	} else if (!g_curve.repeats && seconds >= g_curve.endSeconds) {
		return g_curve.endValue;
	}
	const CurveSegment *at = nullptr;
	for (const CurveSegment &segment : g_curve.segments) {
		if (segment.begin <= seconds) at = &segment;
	}
	if (!at) return NAN;
	return at->value + at->slope * (seconds - at->begin);
}
