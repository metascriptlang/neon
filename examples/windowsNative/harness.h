#ifndef NEON_WINDOWS_HARNESS_H
#define NEON_WINDOWS_HARNESS_H

#ifdef __cplusplus
extern "C" {
#endif

void harnessStart(int logicalWidth, int logicalHeight);
void harnessExpect(const char *name, int x, int y, int r, int g, int b);
void harnessLayout(const char *name, float width, float height);
void harnessExpectCentre(const char *name, const char *layout, int left, int top, int r, int g, int b);
void harnessExpectCount(const char *name, int x, int y, int width, int height, int r, int g, int b, int tolerance, int minCount, int maxCount);
void harnessExpectSize(const char *layout, const char *text, float fontSize, int bold, float maxWidth);
void harnessExpectSizeIn(const char *layout, const char *text, const char *family, float fontSize, int bold, float maxWidth);
int harnessRun(void);
int harnessIsCheck(void);
int harnessSample(const char *title);

#ifdef __cplusplus
}
#endif

#endif
