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

IDWriteFactory *factory() {
	static IDWriteFactory *shared = nullptr;
	if (!shared) {
		must(DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED, __uuidof(IDWriteFactory), (IUnknown **)&shared), "DWriteCreateFactory");
	}
	return shared;
}

ComPtr<IDWriteTextLayout> makeLayout(const std::wstring &text, float size, bool bold, int alignment, float width, float height) {
	ComPtr<IDWriteTextFormat> format;
	must(factory()->CreateTextFormat(L"Segoe UI", nullptr, bold ? DWRITE_FONT_WEIGHT_BOLD : DWRITE_FONT_WEIGHT_NORMAL,
		DWRITE_FONT_STYLE_NORMAL, DWRITE_FONT_STRETCH_NORMAL, size, L"", &format), "CreateTextFormat");
	ComPtr<IDWriteTextLayout> layout;
	must(factory()->CreateTextLayout(text.c_str(), (UINT32)text.size(), format.Get(), width, height, &layout), "CreateTextLayout");
	must(layout->SetTextAlignment(static_cast<DWRITE_TEXT_ALIGNMENT>(alignment)), "SetTextAlignment");
	return layout;
}

}

void TextLabel::SetText(const char *utf8) {
	std::wstring wide;
	int length = utf8[0] ? MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, utf8, -1, nullptr, 0) : 1;
	if (length == 0) {
		fprintf(stderr, "neon windows bridge: niSetText received invalid UTF-8\n");
		fflush(stderr);
		abort();
	}
	wide.resize((size_t)length - 1);
	if (length > 1) MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, utf8, -1, &wide[0], length);
	if (wide == text) return;
	text = wide;
	dirty = true;
}

void TextLabel::SetColor(Color c) {
	if (c.r == color.r && c.g == color.g && c.b == color.b && c.a == color.a) return;
	color = c;
	dirty = true;
}

void TextLabel::SetFont(float s, bool b) {
	if (s == size && b == bold) return;
	size = s;
	bold = b;
	dirty = true;
}

void TextLabel::SetAlignment(const char *value) {
	int next;
	if (!strcmp(value, "auto") || !strcmp(value, "left")) next = DWRITE_TEXT_ALIGNMENT_LEADING;
	else if (!strcmp(value, "right")) next = DWRITE_TEXT_ALIGNMENT_TRAILING;
	else if (!strcmp(value, "center")) next = DWRITE_TEXT_ALIGNMENT_CENTER;
	else if (!strcmp(value, "justify")) next = DWRITE_TEXT_ALIGNMENT_JUSTIFIED;
	else {
		fprintf(stderr, "neon windows bridge: niSetProp(textAlign=%s) is not implemented on Windows yet\n", value);
		fflush(stderr);
		abort();
	}
	if (next == alignment) return;
	alignment = next;
	dirty = true;
}

void TextLabel::Measure(float maxWidth, float scale, float *width, float *height) {
	ComPtr<IDWriteTextLayout> layout = makeLayout(text, size, bold, alignment, maxWidth, kUnboundedHeight);
	DWRITE_TEXT_METRICS metrics;
	must(layout->GetMetrics(&metrics), "GetMetrics");
	*width = ceilf(metrics.width * scale) / scale;
	*height = ceilf(metrics.height * scale) / scale;
}

bool TextLabel::NeedsDraw(int32_t pixelWidth, int32_t pixelHeight) const {
	return dirty || pixelWidth != drawnWidth || pixelHeight != drawnHeight;
}

void TextLabel::Draw(ICompositionContext *context, IVisual *visual, int32_t pixelWidth, int32_t pixelHeight, float scale) {
	bool resized = pixelWidth != drawnWidth || pixelHeight != drawnHeight;
	dirty = false;
	drawnWidth = pixelWidth;
	drawnHeight = pixelHeight;
	if (text.empty() || pixelWidth <= 0 || pixelHeight <= 0) {
		surface.reset();
		visual->Content(nullptr);
		return;
	}
	if (!surface || resized) {
		surface.reset(context->CreateDrawingSurface(pixelWidth, pixelHeight));
		visual->Content(surface.get());
	}
	ComPtr<IDWriteTextLayout> layout = makeLayout(text, size, bold, alignment, pixelWidth / scale, pixelHeight / scale);
	ID2D1DeviceContext *dc = static_cast<ID2D1DeviceContext *>(surface->BeginDrawD2D(96.0f * scale));
	dc->Clear(D2D1::ColorF(0, 0, 0, 0));
	ComPtr<ID2D1SolidColorBrush> brush;
	must(dc->CreateSolidColorBrush(D2D1::ColorF(color.r, color.g, color.b, color.a), &brush), "CreateSolidColorBrush");
	dc->DrawTextLayout(D2D1::Point2F(0, 0), layout.Get(), brush.Get(), D2D1_DRAW_TEXT_OPTIONS_ENABLE_COLOR_FONT);
	surface->EndDraw();
}
