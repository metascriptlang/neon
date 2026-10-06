#include "../../src/platform/native/bridge.h"
#include "../../src/platform/native/loop.h"
#include "nativeBridgeMock.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct MockView {
	struct MockView *parent;
	struct MockView *next;
	struct MockView *firstChild, *lastChild, *previousSibling, *nextSibling;
	int released;
	int tag;
	char text[128];
	float size;
	int isScroll;
	int pressable;
	float x, y, w, h;
	float scaleX, scaleY, translateX, translateY;
	float scrollX, scrollY;
} MockView;

static msClosure s_mount;
static msClosure s_touch;
static msClosure s_resize;
static msClosure s_teardown;
static msClosure s_scroll;
static msClosure s_loop;
static MockView s_container;
static MockView *g_views;
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
static int g_transformWrites;
static int g_restackWrites;
static int g_addChildWrites;
static int g_detachWrites;

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
	v->scaleX = v->scaleY = 1;
	v->next = g_views;
	g_views = v;
	g_created++;
	return v;
}

void *niViewCreate(void) { return create(0); }
void *niTextCreate(void) { return create(17); }
void niViewSetPressable(void *view) { live(view, "niViewSetPressable")->pressable = 1; }
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
	MockView *v = live(view, "niScrollTo");
	v->scrollX = x;
	v->scrollY = y;
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
static void unlinkView(MockView *v) {
	MockView *p = v->parent;
	if (!p) return;
	if (v->previousSibling) v->previousSibling->nextSibling = v->nextSibling;
	else p->firstChild = v->nextSibling;
	if (v->nextSibling) v->nextSibling->previousSibling = v->previousSibling;
	else p->lastChild = v->previousSibling;
	v->parent = NULL;
	v->previousSibling = v->nextSibling = NULL;
}

static void appendView(MockView *p, MockView *v) {
	v->parent = p;
	v->previousSibling = p->lastChild;
	if (p->lastChild) p->lastChild->nextSibling = v;
	else p->firstChild = v;
	p->lastChild = v;
}

void niAddChild(void *parent, void *child) {
	MockView *v = live(child, "niAddChild");
	MockView *p = live(parent, "niAddChild parent");
	if (v->parent) { g_detachWrites++; unlinkView(v); }
	appendView(p, v);
	g_addChildWrites++;
}

void niBringChildToFront(void *child) {
	MockView *v = live(child, "niBringChildToFront");
	MockView *p = v->parent;
	if (!p) { fprintf(stderr, "mock bridge: restacking an unattached view\n"); abort(); }
	if (p->lastChild != v) { unlinkView(v); appendView(p, v); }
	g_restackWrites++;
}

void niRemoveFromParent(void *child) {
	MockView *v = live(child, "niRemoveFromParent");
	if (v->parent) { g_detachWrites++; unlinkView(v); }
}

void niViewRelease(void *view) {
	live(view, "niViewRelease")->released = 1;
	g_releaseCalls++;
}

static int g_scrollFrameWrites = 0;

void niSetFrame(void *view, float x, float y, float w, float h) {
	MockView *v = live(view, "niSetFrame");
	v->x = x; v->y = y; v->w = w; v->h = h;
	if (v->isScroll) g_scrollFrameWrites++;
}

void niSetTransform(void *view, float scaleX, float scaleY, float translateX, float translateY) {
	MockView *v = live(view, "niSetTransform");
	v->scaleX = scaleX; v->scaleY = scaleY;
	v->translateX = translateX; v->translateY = translateY;
	g_transformWrites++;
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
	for (MockView *v = g_views; v; v = v->next) {
		if (!v->released && v->isScroll && v->tag == tag) { v->scrollX = x; v->scrollY = y; break; }
	}
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
int32_t nmLastPressableTag(void) {
	for (MockView *v = g_views; v; v = v->next) {
		if (!v->released && v->pressable && v->tag) return v->tag;
	}
	fprintf(stderr, "mock bridge: no live pressable\n");
	abort();
}


static MockView *tagged(int32_t tag) {
	for (MockView *v = g_views; v; v = v->next) {
		if (!v->released && v->tag == tag) return v;
	}
	fprintf(stderr, "mock bridge: no live view for tag %d\n", tag);
	abort();
}

static float visualCoordinate(MockView *v, float point, int vertical) {
	for (; v && v != &s_container; v = v->parent) {
		float size = vertical ? v->h : v->w;
		float scale = vertical ? v->scaleY : v->scaleX;
		float translation = vertical ? v->translateY : v->translateX;
		float position = vertical ? v->y : v->x;
		float offset = vertical ? v->scrollY : v->scrollX;
		point = position + size * 0.5f + scale * (point - offset - size * 0.5f) + translation;
	}
	return point;
}

int32_t nmTransformWrites(void) { return g_transformWrites; }
float nmVisualX(int32_t tag, float x) { return visualCoordinate(tagged(tag), x, 0); }
float nmVisualY(int32_t tag, float y) { return visualCoordinate(tagged(tag), y, 1); }
float nmLayoutWidth(int32_t tag) { return tagged(tag)->w; }
float nmLayoutHeight(int32_t tag) { return tagged(tag)->h; }
float nmLayoutX(int32_t tag) { return tagged(tag)->x; }
float nmLayoutY(int32_t tag) { return tagged(tag)->y; }
int32_t nmRestackWrites(void) { return g_restackWrites; }
int32_t nmAddChildWrites(void) { return g_addChildWrites; }
int32_t nmDetachWrites(void) { return g_detachWrites; }

int32_t nmPaintTag(int32_t parentTag, int32_t index) {
	MockView *p = parentTag ? tagged(parentTag) : &s_container;
	MockView *v = p->firstChild;
	for (int32_t i = 0; v && i < index; i++) v = v->nextSibling;
	if (!v || index < 0) { fprintf(stderr, "mock bridge: paint index out of bounds\n"); abort(); }
	return v->tag;
}

int32_t nmPaintTextIndex(int32_t parentTag, const char *text) {
	MockView *p = parentTag ? tagged(parentTag) : &s_container;
	int32_t index = 0;
	for (MockView *v = p->firstChild; v; v = v->nextSibling, index++) {
		if (v->size > 0 && strcmp(v->text, text) == 0) return index;
	}
	return -1;
}

static int containsPoint(MockView *v, float x, float y) {
	float originX = visualCoordinate(v, 0, 0), originY = visualCoordinate(v, 0, 1);
	float scaleX = visualCoordinate(v, 1, 0) - originX;
	float scaleY = visualCoordinate(v, 1, 1) - originY;
	if (scaleX == 0 || scaleY == 0) return 0;
	float localX = (x - originX) / scaleX, localY = (y - originY) / scaleY;
	return localX >= v->scrollX && localX < v->scrollX + v->w &&
		localY >= v->scrollY && localY < v->scrollY + v->h;
}

static MockView *hitView(MockView *p, float x, float y) {
	for (MockView *v = p->lastChild; v; v = v->previousSibling) {
		if (v->released || !containsPoint(v, x, y)) continue;
		MockView *hit = hitView(v, x, y);
		if (hit) return hit;
		if (v->pressable && v->tag) return v;
	}
	return NULL;
}

void nmTouchAt(float x, float y, int32_t phase) {
	MockView *hit = hitView(&s_container, x, y);
	if (hit) nmTouch(hit->tag, phase);
}
