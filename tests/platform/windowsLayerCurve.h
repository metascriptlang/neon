#ifndef NEON_WINDOWS_LAYER_CURVE_PROBE_H
#define NEON_WINDOWS_LAYER_CURVE_PROBE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

void wlcBuild(const double *keyTimes, int64_t keyCount, const double *values, int64_t valueCount,
	double durationMs, double repeatCount, int32_t autoreverses, double startMs, double offsetMs, double speed);
int32_t wlcAccepted(void);
const char *wlcRefusal(void);
double wlcSample(double seconds);
void wlcBuildUnsizedTransform(const double *keyTimes, int64_t keyCount, const double *values, int64_t valueCount,
	double durationMs);
double wlcShownScaleX(double seconds);
double wlcShownRotationDegrees(double seconds);
void wlvReset(float pixelWidth, float pixelHeight, float dpiScale);
void wlvPlace(float pixelWidth, float pixelHeight, float dpiScale);
void wlvSetOpacity(float opacity);
void wlvSetTransform(float scaleX, float scaleY, float translateX, float translateY);
void wlvWrite(int32_t property, const double *values, int64_t count);
void wlvHand(int32_t property, const double *keyTimes, int64_t keyCount, const double *values, int64_t valueCount, double durationMs);
void wlvRelease(int32_t property);
double wlvShownOpacity(double seconds);
double wlvShownMatrix(int32_t element, double seconds);

#ifdef __cplusplus
}
#endif

#endif
