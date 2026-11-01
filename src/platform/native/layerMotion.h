#ifndef NEON_NATIVE_LAYER_MOTION_H
#define NEON_NATIVE_LAYER_MOTION_H

#include <stdint.h>

// A view's compositor layer, for a bridge whose platform runs animations off the app thread
// (src/platform/native/layerMotion.ms). Property 0 is opacity, one value per key; property 1 is
// the transform, five values per key: scaleX, scaleY, translateX, translateY, rotation in degrees,
// applied as the centred matrix niSetTransform applies. Component 0 is opacity, 1 to 5 those five.

// Sets the model value with no implicit animation.
void   niLayerWrite(void *view, int32_t property, const double *values, int64_t count);
double niLayerRead(void *view, int32_t component);
// Adds the property's one animation, replacing an earlier one: keyTimes in [0, 1] of durationMs,
// linear between keys, held before its start. Its active local time is offsetMs startMs after the
// call and advances at speed; it is removed when it ends and leaves the model as it is.
void   niLayerAnimate(void *view, int32_t property, const double *keyTimes, int64_t keyCount,
	const double *values, int64_t valueCount, double durationMs, double repeatCount,
	int32_t autoreverses, double startMs, double offsetMs, double speed);
void   niLayerRemove(void *view, int32_t property);
// What the compositor shows now: the model while no animation runs.
double niLayerPresented(void *view, int32_t component);

#endif
