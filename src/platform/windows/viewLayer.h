#pragma once
#include <cmath>
#include <cstdint>
#include <vector>
#include "composition.h"
#include "layerCurve.h"

// A view's transform and opacity as the static writes set them, and the pixel frame its transform turns about.
struct ViewLayer {
	float scaleX = 1, scaleY = 1, translateX = 0, translateY = 0, rotation = 0;
	float opacity = 1;
	bool transformed = false;
	float pixelWidth = 0, pixelHeight = 0, dpiScale = 1;
};

inline void centredMatrix(const ViewLayer &layer, float scaleX, float scaleY, float translateX, float translateY, float degrees, float m[6]) {
	float radians = degrees * 3.14159265358979f / 180.0f;
	float c = cosf(radians), s = sinf(radians);
	float m11 = scaleX * c, m12 = scaleX * s, m21 = -scaleY * s, m22 = scaleY * c;
	float cx = layer.pixelWidth / 2, cy = layer.pixelHeight / 2;
	m[0] = m11;
	m[1] = m12;
	m[2] = m21;
	m[3] = m22;
	m[4] = cx + translateX * layer.dpiScale - (cx * m11 + cy * m21);
	m[5] = cy + translateY * layer.dpiScale - (cx * m12 + cy * m22);
}

inline void showTransform(IVisual *visual, ViewLayer &layer) {
	bool identity = layer.scaleX == 1 && layer.scaleY == 1 && layer.translateX == 0 && layer.translateY == 0 && layer.rotation == 0;
	if (identity && !layer.transformed) return;
	layer.transformed = !identity;
	float m[6];
	centredMatrix(layer, layer.scaleX, layer.scaleY, layer.translateX, layer.translateY, layer.rotation, m);
	visual->TransformMatrix(m);
}

inline void placeLayer(IVisual *visual, ViewLayer &layer, float pixelWidth, float pixelHeight, float dpiScale) {
	layer.pixelWidth = pixelWidth;
	layer.pixelHeight = pixelHeight;
	layer.dpiScale = dpiScale;
	showTransform(visual, layer);
}

inline void setLayerTransform(IVisual *visual, ViewLayer &layer, float scaleX, float scaleY, float translateX, float translateY) {
	layer.scaleX = scaleX;
	layer.scaleY = scaleY;
	layer.translateX = translateX;
	layer.translateY = translateY;
	showTransform(visual, layer);
}

inline void setLayerRotation(IVisual *visual, ViewLayer &layer, float degrees) {
	layer.rotation = degrees;
	showTransform(visual, layer);
}

inline void setLayerOpacity(IVisual *visual, ViewLayer &layer, float opacity) {
	layer.opacity = opacity;
	visual->Opacity(opacity);
}

// property 0 is opacity (one value), 1 the transform (scaleX, scaleY, translateX, translateY, rotation in degrees).
inline void writeLayer(IVisual *visual, ViewLayer &layer, int32_t property, const double *values) {
	if (property == 0) {
		setLayerOpacity(visual, layer, (float)values[0]);
		return;
	}
	layer.scaleX = (float)values[0];
	layer.scaleY = (float)values[1];
	layer.translateX = (float)values[2];
	layer.translateY = (float)values[3];
	layer.rotation = (float)values[4];
	layer.transformed = true;
	showTransform(visual, layer);
}

inline void handLayer(IVisual *visual, ViewLayer &layer, int32_t property, const double *keyTimes, int64_t keyCount,
	const double *values, double durationMs, double repeatCount, bool autoreverses, double startMs, double offsetMs,
	double speed, double lagMs) {
	if (property == 0) {
		std::vector<double> column(values, values + keyCount);
		visual->AnimatedOpacity(curveOf(periodOf(keyTimes, keyCount, column, durationMs, autoreverses),
			repeatCount, startMs, offsetMs, speed), lagMs);
		return;
	}
	Curve curves[6];
	transformCurves(keyTimes, keyCount, values, durationMs, repeatCount, autoreverses, startMs, offsetMs, speed,
		[&layer](const double *at, float m[6]) {
			centredMatrix(layer, (float)at[0], (float)at[1], (float)at[2], (float)at[3], (float)at[4], m);
		},
		curves);
	visual->AnimatedTransform(curves, lagMs);
}

inline void releaseLayer(IVisual *visual, ViewLayer &layer, int32_t property) {
	if (property == 0) {
		visual->Opacity(layer.opacity);
		return;
	}
	float m[6];
	centredMatrix(layer, layer.scaleX, layer.scaleY, layer.translateX, layer.translateY, layer.rotation, m);
	visual->TransformMatrix(m);
}
