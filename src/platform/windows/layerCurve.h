#pragma once
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <vector>
#include "composition.h"

// One period of the track in active milliseconds: the keys forward, then back again when it autoreverses.
struct Period {
	std::vector<double> times;
	std::vector<double> values;
	double length = 0;

	double at(double within) const {
		size_t right = 1;
		while (right + 1 < times.size() && times[right] < within) right++;
		double span = times[right] - times[right - 1];
		double t = span > 0 ? (within - times[right - 1]) / span : 1;
		t = t < 0 ? 0 : t > 1 ? 1 : t;
		return values[right - 1] + (values[right] - values[right - 1]) * t;
	}

	double nextKey(double within) const {
		for (double time : times) {
			if (time > within) return time;
		}
		return length;
	}
};

inline Period periodOf(const double *keyTimes, int64_t keyCount, const std::vector<double> &column, double durationMs, bool autoreverses) {
	Period p;
	for (int64_t i = 0; i < keyCount; i++) {
		p.times.push_back(keyTimes[i] * durationMs);
		p.values.push_back(column[(size_t)i]);
	}
	if (autoreverses) {
		for (int64_t i = keyCount - 2; i >= 0; i--) {
			p.times.push_back(2 * durationMs - keyTimes[i] * durationMs);
			p.values.push_back(column[(size_t)i]);
		}
	}
	p.length = autoreverses ? 2 * durationMs : durationMs;
	return p;
}

inline Curve curveOf(const Period &p, double repeatCount, double startMs, double offsetMs, double speed) {
	Curve curve;
	auto wall = [&](double active) { return (startMs + (active - offsetMs) / speed) / 1000.0; };
	bool forever = !std::isfinite(repeatCount);
	double finalActive = forever ? 0 : repeatCount * p.length;
	double from = offsetMs;
	double end;
	if (forever) {
		double boundary = std::ceil(from / p.length) * p.length;
		if (boundary <= from) boundary += p.length;
		end = boundary + p.length;
	} else {
		end = finalActive;
	}
	if (startMs > 0) {
		double within = from - std::floor(from / p.length) * p.length;
		curve.segments.push_back({0.0, (float)p.at(within), 0.0f});
	}
	double a = from;
	while (a < end) {
		double base = std::floor(a / p.length) * p.length;
		double within = a - base;
		double b = std::min(base + p.nextKey(within), end);
		if (b <= a) b = std::min(base + p.length, end);
		double va = p.at(within), vb = p.at(b - base);
		double slopePerSecond = (vb - va) / (b - a) * speed * 1000.0;
		curve.segments.push_back({wall(a), (float)va, (float)slopePerSecond});
		a = b;
	}
	if (forever) {
		curve.repeats = true;
		curve.repeatBegin = wall(end);
		curve.repeatSeconds = p.length / speed / 1000.0;
	} else {
		double base = std::floor(end / p.length) * p.length;
		if (base == end && end > 0) base -= p.length;
		curve.endSeconds = wall(end);
		curve.endValue = (float)p.at(end - base);
	}
	return curve;
}

// The six matrix elements of a transform track, from keys of five values (scaleX, scaleY, translateX,
// translateY, rotation in degrees) that matrixOf turns into m11, m12, m21, m22, dx, dy.
constexpr double kMaxRotationStepDegrees = 2.0;

template <typename MatrixOf>
inline void transformCurves(const double *keyTimes, int64_t keyCount, const double *values, double durationMs,
	double repeatCount, bool autoreverses, double startMs, double offsetMs, double speed, MatrixOf matrixOf, Curve curves[6]) {
	std::vector<double> times, tuples;
	for (int64_t i = 0; i < keyCount; i++) {
		const double *at = values + i * 5;
		if (i > 0 && keyTimes[i] > keyTimes[i - 1]) {
			const double *before = at - 5;
			int steps = (int)std::ceil(std::fabs(at[4] - before[4]) / kMaxRotationStepDegrees);
			for (int step = 1; step < steps; step++) {
				double f = (double)step / steps;
				times.push_back(keyTimes[i - 1] + (keyTimes[i] - keyTimes[i - 1]) * f);
				for (int c = 0; c < 5; c++) tuples.push_back(before[c] + (at[c] - before[c]) * f);
			}
		}
		times.push_back(keyTimes[i]);
		tuples.insert(tuples.end(), at, at + 5);
	}
	std::vector<double> columns[6];
	for (size_t i = 0; i < times.size(); i++) {
		float m[6];
		matrixOf(tuples.data() + i * 5, m);
		for (int k = 0; k < 6; k++) columns[k].push_back(m[k]);
	}
	for (int k = 0; k < 6; k++) {
		curves[k] = curveOf(periodOf(times.data(), (int64_t)times.size(), columns[k], durationMs, autoreverses),
			repeatCount, startMs, offsetMs, speed);
	}
}
