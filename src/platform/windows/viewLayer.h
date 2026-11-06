#pragma once
#include <cmath>
#include <cstdint>
#include <vector>
#include "composition.h"
#include "layerCurve.h"

// A view's transform and opacity as the static writes set them, and the pixel frame its transform turns about.
// While a property is handed to DirectComposition its track is shown and a static write only updates the model,
// which releaseLayer shows, as Core Animation shows an animation over the layer's model value.
struct ViewLayer {
	float scaleX = 1, scaleY = 1, translateX = 0, translateY = 0, rotation = 0;
	float opacity = 1;
	bool transformed = false;
	bool opacityHanded = false, transformHanded = false;
	float pixelWidth = 0, pixelHeight = 0, dpiScale = 1;
};

inline void motionMatrix(float scaleX, float scaleY, float translateX, float translateY, float degrees, float m[6]) {
	float radians = degrees * 3.14159265358979f / 180.0f;
	float c = cosf(radians), s = sinf(radians);
	m[0] = scaleX * c;
	m[1] = scaleX * s;
	m[2] = -scaleY * s;
	m[3] = scaleY * c;
	m[4] = translateX;
	m[5] = translateY;
}

inline void showFrame(IVisual *visual, const ViewLayer &layer) {
	float g = layer.dpiScale, cx = layer.pixelWidth / 2, cy = layer.pixelHeight / 2;
	const float toCentredDips[6] = {1 / g, 0, 0, 1 / g, -cx / g, -cy / g};
	const float toPixels[6] = {g, 0, 0, g, cx, cy};
	visual->FramedTransform(toCentredDips, toPixels);
}

inline void frameOnce(IVisual *visual, ViewLayer &layer) {
	if (layer.transformed) return;
	layer.transformed = true;
	showFrame(visual, layer);
}

inline void showTransform(IVisual *visual, ViewLayer &layer) {
	if (layer.transformHanded) return;
	bool identity = layer.scaleX == 1 && layer.scaleY == 1 && layer.translateX == 0 && layer.translateY == 0 && layer.rotation == 0;
	if (identity && !layer.transformed) return;
	frameOnce(visual, layer);
	float m[6];
	motionMatrix(layer.scaleX, layer.scaleY, layer.translateX, layer.translateY, layer.rotation, m);
	visual->MotionTransform(m);
}

inline void placeLayer(IVisual *visual, ViewLayer &layer, float pixelWidth, float pixelHeight, float dpiScale) {
	bool moved = pixelWidth != layer.pixelWidth || pixelHeight != layer.pixelHeight || dpiScale != layer.dpiScale;
	layer.pixelWidth = pixelWidth;
	layer.pixelHeight = pixelHeight;
	layer.dpiScale = dpiScale;
	if (moved && layer.transformed) showFrame(visual, layer);
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
	if (!layer.opacityHanded) visual->Opacity(opacity);
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
	showTransform(visual, layer);
}

inline void handLayer(IVisual *visual, ViewLayer &layer, int32_t property, const double *keyTimes, int64_t keyCount,
	const double *values, double durationMs, double repeatCount, bool autoreverses, double startMs, double offsetMs,
	double speed, double lagMs) {
	if (property == 0) {
		std::vector<double> column(values, values + keyCount);
		visual->AnimatedOpacity(curveOf(periodOf(keyTimes, keyCount, column, durationMs, autoreverses),
			repeatCount, startMs, offsetMs, speed), lagMs);
		layer.opacityHanded = true;
		return;
	}
	Curve curves[6];
	transformCurves(keyTimes, keyCount, values, durationMs, repeatCount, autoreverses, startMs, offsetMs, speed,
		[](const double *at, float m[6]) { motionMatrix((float)at[0], (float)at[1], (float)at[2], (float)at[3], (float)at[4], m); },
		curves);
	frameOnce(visual, layer);
	visual->AnimatedTransform(curves, lagMs);
	layer.transformHanded = true;
}

inline void releaseLayer(IVisual *visual, ViewLayer &layer, int32_t property) {
	if (property == 0) {
		layer.opacityHanded = false;
		visual->Opacity(layer.opacity);
		return;
	}
	layer.transformHanded = false;
	showTransform(visual, layer);
}
