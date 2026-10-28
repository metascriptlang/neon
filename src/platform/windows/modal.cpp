#include <windows.h>
#include "modal.h"
#include <algorithm>
#include <cstring>

namespace {
constexpr double kDurationMs = 300;
}

bool Modal::SetProp(const char *name, const char *value) {
	if (strcmp(name, "animationType")) return false;
	animation = !strcmp(value, "fade") ? Animation::Fade : !strcmp(value, "slide") ? Animation::Slide : Animation::None;
	return true;
}

void Modal::Present(double nowMs, IVisual *visual, float pixelHeight) {
	if (animation == Animation::None) return;
	animating = true;
	start = nowMs;
	slideFrom = pixelHeight;
	if (animation == Animation::Fade) visual->Opacity(0);
	else shift = pixelHeight;
}

bool Modal::Step(double nowMs, IVisual *visual) {
	if (!animating) return false;
	float t = (float)std::min(std::max((nowMs - start) / kDurationMs, 0.0), 1.0);
	if (t >= 1) animating = false;
	if (animation == Animation::Fade) {
		visual->Opacity(t);
		return false;
	}
	shift = (1 - t) * slideFrom;
	return true;
}
