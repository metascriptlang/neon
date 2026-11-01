#pragma once
#include <cstdint>
#include <vector>

struct Color {
	float r, g, b, a;
};

// One value over time, as DirectComposition plays it: each segment holds value + slope * (t - begin)
// from its begin (seconds after the Animated call that hands it over) until the next one; then it either repeats
// from repeatBegin for repeatSeconds, or holds endValue from endSeconds.
struct CurveSegment {
	double begin;
	float value, slope;
};

struct Curve {
	std::vector<CurveSegment> segments;
	bool repeats = false;
	double repeatBegin = 0, repeatSeconds = 0;
	double endSeconds = 0;
	float endValue = 0;
};

struct IDrawingSurface {
	virtual ~IDrawingSurface() {}
	virtual void *BeginDrawD2D(float dpi) = 0;
	virtual void EndDraw() = 0;
};

struct IVisual {
	virtual ~IVisual() {}
	virtual void InsertAt(IVisual *visual, int32_t index) = 0;
	virtual void Remove(IVisual *visual) = 0;
	virtual void Opacity(float opacity) = 0;
	virtual void TransformMatrix(const float m[6]) = 0;
	virtual void AnimatedOpacity(const Curve &curve) = 0;
	// m11, m12, m21, m22, dx, dy, as TransformMatrix takes them.
	virtual void AnimatedTransform(const Curve curves[6]) = 0;
	virtual void Size(float width, float height) = 0;
	virtual void Offset(float x, float y) = 0;
	virtual void CornerRadius(float radius) = 0;
	virtual void ClipsChildren(bool clips) = 0;
	virtual void Brush(Color color) = 0;
	virtual void Content(IDrawingSurface *surface) = 0;
};

struct ICompositionContext {
	virtual ~ICompositionContext() {}
	virtual IVisual *CreateSpriteVisual() = 0;
	virtual IDrawingSurface *CreateDrawingSurface(int32_t pixelWidth, int32_t pixelHeight) = 0;
	virtual void Commit() = 0;
};
