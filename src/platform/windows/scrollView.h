#pragma once
#include <cstdint>
#include <memory>
#include "composition.h"

// RNW ScrollViewComponentView.cpp at 1f59db1, ScrollbarHitRegion (:33).
enum class ScrollbarHitRegion : int {
	Unknown = -1,
	ArrowFirst = 0,
	PageUp = 1,
	Thumb = 2,
	PageDown = 3,
	ArrowLast = 4,
};

struct Scroller;

// RNW ScrollViewComponentView.cpp ScrollBarComponent (:42) on this seam. Sizes and positions are pixels, as RNW's;
// a pointer arrives in the ScrollView's own points.
class ScrollBar {
public:
	ScrollBar(ICompositionContext *context, bool vertical);
	~ScrollBar();
	IVisual *Visual() const { return root; }
	void Sync(float pixelWidth, float pixelHeight, float pixelContentWidth, float pixelContentHeight, float pixelX, float pixelY, float scale);
	void UpdateVisibility(bool visible);
	void UpdateColors(bool enabled);

	bool PointerPressed(Scroller *owner, float x, float y);
	void PointerMoved(Scroller *owner, float x, float y);
	void PointerReleased(Scroller *owner, float x, float y);
	void PointerCaptureLost();
	bool Tracking() const { return trackInputOffset != -1; }

private:
	ScrollbarHitRegion HitTest(float x, float y) const;
	int ViewportSize() const;
	int MaxThumbLength() const;
	int ScrollRange() const;
	int ComputedPixelThumbSize() const;
	float ScrollOffsetFromThumbPos(int pos) const;
	void UpdateTrack();
	void UpdateThumb();
	void UpdateRootAndArrowOffsets();
	void OnScaleChanged();
	void UpdateShy(bool shy);
	void SetHighlightedRegion(ScrollbarHitRegion region);
	void UpdateHighlight(ScrollbarHitRegion region);
	void DrawArrow(ScrollbarHitRegion region, bool disabled, bool hovered);
	void MoveThumb(Scroller *owner, float x, float y);

	ICompositionContext *context;
	const bool vertical;
	IVisual *root, *track, *thumb, *arrowFirst, *arrowLast;
	std::unique_ptr<IDrawingSurface> arrowFirstSurface, arrowLastSurface;
	bool wanted = true;
	bool visible = false;
	bool shy = false;
	bool enabled = true;
	int thumbSize = 0;
	float arrowSize = 0, arrowMargin = 0, trackEdgeMargin = 0, trackMargin = 0, thumbWidth = 0, thumbShyWidth = 0;
	int minThumbSize = 0;
	float scale = 0;
	int thumbPos = 0;
	int trackInputOffset = -1;
	ScrollbarHitRegion highlighted = ScrollbarHitRegion::Unknown;
	float offsetX = 0, offsetY = 0;
	float contentWidth = 0, contentHeight = 0;
	float width = 0, height = 0;
};

// RNW CompScrollerVisual (Fabric/Composition/CompositionContextHelper.cpp) without its InteractionTracker:
// a content visual inside the clipped scroll visual, offset by minus the position, which the bridge steps per frame.
struct Scroller {
	IVisual *content = nullptr;
	std::unique_ptr<ScrollBar> verticalBar, horizontalBar;
	int32_t tag = 0;
	float x = 0, y = 0;
	float contentWidth = 0, contentHeight = 0;
	float viewWidth = 0, viewHeight = 0, scale = 1;
	bool horizontal = false;
	bool enabled = true;
	bool moved = false;

	void AttachBars(ICompositionContext *context, IVisual *frame);
	void SyncBars(float viewWidth, float viewHeight, float scale);
	void SetOption(const char *name, const char *value);
	void SetContentSize(float width, float height, float viewWidth, float viewHeight);
	void JumpTo(float toX, float toY, float viewWidth, float viewHeight);
	void AnimateTo(float toX, float toY, float viewWidth, float viewHeight, float scale, double nowMs);
	void Shift(float dx, float dy, float viewWidth, float viewHeight);
	void Clamp(float viewWidth, float viewHeight);
	bool Wheel(float dx, float dy, float viewWidth, float viewHeight, float scale, double nowMs);
	bool Step(double nowMs);
	bool Animating() const { return animating; }
	float TargetX() const { return animating ? toX : x; }
	float TargetY() const { return animating ? toY : y; }

	// The scroll bars' share of the pointer, in the ScrollView's own points (RNW ScrollViewComponentView OnPointer*, :993).
	bool PointerPressed(float px, float py);
	void PointerMoved(float px, float py);
	void PointerReleased(float px, float py);
	void PointerCaptureLost();
	bool Tracking() const;

	bool ScrollBy(float dx, float dy);
	void ScrollToPixels(float pixelX, float pixelY);

private:
	void moveTo(float newX, float newY);

	bool animating = false;
	float fromX = 0, fromY = 0, toX = 0, toY = 0;
	double start = 0, duration = 0;
};
