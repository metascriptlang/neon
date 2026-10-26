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
int harnessShot(const char *title, const char *name, int x, int y, int width, int height);
int harnessCompareShots(const char *first, const char *second, int wantSame, int minDifferent);
void harnessWheel(const char *title, int x, int y, int delta);
void harnessClick(const char *title, int x, int y);
void harnessHover(const char *title, int x, int y);
void harnessDrag(const char *title, int fromX, int fromY, int toX, int toY, int steps);
const char *harnessFileUri(const char *relativePath);
int harnessPostKeys(const char *title, const char *keys);
// UI Automation as a client sees the window. Forward routes the window's WM_GETOBJECT to niwGetObject (Ion's window proc will);
// Start looks an element up by Name on a worker thread and then acts on it (0 read only, 1 Invoke, 2 Toggle); poll Done from a timer
// so the window keeps pumping, then read the result: Number fields found, controlType, enabled, focusable, control, width, height,
// hasInvoke, hasToggle, toggleState, hasRange, rangeMin, rangeMax, rangeNow, hasExpand, expandState, actionResult (-1000 when absent);
// Text fields name, helpText, automationId.
void harnessAutomationForward(const char *title);
void harnessAutomationStart(const char *title, const char *name, int action);
int harnessAutomationDone(void);
int harnessAutomationNumber(const char *field);
const char *harnessAutomationText(const char *field);

#ifdef __cplusplus
}
#endif

#endif
