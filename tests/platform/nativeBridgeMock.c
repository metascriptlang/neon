#include "../../src/platform/native/bridge.h"
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
} MockView;

static msClosure s_mount;
static msClosure s_touch;
static msClosure s_resize;
static msClosure s_teardown;
static MockView s_container;
static int g_lastTag = 0;
static int g_lastPhase = 0;
static int g_created = 0;
static int g_releaseCalls = 0;
static float g_measuredW = 0;
static float g_measuredH = 0;

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
void niViewSetTag(void *view, int32_t tag) { live(view, "niViewSetTag")->tag = tag; }
void niAddChild(void *parent, void *child) { live(child, "niAddChild")->parent = live(parent, "niAddChild parent"); }
void niRemoveFromParent(void *child) { live(child, "niRemoveFromParent")->parent = NULL; }

void niViewRelease(void *view) {
	live(view, "niViewRelease")->released = 1;
	g_releaseCalls++;
}

void niSetFrame(void *view, float x, float y, float w, float h) {
	(void)x; (void)y; (void)w; (void)h;
	live(view, "niSetFrame");
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

int niRunApp(void) {
	call0(s_mount);
	return 0;
}

void *niContainerView(void) { return &s_container; }
float niScreenWidth(void) { return 400; }
float niScreenHeight(void) { return 800; }

int32_t nmViewsCreated(void) { return g_created; }
int32_t nmReleaseCalls(void) { return g_releaseCalls; }

void nmTouch(int32_t tag, int32_t phase) {
	g_lastTag = tag;
	g_lastPhase = phase;
	call0(s_touch);
}

void nmTeardown(void) { call0(s_teardown); }
void nmMount(void) { call0(s_mount); }
