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
	float scaleX, scaleY, translateX, translateY, rotation, opacity;
	float scrollX, scrollY;
	int isInput;
	int control;
	int focused;
	char propNames[24][40];
	char propValues[24][512];
	int propCount;
	float background[4];
} MockView;

static msClosure s_mount;
static msClosure s_touch;
static msClosure s_resize;
static msClosure s_teardown;
static msClosure s_scroll;
static msClosure s_loop;
static msClosure s_control;
static msClosure s_environment;
static int g_controlTag, g_controlPhase;
static char g_controlValue[256];
static float g_controlW, g_controlH;
static float g_keyboardH;
static int g_scheme;
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
static int g_lastViewTag;
static int g_translucent;
static float g_systemInsets[4];

static struct MockView *tagged(int32_t tag);

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
	v->opacity = 1;
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
	g_lastViewTag = tag;
}

void *niInputCreate(void) {
	MockView *v = create(17);
	v->isInput = 1;
	v->control = 1;
	return v;
}

void *niTextAreaCreate(void) {
	void *area = niInputCreate();
	niSetProp(area, "multiline", "true");
	return area;
}

static void *createControl(int kind) {
	MockView *v = create(0);
	v->control = kind;
	return v;
}

void *niSwitchCreate(void) { return createControl(2); }
void *niIndicatorCreate(void) { return createControl(3); }
void *niImageCreate(void) { return createControl(4); }
void *niModalCreate(void) { return createControl(5); }
void *niControlCreate(const char *kind) {
	if (strcmp(kind, "slider") == 0) return createControl(6);
	if (strcmp(kind, "picker") == 0) return createControl(7);
	if (strcmp(kind, "datetimepicker") == 0) return createControl(8);
	fprintf(stderr, "mock bridge: niControlCreate has no control \"%s\"\n", kind);
	abort();
}

void niControlSetTag(void *view, int32_t tag) {
	MockView *v = live(view, "niControlSetTag");
	if (!v->control) { fprintf(stderr, "mock bridge: niControlSetTag on a view that is not a control\n"); abort(); }
	v->tag = tag;
}

void niSetProp(void *view, const char *name, const char *value) {
	MockView *v = live(view, "niSetProp");
	int i = 0;
	while (i < v->propCount && strcmp(v->propNames[i], name) != 0) i++;
	if (i == v->propCount) {
		if (v->propCount == 24) { fprintf(stderr, "mock bridge: too many props\n"); abort(); }
		v->propCount++;
		snprintf(v->propNames[i], sizeof v->propNames[i], "%s", name);
	}
	snprintf(v->propValues[i], sizeof v->propValues[i], "%s", value);
	if (strcmp(name, "statusBarTranslucent") == 0) g_translucent = strcmp(value, "true") == 0;
	if (strcmp(name, "textSpans") == 0) {
		// The label shows the runs' texts in order; each record starts with its text.
		size_t at = 0;
		const char *record = value;
		while (*record && at + 1 < sizeof v->text) {
			const char *end = record;
			while (*end && *end != '\x1f' && *end != '\x1e') end++;
			size_t n = (size_t)(end - record);
			if (at + n >= sizeof v->text) n = sizeof v->text - 1 - at;
			memcpy(v->text + at, record, n);
			at += n;
			while (*end && *end != '\x1e') end++;
			record = *end ? end + 1 : end;
		}
		v->text[at] = 0;
	}
	if (v->isInput && strcmp(name, "value") == 0) snprintf(v->text, sizeof v->text, "%s", value);
}

void niSetFocused(void *view, int focused) {
	MockView *v = live(view, "niSetFocused");
	if (v->focused == focused) return;
	v->focused = focused;
	if (v->tag) nmControl(v->tag, focused ? 1 : 2, v->text);
}

void niSetControlHandler(msClosure handler) { s_control = handler; }
int niLastControlTag(void) { return g_controlTag; }
int niLastControlPhase(void) { return g_controlPhase; }
const char *niLastControlValue(void) { return g_controlValue; }
float niLastControlWidth(void) { return g_controlW; }
float niLastControlHeight(void) { return g_controlH; }
void niSetEnvironmentHandler(msClosure handler) { s_environment = handler; }
float niKeyboardHeight(void) { return g_keyboardH; }
int niColorScheme(void) { return g_scheme; }

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

static int g_scrollShifts = 0;

// Like UIScrollView's contentOffset write, a shift reports itself through the scroll handler
// before it returns.
void niScrollShift(void *view, float dx, float dy) {
	MockView *v = live(view, "niScrollShift");
	v->scrollX += dx;
	v->scrollY += dy;
	g_scrollShifts++;
	if (!v->tag) return;
	g_scrollTag = v->tag;
	g_scrollPhase = 0;
	g_scrollX = v->scrollX;
	g_scrollY = v->scrollY;
	g_scrollW = v->w;
	g_scrollH = v->h;
	g_scrollContentW = g_contentW;
	g_scrollContentH = g_contentH;
	call0(s_scroll);
}

float niScrollOffsetX(void *view) { return live(view, "niScrollOffsetX")->scrollX; }
float niScrollOffsetY(void *view) { return live(view, "niScrollOffsetY")->scrollY; }

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

void niSetRotation(void *view, float degrees) {
	MockView *v = live(view, "niSetRotation");
	v->rotation = degrees;
	g_transformWrites++;
}

void niSetBackgroundColor(void *view, float r, float g, float b, float a) {
	MockView *v = live(view, "niSetBackgroundColor");
	v->background[0] = r; v->background[1] = g; v->background[2] = b; v->background[3] = a;
}

void niSetCornerRadius(void *view, float radius) { (void)radius; live(view, "niSetCornerRadius"); }
void niSetOpacity(void *view, float opacity) { live(view, "niSetOpacity")->opacity = opacity; }

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
	if (v->control == 2) { g_measuredW = 51; g_measuredH = 31; return; }
	if (v->control == 6) { g_measuredW = 0; g_measuredH = 31; return; }
	if (v->control == 7) { g_measuredW = 0; g_measuredH = 44; return; }
	if (v->control == 8) { g_measuredW = 120; g_measuredH = 36; return; }
	float w = (float)strlen(v->text) * v->size * 0.5f;
	int lines = 1;
	while (maxWidth > 0 && w > maxWidth * lines) lines++;
	for (int i = 0; i < v->propCount; i++) {
		if (strcmp(v->propNames[i], "numberOfLines") == 0 && atoi(v->propValues[i]) > 0 && lines > atoi(v->propValues[i])) lines = atoi(v->propValues[i]);
	}
	g_measuredW = w < maxWidth ? w : maxWidth;
	g_measuredH = (v->size + 4) * lines;
}

float niMeasuredW(void) { return g_measuredW; }
float niMeasuredH(void) { return g_measuredH; }

void niSetTouchHandler(msClosure handler) { s_touch = handler; }
int niLastTouchTag(void) { return g_lastTag; }
int niLastTouchPhase(void) { return g_lastPhase; }
static float g_touchX = 0, g_touchY = 0;
static double g_touchTime = 0;
static int g_responderTag = 0, g_responderBlocks = 0;
float niLastTouchX(void) { return g_touchX; }
float niLastTouchY(void) { return g_touchY; }
double niLastTouchTime(void) { return g_touchTime; }
void niSetResponder(void *view, int block) {
	g_responderTag = ((MockView *)view)->tag;
	g_responderBlocks = block;
}
void niClearResponder(void) {
	g_responderTag = 0;
	g_responderBlocks = 0;
}
int32_t nmResponderTag(void) { return g_responderTag; }
int32_t nmResponderBlocks(void) { return g_responderBlocks; }

void niRegisterApp(msClosure mount) { s_mount = mount; }
void niSetResizeHandler(msClosure handler) { s_resize = handler; }
void niSetTeardownHandler(msClosure handler) { s_teardown = handler; }
void niSetLoopHandler(msClosure handler) { s_loop = handler; }
void niSetFrameHandler(msClosure handler) { (void)handler; }
int niRequestFrame(void) { return 0; }

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

float niSafeAreaInset(int edge) { return g_translucent && edge >= 0 && edge < 4 ? g_systemInsets[edge] : 0; }

void nmSystemInsets(float top, float right, float bottom, float left) {
	g_systemInsets[0] = top; g_systemInsets[1] = right; g_systemInsets[2] = bottom; g_systemInsets[3] = left;
	call0(s_resize);
}

int32_t nmViewsCreated(void) { return g_created; }
int32_t nmReleaseCalls(void) { return g_releaseCalls; }

void nmTouchFull(int32_t tag, int32_t phase, float x, float y, double time) {
	g_touchX = x;
	g_touchY = y;
	g_touchTime = time;
	nmTouch(tag, phase);
}

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

void nmControlSized(int32_t tag, int32_t phase, const char *value, float width, float height) {
	g_controlTag = tag;
	g_controlPhase = phase;
	snprintf(g_controlValue, sizeof g_controlValue, "%s", value);
	g_controlW = width;
	g_controlH = height;
	for (MockView *v = g_views; v; v = v->next) {
		if (!v->released && v->tag == tag && v->isInput && phase == 0) { snprintf(v->text, sizeof v->text, "%s", value); break; }
	}
	call0(s_control);
}

void nmControl(int32_t tag, int32_t phase, const char *value) { nmControlSized(tag, phase, value, 0, 0); }

void nmEnvironment(float keyboardHeight, int32_t dark) {
	g_keyboardH = keyboardHeight;
	g_scheme = dark;
	call0(s_environment);
}

int32_t nmLastControlTag(int32_t kind) {
	for (MockView *v = g_views; v; v = v->next) {
		if (!v->released && v->control == kind && v->tag) return v->tag;
	}
	fprintf(stderr, "mock bridge: no live tagged control of kind %d\n", kind);
	abort();
}

int32_t nmLastInputTag(void) {
	for (MockView *v = g_views; v; v = v->next) {
		if (!v->released && v->isInput && v->tag) return v->tag;
	}
	fprintf(stderr, "mock bridge: no live tagged input\n");
	abort();
}

int32_t nmFocused(int32_t tag) { return tagged(tag)->focused; }

const char *nmProp(int32_t tag, const char *name) {
	MockView *v = tagged(tag);
	for (int i = 0; i < v->propCount; i++) {
		if (strcmp(v->propNames[i], name) == 0) return v->propValues[i];
	}
	return "<unset>";
}
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


static MockView *tagged(int32_t tag);
float nmOpacity(int32_t tag);
float nmBackgroundAlpha(int32_t tag);

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
float nmRotation(int32_t tag) { return tagged(tag)->rotation; }
float nmOpacity(int32_t tag) { return tagged(tag)->opacity; }
float nmTranslateX(int32_t tag) { return tagged(tag)->translateX; }
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
		if (v->control == 5) return v;
	}
	return NULL;
}

void nmTouchAt(float x, float y, int32_t phase) {
	MockView *hit = hitView(&s_container, x, y);
	if (hit && hit->tag) nmTouch(hit->tag, phase);
}

static MockView *labelled(const char *text) {
	for (MockView *v = g_views; v; v = v->next) {
		if (!v->released && v->size > 0 && strcmp(v->text, text) == 0) return v;
	}
	fprintf(stderr, "mock bridge: no live label \"%s\"\n", text);
	abort();
}

float nmTextWidth(const char *text) { return labelled(text)->w; }
const char *nmLabelProp(const char *text, const char *name) {
	MockView *v = labelled(text);
	for (int i = 0; i < v->propCount; i++) {
		if (strcmp(v->propNames[i], name) == 0) return v->propValues[i];
	}
	return "<unset>";
}
float nmTextVisualX(const char *text) { return visualCoordinate(labelled(text), 0, 0); }
float nmTextVisualY(const char *text) { return visualCoordinate(labelled(text), 0, 1); }
float nmScrollOffsetX(int32_t tag) { return tagged(tag)->scrollX; }
float nmScrollOffsetY(int32_t tag) { return tagged(tag)->scrollY; }
int32_t nmScrollShifts(void) { return g_scrollShifts; }
float nmTextHeight(const char *text) { return labelled(text)->h; }

#include "../../src/platform/native/app.h"

static msClosure s_app;
static int g_appEvent;
static char g_appValue[512];
static int g_appResult;
static char g_appLog[4096];
static char g_appReplyNames[16][32];
static char g_appReplyValues[16][128];
static int g_appReplyCount;

const char *niAppCall(const char *name, const char *arg) {
	size_t used = strlen(g_appLog);
	snprintf(g_appLog + used, sizeof g_appLog - used, "%s%s(%s)", used ? ";" : "", name, arg ? arg : "");
	for (int i = 0; i < g_appReplyCount; i++) {
		if (strcmp(g_appReplyNames[i], name) == 0) return g_appReplyValues[i];
	}
	return "";
}

void niSetAppHandler(msClosure handler) { s_app = handler; }
int niLastAppEvent(void) { return g_appEvent; }
const char *niLastAppValue(void) { return g_appValue; }
void niSetAppEventResult(int result) { g_appResult = result; }

void nmAppReply(const char *name, const char *value) {
	for (int i = 0; i < g_appReplyCount; i++) {
		if (strcmp(g_appReplyNames[i], name) == 0) {
			snprintf(g_appReplyValues[i], sizeof g_appReplyValues[i], "%s", value);
			return;
		}
	}
	if (g_appReplyCount == 16) {
		fprintf(stderr, "mock bridge: more than 16 app replies\n");
		abort();
	}
	snprintf(g_appReplyNames[g_appReplyCount], sizeof g_appReplyNames[0], "%s", name);
	snprintf(g_appReplyValues[g_appReplyCount], sizeof g_appReplyValues[0], "%s", value);
	g_appReplyCount += 1;
}

const char *nmAppLog(void) { return g_appLog; }
void nmAppLogClear(void) { g_appLog[0] = 0; }

int32_t nmAppEvent(int32_t kind, const char *value) {
	g_appEvent = kind;
	snprintf(g_appValue, sizeof g_appValue, "%s", value);
	g_appResult = 0;
	call0(s_app);
	return g_appResult;
}
float nmBackgroundAlpha(int32_t tag) { return tagged(tag)->background[3]; }
int32_t nmLastViewTag(void) { return g_lastViewTag; }

const char *nmAnyProp(const char *name) {
	for (MockView *v = g_views; v; v = v->next) {
		if (v->released) continue;
		for (int i = 0; i < v->propCount; i++) {
			if (strcmp(v->propNames[i], name) == 0) return v->propValues[i];
		}
	}
	return "<unset>";
}

int32_t nmTagWithProp(const char *name, const char *value) {
	for (MockView *v = g_views; v; v = v->next) {
		if (v->released || !v->tag) continue;
		for (int i = 0; i < v->propCount; i++) {
			if (strcmp(v->propNames[i], name) == 0 && strcmp(v->propValues[i], value) == 0) return v->tag;
		}
	}
	fprintf(stderr, "mock bridge: no live tagged view with %s=%s\n", name, value);
	abort();
}

int32_t nmHasLabel(const char *text) {
	for (MockView *v = g_views; v; v = v->next) {
		if (!v->released && v->size > 0 && strcmp(v->text, text) == 0) return 1;
	}
	return 0;
}
