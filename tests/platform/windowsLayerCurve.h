#ifndef NEON_WINDOWS_LAYER_CURVE_PROBE_H
#define NEON_WINDOWS_LAYER_CURVE_PROBE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Builds the opacity curve the Windows bridge hands DirectComposition for these niLayerAnimate arguments.
void wlcBuild(const double *keyTimes, int64_t keyCount, const double *values, int64_t valueCount,
	double durationMs, double repeatCount, int32_t autoreverses, double startMs, double offsetMs, double speed);
// 1 when IDCompositionAnimation would accept the curve's segments in order, else 0 with wlcRefusal naming why.
int32_t wlcAccepted(void);
const char *wlcRefusal(void);
// The curve's value at this many seconds after it is applied, as DirectComposition samples it.
double wlcSample(double seconds);

#ifdef __cplusplus
}
#endif

#endif
