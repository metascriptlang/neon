#pragma once
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
const char *imageLoopStart(void);
const char *imageLoopPictureUri(void);
void imageLoopOnWake(void);
void imageLoopOnReport(void);
int32_t imageLoopFinish(void);
#ifdef __cplusplus
}
#endif
