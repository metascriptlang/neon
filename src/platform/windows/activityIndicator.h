#pragma once
#include <cstdint>
#include <memory>
#include "composition.h"

// RNW ActivityIndicatorComponentView on this seam. Its CompActivityVisual plays a 2 s lottie ProgressRing through
// composition animations; this seam has no animation object, so the bridge steps the phase per frame from the clock
// and redraws the ring into a surface.
class ActivityIndicator {
public:
	ActivityIndicator(ICompositionContext *context, IVisual *host);
	~ActivityIndicator();
	bool SetProp(const char *name, const char *value);
	// The view's box in pixels. Draws when the phase, a prop or the box changed.
	void Step(int32_t pixelWidth, int32_t pixelHeight, double nowMs);
	bool Running() const { return visible && !stopped; }

private:
	void update();
	void draw(int32_t side, double phase);

	ICompositionContext *context;
	IVisual *host;
	IVisual *ring;
	std::unique_ptr<IDrawingSurface> surface;
	bool animating = true;
	bool hidesWhenStopped = true;
	bool visible = true;
	bool stopped = false;
	bool dirty = true;
	Color color;
	int32_t boxWidth = -1, boxHeight = -1, side = 0;
	double startMs = -1;
};
