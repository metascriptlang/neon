// Neon iOS host — UIKit bridge, first cut of the ios-host arc
// (~/metascript/.wt/ios-host.md). C ABI over UIKit: views cross as void*,
// colors as floats, text as const char*. Events cross the other way as
// msClosure — the exact shape void/src/sokol/bridge.h ships.
//
// Deliberate first-cut limits (see the card): views are created retained and
// never released (app-lifetime, like the Nim reference), rotation is not
// handled, and text measure is UILabel sizeThatFits, not a yoga measure func.
#ifndef NEON_IOS_BRIDGE_H
#define NEON_IOS_BRIDGE_H

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
// One touch-forwarding view class fires every phase; the tag routes to the
// MS-side registry. The last phase's tag is readable from the () => void
// closure (msClosure carries no args).
void niSetTouchHandler(msClosure handler);
int  niLastTouchTag(void);
int  niLastTouchPhase(void); // 0 = down, 1 = up, 2 = press, 3 = cancel

// --- app lifecycle ---
void  niRegisterApp(msClosure mount);
int   niRunApp(void);
void *niContainerView(void);
float niScreenWidth(void);
float niScreenHeight(void);

#endif
