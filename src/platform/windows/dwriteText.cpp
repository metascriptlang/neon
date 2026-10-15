#include <windows.h>
#include <d2d1_1.h>
#include <dwrite.h>
#include <wrl/client.h>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include "dwriteText.h"
#include "must.h"

using Microsoft::WRL::ComPtr;

namespace {

const float kUnboundedHeight = 1e6f;
int g_layoutsBuilt = 0;

IDWriteFactory *factory() {
	static IDWriteFactory *shared = nullptr;
	if (!shared) {
		must(DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED, __uuidof(IDWriteFactory), (IUnknown **)&shared), "DWriteCreateFactory");
	}
	return shared;
}

[[noreturn]] void refuse(const char *what, const char *value) {
	fprintf(stderr, "neon windows bridge: %s \"%s\"\n", what, value);
	fflush(stderr);
	abort();
}

std::wstring widen(const char *utf8, size_t bytes, const char *what) {
	std::wstring wide;
	if (bytes == 0) return wide;
	int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, utf8, (int)bytes, nullptr, 0);
	if (length == 0) refuse(what, "invalid UTF-8");
	wide.resize((size_t)length);
	MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, utf8, (int)bytes, &wide[0], length);
	return wide;
}

int hexDigit(char c) {
	if (c >= '0' && c <= '9') return c - '0';
	if (c >= 'a' && c <= 'f') return c - 'a' + 10;
	if (c >= 'A' && c <= 'F') return c - 'A' + 10;
	return -1;
}

// "#rgb", "#rrggbb" or "#rrggbbaa", the forms Neon's style colours take; anything else is refused by name.
Color parseColor(const std::string &css) {
	size_t n = css.size();
	if (n < 4 || css[0] != '#' || (n != 4 && n != 7 && n != 9)) refuse("textSpans colour is not #rgb, #rrggbb or #rrggbbaa:", css.c_str());
	int digits[8];
	for (size_t i = 1; i < n; i++) {
		digits[i - 1] = hexDigit(css[i]);
		if (digits[i - 1] < 0) refuse("textSpans colour has a non-hex digit:", css.c_str());
	}
	if (n == 4) return Color{digits[0] * 17 / 255.0f, digits[1] * 17 / 255.0f, digits[2] * 17 / 255.0f, 1};
	float a = n == 9 ? (digits[6] * 16 + digits[7]) / 255.0f : 1;
	return Color{(digits[0] * 16 + digits[1]) / 255.0f, (digits[2] * 16 + digits[3]) / 255.0f, (digits[4] * 16 + digits[5]) / 255.0f, a};
}

bool sameShape(const TextRunStyle &a, const TextRunStyle &b) {
	return a.start == b.start && a.length == b.length && a.size == b.size && a.bold == b.bold && a.italic == b.italic &&
		a.underline == b.underline && a.strike == b.strike;
}

}

int TextLabel::LayoutsBuilt() { return g_layoutsBuilt; }

void TextLabel::SetText(const char *utf8) {
	std::wstring wide = widen(utf8, strlen(utf8), "niSetText received");
	if (wide == text && runs.empty()) return;
	text = wide;
	runs.clear();
	layoutStale = true;
}

// Neon's textSpans: records split by U+001E, each text, colour, size, bold, italic, underline, line-through and
// press tag, split by U+001F (src/platform/native/host.ms encodeSpan).
void TextLabel::SetRuns(const char *encoded) {
	std::wstring nextText;
	std::vector<TextRunStyle> next;
	const char *record = encoded;
	while (*record) {
		const char *fields[8];
		size_t lengths[8];
		const char *at = record;
		int count = 0;
		while (count < 8) {
			const char *end = at;
			while (*end && *end != '\x1f' && *end != '\x1e') end++;
			fields[count] = at;
			lengths[count] = (size_t)(end - at);
			count++;
			if (*end != '\x1f') {
				at = end;
				break;
			}
			at = end + 1;
		}
		if (count != 8) refuse("textSpans record does not have 8 fields:", record);
		TextRunStyle run;
		std::wstring piece = widen(fields[0], lengths[0], "textSpans text is");
		run.start = (uint32_t)nextText.size();
		run.length = (uint32_t)piece.size();
		nextText += piece;
		std::string css(fields[1], lengths[1]);
		run.hasColor = !css.empty();
		if (run.hasColor) run.color = parseColor(css);
		run.size = strtof(std::string(fields[2], lengths[2]).c_str(), nullptr);
		run.bold = fields[3][0] == '1';
		run.italic = fields[4][0] == '1';
		run.underline = fields[5][0] == '1';
		run.strike = fields[6][0] == '1';
		run.tag = (int32_t)strtol(std::string(fields[7], lengths[7]).c_str(), nullptr, 10);
		next.push_back(run);
		record = *at == '\x1e' ? at + 1 : at;
	}
	bool shapeKept = nextText == text && next.size() == runs.size();
	for (size_t i = 0; shapeKept && i < next.size(); i++) shapeKept = sameShape(next[i], runs[i]);
	text = nextText;
	runs = next;
	if (shapeKept) paintDirty = true;
	else layoutStale = true;
}

void TextLabel::SetColor(Color c) {
	if (c.r == color.r && c.g == color.g && c.b == color.b && c.a == color.a) return;
	color = c;
	paintDirty = true;
}

void TextLabel::SetFont(float s, bool b) {
	if (s == size && b == bold) return;
	size = s;
	bold = b;
	layoutStale = true;
}

void TextLabel::SetFamily(const char *utf8) {
	std::wstring next = utf8[0] ? widen(utf8, strlen(utf8), "fontFamily is") : std::wstring(L"Segoe UI");
	if (next == family) return;
	if (utf8[0]) {
		ComPtr<IDWriteFontCollection> fonts;
		must(factory()->GetSystemFontCollection(&fonts), "GetSystemFontCollection");
		UINT32 index = 0;
		BOOL exists = FALSE;
		must(fonts->FindFamilyName(next.c_str(), &index, &exists), "FindFamilyName");
		if (!exists) refuse("fontFamily names no font family installed on this system:", utf8);
	}
	family = next;
	layoutStale = true;
}

void TextLabel::SetAlignment(const char *value) {
	int next;
	if (!strcmp(value, "auto") || !strcmp(value, "left")) next = DWRITE_TEXT_ALIGNMENT_LEADING;
	else if (!strcmp(value, "right")) next = DWRITE_TEXT_ALIGNMENT_TRAILING;
	else if (!strcmp(value, "center")) next = DWRITE_TEXT_ALIGNMENT_CENTER;
	else if (!strcmp(value, "justify")) next = DWRITE_TEXT_ALIGNMENT_JUSTIFIED;
	else refuse("niSetProp(textAlign) is not implemented on Windows yet for", value);
	if (next == alignment) return;
	alignment = next;
	layoutStale = true;
}

IDWriteTextLayout *TextLabel::Layout(float width, float height) {
	if (layoutStale || !layout) {
		ComPtr<IDWriteTextFormat> format;
		must(factory()->CreateTextFormat(family.c_str(), nullptr, bold ? DWRITE_FONT_WEIGHT_BOLD : DWRITE_FONT_WEIGHT_NORMAL,
			DWRITE_FONT_STYLE_NORMAL, DWRITE_FONT_STRETCH_NORMAL, size, L"", &format), "CreateTextFormat");
		layout.Reset();
		must(factory()->CreateTextLayout(text.c_str(), (UINT32)text.size(), format.Get(), width, height, &layout), "CreateTextLayout");
		must(layout->SetTextAlignment(static_cast<DWRITE_TEXT_ALIGNMENT>(alignment)), "SetTextAlignment");
		for (const TextRunStyle &run : runs) {
			DWRITE_TEXT_RANGE range = {run.start, run.length};
			must(layout->SetFontSize(run.size, range), "SetFontSize");
			must(layout->SetFontWeight(run.bold ? DWRITE_FONT_WEIGHT_BOLD : DWRITE_FONT_WEIGHT_NORMAL, range), "SetFontWeight");
			must(layout->SetFontStyle(run.italic ? DWRITE_FONT_STYLE_ITALIC : DWRITE_FONT_STYLE_NORMAL, range), "SetFontStyle");
			must(layout->SetUnderline(run.underline, range), "SetUnderline");
			must(layout->SetStrikethrough(run.strike, range), "SetStrikethrough");
		}
		g_layoutsBuilt += 1;
		layoutStale = false;
		layoutWidth = width;
		layoutHeight = height;
		paintDirty = true;
		return layout.Get();
	}
	if (width != layoutWidth) {
		must(layout->SetMaxWidth(width), "SetMaxWidth");
		layoutWidth = width;
	}
	if (height != layoutHeight) {
		must(layout->SetMaxHeight(height), "SetMaxHeight");
		layoutHeight = height;
	}
	return layout.Get();
}

void TextLabel::Measure(float maxWidth, float scale, float *width, float *height) {
	DWRITE_TEXT_METRICS metrics;
	must(Layout(maxWidth, kUnboundedHeight)->GetMetrics(&metrics), "GetMetrics");
	*width = ceilf(metrics.width * scale) / scale;
	*height = ceilf(metrics.height * scale) / scale;
}

bool TextLabel::NeedsDraw(int32_t pixelWidth, int32_t pixelHeight) const {
	return layoutStale || paintDirty || pixelWidth != drawnWidth || pixelHeight != drawnHeight;
}

void TextLabel::Draw(ICompositionContext *context, IVisual *visual, int32_t pixelWidth, int32_t pixelHeight, float scale) {
	bool resized = pixelWidth != drawnWidth || pixelHeight != drawnHeight;
	drawnWidth = pixelWidth;
	drawnHeight = pixelHeight;
	drawnScale = scale;
	if (text.empty() || pixelWidth <= 0 || pixelHeight <= 0) {
		paintDirty = false;
		surface.reset();
		visual->Content(nullptr);
		return;
	}
	if (!surface || resized) {
		surface.reset(context->CreateDrawingSurface(pixelWidth, pixelHeight));
		visual->Content(surface.get());
	}
	IDWriteTextLayout *drawn = Layout(pixelWidth / scale, pixelHeight / scale);
	paintDirty = false;
	ID2D1DeviceContext *dc = static_cast<ID2D1DeviceContext *>(surface->BeginDrawD2D(96.0f * scale));
	dc->Clear(D2D1::ColorF(0, 0, 0, 0));
	ComPtr<ID2D1SolidColorBrush> brush;
	must(dc->CreateSolidColorBrush(D2D1::ColorF(color.r, color.g, color.b, color.a), &brush), "CreateSolidColorBrush");
	std::vector<ComPtr<ID2D1SolidColorBrush>> runBrushes;
	for (const TextRunStyle &run : runs) {
		DWRITE_TEXT_RANGE range = {run.start, run.length};
		if (!run.hasColor) {
			must(drawn->SetDrawingEffect(nullptr, range), "SetDrawingEffect");
			continue;
		}
		ComPtr<ID2D1SolidColorBrush> runBrush;
		must(dc->CreateSolidColorBrush(D2D1::ColorF(run.color.r, run.color.g, run.color.b, run.color.a), &runBrush), "CreateSolidColorBrush");
		must(drawn->SetDrawingEffect(runBrush.Get(), range), "SetDrawingEffect");
		runBrushes.push_back(runBrush);
	}
	dc->DrawTextLayout(D2D1::Point2F(0, 0), drawn, brush.Get(), D2D1_DRAW_TEXT_OPTIONS_ENABLE_COLOR_FONT);
	surface->EndDraw();
}

int32_t TextLabel::TagAt(float x, float y) {
	if (runs.empty() || drawnWidth <= 0 || drawnHeight <= 0) return 0;
	BOOL trailing = FALSE, inside = FALSE;
	DWRITE_HIT_TEST_METRICS metrics;
	must(Layout(drawnWidth / drawnScale, drawnHeight / drawnScale)->HitTestPoint(x, y, &trailing, &inside, &metrics), "HitTestPoint");
	if (!inside) return 0;
	for (const TextRunStyle &run : runs) {
		if (metrics.textPosition >= run.start && metrics.textPosition < run.start + run.length) return run.tag;
	}
	return 0;
}
