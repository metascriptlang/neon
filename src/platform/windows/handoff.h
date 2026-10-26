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

#define NIW_KEY_RELEASE 0
#define NIW_KEY_PRESS 1
#define NIW_KEY_REPEAT 2

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
void niwKey(int action, int ionScancode, int ctrl, const char *text);
void niwText(const char *text);
void niwPreedit(const char *text, int cursor);
void niwFocus(int focused);
int niwIonCursor(void);
int niwFocusedCaret(void);
int niwCaretPixelX(void);
int niwCaretPixelY(void);
int niwCaretPixelW(void);
int niwCaretPixelH(void);
// WM_GETOBJECT for the window the scene is attached to: returns 1 with the LRESULT in *result when Neon answers it
// (a UI Automation root object), 0 to leave it to the window proc. niwDisconnectAutomation drops the provider when the window closes.
int niwGetObject(void *hwnd, unsigned long long wParam, long long lParam, long long *result);
void niwDisconnectAutomation(void *hwnd);
int niwStoredAccessibility(const char *name, const char *value);
// DirectWrite text layouts built since the process began, so a check can see that a colour change built none.
int niwLayoutsBuilt(void);
void niwShutdown(void);

#ifdef __cplusplus
}
#endif

#endif
