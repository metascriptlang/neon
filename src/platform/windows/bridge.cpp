#include <windows.h>
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <map>
#include <memory>
#include <string>
#include <vector>
#include "composition.h"
#include "dcompComposition.h"
#include "dwriteText.h"
#include "handoff.h"
extern "C" {
#include "../native/bridge.h"
#include "../native/app.h"
#include "../native/loop.h"
}

namespace {

struct View {
	int refs = 1;
	int32_t tag = 0;
	IVisual *visual = nullptr;
	View *parent = nullptr;
	std::vector<View *> children;
	float x = 0, y = 0, w = 0, h = 0;
	float scaleX = 1, scaleY = 1, translateX = 0, translateY = 0, rotation = 0;
	bool transformed = false;
	float radius = 0;
	bool pressable = false;
	std::map<std::string, std::string> accessibility;
	std::unique_ptr<TextLabel> label;
	bool labelQueued = false;
};

ICompositionContext *g_context = nullptr;
View *g_container = nullptr;
float g_scale = 1;
float g_width = 0;
float g_height = 0;
float g_measuredW = 0;
float g_measuredH = 0;
std::vector<View *> g_dirtyLabels;
msClosure s_mount, s_resize, s_teardown, s_loop, s_frame, s_touch, s_scroll, s_control, s_environment, s_app, s_requester;
bool g_frameRequested = false;
bool g_frameWanted = false;
bool g_inFrame = false;

struct Touch {
	bool active = false;
	std::vector<View *> chain;
};

Touch g_touch;
int32_t g_touchTag = 0;
int32_t g_touchPhase = 0;
float g_touchX = 0;
float g_touchY = 0;
double g_touchTime = 0;
View *g_responder = nullptr;

[[noreturn]] void fail(const char *message) {
	fprintf(stderr, "neon windows bridge: %s\n", message);
	fflush(stderr);
	abort();
}

[[noreturn]] void unimplemented(const char *what) {
	char message[192];
	snprintf(message, sizeof message, "%s is not implemented on Windows yet", what);
	fail(message);
}

void invoke(msClosure c) {
	if (c.env) ((void (*)(void *))c.fn)(c.env);
	else ((void (*)(void))c.fn)();
}

void requireAttached(const char *what) {
	if (g_context) return;
	char message[192];
	snprintf(message, sizeof message, "%s before niwAttach", what);
	fail(message);
}

void release(View *view) {
	if (--view->refs > 0) return;
	if (g_responder == view) g_responder = nullptr;
	if (view->labelQueued) g_dirtyLabels.erase(std::remove(g_dirtyLabels.begin(), g_dirtyLabels.end(), view), g_dirtyLabels.end());
	for (View *child : view->children) {
		view->visual->Remove(child->visual);
		child->parent = nullptr;
		release(child);
	}
	delete view->visual;
	delete view;
}

void detach(View *child) {
	View *parent = child->parent;
	if (!parent) return;
	parent->children.erase(std::remove(parent->children.begin(), parent->children.end(), child), parent->children.end());
	parent->visual->Remove(child->visual);
	child->parent = nullptr;
	release(child);
}

void requestHostFrame() {
	if (g_frameRequested || !s_requester.fn) return;
	g_frameRequested = true;
	invoke(s_requester);
}

void changed() {
	if (!g_inFrame) requestHostFrame();
}

void queueLabel(View *view) {
	changed();
	if (view->labelQueued) return;
	view->labelQueued = true;
	g_dirtyLabels.push_back(view);
}

void drawLabels() {
	std::vector<View *> due;
	due.swap(g_dirtyLabels);
	for (View *view : due) {
		view->labelQueued = false;
		int32_t pixelWidth = (int32_t)(roundf((view->x + view->w) * g_scale) - roundf(view->x * g_scale));
		int32_t pixelHeight = (int32_t)(roundf((view->y + view->h) * g_scale) - roundf(view->y * g_scale));
		if (view->label->NeedsDraw(pixelWidth, pixelHeight)) view->label->Draw(g_context, view->visual, pixelWidth, pixelHeight, g_scale);
	}
}

TextLabel *labelOf(void *view, const char *what) {
	View *v = static_cast<View *>(view);
	if (!v->label) {
		char message[192];
		snprintf(message, sizeof message, "%s on a view that is not a Text", what);
		unimplemented(message);
	}
	return v->label.get();
}

void applyGeometry(View *view) {
	float left = roundf(view->x * g_scale);
	float top = roundf(view->y * g_scale);
	float right = roundf((view->x + view->w) * g_scale);
	float bottom = roundf((view->y + view->h) * g_scale);
	view->visual->Offset(left, top);
	view->visual->Size(right - left, bottom - top);
	if (view->label) queueLabel(view);

	bool identity = view->scaleX == 1 && view->scaleY == 1 && view->translateX == 0 && view->translateY == 0 && view->rotation == 0;
	if (identity && !view->transformed) return;
	view->transformed = !identity;
	float radians = view->rotation * 3.14159265358979f / 180.0f;
	float c = cosf(radians), s = sinf(radians);
	float m11 = view->scaleX * c, m12 = view->scaleX * s, m21 = -view->scaleY * s, m22 = view->scaleY * c;
	float cx = (right - left) / 2, cy = (bottom - top) / 2;
	float m[6] = {
		m11, m12, m21, m22,
		cx + view->translateX * g_scale - (cx * m11 + cy * m21),
		cy + view->translateY * g_scale - (cx * m12 + cy * m22),
	};
	view->visual->TransformMatrix(m);
}

View *as(void *view) { return static_cast<View *>(view); }

bool isAccessibilityProp(const char *name) {
	return !strcmp(name, "accessible") || !strcmp(name, "accessibilityLabel") || !strcmp(name, "accessibilityHint") ||
		!strcmp(name, "accessibilityRole") || !strcmp(name, "accessibilityState");
}

int countStored(const View *view, const char *name, const char *value) {
	auto found = view->accessibility.find(name);
	int count = found != view->accessibility.end() && found->second == value ? 1 : 0;
	for (const View *child : view->children) count += countStored(child, name, value);
	return count;
}

void rescale(View *parent) {
	for (View *child : parent->children) {
		applyGeometry(child);
		child->visual->CornerRadius(child->radius * g_scale);
		if (child->label) child->label->Invalidate();
		rescale(child);
	}
}

bool toLocal(const View *view, float px, float py, float *lx, float *ly) {
	float radians = view->rotation * 3.14159265358979f / 180.0f;
	float c = cosf(radians), s = sinf(radians);
	float m11 = view->scaleX * c, m12 = view->scaleX * s, m21 = -view->scaleY * s, m22 = view->scaleY * c;
	float det = m11 * m22 - m12 * m21;
	if (det == 0) return false;
	float cx = view->w / 2, cy = view->h / 2;
	float dx = px - (view->x + cx + view->translateX), dy = py - (view->y + cy + view->translateY);
	*lx = cx + (dx * m22 - dy * m21) / det;
	*ly = cy + (dy * m11 - dx * m12) / det;
	return true;
}

View *hit(View *view, float px, float py) {
	float lx, ly;
	if (!toLocal(view, px, py, &lx, &ly)) return nullptr;
	bool inside = lx >= 0 && lx <= view->w && ly >= 0 && ly <= view->h;
	bool clipsChildren = view->radius > 0;
	if (inside || !clipsChildren) {
		for (auto child = view->children.rbegin(); child != view->children.rend(); ++child) {
			if (View *found = hit(*child, lx, ly)) return found;
		}
	}
	return inside && (!view->label || view->pressable) ? view : nullptr;
}

View *hitTest(float x, float y) {
	for (auto child = g_container->children.rbegin(); child != g_container->children.rend(); ++child) {
		if (View *found = hit(*child, x, y)) return found;
	}
	return nullptr;
}

bool within(const View *at, const View *ancestor) {
	for (; at; at = at->parent) {
		if (at == ancestor) return true;
	}
	return false;
}

double nowMs() {
	LARGE_INTEGER frequency, counter;
	QueryPerformanceFrequency(&frequency);
	QueryPerformanceCounter(&counter);
	return (double)counter.QuadPart * 1000.0 / (double)frequency.QuadPart;
}

void report(View *view, int32_t phase, float x, float y, double time) {
	g_touchTag = view->tag;
	g_touchPhase = phase;
	g_touchX = x;
	g_touchY = y;
	g_touchTime = time;
	invoke(s_touch);
}

void endTouch() {
	std::vector<View *> chain;
	chain.swap(g_touch.chain);
	g_touch.active = false;
	for (View *view : chain) release(view);
}

}

extern "C" {

void niwAttach(void *dcompDevice2, void *parentVisual2, float dpi, float logicalWidth, float logicalHeight) {
	if (g_context) fail("niwAttach called twice");
	g_context = CreateDCompContext(dcompDevice2);
	g_container = new View();
	g_container->visual = AdoptDCompVisual(g_context, parentVisual2);
	g_scale = dpi / 96.0f;
	g_width = logicalWidth;
	g_height = logicalHeight;
}

void niwResize(float dpi, float logicalWidth, float logicalHeight) {
	requireAttached("niwResize");
	float scale = dpi / 96.0f;
	bool rescaled = scale != g_scale;
	g_scale = scale;
	g_width = logicalWidth;
	g_height = logicalHeight;
	if (rescaled) rescale(g_container);
	if (s_resize.fn) invoke(s_resize);
	changed();
}

void niwFrame(void) {
	requireAttached("niwFrame");
	g_frameRequested = false;
	g_inFrame = true;
	if (s_loop.fn) invoke(s_loop);
	else niLoopRun();
	if (g_frameWanted) {
		g_frameWanted = false;
		if (s_frame.fn) invoke(s_frame);
	}
	drawLabels();
	g_context->Commit();
	g_inFrame = false;
}

void niwSetFrameRequester(msClosure requester) { s_requester = requester; }

int niwStoredAccessibility(const char *name, const char *value) {
	requireAttached("niwStoredAccessibility");
	return countStored(g_container, name, value);
}

void niwPointer(int kind, float pixelX, float pixelY) {
	requireAttached("niwPointer");
	if (!s_touch.fn) return;
	float x = pixelX / g_scale, y = pixelY / g_scale;
	double time = nowMs();
	if (kind == NIW_POINTER_DOWN) {
		if (g_touch.active) return;
		for (View *at = hitTest(x, y); at && at != g_container; at = at->parent) {
			if (at->tag == 0) continue;
			at->refs += 1;
			g_touch.chain.push_back(at);
		}
		g_touch.active = !g_touch.chain.empty();
		if (!g_touch.active) return;
		std::vector<View *> chain = g_touch.chain;
		for (View *view : chain) report(view, 0, x, y, time);
	} else if (!g_touch.active) {
		return;
	} else if (kind == NIW_POINTER_MOVE) {
		std::vector<View *> chain = g_touch.chain;
		for (View *view : chain) report(view, 4, x, y, time);
	} else if (kind == NIW_POINTER_UP) {
		View *at = hitTest(x, y);
		std::vector<View *> chain = g_touch.chain;
		for (View *view : chain) {
			if (within(at, view)) {
				report(view, 1, x, y, time);
				report(view, 2, x, y, time);
			} else {
				report(view, 3, x, y, time);
			}
		}
		endTouch();
	} else if (kind == NIW_POINTER_CANCEL) {
		std::vector<View *> chain = g_touch.chain;
		for (View *view : chain) report(view, 3, x, y, time);
		endTouch();
	} else {
		char message[64];
		snprintf(message, sizeof message, "niwPointer kind %d", kind);
		fail(message);
	}
}

int niwPump(void) {
	requireAttached("niwPump");
	if (s_loop.fn) invoke(s_loop);
	else niLoopRun();
	drawLabels();
	g_context->Commit();
	return niLoopNext();
}

void niwShutdown(void) {
	if (s_teardown.fn) invoke(s_teardown);
}

void *niViewCreate(void) {
	requireAttached("niViewCreate");
	View *view = new View();
	view->visual = g_context->CreateSpriteVisual();
	return view;
}

void *niTextCreate(void) {
	requireAttached("niTextCreate");
	View *view = new View();
	view->visual = g_context->CreateSpriteVisual();
	view->label.reset(new TextLabel());
	return view;
}

void niViewSetTag(void *view, int32_t tag) { as(view)->tag = tag; }

void niViewSetPressable(void *view) { as(view)->pressable = true; }

int niLastTouchTag(void) { return g_touchTag; }
int niLastTouchPhase(void) { return g_touchPhase; }
float niLastTouchX(void) { return g_touchX; }
float niLastTouchY(void) { return g_touchY; }
double niLastTouchTime(void) { return g_touchTime; }

void niSetResponder(void *view, int blockNativeResponder) { g_responder = blockNativeResponder ? as(view) : nullptr; }
void niClearResponder(void) { g_responder = nullptr; }

void niAddChild(void *parent, void *child) {
	View *p = as(parent), *c = as(child);
	c->refs += 1;
	detach(c);
	p->visual->InsertAt(c->visual, (int32_t)p->children.size());
	p->children.push_back(c);
	c->parent = p;
	changed();
}

void niBringChildToFront(void *child) {
	View *c = as(child);
	View *p = c->parent;
	if (!p) return;
	p->visual->Remove(c->visual);
	p->children.erase(std::remove(p->children.begin(), p->children.end(), c), p->children.end());
	p->visual->InsertAt(c->visual, (int32_t)p->children.size());
	p->children.push_back(c);
	changed();
}

void niRemoveFromParent(void *child) {
	detach(as(child));
	changed();
}

void niViewRelease(void *view) { release(as(view)); }

void niSetFrame(void *view, float x, float y, float w, float h) {
	View *v = as(view);
	v->x = x;
	v->y = y;
	v->w = w;
	v->h = h;
	applyGeometry(v);
	changed();
}

void niSetTransform(void *view, float scaleX, float scaleY, float translateX, float translateY) {
	View *v = as(view);
	v->scaleX = scaleX;
	v->scaleY = scaleY;
	v->translateX = translateX;
	v->translateY = translateY;
	applyGeometry(v);
	changed();
}

void niSetRotation(void *view, float degrees) {
	View *v = as(view);
	v->rotation = degrees;
	applyGeometry(v);
	changed();
}

void niSetBackgroundColor(void *view, float r, float g, float b, float a) {
	if (as(view)->label) unimplemented("niSetBackgroundColor on a Text");
	as(view)->visual->Brush(Color{r, g, b, a});
	changed();
}

void niSetCornerRadius(void *view, float radius) {
	as(view)->radius = radius;
	as(view)->visual->CornerRadius(radius * g_scale);
	changed();
}

void niSetOpacity(void *view, float opacity) {
	as(view)->visual->Opacity(opacity);
	changed();
}

void niRegisterApp(msClosure mount) { s_mount = mount; }
void niSetResizeHandler(msClosure handler) { s_resize = handler; }
void niSetTeardownHandler(msClosure handler) { s_teardown = handler; }
void niSetLoopHandler(msClosure handler) { s_loop = handler; }
void niSetFrameHandler(msClosure handler) { s_frame = handler; }
void niSetTouchHandler(msClosure handler) { s_touch = handler; }
void niSetScrollHandler(msClosure handler) { s_scroll = handler; }
void niSetControlHandler(msClosure handler) { s_control = handler; }
void niSetEnvironmentHandler(msClosure handler) { s_environment = handler; }
void niSetAppHandler(msClosure handler) { s_app = handler; }

int niRequestFrame(void) {
	if (!s_requester.fn) return 0;
	g_frameWanted = true;
	requestHostFrame();
	return 1;
}

int niRunApp(void) {
	requireAttached("niRunApp");
	if (!s_mount.fn) fail("niRunApp before niRegisterApp");
	invoke(s_mount);
	changed();
	return 0;
}

void *niContainerView(void) {
	requireAttached("niContainerView");
	return g_container;
}

float niScreenWidth(void) { return g_width; }
float niScreenHeight(void) { return g_height; }
float niSafeAreaInset(int edge) { (void)edge; return 0; }
float niKeyboardHeight(void) { return 0; }
int niColorScheme(void) { return 0; }

void niInvokeClosure(msClosure c) { invoke(c); }

const char *niAppCall(const char *name, const char *arg) {
	static char reply[64];
	(void)arg;
	if (!strcmp(name, "platform")) {
		typedef LONG(WINAPI * RtlGetVersionFn)(PRTL_OSVERSIONINFOW);
		RtlGetVersionFn getVersion = (RtlGetVersionFn)GetProcAddress(GetModuleHandleW(L"ntdll.dll"), "RtlGetVersion");
		RTL_OSVERSIONINFOW version = {};
		version.dwOSVersionInfoSize = sizeof version;
		if (!getVersion || getVersion(&version) != 0) unimplemented("niAppCall(platform): RtlGetVersion");
		snprintf(reply, sizeof reply, "%lu.%lu.%lu", version.dwMajorVersion, version.dwMinorVersion, version.dwBuildNumber);
	} else if (!strcmp(name, "isPad") || !strcmp(name, "a11y.screenReader") || !strcmp(name, "a11y.reduceMotion")) {
		snprintf(reply, sizeof reply, "0");
	} else if (!strcmp(name, "pixelRatio")) {
		snprintf(reply, sizeof reply, "%g", g_scale);
	} else if (!strcmp(name, "fontScale")) {
		snprintf(reply, sizeof reply, "1");
	} else if (!strcmp(name, "screen")) {
		snprintf(reply, sizeof reply, "%g\x1f" "%g", g_width, g_height);
	} else if (!strcmp(name, "appState")) {
		snprintf(reply, sizeof reply, "active");
	} else if (!strcmp(name, "notification.install")) {
		reply[0] = '\0';
	} else {
		char what[128];
		snprintf(what, sizeof what, "niAppCall(%s)", name);
		unimplemented(what);
	}
	return reply;
}

#define UNIMPLEMENTED(ret, name, params) ret name params { unimplemented(#name); }

UNIMPLEMENTED(void *, niScrollCreate, (void))
UNIMPLEMENTED(void, niScrollSetTag, (void *scroll, int32_t tag))
UNIMPLEMENTED(void, niScrollSetContentSize, (void *scroll, float w, float h))
UNIMPLEMENTED(void, niScrollTo, (void *scroll, float x, float y, int animated))
UNIMPLEMENTED(void, niScrollSetOption, (void *scroll, const char *name, const char *value))
UNIMPLEMENTED(void, niScrollShift, (void *scroll, float dx, float dy))
UNIMPLEMENTED(float, niScrollOffsetX, (void *scroll))
UNIMPLEMENTED(float, niScrollOffsetY, (void *scroll))
UNIMPLEMENTED(void *, niInputCreate, (void))
UNIMPLEMENTED(void *, niTextAreaCreate, (void))
UNIMPLEMENTED(void *, niSwitchCreate, (void))
UNIMPLEMENTED(void *, niIndicatorCreate, (void))
UNIMPLEMENTED(void *, niImageCreate, (void))
UNIMPLEMENTED(void *, niModalCreate, (void))
UNIMPLEMENTED(void *, niControlCreate, (const char *kind))
UNIMPLEMENTED(void, niControlSetTag, (void *control, int32_t tag))
UNIMPLEMENTED(void, niSetFocused, (void *control, int focused))
UNIMPLEMENTED(int, niLastControlTag, (void))
UNIMPLEMENTED(int, niLastControlPhase, (void))
UNIMPLEMENTED(const char *, niLastControlValue, (void))
UNIMPLEMENTED(float, niLastControlWidth, (void))
UNIMPLEMENTED(float, niLastControlHeight, (void))
UNIMPLEMENTED(int, niLastScrollTag, (void))
UNIMPLEMENTED(int, niLastScrollPhase, (void))
UNIMPLEMENTED(float, niLastScrollX, (void))
UNIMPLEMENTED(float, niLastScrollY, (void))
UNIMPLEMENTED(float, niLastScrollWidth, (void))
UNIMPLEMENTED(float, niLastScrollHeight, (void))
UNIMPLEMENTED(float, niLastScrollContentWidth, (void))
UNIMPLEMENTED(float, niLastScrollContentHeight, (void))
UNIMPLEMENTED(void, niSetReloadPoll, (msClosure poll))
UNIMPLEMENTED(int, niLastAppEvent, (void))
UNIMPLEMENTED(const char *, niLastAppValue, (void))
UNIMPLEMENTED(void, niSetAppEventResult, (int result))

void niSetText(void *label, const char *s) {
	labelOf(label, "niSetText")->SetText(s ? s : "");
	queueLabel(as(label));
}

void niSetTextColor(void *label, float r, float g, float b, float a) {
	labelOf(label, "niSetTextColor")->SetColor(Color{r, g, b, a});
	queueLabel(as(label));
}

void niSetFont(void *label, float size, int bold) {
	labelOf(label, "niSetFont")->SetFont(size, bold != 0);
	queueLabel(as(label));
}

void niMeasureText(void *label, float maxWidth) {
	requireAttached("niMeasureText");
	labelOf(label, "niMeasureText")->Measure(maxWidth, g_scale, &g_measuredW, &g_measuredH);
}

float niMeasuredW(void) { return g_measuredW; }
float niMeasuredH(void) { return g_measuredH; }

void niSetProp(void *view, const char *name, const char *value) {
	if (as(view)->label && !strcmp(name, "textAlign")) {
		as(view)->label->SetAlignment(value);
		queueLabel(as(view));
		return;
	}
	if (isAccessibilityProp(name)) {
		as(view)->accessibility[name] = value;
		return;
	}
	char what[128];
	snprintf(what, sizeof what, "niSetProp(%s)", name);
	unimplemented(what);
}

}
