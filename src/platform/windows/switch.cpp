#include <windows.h>
#include <d2d1_1.h>
#include <wrl/client.h>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include "must.h"
#include "switch.h"

using Microsoft::WRL::ComPtr;

namespace {

// RNW SwitchComponentView.cpp SwitchConstants (:15-25), points.
const float kThumbMargin = 4.0f;
const float kThumbWidth = 12.0f;
const float kThumbWidthHover = 14.0f;
const float kThumbWidthPressed = 17.0f;
const float kTrackWidth = 40.0f;
const float kTrackHeight = 20.0f;
const float kTrackCornerRadius = 10.0f;
const float kTrackStrokeThickness = 1.0f;

// RNW Theme.cpp at aedf6c5, the light theme: ToggleSwitch* names (:237-260) resolved through s_lightColors (:286-313).
// AccentDark1 is the system accent in RNW (:127); the Windows default accent's dark1 stands in until UISettings is read.
const Color kAccentDark1 = {0, 0x5F / 255.0f, 0xB8 / 255.0f, 1};
const Color kAccentOnPointerOver = {0, 0x5F / 255.0f, 0xB8 / 255.0f, 0.9f};
const Color kAccentOnPressed = {0, 0x5F / 255.0f, 0xB8 / 255.0f, 0.8f};
const Color kAccentFillColorDisabled = {0, 0, 0, 0x37 / 255.0f};
const Color kControlAltFillColorSecondary = {0, 0, 0, 0x06 / 255.0f};
const Color kControlAltFillColorTertiary = {0, 0, 0, 0x0F / 255.0f};
const Color kControlAltFillColorQuarternary = {0, 0, 0, 0x18 / 255.0f};
const Color kControlAltFillColorDisabled = {1, 1, 1, 0};
const Color kControlStrongStrokeColorDefault = {0, 0, 0, 0x72 / 255.0f};
const Color kControlStrongStrokeColorDisabled = {0, 0, 0, 0x37 / 255.0f};
const Color kTextFillColorSecondary = {0, 0, 0, 0x9E / 255.0f};
const Color kTextFillColorDisabled = {0, 0, 0, 0x5C / 255.0f};
const Color kTextOnAccentFillColorPrimary = {1, 1, 1, 1};

[[noreturn]] void refuse(const char *what, const char *value) {
	fprintf(stderr, "neon windows bridge: Switch %s \"%s\"\n", what, value);
	fflush(stderr);
	abort();
}

bool flag(const char *name, const char *value) {
	if (!strcmp(value, "true")) return true;
	if (!strcmp(value, "false") || value[0] == '\0') return false;
	char what[96];
	snprintf(what, sizeof what, "%s is not true or false:", name);
	refuse(what, value);
}

int hexDigit(char c) {
	if (c >= '0' && c <= '9') return c - '0';
	if (c >= 'a' && c <= 'f') return c - 'a' + 10;
	if (c >= 'A' && c <= 'F') return c - 'A' + 10;
	return -1;
}

Color parseColor(const char *name, const char *css) {
	size_t n = strlen(css);
	char what[96];
	snprintf(what, sizeof what, "%s is not #rgb, #rrggbb or #rrggbbaa:", name);
	if (n < 4 || css[0] != '#' || (n != 4 && n != 7 && n != 9)) refuse(what, css);
	int digits[8];
	for (size_t i = 1; i < n; i++) {
		digits[i - 1] = hexDigit(css[i]);
		if (digits[i - 1] < 0) refuse(what, css);
	}
	if (n == 4) return Color{digits[0] * 17 / 255.0f, digits[1] * 17 / 255.0f, digits[2] * 17 / 255.0f, 1};
	float a = n == 9 ? (digits[6] * 16 + digits[7]) / 255.0f : 1;
	return Color{(digits[0] * 16 + digits[1]) / 255.0f, (digits[2] * 16 + digits[3]) / 255.0f, (digits[4] * 16 + digits[5]) / 255.0f, a};
}

bool same(Color a, Color b) { return a.r == b.r && a.g == b.g && a.b == b.b && a.a == b.a; }

}

SwitchControl::SwitchControl(ICompositionContext *context, IVisual *root) : context(context), root(root) {
	track = context->CreateSpriteVisual();
	thumb = context->CreateSpriteVisual();
	root->InsertAt(track, 0);
	track->InsertAt(thumb, 0);
}

SwitchControl::~SwitchControl() {
	track->Remove(thumb);
	root->Remove(track);
	delete thumb;
	delete track;
}

void SwitchControl::Measure(float *w, float *h) {
	*w = kTrackWidth;
	*h = kTrackHeight;
}

bool SwitchControl::SetProp(const char *name, const char *text) {
	if (!strcmp(name, "value")) value = flag(name, text);
	else if (!strcmp(name, "disabled")) disabled = flag(name, text);
	else if (!strcmp(name, "thumbColor")) {
		hasThumbColor = text[0] != '\0';
		if (hasThumbColor) thumbColor = parseColor(name, text);
	} else if (!strcmp(name, "trackColorOn")) {
		hasOnColor = text[0] != '\0';
		if (hasOnColor) onColor = parseColor(name, text);
	} else if (!strcmp(name, "trackColorOff")) {
		hasOffColor = text[0] != '\0';
		if (hasOffColor) offColor = parseColor(name, text);
	} else return false;
	Update();
	return true;
}

// RNW updateLayoutMetrics (:100): the track is centred in the frame at its own size, whatever the frame is.
void SwitchControl::Layout(float newWidth, float newHeight, float newScale) {
	width = newWidth;
	height = newHeight;
	scale = newScale;
	Update();
}

void SwitchControl::SetHovered(bool on) {
	if (hovered == on) return;
	hovered = on;
	Update();
}

void SwitchControl::SetPressed(bool on) {
	if (pressed == on) return;
	pressed = on;
	Update();
}

// RNW updateVisuals (:128): the colours of the state, the thumb's size by pointer state, and where the value puts it.
void SwitchControl::Update() {
	if (scale <= 0) return;
	Color fill, stroke, thumbFill;
	if (value) {
		fill = stroke = disabled ? kAccentFillColorDisabled : pressed ? kAccentOnPressed : hovered ? kAccentOnPointerOver : kAccentDark1;
		thumbFill = kTextOnAccentFillColorPrimary;
	} else {
		fill = disabled ? kControlAltFillColorDisabled : pressed ? kControlAltFillColorQuarternary : hovered ? kControlAltFillColorTertiary : kControlAltFillColorSecondary;
		stroke = disabled ? kControlStrongStrokeColorDisabled : kControlStrongStrokeColorDefault;
		thumbFill = disabled ? kTextFillColorDisabled : kTextFillColorSecondary;
	}

	float thumbW = kThumbWidth, thumbH = kThumbWidth;
	if (!disabled && pressed) {
		thumbW = kThumbWidthPressed;
		thumbH = kThumbWidthHover;
	} else if (!disabled && hovered) {
		thumbW = kThumbWidthHover;
		thumbH = kThumbWidthHover;
	}

	if (!disabled && hasThumbColor) thumbFill = thumbColor;
	if (!disabled && hasOnColor && value) fill = onColor;
	else if (!disabled && hasOffColor && !value) fill = offColor;

	bool outlined = (!hasOnColor && value) || (!hasOffColor && !value);
	float thickness = outlined ? roundf(kTrackStrokeThickness * scale) : 0;

	int32_t trackW = (int32_t)roundf(kTrackWidth * scale), trackH = (int32_t)roundf(kTrackHeight * scale);
	DrawTrack(trackW, trackH, fill, stroke, thickness);
	track->Size((float)trackW, (float)trackH);
	track->Offset(roundf((width - kTrackWidth) * scale / 2.0f), roundf((height - kTrackHeight) * scale / 2.0f));

	float offsetY = (kTrackHeight - thumbH) * scale / 2.0f;
	thumb->Offset(roundf(value ? (kTrackWidth - (kThumbMargin + thumbW)) * scale : kThumbMargin * scale), roundf(offsetY));
	thumb->Size(roundf(thumbW * scale), roundf(thumbH * scale));
	thumb->CornerRadius(roundf(thumbH * scale) / 2.0f);
	thumb->Brush(thumbFill);
}

// The track is a rounded rectangle of fill and, when outlined, a ring of stroke around it, drawn apart so that a
// translucent stroke does not tint the fill. Pixels, at 96 dpi, as the visual's own fill is drawn.
void SwitchControl::DrawTrack(int32_t pixelWidth, int32_t pixelHeight, Color fill, Color stroke, float thickness) {
	if (surface && pixelWidth == drawnWidth && pixelHeight == drawnHeight && same(fill, drawnFill) && same(stroke, drawnStroke) &&
		thickness == drawnThickness) return;
	if (!surface || pixelWidth != drawnWidth || pixelHeight != drawnHeight) {
		surface.reset(context->CreateDrawingSurface(pixelWidth, pixelHeight));
		track->Content(surface.get());
	}
	drawnWidth = pixelWidth;
	drawnHeight = pixelHeight;
	drawnFill = fill;
	drawnStroke = stroke;
	drawnThickness = thickness;

	ID2D1DeviceContext *dc = static_cast<ID2D1DeviceContext *>(surface->BeginDrawD2D(96.0f));
	dc->Clear(D2D1::ColorF(0, 0, 0, 0));
	float radius = kTrackCornerRadius * scale;
	float w = (float)pixelWidth, h = (float)pixelHeight;
	ComPtr<ID2D1SolidColorBrush> brush;
	must(dc->CreateSolidColorBrush(D2D1::ColorF(fill.r, fill.g, fill.b, fill.a), &brush), "CreateSolidColorBrush");
	dc->FillRoundedRectangle(D2D1::RoundedRect(D2D1::RectF(thickness, thickness, w - thickness, h - thickness), radius - thickness, radius - thickness), brush.Get());
	if (thickness > 0) {
		brush->SetColor(D2D1::ColorF(stroke.r, stroke.g, stroke.b, stroke.a));
		float half = thickness / 2.0f;
		dc->DrawRoundedRectangle(D2D1::RoundedRect(D2D1::RectF(half, half, w - half, h - half), radius - half, radius - half), brush.Get(), thickness);
	}
	surface->EndDraw();
}
