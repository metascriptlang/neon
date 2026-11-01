#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
void motionSampleScreenLater(const char *title, int32_t clientX, int32_t clientY, double firstMs, double secondMs);
int32_t motionSamplesReady(void);
int32_t motionSampledBlue(int32_t index);
double motionSampledAtMs(int32_t index);
#ifdef __cplusplus
}
#endif
