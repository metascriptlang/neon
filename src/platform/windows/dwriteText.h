#pragma once
#include <dwrite.h>
#include <wrl/client.h>
#include <cstdint>
#include <memory>
#include <string>
#include <vector>
#include "composition.h"

// One run of a label's text, in UTF-16 units; a run without colour draws in the label's.
struct TextRunStyle {
	uint32_t start = 0;
	uint32_t length = 0;
	bool hasColor = false;
	Color color = {0, 0, 0, 1};
	float size = 17;
	bool bold = false;
	bool italic = false;
	bool underline = false;
	bool strike = false;
	int32_t tag = 0;
};

// A label keeps one DirectWrite layout. Text, size, weight, style and decoration rebuild it; a new width only
// breaks lines again (SetMaxWidth); a colour reaches the glyphs at draw time as a drawing effect, so a change of
// colour alone redraws without laying out again.
class TextLabel {
public:
	void SetText(const char *utf8);
	void SetRuns(const char *encoded);
	void SetColor(Color color);
	void SetFont(float size, bool bold);
	void SetFamily(const char *utf8);
	void SetAlignment(const char *value);
	void SetWritingDirection(const char *value);
	void Invalidate() { paintDirty = true; }
	const std::wstring &Text() const { return text; }
	void Measure(float maxWidth, float scale, float *width, float *height);
	bool NeedsDraw(int32_t pixelWidth, int32_t pixelHeight) const;
	void Draw(ICompositionContext *context, IVisual *visual, int32_t pixelWidth, int32_t pixelHeight, float scale);
	// The tag of the run under a point in the label's own points, 0 over an untagged run or no text.
	int32_t TagAt(float x, float y);
	static int LayoutsBuilt();

private:
	IDWriteTextLayout *Layout(float width, float height);

	std::wstring text;
	std::vector<TextRunStyle> runs;
	Color color = {0, 0, 0, 1};
	float size = 17;
	bool bold = false;
	std::wstring family = L"Segoe UI";
	int alignment = 0;
	DWRITE_READING_DIRECTION readingDirection = DWRITE_READING_DIRECTION_LEFT_TO_RIGHT;
	bool layoutStale = true;
	bool paintDirty = true;
	Microsoft::WRL::ComPtr<IDWriteTextLayout> layout;
	float layoutWidth = -1, layoutHeight = -1;
	int32_t drawnWidth = 0, drawnHeight = 0;
	float drawnScale = 1;
	std::unique_ptr<IDrawingSurface> surface;
};
