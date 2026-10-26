#pragma once
#include "composition.h"

// macOS modal.m on this seam: animationType fade or slide, 0.3 s, started when the Modal joins the root.
class Modal {
public:
	bool SetProp(const char *name, const char *value);
	void Present(double nowMs, IVisual *visual, float pixelHeight);
	bool Step(double nowMs, IVisual *visual);
	bool Animating() const { return animating; }
	float SlideShift() const { return shift; }

private:
	enum class Animation { None, Fade, Slide };

	Animation animation = Animation::None;
	bool animating = false;
	double start = 0;
	float slideFrom = 0;
	float shift = 0;
};
