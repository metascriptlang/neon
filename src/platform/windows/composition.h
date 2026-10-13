#pragma once
#include <cstdint>

struct Color {
	float r, g, b, a;
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
	virtual void Size(float width, float height) = 0;
	virtual void Offset(float x, float y) = 0;
	virtual void CornerRadius(float radius) = 0;
	virtual void Brush(Color color) = 0;
	virtual void Content(IDrawingSurface *surface) = 0;
};

struct ICompositionContext {
	virtual ~ICompositionContext() {}
	virtual IVisual *CreateSpriteVisual() = 0;
	virtual IDrawingSurface *CreateDrawingSurface(int32_t pixelWidth, int32_t pixelHeight) = 0;
	virtual void Commit() = 0;
};
