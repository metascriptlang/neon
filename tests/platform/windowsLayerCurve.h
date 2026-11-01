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

#ifdef __cplusplus
}
#endif

#endif
