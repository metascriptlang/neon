#pragma once
#include <memory>
#include <string>
#include "composition.h"

class TextLabel {
public:
	void SetText(const char *utf8);
	void SetColor(Color color);
	void SetFont(float size, bool bold);
	void SetAlignment(const char *value);
	void Invalidate() { dirty = true; }
	void Measure(float maxWidth, float scale, float *width, float *height);
	bool NeedsDraw(int32_t pixelWidth, int32_t pixelHeight) const;
	void Draw(ICompositionContext *context, IVisual *visual, int32_t pixelWidth, int32_t pixelHeight, float scale);

private:
	std::wstring text;
	Color color = {0, 0, 0, 1};
	float size = 17;
	bool bold = false;
	int alignment = 0;
	bool dirty = true;
	int32_t drawnWidth = 0, drawnHeight = 0;
	std::unique_ptr<IDrawingSurface> surface;
};
