#ifndef NEON_MACOS_HARNESS_H
#define NEON_MACOS_HARNESS_H

#ifdef __cplusplus
extern "C" {
#endif

// Coordinates are window points from the content's top-left; colours are sRGB bytes.
int harnessIsCheck(void);
void harnessExpect(const char *name, int x, int y, int r, int g, int b);
void harnessExpectCount(const char *name, int x, int y, int width, int height, int r, int g, int b, int tolerance, int minCount, int maxCount);
int harnessSample(const char *title);
void harnessClick(const char *title, int x, int y);
void harnessPointer(const char *title, int kind, int x, int y);
void harnessWheel(const char *title, int x, int y, int lines);
int harnessPostKeys(const char *title, const char *keys);

#ifdef __cplusplus
}
#endif

#endif
