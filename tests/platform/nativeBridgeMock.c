#include "../../src/platform/native/bridge.h"
#include "../../src/platform/native/loop.h"
#include "nativeBridgeMock.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct MockView {
	struct MockView *parent;
	int released;
	int tag;
	char text[128];
	float size;
	int isScroll;
} MockView;

static msClosure s_mount;
static msClosure s_touch;
static msClosure s_resize;
static msClosure s_teardown;
static msClosure s_scroll;
static msClosure s_loop;
static MockView s_container;
static int g_scrollPhase;
static int g_lastTag = 0;
static int g_lastPhase = 0;
static int g_created = 0;
static int g_releaseCalls = 0;
static float g_measuredW = 0;
static float g_measuredH = 0;
static float g_screenW = 400;
static float g_screenH = 800;
static int g_scrollTag = 0;
static float g_scrollX = 0, g_scrollY = 0, g_scrollW = 0, g_scrollH = 0, g_scrollContentW = 0, g_scrollContentH = 0;
static int g_lastScrollTag = 0;
static float g_contentW = 0, g_contentH = 0;
static float g_scrolledX = -1, g_scrolledY = -1;
static int g_scrolledAnimated = -1;

static void call0(msClosure c) {
	if (!c.fn) return;
	if (c.env) ((void (*)(void *))c.fn)(c.env);
	else ((void (*)(void))c.fn)();
}

static MockView *live(void *view, const char *op) {
	MockView *v = (MockView *)view;
	if (v->released) {
		fprintf(stderr, "mock bridge: %s on a released view\n", op);
		abort();
	}
	return v;
}

static void *create(float size) {
	MockView *v = calloc(1, sizeof(MockView));
	v->size = size;
	g_created++;
	return v;
}

void *niViewCreate(void) { return create(0); }
void *niTextCreate(void) { return create(17); }
void niViewSetPressable(void *view) { live(view, "niViewSetPressable"); }
void niViewSetTag(void *view, int32_t tag) {
	MockView *v = live(view, "niViewSetTag");
	if (v->isScroll) {
		fprintf(stderr, "mock bridge: niViewSetTag on a scroll view installs a touch listener that takes its drags\n");
		abort();
	}
	v->tag = tag;
}

void *niScrollCreate(void) {
	MockView *v = create(0);
	v->isScroll = 1;
	return v;
}

void niScrollSetTag(void *view, int32_t tag) {
	live(view, "niScrollSetTag")->tag = tag;
	g_lastScrollTag = tag;
}

static int g_contentWrites = 0;

void niScrollSetContentSize(void *view, float w, float h) {
	live(view, "niScrollSetContentSize");
	g_contentW = w;
	g_contentH = h;
	g_contentWrites++;
}

void niScrollTo(void *view, float x, float y, int animated) {
	live(view, "niScrollTo");
	g_scrolledX = x;
	g_scrolledY = y;
	g_scrolledAnimated = animated;
}

void niScrollSetOption(void *view, const char *name, const char *value) {
	(void)name; (void)value;
	live(view, "niScrollSetOption");
}

void niSetScrollHandler(msClosure handler) { s_scroll = handler; }
int niLastScrollTag(void) { return g_scrollTag; }
int niLastScrollPhase(void) { return g_scrollPhase; }
float niLastScrollX(void) { return g_scrollX; }
float niLastScrollY(void) { return g_scrollY; }
float niLastScrollWidth(void) { return g_scrollW; }
float niLastScrollHeight(void) { return g_scrollH; }
float niLastScrollContentWidth(void) { return g_scrollContentW; }
float niLastScrollContentHeight(void) { return g_scrollContentH; }
void niAddChild(void *parent, void *child) { live(child, "niAddChild")->parent = live(parent, "niAddChild parent"); }
void niRemoveFromParent(void *child) { live(child, "niRemoveFromParent")->parent = NULL; }

void niViewRelease(void *view) {
	live(view, "niViewRelease")->released = 1;
	g_releaseCalls++;
}

static int g_scrollFrameWrites = 0;

void niSetFrame(void *view, float x, float y, float w, float h) {
	(void)x; (void)y; (void)w; (void)h;
	MockView *v = live(view, "niSetFrame");
	if (v->isScroll) g_scrollFrameWrites++;
}

void niSetBackgroundColor(void *view, float r, float g, float b, float a) {
	(void)r; (void)g; (void)b; (void)a;
	live(view, "niSetBackgroundColor");
}

void niSetCornerRadius(void *view, float radius) { (void)radius; live(view, "niSetCornerRadius"); }
void niSetOpacity(void *view, float opacity) { (void)opacity; live(view, "niSetOpacity"); }

void niSetText(void *label, const char *s) {
	MockView *v = live(label, "niSetText");
	snprintf(v->text, sizeof v->text, "%s", s ? s : "");
}

void niSetTextColor(void *label, float r, float g, float b, float a) {
	(void)r; (void)g; (void)b; (void)a;
	live(label, "niSetTextColor");
}

void niSetFont(void *label, float size, int bold) {
	(void)bold;
	live(label, "niSetFont")->size = size;
}

void niMeasureText(void *label, float maxWidth) {
	MockView *v = live(label, "niMeasureText");
	float w = (float)strlen(v->text) * v->size * 0.5f;
	g_measuredW = w < maxWidth ? w : maxWidth;
	g_measuredH = v->size + 4;
}

float niMeasuredW(void) { return g_measuredW; }
float niMeasuredH(void) { return g_measuredH; }

void niSetTouchHandler(msClosure handler) { s_touch = handler; }
int niLastTouchTag(void) { return g_lastTag; }
int niLastTouchPhase(void) { return g_lastPhase; }

void niRegisterApp(msClosure mount) { s_mount = mount; }
void niSetResizeHandler(msClosure handler) { s_resize = handler; }
void niSetTeardownHandler(msClosure handler) { s_teardown = handler; }
void niSetLoopHandler(msClosure handler) { s_loop = handler; }

int niRunApp(void) {
	call0(s_mount);
	return 0;
}

void *niContainerView(void) { return &s_container; }
float niScreenWidth(void) { return g_screenW; }
static int g_screenHeightReads = 0;
float niScreenHeight(void) {
	g_screenHeightReads++;
	return g_screenH;
}

int32_t nmViewsCreated(void) { return g_created; }
int32_t nmReleaseCalls(void) { return g_releaseCalls; }

void nmTouch(int32_t tag, int32_t phase) {
	g_lastTag = tag;
	g_lastPhase = phase;
	call0(s_touch);
}

void nmTeardown(void) { call0(s_teardown); }

int32_t nmLoop(void) {
	if (s_loop.fn) call0(s_loop);
	else niLoopRun();
	return niLoopNext();
}
void nmMount(void) { call0(s_mount); }

void nmResize(float width, float height) {
	g_screenW = width;
	g_screenH = height;
	call0(s_resize);
}

void nmScroll(int32_t tag, float x, float y, float width, float height, float contentWidth, float contentHeight) {
	g_scrollTag = tag;
	g_scrollPhase = 0;
	g_scrollX = x;
	g_scrollY = y;
	g_scrollW = width;
	g_scrollH = height;
	g_scrollContentW = contentWidth;
	g_scrollContentH = contentHeight;
	call0(s_scroll);
}

int32_t nmLastScrollTag(void) { return g_lastScrollTag; }
float nmContentWidth(void) { return g_contentW; }
float nmContentHeight(void) { return g_contentH; }
float nmScrolledX(void) { return g_scrolledX; }
float nmScrolledY(void) { return g_scrolledY; }
int32_t nmScrolledAnimated(void) { return g_scrolledAnimated; }
int32_t nmContentSizeWrites(void) { return g_contentWrites; }
int32_t nmScrollFrameWrites(void) { return g_scrollFrameWrites; }
int32_t nmScreenHeightReads(void) { return g_screenHeightReads; }

