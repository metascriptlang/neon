#pragma once
#include <cstdint>
#include "composition.h"

// RNW CompScrollerVisual (Fabric/Composition/CompositionContextHelper.cpp) without its InteractionTracker:
// a content visual inside the clipped scroll visual, offset by minus the position, which the bridge steps per frame.
struct Scroller {
	IVisual *content = nullptr;
	int32_t tag = 0;
	float x = 0, y = 0;
	float contentWidth = 0, contentHeight = 0;
	bool horizontal = false;
	bool enabled = true;
	bool moved = false;

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

private:
	void moveTo(float newX, float newY);

	bool animating = false;
	float fromX = 0, fromY = 0, toX = 0, toY = 0;
	double start = 0, duration = 0;
};
