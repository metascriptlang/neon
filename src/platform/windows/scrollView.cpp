#include <windows.h>
#include <d2d1_1.h>
#include <dwrite.h>
#include <wrl/client.h>
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include "must.h"
#include "scrollView.h"

using Microsoft::WRL::ComPtr;

namespace {

const float kWheelDelta = 120.0f;
const double kMsPerPixel = 5.0;
const double kMinMs = 50.0;
const double kMaxMs = 1000.0;
const float kLineDelta = 16.0f;

// RNW Theme.cpp at 1f59db1, the light theme: ScrollBar* names (:272-281) resolved through s_lightColors (:298, :311-313).
const Color kControlStrongFillColorDefault = {0, 0, 0, 0x72 / 255.0f};
const Color kControlStrongFillColorDisabled = {0, 0, 0, 0x51 / 255.0f};
const Color kTextFillColorSecondary = {0, 0, 0, 0x9E / 255.0f};
const Color kAcrylicInAppFillColorDefault = {1, 1, 1, 0x9E / 255.0f};

[[noreturn]] void refuse(const char *name, const char *value) {
	fprintf(stderr, "neon windows bridge: ScrollView %s=\"%s\" is not implemented on Windows yet\n", name, value);
	fflush(stderr);
	abort();
}

float maxOffset(float content, float view) { return std::max(content - view, 0.0f); }

IDWriteFactory *dwrite() {
	static IDWriteFactory *shared = nullptr;
	if (!shared) {
		must(DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED, __uuidof(IDWriteFactory), (IUnknown **)&shared), "DWriteCreateFactory");
	}
	return shared;
}

void scaleThumb(IVisual *thumb, bool vertical, float by) {
	float m[6] = {vertical ? by : 1.0f, 0, 0, vertical ? 1.0f : by, 0, 0};
	thumb->TransformMatrix(m);
}

}

ScrollBar::ScrollBar(ICompositionContext *context, bool vertical) : context(context), vertical(vertical) {
	root = context->CreateSpriteVisual();
	track = context->CreateSpriteVisual();
	thumb = context->CreateSpriteVisual();
	arrowFirst = context->CreateSpriteVisual();
	arrowLast = context->CreateSpriteVisual();
	root->InsertAt(track, 0);
	root->InsertAt(arrowFirst, 1);
	root->InsertAt(arrowLast, 2);
	root->InsertAt(thumb, 3);
	track->Brush(kAcrylicInAppFillColorDefault);
	UpdateShy(true);
}

ScrollBar::~ScrollBar() {
	delete thumb;
	delete arrowLast;
	delete arrowFirst;
	delete track;
	delete root;
}

void ScrollBar::Sync(float pixelWidth, float pixelHeight, float pixelContentWidth, float pixelContentHeight, float pixelX, float pixelY, float newScale) {
	bool resized = pixelWidth != width || pixelHeight != height;
	bool rescaled = newScale != scale;
	width = pixelWidth;
	height = pixelHeight;
	if (rescaled) {
		scale = newScale;
		OnScaleChanged();
	}
	if (resized || rescaled) UpdateTrack();
	contentWidth = pixelContentWidth;
	contentHeight = pixelContentHeight;
	offsetX = pixelX;
	offsetY = pixelY;
	UpdateThumb();
	UpdateVisibility(wanted);
}

void ScrollBar::UpdateTrack() {
	if (vertical) {
		track->Size(arrowSize, std::max(height - trackMargin * 2, 0.0f));
		track->Offset(0, trackMargin);
	} else {
		track->Size(std::max(width - trackMargin * 2, 0.0f), arrowSize);
		track->Offset(trackMargin, 0);
	}
	UpdateRootAndArrowOffsets();
}

// RNW updateVisibility (:120) keeps the prop and the overflow in one flag, so a bar hidden while its content fit
// stayed hidden once the content grew; the prop is kept apart here.
void ScrollBar::UpdateVisibility(bool isWanted) {
	wanted = isWanted;
	bool empty = (width <= 0 && height <= 0) || (contentWidth <= 0 && contentHeight <= 0);
	visible = !empty && wanted && (vertical ? contentHeight > height : contentWidth > width);
	root->Opacity(visible ? 1.0f : 0.0f);
}

void ScrollBar::UpdateRootAndArrowOffsets() {
	if (vertical) {
		root->Size(arrowSize, height);
		root->Offset(width - (arrowSize + trackEdgeMargin), 0);
		arrowFirst->Offset(0, arrowMargin);
		arrowLast->Offset(0, height - (arrowSize + arrowMargin));
	} else {
		root->Size(width, arrowSize);
		root->Offset(0, height - (arrowSize + trackEdgeMargin));
		arrowFirst->Offset(arrowMargin, 0);
		arrowLast->Offset(width - (arrowSize + arrowMargin), 0);
	}
}

// RNW onScaleChanged (:158): the numbers are its XAML resources.
void ScrollBar::OnScaleChanged() {
	arrowSize = 12 * scale;
	thumbWidth = 6 * scale;
	thumbShyWidth = 2 * scale;
	arrowMargin = 4 * scale;
	trackEdgeMargin = 1 * scale;
	trackMargin = (2 + 1) * scale;
	minThumbSize = (int)(30 * scale);
	thumb->CornerRadius(thumbWidth / 2.0f);
	track->CornerRadius(arrowSize / 2.0f);
	arrowFirst->Size(arrowSize, arrowSize);
	arrowLast->Size(arrowSize, arrowSize);
	arrowFirstSurface.reset();
	arrowLastSurface.reset();
	DrawArrow(ScrollbarHitRegion::ArrowFirst, !enabled, highlighted == ScrollbarHitRegion::ArrowFirst);
	DrawArrow(ScrollbarHitRegion::ArrowLast, !enabled, highlighted == ScrollbarHitRegion::ArrowLast);
	UpdateHighlight(ScrollbarHitRegion::Thumb);
}

ScrollbarHitRegion ScrollBar::HitTest(float px, float py) const {
	float x = px * scale, y = py * scale;
	float along = vertical ? y : x, across = vertical ? x : y, extent = vertical ? height : width, side = vertical ? width : height;
	if (across < side - (arrowSize + trackEdgeMargin)) return ScrollbarHitRegion::Unknown;
	if (along < arrowSize + arrowMargin) return ScrollbarHitRegion::ArrowFirst;
	if (along < arrowSize + arrowMargin + thumbPos) return ScrollbarHitRegion::PageUp;
	if (along < arrowSize + arrowMargin + thumbPos + thumbSize) return ScrollbarHitRegion::Thumb;
	if (along < extent - (arrowSize + arrowMargin)) return ScrollbarHitRegion::PageDown;
	return ScrollbarHitRegion::ArrowLast;
}

int ScrollBar::ViewportSize() const { return (int)(vertical ? height : width); }

int ScrollBar::MaxThumbLength() const { return std::max((int)(ViewportSize() - 2 * (arrowSize + arrowMargin)), 0); }

int ScrollBar::ScrollRange() const { return (int)(vertical ? contentHeight : contentWidth); }

int ScrollBar::ComputedPixelThumbSize() const {
	int range = ScrollRange();
	if (range <= 0) return 0;
	return std::max(MulDiv(std::min(range, ViewportSize()), MaxThumbLength(), range), 0);
}

float ScrollBar::ScrollOffsetFromThumbPos(int pos) const {
	int maxThumbLength = MaxThumbLength(), range = ScrollRange(), computed = ComputedPixelThumbSize();
	int correction = 0;
	if (!(minThumbSize <= computed || maxThumbLength < 2 * minThumbSize)) correction = minThumbSize - computed;
	return std::clamp((float)MulDiv(pos, range, maxThumbLength - correction), 0.0f, (float)range);
}

void ScrollBar::UpdateThumb() {
	int maxThumbLength = MaxThumbLength(), range = ScrollRange();
	int offset = (int)(vertical ? offsetY : offsetX);
	int computed = ComputedPixelThumbSize();
	int correction = 0;
	if (minThumbSize <= computed || maxThumbLength < 2 * minThumbSize) {
		thumbSize = computed;
	} else {
		correction = minThumbSize - computed;
		thumbSize = minThumbSize;
	}
	thumbPos = range > 0 ? MulDiv(offset, maxThumbLength - correction, range) : 0;

	float across = (arrowSize - thumbWidth) / 2.0f + (shy ? thumbWidth - thumbShyWidth : 0.0f);
	float along = arrowSize + arrowMargin + (float)thumbPos;
	if (vertical) {
		thumb->Size(thumbWidth, (float)thumbSize);
		thumb->Offset(across, along);
	} else {
		thumb->Size((float)thumbSize, thumbWidth);
		thumb->Offset(along, across);
	}
	scaleThumb(thumb, vertical, shy && thumbWidth > 0 ? thumbShyWidth / thumbWidth : 1.0f);
}

void ScrollBar::UpdateShy(bool newShy) {
	if (newShy == shy) return;
	shy = newShy;
	track->Opacity(shy ? 0.0f : 1.0f);
	arrowFirst->Opacity(shy ? 0.0f : 1.0f);
	arrowLast->Opacity(shy ? 0.0f : 1.0f);
	UpdateThumb();
}

void ScrollBar::SetHighlightedRegion(ScrollbarHitRegion region) {
	if (highlighted == region) return;
	ScrollbarHitRegion old = highlighted;
	highlighted = region;
	UpdateHighlight(old);
	UpdateHighlight(highlighted);
}

void ScrollBar::UpdateColors(bool isEnabled) {
	enabled = isEnabled;
	UpdateHighlight(ScrollbarHitRegion::ArrowFirst);
	UpdateHighlight(ScrollbarHitRegion::ArrowLast);
	UpdateHighlight(ScrollbarHitRegion::Thumb);
}

void ScrollBar::UpdateHighlight(ScrollbarHitRegion region) {
	if (region == ScrollbarHitRegion::ArrowFirst || region == ScrollbarHitRegion::ArrowLast) {
		DrawArrow(region, !enabled, highlighted == region);
	}
	if (region == ScrollbarHitRegion::ArrowFirst || region == ScrollbarHitRegion::ArrowLast || region == ScrollbarHitRegion::Thumb) {
		thumb->Brush(enabled ? kControlStrongFillColorDefault : kControlStrongFillColorDisabled);
	}
}

// RNW drawArrow (:456): one Segoe Fluent Icons glyph at 8 points, centred in the arrow's square.
void ScrollBar::DrawArrow(ScrollbarHitRegion region, bool disabled, bool hovered) {
	if (scale <= 0 || arrowSize <= 0) return;
	bool first = region == ScrollbarHitRegion::ArrowFirst;
	std::unique_ptr<IDrawingSurface> &surface = first ? arrowFirstSurface : arrowLastSurface;
	int32_t side = (int32_t)ceilf(arrowSize);
	if (!surface) surface.reset(context->CreateDrawingSurface(side, side));

	ComPtr<IDWriteTextFormat> format;
	must(dwrite()->CreateTextFormat(L"Segoe Fluent Icons", nullptr, DWRITE_FONT_WEIGHT_REGULAR, DWRITE_FONT_STYLE_NORMAL,
		DWRITE_FONT_STRETCH_NORMAL, 8, L"", &format), "CreateTextFormat");
	must(format->SetTextAlignment(DWRITE_TEXT_ALIGNMENT_CENTER), "SetTextAlignment");
	const wchar_t *glyph = vertical ? (first ? L"" : L"") : (first ? L"" : L"");
	ComPtr<IDWriteTextLayout> layout;
	must(dwrite()->CreateTextLayout(glyph, 1, format.Get(), arrowSize / scale, arrowSize / scale, &layout), "CreateTextLayout");
	DWRITE_TEXT_METRICS metrics = {};
	must(layout->GetMetrics(&metrics), "GetMetrics");

	ID2D1DeviceContext *dc = static_cast<ID2D1DeviceContext *>(surface->BeginDrawD2D(96.0f * scale));
	dc->Clear(D2D1::ColorF(0, 0, 0, 0));
	Color c = disabled ? kControlStrongFillColorDisabled : hovered ? kTextFillColorSecondary : kControlStrongFillColorDefault;
	ComPtr<ID2D1SolidColorBrush> brush;
	must(dc->CreateSolidColorBrush(D2D1::ColorF(c.r, c.g, c.b, c.a), &brush), "CreateSolidColorBrush");
	float top = (float)(int)((arrowSize - metrics.height) / 2.0f) / scale;
	dc->DrawTextLayout(D2D1::Point2F(0, top), layout.Get(), brush.Get(), D2D1_DRAW_TEXT_OPTIONS_ENABLE_COLOR_FONT);
	surface->EndDraw();
	(first ? arrowFirst : arrowLast)->Content(surface.get());
}

void ScrollBar::MoveThumb(Scroller *owner, float x, float y) {
	int tracking = (int)((vertical ? y : x) * scale) - trackInputOffset;
	float pixel = ScrollOffsetFromThumbPos(tracking);
	if (vertical) owner->ScrollToPixels(offsetX, pixel);
	else owner->ScrollToPixels(pixel, offsetY);
}

// RNW OnPointerPressed (:356): the horizontal bar's track takes a press without paging, as RNW's does.
bool ScrollBar::PointerPressed(Scroller *owner, float x, float y) {
	if (!visible) return false;
	switch (HitTest(x, y)) {
	case ScrollbarHitRegion::ArrowFirst:
		if (vertical) owner->ScrollBy(0, -kLineDelta);
		else owner->ScrollBy(-kLineDelta, 0);
		return true;
	case ScrollbarHitRegion::ArrowLast:
		if (vertical) owner->ScrollBy(0, kLineDelta);
		else owner->ScrollBy(kLineDelta, 0);
		return true;
	case ScrollbarHitRegion::PageUp:
		if (vertical) owner->ScrollBy(0, -owner->viewHeight);
		return true;
	case ScrollbarHitRegion::PageDown:
		if (vertical) owner->ScrollBy(0, owner->viewHeight);
		return true;
	case ScrollbarHitRegion::Thumb:
		trackInputOffset = (int)((vertical ? y : x) * scale) - thumbPos;
		MoveThumb(owner, x, y);
		return true;
	default:
		return false;
	}
}

void ScrollBar::PointerMoved(Scroller *owner, float x, float y) {
	if (!visible) return;
	if (trackInputOffset != -1) {
		MoveThumb(owner, x, y);
		return;
	}
	ScrollbarHitRegion region = HitTest(x, y);
	UpdateShy(region == ScrollbarHitRegion::Unknown);
	SetHighlightedRegion(region);
}

void ScrollBar::PointerReleased(Scroller *owner, float x, float y) {
	if (!visible || trackInputOffset == -1) return;
	MoveThumb(owner, x, y);
	trackInputOffset = -1;
	UpdateShy(HitTest(x, y) == ScrollbarHitRegion::Unknown);
}

void ScrollBar::PointerCaptureLost() {
	if (!visible) return;
	trackInputOffset = -1;
	UpdateShy(true);
}

void Scroller::AttachBars(ICompositionContext *context, IVisual *frame) {
	verticalBar.reset(new ScrollBar(context, true));
	horizontalBar.reset(new ScrollBar(context, false));
	frame->InsertAt(verticalBar->Visual(), 1);
	frame->InsertAt(horizontalBar->Visual(), 2);
}

// RNW updateContentVisualSize (:891): a bar measures content of at least the frame's size.
void Scroller::SyncBars(float newViewWidth, float newViewHeight, float newScale) {
	viewWidth = newViewWidth;
	viewHeight = newViewHeight;
	scale = newScale;
	float w = viewWidth * scale, h = viewHeight * scale;
	float cw = std::max(contentWidth, viewWidth) * scale, ch = std::max(contentHeight, viewHeight) * scale;
	verticalBar->Sync(w, h, cw, ch, x * scale, y * scale, scale);
	horizontalBar->Sync(w, h, cw, ch, x * scale, y * scale, scale);
}

bool Scroller::PointerPressed(float px, float py) {
	return verticalBar->PointerPressed(this, px, py) || horizontalBar->PointerPressed(this, px, py);
}

void Scroller::PointerMoved(float px, float py) {
	verticalBar->PointerMoved(this, px, py);
	horizontalBar->PointerMoved(this, px, py);
}

void Scroller::PointerReleased(float px, float py) {
	verticalBar->PointerReleased(this, px, py);
	horizontalBar->PointerReleased(this, px, py);
}

void Scroller::PointerCaptureLost() {
	verticalBar->PointerCaptureLost();
	horizontalBar->PointerCaptureLost();
}

bool Scroller::Tracking() const { return verticalBar->Tracking() || horizontalBar->Tracking(); }

// RNW scrollUp/scrollDown/scrollLeft/scrollRight (:1112-1190): nothing when scrolling is off or already at that end.
bool Scroller::ScrollBy(float dx, float dy) {
	if (!enabled) return false;
	float wantX = std::clamp(x + dx, 0.0f, maxOffset(contentWidth, viewWidth));
	float wantY = std::clamp(y + dy, 0.0f, maxOffset(contentHeight, viewHeight));
	if (wantX == x && wantY == y) return false;
	JumpTo(wantX, wantY, viewWidth, viewHeight);
	return true;
}

// RNW scrollTo (:1194): a thumb drag scrolls even when scrollEnabled is false, as a programmatic scroll does.
void Scroller::ScrollToPixels(float pixelX, float pixelY) {
	JumpTo(pixelX / scale, pixelY / scale, viewWidth, viewHeight);
}

void Scroller::moveTo(float newX, float newY) {
	if (newX == x && newY == y) return;
	x = newX;
	y = newY;
	moved = true;
}

void Scroller::SetOption(const char *name, const char *value) {
	bool yes = !strcmp(value, "true");
	if (!strcmp(name, "horizontal")) horizontal = yes;
	else if (!strcmp(name, "scrollEnabled")) {
		enabled = value[0] == '\0' || yes;
		verticalBar->UpdateColors(enabled);
		horizontalBar->UpdateColors(enabled);
	} else if (!strcmp(name, "showsHorizontalScrollIndicator")) horizontalBar->UpdateVisibility(value[0] == '\0' || yes);
	else if (!strcmp(name, "showsVerticalScrollIndicator")) verticalBar->UpdateVisibility(value[0] == '\0' || yes);
	else if (!strcmp(name, "keyboardDismissMode") || !strcmp(name, "keyboardShouldPersistTaps")) {}
	else if (!strcmp(name, "pagingEnabled") || !strcmp(name, "refreshEnabled") || !strcmp(name, "refreshing")) {
		if (yes) refuse(name, value);
	} else refuse(name, value);
}

void Scroller::Clamp(float viewWidth, float viewHeight) {
	float mx = maxOffset(contentWidth, viewWidth), my = maxOffset(contentHeight, viewHeight);
	if (animating) {
		toX = std::clamp(toX, 0.0f, mx);
		toY = std::clamp(toY, 0.0f, my);
	}
	moveTo(std::clamp(x, 0.0f, mx), std::clamp(y, 0.0f, my));
}

void Scroller::SetContentSize(float width, float height, float viewWidth, float viewHeight) {
	contentWidth = width;
	contentHeight = height;
	Clamp(viewWidth, viewHeight);
}

void Scroller::JumpTo(float toXIn, float toYIn, float viewWidth, float viewHeight) {
	animating = false;
	moveTo(std::clamp(toXIn, 0.0f, maxOffset(contentWidth, viewWidth)), std::clamp(toYIn, 0.0f, maxOffset(contentHeight, viewHeight)));
}

void Scroller::AnimateTo(float toXIn, float toYIn, float viewWidth, float viewHeight, float scale, double nowMs) {
	float targetX = std::clamp(toXIn, 0.0f, maxOffset(contentWidth, viewWidth));
	float targetY = std::clamp(toYIn, 0.0f, maxOffset(contentHeight, viewHeight));
	double pixels = std::sqrt(std::pow((targetX - x) * scale, 2.0f) + std::pow((targetY - y) * scale, 2.0f));
	if (pixels < 0.5) {
		JumpTo(targetX, targetY, viewWidth, viewHeight);
		return;
	}
	animating = true;
	fromX = x;
	fromY = y;
	toX = targetX;
	toY = targetY;
	start = nowMs;
	duration = std::clamp(std::floor(pixels) * kMsPerPixel, kMinMs, kMaxMs);
}

void Scroller::Shift(float dx, float dy, float viewWidth, float viewHeight) {
	if (animating) {
		fromX += dx;
		fromY += dy;
		toX += dx;
		toY += dy;
	}
	moveTo(x + dx, y + dy);
	Clamp(viewWidth, viewHeight);
}

bool Scroller::Wheel(float dx, float dy, float viewWidth, float viewHeight, float scale, double nowMs) {
	if (!enabled) return false;
	float fromTargetX = TargetX(), fromTargetY = TargetY();
	float wantX = std::clamp(fromTargetX + dx * kWheelDelta, 0.0f, maxOffset(contentWidth, viewWidth));
	float wantY = std::clamp(fromTargetY - dy * kWheelDelta, 0.0f, maxOffset(contentHeight, viewHeight));
	if (wantX == fromTargetX && wantY == fromTargetY) return false;
	AnimateTo(wantX, wantY, viewWidth, viewHeight, scale, nowMs);
	return true;
}

bool Scroller::Step(double nowMs) {
	if (!animating) return false;
	double t = duration > 0 ? (nowMs - start) / duration : 1.0;
	if (t >= 1.0) {
		animating = false;
		moveTo(toX, toY);
		return false;
	}
	double eased = 1.0 - std::pow(1.0 - t, 3.0);
	moveTo((float)(fromX + (toX - fromX) * eased), (float)(fromY + (toY - fromY) * eased));
	return true;
}
