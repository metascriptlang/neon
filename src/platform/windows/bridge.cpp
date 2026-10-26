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
#include "activityIndicator.h"
#include "automation.h"
#include "composition.h"
#include "dcompComposition.h"
#include "dwriteText.h"
#include "image.h"
#include "textInput.h"
#include "handoff.h"
#include "scrollView.h"
#include "modal.h"
#include "switch.h"
extern "C" {
#include "../native/bridge.h"
#include "../native/app.h"
#include "../native/loop.h"
void ionWakeLoop(void);
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
	std::unique_ptr<Scroller> scroller;
	bool labelQueued = false;
	std::unique_ptr<TextInput> input;
	bool inputQueued = false;
	std::unique_ptr<ImagePicture> picture;
	bool pictureQueued = false;
	std::unique_ptr<ActivityIndicator> indicator;
	std::unique_ptr<Modal> modal;
	std::unique_ptr<SwitchControl> toggle;
	int automationId = 0;
};

ICompositionContext *g_context = nullptr;
View *g_container = nullptr;
float g_scale = 1;
float g_width = 0;
float g_height = 0;
float g_measuredW = 0;
float g_measuredH = 0;
std::vector<View *> g_dirtyLabels;
std::vector<View *> g_dirtyInputs;
std::vector<View *> g_dirtyPictures;
View *g_focusedInput = nullptr;
View *g_pressedInput = nullptr;
View *g_focusedSwitch = nullptr;
View *g_pressedSwitch = nullptr;
View *g_hoveredSwitch = nullptr;
std::map<int, View *> g_automationViews;
int g_nextAutomationId = uia::kRootId + 1;
int g_announcedFocus = 0;
bool g_windowFocused = true;
int g_ionCursor = 0;
float g_caret[4];

struct ControlReport {
	int32_t tag;
	int32_t phase;
	std::string value;
	float width;
	float height;
};

std::vector<ControlReport> g_reports;
int32_t g_controlTag = 0;
int32_t g_controlPhase = 0;
std::string g_controlValue;
float g_controlWidth = 0;
float g_controlHeight = 0;
msClosure s_mount, s_resize, s_teardown, s_loop, s_frame, s_touch, s_scroll, s_control, s_environment, s_app, s_requester;
bool g_frameRequested = false;
bool g_frameWanted = false;
bool g_inFrame = false;

struct Touch {
	bool active = false;
	std::vector<View *> chain;
	// A pressable run of a label under the finger reports first, as its own tag, the way iOS and Android do.
	int32_t spanTag = 0;
	View *spanLabel = nullptr;
};

Touch g_touch;
int32_t g_touchTag = 0;
int32_t g_touchPhase = 0;
float g_touchX = 0;
float g_touchY = 0;
double g_touchTime = 0;
View *g_responder = nullptr;
View *g_barCapture = nullptr;
std::vector<View *> g_scrolls;
std::vector<View *> g_indicators;
int32_t g_scrollTag = 0;
int32_t g_scrollPhase = 0;
float g_scrollX = 0, g_scrollY = 0, g_scrollW = 0, g_scrollH = 0, g_scrollContentW = 0, g_scrollContentH = 0;

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

IVisual *childHost(View *view) { return view->scroller ? view->scroller->content : view->visual; }

void release(View *view) {
	if (--view->refs > 0) return;
	if (g_responder == view) g_responder = nullptr;
	if (g_focusedInput == view) g_focusedInput = nullptr;
	if (g_pressedInput == view) g_pressedInput = nullptr;
	if (g_focusedSwitch == view) g_focusedSwitch = nullptr;
	if (g_pressedSwitch == view) g_pressedSwitch = nullptr;
	if (g_hoveredSwitch == view) g_hoveredSwitch = nullptr;
	if (view->automationId) g_automationViews.erase(view->automationId);
	if (view->labelQueued) g_dirtyLabels.erase(std::remove(g_dirtyLabels.begin(), g_dirtyLabels.end(), view), g_dirtyLabels.end());
	if (view->scroller) g_scrolls.erase(std::remove(g_scrolls.begin(), g_scrolls.end(), view), g_scrolls.end());
	if (view->inputQueued) g_dirtyInputs.erase(std::remove(g_dirtyInputs.begin(), g_dirtyInputs.end(), view), g_dirtyInputs.end());
	if (view->pictureQueued) g_dirtyPictures.erase(std::remove(g_dirtyPictures.begin(), g_dirtyPictures.end(), view), g_dirtyPictures.end());
	view->input.reset();
	if (view->indicator) g_indicators.erase(std::remove(g_indicators.begin(), g_indicators.end(), view), g_indicators.end());
	view->indicator.reset();
	view->toggle.reset();
	for (View *child : view->children) {
		childHost(view)->Remove(child->visual);
		child->parent = nullptr;
		release(child);
	}
	if (view->scroller) delete view->scroller->content;
	delete view->visual;
	delete view;
}

void detach(View *child) {
	View *parent = child->parent;
	if (!parent) return;
	parent->children.erase(std::remove(parent->children.begin(), parent->children.end(), child), parent->children.end());
	childHost(parent)->Remove(child->visual);
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

void queueInput(View *view) {
	changed();
	if (view->inputQueued) return;
	view->inputQueued = true;
	g_dirtyInputs.push_back(view);
}

void reportControl(View *view, int32_t phase, const std::string &value, float width = 0, float height = 0) {
	if (view->tag != 0) g_reports.push_back({view->tag, phase, value, width, height});
}

void flushReports() {
	while (!g_reports.empty()) {
		ControlReport next = g_reports.front();
		g_reports.erase(g_reports.begin());
		g_controlTag = next.tag;
		g_controlPhase = next.phase;
		g_controlValue = next.value;
		g_controlWidth = next.width;
		g_controlHeight = next.height;
		if (s_control.fn) invoke(s_control);
	}
}

void blurInput(View *view) {
	if (g_focusedInput != view) return;
	g_focusedInput = nullptr;
	view->input->Focus(false);
	reportControl(view, kInputBlur, view->input->Text());
}

void focusInput(View *view) {
	if (g_focusedInput == view) return;
	g_focusedSwitch = nullptr;
	if (g_focusedInput) blurInput(g_focusedInput);
	g_focusedInput = view;
	view->input->WindowFocus(g_windowFocused);
	view->input->Focus(true);
	reportControl(view, kInputFocus, view->input->Text());
}

struct InputSink : TextInputSink {
	void InputReport(TextInput *input, int phase, const std::string &value) override {
		View *view = static_cast<View *>(input->Owner());
		reportControl(view, phase, value);
		if (phase == kInputSubmit && input->BlursOnSubmit()) blurInput(view);
	}
	void InputDirty(TextInput *input) override { queueInput(static_cast<View *>(input->Owner())); }
};

InputSink g_inputSink;

void queuePicture(View *view) {
	changed();
	if (view->pictureQueued) return;
	view->pictureQueued = true;
	g_dirtyPictures.push_back(view);
}

bool isMounted(const View *view) {
	for (; view; view = view->parent) {
		if (view == g_container) return true;
	}
	return false;
}

void pixelBox(const View *view, int32_t *pixelWidth, int32_t *pixelHeight) {
	*pixelWidth = (int32_t)(roundf((view->x + view->w) * g_scale) - roundf(view->x * g_scale));
	*pixelHeight = (int32_t)(roundf((view->y + view->h) * g_scale) - roundf(view->y * g_scale));
}

void drawInputs() {
	std::vector<View *> due;
	due.swap(g_dirtyInputs);
	for (View *view : due) {
		view->inputQueued = false;
		if (isMounted(view) && view->input->TakeAutoFocus()) focusInput(view);
		int32_t pixelWidth, pixelHeight;
		pixelBox(view, &pixelWidth, &pixelHeight);
		if (view->input->NeedsDraw(pixelWidth, pixelHeight)) view->input->Draw(g_context, view->visual, pixelWidth, pixelHeight, g_scale);
	}
	flushReports();
}

void drawPictures() {
	std::vector<View *> due;
	due.swap(g_dirtyPictures);
	for (View *view : due) {
		view->pictureQueued = false;
		std::string error;
		float width, height;
		ImageReport report = view->picture->TakeReport(&error, &width, &height);
		int32_t pixelWidth, pixelHeight;
		pixelBox(view, &pixelWidth, &pixelHeight);
		if (view->picture->NeedsDraw(pixelWidth, pixelHeight)) view->picture->Draw(g_context, view->visual, pixelWidth, pixelHeight, g_scale);
		if (report == kImageLoad) reportControl(view, 5, "", width, height);
		if (report == kImageError) reportControl(view, 6, error);
	}
	flushReports();
}

TextInput *inputOf(void *view) { return static_cast<View *>(view)->input.get(); }

TextLabel *labelOf(void *view, const char *what) {
	View *v = static_cast<View *>(view);
	if (!v->label) {
		char message[192];
		snprintf(message, sizeof message, "%s on a view that is not a Text", what);
		unimplemented(message);
	}
	return v->label.get();
}

void applyScroll(View *view) {
	Scroller *s = view->scroller.get();
	s->content->Offset(-roundf(s->x * g_scale), -roundf(s->y * g_scale));
	s->SyncBars(view->w, view->h, g_scale);
	if (s->moved) changed();
}

void applyGeometry(View *view) {
	float left = roundf(view->x * g_scale);
	float top = roundf(view->y * g_scale);
	float right = roundf((view->x + view->w) * g_scale);
	float bottom = roundf((view->y + view->h) * g_scale);
	view->visual->Offset(left, top + (view->modal ? roundf(view->modal->SlideShift()) : 0));
	view->visual->Size(right - left, bottom - top);
	if (view->label) queueLabel(view);
	if (view->scroller) {
		view->scroller->Clamp(view->w, view->h);
		applyScroll(view);
	}
	if (view->input) queueInput(view);
	if (view->picture) queuePicture(view);
	if (view->toggle) view->toggle->Layout(view->w, view->h, g_scale);

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
		!strcmp(name, "accessibilityRole") || !strcmp(name, "accessibilityState") || !strcmp(name, "role") ||
		!strcmp(name, "accessibilityValue") || !strcmp(name, "accessibilityLiveRegion") || !strcmp(name, "testID") ||
		!strcmp(name, "nativeID");
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
		if (child->input) queueInput(child);
		if (child->picture) {
			child->picture->Invalidate();
			queuePicture(child);
		}
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

View *hit(View *view, float px, float py, float *foundX, float *foundY) {
	float lx, ly;
	if (!toLocal(view, px, py, &lx, &ly)) return nullptr;
	bool inside = lx >= 0 && lx <= view->w && ly >= 0 && ly <= view->h;
	bool clipsChildren = view->radius > 0 || view->scroller;
	float cx = view->scroller ? lx + view->scroller->x : lx, cy = view->scroller ? ly + view->scroller->y : ly;
	if (inside || !clipsChildren) {
		for (auto child = view->children.rbegin(); child != view->children.rend(); ++child) {
			if (View *found = hit(*child, cx, cy, foundX, foundY)) return found;
		}
	}
	if (!inside || (view->label && !view->pressable)) return nullptr;
	*foundX = lx;
	*foundY = ly;
	return view;
}

View *hitTest(float x, float y, float *localX = nullptr, float *localY = nullptr) {
	float lx = 0, ly = 0;
	for (auto child = g_container->children.rbegin(); child != g_container->children.rend(); ++child) {
		if (View *found = hit(*child, x, y, &lx, &ly)) {
			if (localX) *localX = lx;
			if (localY) *localY = ly;
			return found;
		}
	}
	return nullptr;
}

int32_t spanTagAt(View *view, float lx, float ly) {
	return view && view->label ? view->label->TagAt(lx, ly) : 0;
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

View *topModal() {
	for (auto child = g_container->children.rbegin(); child != g_container->children.rend(); ++child) {
		if ((*child)->modal) return *child;
	}
	return nullptr;
}

void stepModals() {
	double now = nowMs();
	for (View *child : g_container->children) {
		if (child->modal && child->modal->Step(now, child->visual)) applyGeometry(child);
	}
}

bool modalsPending() {
	for (const View *child : g_container->children) {
		if (child->modal && child->modal->Animating()) return true;
	}
	return false;
}

void reportTag(int32_t tag, int32_t phase, float x, float y, double time) {
	g_touchTag = tag;
	g_touchPhase = phase;
	g_touchX = x;
	g_touchY = y;
	g_touchTime = time;
	invoke(s_touch);
}

void report(View *view, int32_t phase, float x, float y, double time) {
	g_touchTag = view->tag;
	g_touchPhase = phase;
	g_touchX = x;
	g_touchY = y;
	g_touchTime = time;
	invoke(s_touch);
}

void reportScrolls() {
	double now = nowMs();
	std::vector<View *> due = g_scrolls;
	for (View *view : due) {
		Scroller *s = view->scroller.get();
		s->Step(now);
		if (!s->moved) continue;
		s->moved = false;
		applyScroll(view);
		if (!s_scroll.fn || s->tag == 0) continue;
		g_scrollTag = s->tag;
		g_scrollPhase = 0;
		g_scrollX = s->x;
		g_scrollY = s->y;
		g_scrollW = view->w;
		g_scrollH = view->h;
		g_scrollContentW = std::max(s->contentWidth, view->w);
		g_scrollContentH = std::max(s->contentHeight, view->h);
		invoke(s_scroll);
	}
}

bool scrollsPending() {
	for (View *view : g_scrolls) {
		if (view->scroller->moved || view->scroller->Animating()) return true;
	}
	return false;
}

void stepIndicators() {
	double now = nowMs();
	for (View *view : g_indicators) {
		int32_t pixelWidth, pixelHeight;
		pixelBox(view, &pixelWidth, &pixelHeight);
		view->indicator->Step(pixelWidth, pixelHeight, now);
	}
}

bool indicatorsPending() {
	for (View *view : g_indicators) {
		if (view->indicator->Running() && isMounted(view)) return true;
	}
	return false;
}

Scroller *scrollerOf(void *scroll, const char *what) {
	View *v = static_cast<View *>(scroll);
	if (!v->scroller) {
		char message[192];
		snprintf(message, sizeof message, "%s on a view that is not a ScrollView", what);
		fail(message);
	}
	return v->scroller.get();
}

// A TextInput takes the pointer from down to up, as a UITextField does, so no touch chain starts on it.
bool pointInput(int kind, float x, float y) {
	float lx = 0, ly = 0;
	View *top = g_touch.active ? nullptr : hitTest(x, y, &lx, &ly);
	if (kind == NIW_POINTER_MOVE) g_ionCursor = top && top->input ? 2 : 0;
	if (kind == NIW_POINTER_DOWN && top && top->input && !g_pressedInput) {
		g_pressedInput = top;
		focusInput(top);
		top->input->Pointer(kind, lx * g_scale, ly * g_scale);
		flushReports();
		return true;
	}
	if (!g_pressedInput) return false;
	View *pressed = g_pressedInput;
	float px = x, py = y;
	for (const View *at = pressed; at && at != g_container; at = at->parent) {
		px -= at->x;
		py -= at->y;
		if (at != pressed && at->scroller) {
			px += at->scroller->x;
			py += at->scroller->y;
		}
	}
	if (kind == NIW_POINTER_UP || kind == NIW_POINTER_CANCEL) g_pressedInput = nullptr;
	pressed->input->Pointer(kind, px * g_scale, py * g_scale);
	flushReports();
	return true;
}

void flipSwitch(View *view) {
	reportControl(view, kSwitchValueChange, view->toggle->Value() ? "false" : "true");
	flushReports();
}

void hoverSwitch(View *over) {
	if (g_hoveredSwitch == over) return;
	if (g_hoveredSwitch) g_hoveredSwitch->toggle->SetHovered(false);
	g_hoveredSwitch = over;
	if (over) over->toggle->SetHovered(true);
	changed();
}

// RNW SwitchComponentView OnPointerPressed/Released/Entered/Exited (:262-316): a press on an enabled switch focuses
// it and shows the pressed state, the release over it asks for the flip, and the switch itself keeps showing `value`.
bool pointSwitch(int kind, float x, float y) {
	View *top = g_touch.active || g_pressedInput ? nullptr : hitTest(x, y);
	View *over = top && top->toggle ? top : nullptr;
	if (kind == NIW_POINTER_MOVE || kind == NIW_POINTER_CANCEL) hoverSwitch(kind == NIW_POINTER_MOVE && (!g_pressedSwitch || over == g_pressedSwitch) ? over : nullptr);
	if (kind == NIW_POINTER_DOWN && over && !g_pressedSwitch) {
		g_pressedSwitch = over;
		if (!over->toggle->Disabled()) {
			g_focusedSwitch = over;
			if (g_focusedInput) blurInput(g_focusedInput);
			over->toggle->SetPressed(true);
			changed();
		}
		return true;
	}
	if (!g_pressedSwitch) return false;
	View *pressed = g_pressedSwitch;
	if (kind == NIW_POINTER_UP || kind == NIW_POINTER_CANCEL) {
		g_pressedSwitch = nullptr;
		pressed->toggle->SetPressed(false);
		changed();
		if (kind == NIW_POINTER_UP && !pressed->toggle->Disabled() && hitTest(x, y) == pressed) flipSwitch(pressed);
	}
	return true;
}

bool localPoint(const View *view, float x, float y, float *lx, float *ly) {
	float px = x, py = y;
	if (view->parent && view->parent != g_container) {
		if (!localPoint(view->parent, x, y, &px, &py)) return false;
		if (view->parent->scroller) {
			px += view->parent->scroller->x;
			py += view->parent->scroller->y;
		}
	}
	return toLocal(view, px, py, lx, ly);
}

// RNW ScrollViewComponentView OnPointerPressed/Moved/Released/CaptureLost (:993-1020): the ScrollViews under the
// pointer hand it to their bars first; a press a bar takes never reaches the touch chain, and a thumb drag keeps it.
bool scrollBarPointer(int kind, float x, float y) {
	float lx = 0, ly = 0;
	if (g_barCapture) {
		View *captured = g_barCapture;
		bool inside = localPoint(captured, x, y, &lx, &ly);
		if (kind == NIW_POINTER_MOVE) {
			if (inside) captured->scroller->PointerMoved(lx, ly);
		} else if (kind == NIW_POINTER_UP || kind == NIW_POINTER_CANCEL) {
			if (kind == NIW_POINTER_UP && inside) captured->scroller->PointerReleased(lx, ly);
			else captured->scroller->PointerCaptureLost();
			g_barCapture = nullptr;
			release(captured);
		}
		changed();
		return true;
	}
	if (kind != NIW_POINTER_DOWN && kind != NIW_POINTER_MOVE) return false;
	for (View *at = hitTest(x, y); at && at != g_container; at = at->parent) {
		if (!at->scroller || !localPoint(at, x, y, &lx, &ly)) continue;
		if (kind == NIW_POINTER_MOVE) {
			at->scroller->PointerMoved(lx, ly);
			changed();
		} else if (at->scroller->PointerPressed(lx, ly)) {
			if (at->scroller->Tracking()) {
				at->refs += 1;
				g_barCapture = at;
			}
			changed();
			return true;
		}
	}
	return false;
}

void endTouch() {
	std::vector<View *> chain;
	chain.swap(g_touch.chain);
	g_touch.active = false;
	g_touch.spanTag = 0;
	if (g_touch.spanLabel) release(g_touch.spanLabel);
	g_touch.spanLabel = nullptr;
	for (View *view : chain) release(view);
}


int g_appEvent = 0;
std::string g_appValue;
std::map<uint32_t, std::string> g_sizeFetches;
std::vector<std::string> g_sizeReady;

void emitApp(int kind, const std::string &value) {
	if (!s_app.fn) return;
	g_appEvent = kind;
	g_appValue = value;
	invoke(s_app);
	changed();
}

// The NI_APP_IMAGE_SIZE value, as the macOS host sends it: "id 0x1f width 0x1f height 0x1f error", in pixels.
std::string sizeValue(const std::string &request, const ImageSize &size) {
	bool failed = !size.error.empty();
	return request + "\x1f" + std::to_string(failed ? 0 : size.width) + "\x1f" + std::to_string(failed ? 0 : size.height) + "\x1f" + size.error;
}

// Image.getSize / Image.prefetch: "id 0x1f uri" in; the answer comes back through the app handler once the host thread
// is woken, for a local source as for a download.
void imageSize(const char *arg) {
	const char *split = strchr(arg, '\x1f');
	if (!split) {
		char message[256];
		snprintf(message, sizeof message, "niAppCall(image.size) wants \"id 0x1f uri\": %s", arg);
		fail(message);
	}
	std::string request(arg, split);
	const char *uri = split + 1;
	if (ImageIsNetwork(uri)) {
		g_sizeFetches[ImageFetch(uri)] = request;
		return;
	}
	g_sizeReady.push_back(sizeValue(request, ImageHeaderSize(uri)));
	ionWakeLoop();
}

int automationId(View *view) {
	if (view == g_container) return uia::kRootId;
	if (!view->automationId) {
		view->automationId = g_nextAutomationId++;
		g_automationViews[view->automationId] = view;
	}
	return view->automationId;
}

View *automationView(int id) {
	if (id == uia::kRootId) return g_container;
	auto found = g_automationViews.find(id);
	return found == g_automationViews.end() || !isMounted(found->second) ? nullptr : found->second;
}

std::string storedAccessibility(const View *view, const char *name) {
	auto found = view->accessibility.find(name);
	return found == view->accessibility.end() ? std::string() : found->second;
}

View *hitAny(View *view, float px, float py) {
	float lx, ly;
	if (!toLocal(view, px, py, &lx, &ly)) return nullptr;
	bool inside = lx >= 0 && lx <= view->w && ly >= 0 && ly <= view->h;
	bool clipsChildren = view->radius > 0 || view->scroller;
	float cx = view->scroller ? lx + view->scroller->x : lx, cy = view->scroller ? ly + view->scroller->y : ly;
	if (inside || !clipsChildren) {
		for (auto child = view->children.rbegin(); child != view->children.rend(); ++child) {
			if (View *found = hitAny(*child, cx, cy)) return found;
		}
	}
	return inside ? view : nullptr;
}

bool pressView(View *view) {
	if (!s_touch.fn || g_touch.active) return false;
	float x = view->w / 2, y = view->h / 2;
	for (View *at = view; at && at != g_container; at = at->parent) {
		x += at->x;
		y += at->y;
		if (at != view && at->scroller) {
			x -= at->scroller->x;
			y -= at->scroller->y;
		}
		if (at->tag == 0) continue;
		at->refs += 1;
		g_touch.chain.push_back(at);
	}
	if (g_touch.chain.empty()) return false;
	g_touch.active = true;
	double time = nowMs();
	std::vector<View *> chain = g_touch.chain;
	for (View *at : chain) report(at, 0, x, y, time);
	for (View *at : chain) {
		report(at, 1, x, y, time);
		report(at, 2, x, y, time);
	}
	endTouch();
	return true;
}

}

namespace uia {

bool Describe(int id, Element *out) {
	View *view = automationView(id);
	if (!view || view == g_container) return false;
	out->label = storedAccessibility(view, "accessibilityLabel");
	out->hint = storedAccessibility(view, "accessibilityHint");
	out->role = storedAccessibility(view, "role");
	out->ariaRole = storedAccessibility(view, "accessibilityRole");
	out->state = storedAccessibility(view, "accessibilityState");
	out->value = storedAccessibility(view, "accessibilityValue");
	out->live = storedAccessibility(view, "accessibilityLiveRegion");
	out->testId = storedAccessibility(view, "testID");
	if (out->testId.empty()) out->testId = storedAccessibility(view, "nativeID");
	if (view->label) out->text = view->label->Text();
	if (view->input) out->inputText = view->input->Text();
	std::string accessible = storedAccessibility(view, "accessible");
	out->accessible = accessible.empty() ? view->label || view->toggle || view->input : accessible == "true";
	out->pressable = view->pressable;
	out->isSwitch = view->toggle != nullptr;
	out->switchOn = view->toggle && view->toggle->Value();
	out->switchDisabled = view->toggle && view->toggle->Disabled();
	out->isInput = view->input != nullptr;
	out->isImage = view->picture != nullptr;
	out->focused = view == g_focusedInput || view == g_focusedSwitch;
	float left = 0, top = 0;
	for (const View *at = view; at && at != g_container; at = at->parent) {
		left += roundf(at->x * g_scale);
		top += roundf(at->y * g_scale);
		if (at != view && at->scroller) {
			left -= roundf(at->scroller->x * g_scale);
			top -= roundf(at->scroller->y * g_scale);
		}
	}
	int32_t pixelWidth, pixelHeight;
	pixelBox(view, &pixelWidth, &pixelHeight);
	out->bounds = {(LONG)left, (LONG)top, (LONG)left + pixelWidth, (LONG)top + pixelHeight};
	return true;
}

int Navigate(int id, Direction direction) {
	View *view = automationView(id);
	if (!view) return 0;
	if (direction == kFirstChild) return view->children.empty() ? 0 : automationId(view->children.front());
	if (direction == kLastChild) return view->children.empty() ? 0 : automationId(view->children.back());
	View *parent = view->parent;
	if (!parent) return 0;
	if (direction == kParent) return automationId(parent);
	auto at = std::find(parent->children.begin(), parent->children.end(), view);
	if (direction == kNextSibling) return ++at == parent->children.end() ? 0 : automationId(*at);
	return at == parent->children.begin() ? 0 : automationId(*--at);
}

int ElementAt(int pixelX, int pixelY) {
	if (!g_container) return 0;
	float x = pixelX / g_scale, y = pixelY / g_scale;
	for (auto child = g_container->children.rbegin(); child != g_container->children.rend(); ++child) {
		if (View *found = hitAny(*child, x, y)) return automationId(found);
	}
	return 0;
}

int FocusedElement() {
	if (g_focusedInput) return automationId(g_focusedInput);
	return g_focusedSwitch ? automationId(g_focusedSwitch) : 0;
}

bool Invoke(int id) {
	View *view = automationView(id);
	return view && view->pressable && pressView(view);
}

bool Toggle(int id) {
	View *view = automationView(id);
	if (!view) return false;
	if (view->toggle) {
		if (view->toggle->Disabled()) return false;
		flipSwitch(view);
		return true;
	}
	return view->pressable && pressView(view);
}

bool Focus(int id) {
	View *view = automationView(id);
	if (!view) return false;
	if (view->input) {
		focusInput(view);
		flushReports();
	} else if (view->toggle && !view->toggle->Disabled()) {
		g_focusedSwitch = view;
		if (g_focusedInput) blurInput(g_focusedInput);
	} else {
		return false;
	}
	changed();
	return true;
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
	int focusedNow = uia::FocusedElement();
	if (focusedNow != g_announcedFocus) {
		g_announcedFocus = focusedNow;
		if (uia::Listening()) uia::FocusChanged(focusedNow);
	}
	g_frameRequested = false;
	g_inFrame = true;
	reportScrolls();
	if (s_loop.fn) invoke(s_loop);
	else niLoopRun();
	stepIndicators();
	if (g_frameWanted) {
		g_frameWanted = false;
		if (s_frame.fn) invoke(s_frame);
	}
	stepModals();
	drawInputs();
	drawPictures();
	drawLabels();
	g_context->Commit();
	g_inFrame = false;
	if (scrollsPending() || indicatorsPending() || modalsPending()) requestHostFrame();
}

void niwSetFrameRequester(msClosure requester) { s_requester = requester; }

int niwLayoutsBuilt(void) { return TextLabel::LayoutsBuilt(); }

int niwGetObject(void *hwnd, unsigned long long wParam, long long lParam, long long *result) {
	requireAttached("niwGetObject");
	LRESULT answer = 0;
	if (!uia::GetObject((HWND)hwnd, (WPARAM)wParam, (LPARAM)lParam, &answer)) return 0;
	*result = (long long)answer;
	return 1;
}

void niwDisconnectAutomation(void *hwnd) { uia::Disconnect((HWND)hwnd); }

int niwStoredAccessibility(const char *name, const char *value) {
	requireAttached("niwStoredAccessibility");
	return countStored(g_container, name, value);
}

void niwPointer(int kind, float pixelX, float pixelY) {
	requireAttached("niwPointer");
	float x = pixelX / g_scale, y = pixelY / g_scale;
	if (scrollBarPointer(kind, x, y)) return;
	if (!s_touch.fn) return;
	double time = nowMs();
	if (pointInput(kind, x, y)) return;
	if (pointSwitch(kind, x, y)) return;
	if (kind == NIW_POINTER_DOWN) {
		if (g_touch.active) return;
		float lx = 0, ly = 0;
		View *top = hitTest(x, y, &lx, &ly);
		g_touch.spanTag = spanTagAt(top, lx, ly);
		if (g_touch.spanTag != 0) {
			top->refs += 1;
			g_touch.spanLabel = top;
		}
		for (View *at = top; at && at != g_container; at = at->parent) {
			if (at->tag == 0) continue;
			at->refs += 1;
			g_touch.chain.push_back(at);
		}
		g_touch.active = !g_touch.chain.empty() || g_touch.spanTag != 0;
		if (!g_touch.active) return;
		if (g_touch.spanTag != 0) reportTag(g_touch.spanTag, 0, x, y, time);
		std::vector<View *> chain = g_touch.chain;
		for (View *view : chain) report(view, 0, x, y, time);
	} else if (!g_touch.active) {
		return;
	} else if (kind == NIW_POINTER_MOVE) {
		if (g_touch.spanTag != 0) reportTag(g_touch.spanTag, 4, x, y, time);
		std::vector<View *> chain = g_touch.chain;
		for (View *view : chain) report(view, 4, x, y, time);
	} else if (kind == NIW_POINTER_UP) {
		float lx = 0, ly = 0;
		View *at = hitTest(x, y, &lx, &ly);
		if (g_touch.spanTag != 0) {
			if (at == g_touch.spanLabel && spanTagAt(at, lx, ly) == g_touch.spanTag) {
				reportTag(g_touch.spanTag, 1, x, y, time);
				reportTag(g_touch.spanTag, 2, x, y, time);
			} else {
				reportTag(g_touch.spanTag, 3, x, y, time);
			}
		}
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
		if (g_touch.spanTag != 0) reportTag(g_touch.spanTag, 3, x, y, time);
		std::vector<View *> chain = g_touch.chain;
		for (View *view : chain) report(view, 3, x, y, time);
		endTouch();
	} else {
		char message[64];
		snprintf(message, sizeof message, "niwPointer kind %d", kind);
		fail(message);
	}
}

void niwWheel(float pixelX, float pixelY, float notchesX, float notchesY) {
	requireAttached("niwWheel");
	float x = pixelX / g_scale, y = pixelY / g_scale;
	for (View *at = hitTest(x, y); at && at != g_container; at = at->parent) {
		if (at->scroller && at->scroller->Wheel(notchesX, notchesY, at->w, at->h, g_scale, nowMs())) {
			changed();
			return;
		}
	}
}

int niwPump(void) {
	requireAttached("niwPump");
	reportScrolls();
	if (s_loop.fn) invoke(s_loop);
	else niLoopRun();
	stepIndicators();
	stepModals();
	drawInputs();
	drawPictures();
	drawLabels();
	g_context->Commit();
	return niLoopNext();
}

void niwDrainImages(void) {
	if (!g_context) return;
	std::vector<std::string> ready;
	ready.swap(g_sizeReady);
	for (const std::string &value : ready) emitApp(NI_APP_IMAGE_SIZE, value);
	for (const ImageDownload &download : ImageTakeDownloads()) {
		auto request = g_sizeFetches.find(download.id);
		if (request != g_sizeFetches.end()) {
			std::string id = request->second;
			g_sizeFetches.erase(request);
			ImageSize size = download.error.empty() ? ImageHeaderSizeOfFile(download.path) : ImageSize{0, 0, download.error};
			emitApp(NI_APP_IMAGE_SIZE, sizeValue(id, size));
		} else if (ImagePicture *picture = ImagePicture::Waiting(download.id)) {
			picture->Deliver(download);
			queuePicture(static_cast<View *>(picture->owner));
		}
	}
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

void *niScrollCreate(void) {
	requireAttached("niScrollCreate");
	View *view = new View();
	view->visual = g_context->CreateSpriteVisual();
	view->visual->ClipsChildren(true);
	view->scroller.reset(new Scroller());
	view->scroller->content = g_context->CreateSpriteVisual();
	view->visual->InsertAt(view->scroller->content, 0);
	view->scroller->AttachBars(g_context, view->visual);
	g_scrolls.push_back(view);
	return view;
}

void *niIndicatorCreate(void) {
	requireAttached("niIndicatorCreate");
	View *view = new View();
	view->visual = g_context->CreateSpriteVisual();
	view->indicator.reset(new ActivityIndicator(g_context, view->visual));
	g_indicators.push_back(view);
	return view;
}

void *niModalCreate(void) {
	requireAttached("niModalCreate");
	View *view = new View();
	view->visual = g_context->CreateSpriteVisual();
	view->modal.reset(new Modal());
	return view;
}

void niScrollSetTag(void *scroll, int32_t tag) { scrollerOf(scroll, "niScrollSetTag")->tag = tag; }

void niScrollSetContentSize(void *scroll, float w, float h) {
	scrollerOf(scroll, "niScrollSetContentSize")->SetContentSize(w, h, as(scroll)->w, as(scroll)->h);
	applyScroll(as(scroll));
}

void niScrollTo(void *scroll, float x, float y, int animated) {
	Scroller *s = scrollerOf(scroll, "niScrollTo");
	if (animated) s->AnimateTo(x, y, as(scroll)->w, as(scroll)->h, g_scale, nowMs());
	else s->JumpTo(x, y, as(scroll)->w, as(scroll)->h);
	applyScroll(as(scroll));
	changed();
}

void niScrollSetOption(void *scroll, const char *name, const char *value) {
	scrollerOf(scroll, "niScrollSetOption")->SetOption(name, value);
}

void niScrollShift(void *scroll, float dx, float dy) {
	scrollerOf(scroll, "niScrollShift")->Shift(dx, dy, as(scroll)->w, as(scroll)->h);
	applyScroll(as(scroll));
}

float niScrollOffsetX(void *scroll) { return scrollerOf(scroll, "niScrollOffsetX")->x; }
float niScrollOffsetY(void *scroll) { return scrollerOf(scroll, "niScrollOffsetY")->y; }

int niLastScrollTag(void) { return g_scrollTag; }
int niLastScrollPhase(void) { return g_scrollPhase; }
float niLastScrollX(void) { return g_scrollX; }
float niLastScrollY(void) { return g_scrollY; }
float niLastScrollWidth(void) { return g_scrollW; }
float niLastScrollHeight(void) { return g_scrollH; }
float niLastScrollContentWidth(void) { return g_scrollContentW; }
float niLastScrollContentHeight(void) { return g_scrollContentH; }

void *niTextCreate(void) {
	requireAttached("niTextCreate");
	View *view = new View();
	view->visual = g_context->CreateSpriteVisual();
	view->label.reset(new TextLabel());
	return view;
}

void *niImageCreate(void) {
	requireAttached("niImageCreate");
	View *view = new View();
	view->visual = g_context->CreateSpriteVisual();
	view->picture.reset(new ImagePicture());
	view->picture->owner = view;
	return view;
}

void *createInput(bool multiline, const char *what) {
	requireAttached(what);
	View *view = new View();
	view->visual = g_context->CreateSpriteVisual();
	view->input.reset(new TextInput(&g_inputSink, view, multiline));
	queueInput(view);
	return view;
}

void *niInputCreate(void) { return createInput(false, "niInputCreate"); }
void *niTextAreaCreate(void) { return createInput(true, "niTextAreaCreate"); }

void *niSwitchCreate(void) {
	requireAttached("niSwitchCreate");
	View *view = new View();
	view->visual = g_context->CreateSpriteVisual();
	view->toggle.reset(new SwitchControl(g_context, view->visual));
	return view;
}

void niControlSetTag(void *control, int32_t tag) {
	if (!as(control)->input && !as(control)->picture && !as(control)->toggle) unimplemented("niControlSetTag on a control that is not a TextInput, an Image or a Switch");
	as(control)->tag = tag;
}

void niSetFocused(void *control, int focused) {
	if (!as(control)->input) unimplemented("niSetFocused on a control that is not a TextInput");
	if (focused) focusInput(as(control));
	else blurInput(as(control));
	flushReports();
}

int niLastControlTag(void) { return g_controlTag; }
int niLastControlPhase(void) { return g_controlPhase; }
const char *niLastControlValue(void) { return g_controlValue.c_str(); }
float niLastControlWidth(void) { return g_controlWidth; }
float niLastControlHeight(void) { return g_controlHeight; }

void niwKey(int action, int ionScancode, int ctrl, const char *text) {
	if (action != NIW_KEY_RELEASE && MapVirtualKeyW((UINT)ionScancode, MAPVK_VSC_TO_VK_EX) == VK_ESCAPE) {
		View *modal = topModal();
		if (modal && modal->tag != 0) {
			reportControl(modal, 7, "");
			flushReports();
			return;
		}
	}
	if (g_focusedSwitch) {
		if (action == NIW_KEY_RELEASE && MapVirtualKeyW((UINT)ionScancode, MAPVK_VSC_TO_VK_EX) == VK_SPACE && !g_focusedSwitch->toggle->Disabled()) flipSwitch(g_focusedSwitch);
		return;
	}
	if (!g_focusedInput) return;
	g_focusedInput->input->Key(action, ionScancode, ctrl != 0, text ? text : "");
	flushReports();
}

void niwText(const char *text) {
	if (!g_focusedInput) return;
	g_focusedInput->input->Insert(text ? text : "");
	flushReports();
}

void niwPreedit(const char *text, int cursor) {
	if (!g_focusedInput) return;
	g_focusedInput->input->Preedit(text ? text : "", cursor);
	flushReports();
}

void niwFocus(int focused) {
	g_windowFocused = focused != 0;
	if (g_focusedInput) g_focusedInput->input->WindowFocus(g_windowFocused);
}

int niwIonCursor(void) { return g_ionCursor; }

int niwFocusedCaret(void) {
	if (!g_focusedInput) return 0;
	float x, y, w, h;
	if (!g_focusedInput->input->CaretRect(&x, &y, &w, &h)) return 0;
	for (const View *at = g_focusedInput; at && at != g_container; at = at->parent) {
		x += roundf(at->x * g_scale);
		y += roundf(at->y * g_scale);
		if (at != g_focusedInput && at->scroller) {
			x -= roundf(at->scroller->x * g_scale);
			y -= roundf(at->scroller->y * g_scale);
		}
	}
	g_caret[0] = x;
	g_caret[1] = y;
	g_caret[2] = w;
	g_caret[3] = h;
	return 1;
}

int niwCaretPixelX(void) { return (int)g_caret[0]; }
int niwCaretPixelY(void) { return (int)g_caret[1]; }
int niwCaretPixelW(void) { return (int)g_caret[2]; }
int niwCaretPixelH(void) { return (int)g_caret[3]; }

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
	childHost(p)->InsertAt(c->visual, (int32_t)p->children.size());
	p->children.push_back(c);
	c->parent = p;
	if (c->modal && isMounted(c)) c->modal->Present(nowMs(), c->visual, g_height * g_scale);
	changed();
}

void niBringChildToFront(void *child) {
	View *c = as(child);
	View *p = c->parent;
	if (!p) return;
	childHost(p)->Remove(c->visual);
	p->children.erase(std::remove(p->children.begin(), p->children.end(), c), p->children.end());
	childHost(p)->InsertAt(c->visual, (int32_t)p->children.size());
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
	if (as(view)->input) {
		as(view)->input->SetBackground(Color{r, g, b, a});
		return;
	}
	if (as(view)->picture) {
		as(view)->picture->SetBackground(Color{r, g, b, a});
		queuePicture(as(view));
		return;
	}
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
	if (!strcmp(name, "image.size")) {
		imageSize(arg ? arg : "");
		reply[0] = '\0';
	} else if (!strcmp(name, "platform")) {
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

UNIMPLEMENTED(void, niSetReloadPoll, (msClosure poll))
int niLastAppEvent(void) { return g_appEvent; }
const char *niLastAppValue(void) { return g_appValue.c_str(); }
UNIMPLEMENTED(void, niSetAppEventResult, (int result))

void niSetText(void *label, const char *s) {
	labelOf(label, "niSetText")->SetText(s ? s : "");
	queueLabel(as(label));
}

void niSetTextColor(void *label, float r, float g, float b, float a) {
	if (TextInput *input = inputOf(label)) {
		input->SetColor(Color{r, g, b, a});
		return;
	}
	labelOf(label, "niSetTextColor")->SetColor(Color{r, g, b, a});
	queueLabel(as(label));
}

void niSetFont(void *label, float size, int bold) {
	if (TextInput *input = inputOf(label)) {
		input->SetFont(size, bold != 0);
		return;
	}
	labelOf(label, "niSetFont")->SetFont(size, bold != 0);
	queueLabel(as(label));
}

void niMeasureText(void *label, float maxWidth) {
	requireAttached("niMeasureText");
	if (as(label)->toggle) {
		SwitchControl::Measure(&g_measuredW, &g_measuredH);
		return;
	}
	if (TextInput *input = inputOf(label)) {
		input->Measure(maxWidth, g_scale, &g_measuredW, &g_measuredH);
		return;
	}
	labelOf(label, "niMeasureText")->Measure(maxWidth, g_scale, &g_measuredW, &g_measuredH);
}

float niMeasuredW(void) { return g_measuredW; }
float niMeasuredH(void) { return g_measuredH; }

static void setProp(void *view, const char *name, const char *value) {
	if (as(view)->modal && as(view)->modal->SetProp(name, value)) return;
	if (as(view)->input && as(view)->input->SetProp(name, value)) return;
	if ((as(view)->indicator && as(view)->indicator->SetProp(name, value)) || (as(view)->toggle && as(view)->toggle->SetProp(name, value))) {
		changed();
		return;
	}
	if (as(view)->label && !strcmp(name, "textSpans")) {
		as(view)->label->SetRuns(value);
		queueLabel(as(view));
		return;
	}
	if (as(view)->label && !strcmp(name, "fontFamily")) {
		as(view)->label->SetFamily(value);
		queueLabel(as(view));
		return;
	}
	if (as(view)->label && !strcmp(name, "textAlign")) {
		as(view)->label->SetAlignment(value);
		queueLabel(as(view));
		return;
	}
	if (as(view)->label && !strcmp(name, "writingDirection")) {
		as(view)->label->SetWritingDirection(value);
		queueLabel(as(view));
		return;
	}
	if (as(view)->picture && as(view)->picture->SetProp(name, value)) {
		queuePicture(as(view));
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

void niSetProp(void *view, const char *name, const char *value) {
	int id = uia::Listening() ? automationId(as(view)) : 0;
	uia::Element before, after;
	bool described = id && uia::Describe(id, &before);
	setProp(view, name, value);
	if (described && uia::Describe(id, &after)) uia::PropertiesChanged(id, before, after);
}

}
