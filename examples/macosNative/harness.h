#ifndef NEON_MACOS_HARNESS_H
#define NEON_MACOS_HARNESS_H

#ifdef __cplusplus
extern "C" {
#endif

// Coordinates are window points from the content's top-left; colours are sRGB bytes.
int harnessIsCheck(void);
void harnessExpect(const char *name, int x, int y, int r, int g, int b);
void harnessExpectCount(const char *name, int x, int y, int width, int height, int r, int g, int b, int tolerance, int minCount, int maxCount);
void harnessLayout(const char *name, float width, float height);
void harnessExpectCentre(const char *name, const char *layout, int left, int top, int r, int g, int b);
// The layout's size against the same text measured here by an NSLayoutManager, allowing one point above: yoga lays out on whole points.
void harnessExpectSize(const char *layout, const char *text, float fontSize, int bold, float maxWidth);
int harnessSample(const char *title);
void harnessClick(const char *title, int x, int y);
void harnessPointer(const char *title, int kind, int x, int y);
// A pixel-unit wheel event of the given points; negative moves the content up, as a scroll down does.
void harnessWheel(const char *title, int x, int y, int points);
// "\n" is Return, "\b" Delete and "\x1b" Escape.
int harnessPostKeys(const char *title, const char *keys);
// The first responder's NSTextInputClient, as an input method drives it: marked text, then a commit replacing it.
void harnessCompose(const char *title, const char *marked);
void harnessCommit(const char *title, const char *text);
int harnessFocusedText(const char *title);
// niMeasureInWindow on the view whose accessibilityLabel is label: "x,y,w,h" on success, else its return code.
const char *harnessMeasure(const char *title, const char *label);
// niMeasureInWindow on a NeonView that was never attached.
int harnessMeasureDetached(void);
void harnessHide(const char *title, const char *label);
// Each NSSwitch in the window in view-tree order, 1 for on and 0 for off.
const char *harnessSwitchStates(const char *title);
// The first WKWebView's page, snapshotted by WebKit (asynchronous); then a pixel in web view points as 0xRRGGBB,
// or -1 before the snapshot arrives.
void harnessSnapshotWeb(const char *title);
int harnessWebPixel(int x, int y);

#ifdef __cplusplus
}
#endif

#endif
