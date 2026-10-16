#ifndef NEON_WINDOWS_HANDOFF_H
#define NEON_WINDOWS_HANDOFF_H

#ifndef MS_CLOSURE_DEFINED
#define MS_CLOSURE_DEFINED
typedef struct {
	void *fn;
	void *env;
} msClosure;
#endif

#define NIW_POINTER_DOWN 0
#define NIW_POINTER_UP 1
#define NIW_POINTER_MOVE 2
#define NIW_POINTER_CANCEL 3

#ifdef __cplusplus
extern "C" {
#endif

void niwAttach(void *dcompDevice2, void *parentVisual2, float dpi, float logicalWidth, float logicalHeight);
int niwPump(void);
void niwFrame(void);
void niwResize(float dpi, float logicalWidth, float logicalHeight);
void niwPointer(int kind, float pixelX, float pixelY);
// Wheel notches as WM_MOUSEWHEEL / WM_MOUSEHWHEEL report them over WHEEL_DELTA: positive is away from the user, or right.
void niwWheel(float pixelX, float pixelY, float notchesX, float notchesY);
void niwSetFrameRequester(msClosure requester);
int niwStoredAccessibility(const char *name, const char *value);
// DirectWrite text layouts built since the process began, so a check can see that a colour change built none.
int niwLayoutsBuilt(void);
void niwShutdown(void);

#ifdef __cplusplus
}
#endif

#endif
