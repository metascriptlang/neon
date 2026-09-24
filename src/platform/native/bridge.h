#ifndef NEON_NATIVE_BRIDGE_H
#define NEON_NATIVE_BRIDGE_H

#include <stdint.h>

#ifndef MS_CLOSURE_DEFINED
#define MS_CLOSURE_DEFINED
typedef struct {
	void *fn;
	void *env;
} msClosure;
#endif

// --- views ---
void *niViewCreate(void);
void  niViewSetTag(void *view, int32_t tag);
void *niTextCreate(void);
void  niAddChild(void *parent, void *child);
void  niRemoveFromParent(void *child);
void  niViewRelease(void *view);
void  niSetFrame(void *view, float x, float y, float w, float h);
void  niSetBackgroundColor(void *view, float r, float g, float b, float a);
void  niSetCornerRadius(void *view, float radius);
void  niSetOpacity(void *view, float opacity);

// --- text ---
void  niSetText(void *label, const char *s);
void  niSetTextColor(void *label, float r, float g, float b, float a);
void  niSetFont(void *label, float size, int bold);
void  niMeasureText(void *label, float maxWidth);
float niMeasuredW(void);
float niMeasuredH(void);

// --- events ---
// Every touch phase fires the one handler; the tag routes to the MS-side
// registry. The last phase's tag is readable from the () => void closure
// (msClosure carries no args).
void niSetTouchHandler(msClosure handler);
int  niLastTouchTag(void);
int  niLastTouchPhase(void); // 0 = down, 1 = up, 2 = press, 3 = cancel

// --- app lifecycle ---
void  niRegisterApp(msClosure mount);
void  niSetResizeHandler(msClosure handler);
void  niSetTeardownHandler(msClosure handler);
int   niRunApp(void);
void *niContainerView(void);
float niScreenWidth(void);
float niScreenHeight(void);

#endif
