#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include "scrollView.h"

namespace {

const float kWheelDelta = 120.0f;
const double kMsPerPixel = 5.0;
const double kMinMs = 50.0;
const double kMaxMs = 1000.0;

[[noreturn]] void refuse(const char *name, const char *value) {
	fprintf(stderr, "neon windows bridge: ScrollView %s=\"%s\" is not implemented on Windows yet\n", name, value);
	fflush(stderr);
	abort();
}

float maxOffset(float content, float view) { return std::max(content - view, 0.0f); }

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
	else if (!strcmp(name, "scrollEnabled")) enabled = value[0] == '\0' || yes;
	else if (!strcmp(name, "showsHorizontalScrollIndicator") || !strcmp(name, "showsVerticalScrollIndicator")) {}
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
