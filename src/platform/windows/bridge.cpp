#include <windows.h>
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <memory>
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
msClosure s_mount, s_resize, s_teardown, s_loop, s_frame, s_touch, s_scroll, s_control, s_environment, s_app;

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

void queueLabel(View *view) {
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

void niAddChild(void *parent, void *child) {
	View *p = as(parent), *c = as(child);
	c->refs += 1;
	detach(c);
	p->visual->InsertAt(c->visual, (int32_t)p->children.size());
	p->children.push_back(c);
	c->parent = p;
}

void niBringChildToFront(void *child) {
	View *c = as(child);
	View *p = c->parent;
	if (!p) return;
	p->visual->Remove(c->visual);
	p->children.erase(std::remove(p->children.begin(), p->children.end(), c), p->children.end());
	p->visual->InsertAt(c->visual, (int32_t)p->children.size());
	p->children.push_back(c);
}

void niRemoveFromParent(void *child) { detach(as(child)); }

void niViewRelease(void *view) { release(as(view)); }

void niSetFrame(void *view, float x, float y, float w, float h) {
	View *v = as(view);
	v->x = x;
	v->y = y;
	v->w = w;
	v->h = h;
	applyGeometry(v);
}

void niSetTransform(void *view, float scaleX, float scaleY, float translateX, float translateY) {
	View *v = as(view);
	v->scaleX = scaleX;
	v->scaleY = scaleY;
	v->translateX = translateX;
	v->translateY = translateY;
	applyGeometry(v);
}

void niSetRotation(void *view, float degrees) {
	View *v = as(view);
	v->rotation = degrees;
	applyGeometry(v);
}

void niSetBackgroundColor(void *view, float r, float g, float b, float a) {
	if (as(view)->label) unimplemented("niSetBackgroundColor on a Text");
	as(view)->visual->Brush(Color{r, g, b, a});
}

void niSetCornerRadius(void *view, float radius) { as(view)->visual->CornerRadius(radius * g_scale); }

void niSetOpacity(void *view, float opacity) { as(view)->visual->Opacity(opacity); }

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

int niRequestFrame(void) { return 0; }

int niRunApp(void) {
	requireAttached("niRunApp");
	if (!s_mount.fn) fail("niRunApp before niRegisterApp");
	invoke(s_mount);
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

UNIMPLEMENTED(void, niViewSetPressable, (void *view))
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
UNIMPLEMENTED(int, niLastTouchTag, (void))
UNIMPLEMENTED(int, niLastTouchPhase, (void))
UNIMPLEMENTED(float, niLastTouchX, (void))
UNIMPLEMENTED(float, niLastTouchY, (void))
UNIMPLEMENTED(double, niLastTouchTime, (void))
UNIMPLEMENTED(void, niSetResponder, (void *view, int blockNativeResponder))
UNIMPLEMENTED(void, niClearResponder, (void))
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
	char what[128];
	snprintf(what, sizeof what, "niSetProp(%s)", name);
	unimplemented(what);
}

}
