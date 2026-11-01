#include <stdint.h>
void motionSampleLater(void *view, double firstMs, double secondMs);
int32_t motionSamplesReady(void);
double motionSampledOpacity(int32_t index);
double motionSampledAtMs(int32_t index);
void motionLayerClock(void *view, double ms);
void motionCommit(void);
void motionDetach(void *view);
void motionReattach(void *view);
int32_t motionHasAnimation(void *view, int32_t property);
