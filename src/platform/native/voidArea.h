#ifndef NEON_NATIVE_VOID_AREA_H
#define NEON_NATIVE_VOID_AREA_H

#include "bridge.h"

// A <Void>'s native view: Void draws into its layer (a CAMetalLayer on iOS) through viewCreate.
void *niVoidAreaCreate(void);
long long niVoidAreaLayer(void *view);

// One handler for every area view; the event it reports is read through niLastVoidArea*.
// Event 0 is a resize to a drawable size in pixels; 1..4 are touches began, moved, ended and
// cancelled, listing every touch on the view in pixels, with the ones this event changed.
void niSetVoidAreaHandler(msClosure handler);
void *niLastVoidAreaView(void);
int niLastVoidAreaEvent(void);
int niLastVoidAreaWidth(void);
int niLastVoidAreaHeight(void);
float niLastVoidAreaScale(void);
int niLastVoidAreaTouchCount(void);
long long niLastVoidAreaTouchId(int index);
float niLastVoidAreaTouchX(int index);
float niLastVoidAreaTouchY(int index);
int niLastVoidAreaTouchChanged(int index);

#endif
