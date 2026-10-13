#ifndef NEON_WINDOWS_HARNESS_H
#define NEON_WINDOWS_HARNESS_H

#ifdef __cplusplus
extern "C" {
#endif

void harnessStart(int logicalWidth, int logicalHeight);
void harnessExpect(const char *name, int x, int y, int r, int g, int b);
int harnessRun(void);

#ifdef __cplusplus
}
#endif

#endif
