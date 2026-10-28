#include <windows.h>
#include <d2d1_1.h>
#include <wrl/client.h>
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include "activityIndicator.h"
#include "must.h"

using Microsoft::WRL::ComPtr;

namespace {

// CompActivityVisual (CompositionContextHelper.cpp:1456): an 80 x 80 box, the ring of radius 7 and stroke 1.5 under Scale 5.
const float kBox = 80.0f;
const float kRadius = 35.0f;
const float kStroke = 7.5f;
const double kPeriodMs = 2000.0;
// CompActivityVisual::StopAnimation (:1869) leaves Progress at 0.7.
const double kStoppedPhase = 0.7;
// ProgressRingForegroundTheme is AccentFillColorDefault, SystemAccentColorDark1 (Theme.cpp:262,266); this is the default accent's.
const Color kAccentDark1 = {0.0f, 0x5A / 255.0f, 0x9E / 255.0f, 1.0f};
const float kPi = 3.14159265358979f;

[[noreturn]] void refuse(const char *what, const char *got) {
	fprintf(stderr, "neon windows bridge: %s \"%s\"\n", what, got);
	fflush(stderr);
	abort();
}

int hexDigit(char c) {
	if (c >= '0' && c <= '9') return c - '0';
	if (c >= 'a' && c <= 'f') return c - 'a' + 10;
	if (c >= 'A' && c <= 'F') return c - 'A' + 10;
	return -1;
}

Color parseColor(const char *css) {
	const char *what = "ActivityIndicator color is not #rgb, #rrggbb or #rrggbbaa:";
	size_t n = strlen(css);
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

D2D1_POINT_2F onCircle(float centre, float radius, double degrees) {
	double radians = degrees * kPi / 180.0;
	return D2D1::Point2F(centre + radius * (float)cos(radians), centre + radius * (float)sin(radians));
}

}

ActivityIndicator::ActivityIndicator(ICompositionContext *context, IVisual *host) : context(context), host(host), color(kAccentDark1) {
	ring = context->CreateSpriteVisual();
	host->InsertAt(ring, 0);
}

ActivityIndicator::~ActivityIndicator() {
	host->Remove(ring);
	delete ring;
}

bool ActivityIndicator::SetProp(const char *name, const char *value) {
	if (!strcmp(name, "color")) {
		color = value[0] ? parseColor(value) : kAccentDark1;
		dirty = true;
		return true;
	}
	bool wasAnimating = animating, wasHiding = hidesWhenStopped;
	if (!strcmp(name, "animating")) animating = strcmp(value, "false") != 0;
	else if (!strcmp(name, "hidesWhenStopped")) hidesWhenStopped = strcmp(value, "false") != 0;
	else return false;
	if (animating != wasAnimating || hidesWhenStopped != wasHiding) update();
	return true;
}

// ActivityIndicatorComponentView::updateProps (ActivityIndicatorComponentView.cpp:63-75).
void ActivityIndicator::update() {
	visible = !(hidesWhenStopped && !animating);
	dirty = true;
	if (!animating && !hidesWhenStopped) {
		stopped = true;
	} else if (stopped) {
		stopped = false;
		startMs = -1;
	}
}

void ActivityIndicator::Step(int32_t pixelWidth, int32_t pixelHeight, double nowMs) {
	bool moved = pixelWidth != boxWidth || pixelHeight != boxHeight;
	bool placed = moved || dirty;
	if (!placed && !Running()) return;
	boxWidth = pixelWidth;
	boxHeight = pixelHeight;
	int32_t wanted = std::min(pixelWidth, pixelHeight);
	if (!visible || wanted <= 0) {
		if (placed) ring->Opacity(0.0f);
		dirty = false;
		return;
	}
	if (startMs < 0) startMs = nowMs;
	if (wanted != side || !surface) {
		side = wanted;
		surface.reset(context->CreateDrawingSurface(side, side));
		ring->Content(surface.get());
		ring->Size((float)side, (float)side);
	}
	if (placed) {
		ring->Offset(floorf((pixelWidth - side) / 2.0f), floorf((pixelHeight - side) / 2.0f));
		ring->Opacity(1.0f);
	}
	draw(side, stopped ? kStoppedPhase : fmod(nowMs - startMs, kPeriodMs) / kPeriodMs);
	dirty = false;
}

// The lottie's keyframes (CompositionContextHelper.cpp:1633-1687). Its cubic-bezier easing (0.167,0.167)-(0.833,0.833)
// lies on the diagonal, so it is linear. The container rotates 900 degrees per period. In the first half an arc grows from
// the path start to half the ring (TrimEnd 0 to 0.5, Foreground_1 opaque); in the second its start runs up to the end
// (TrimStart 0 to 0.5, Foreground_0 opaque).
void ActivityIndicator::draw(int32_t side, double phase) {
	float scale = (float)side / kBox;
	float centre = (float)side / 2.0f;
	float radius = kRadius * scale;
	double from = phase < 0.5 ? 0.0 : 180.0 * (2.0 * phase - 1.0);
	double to = phase < 0.5 ? 180.0 * 2.0 * phase : 180.0;
	to = std::max(to, from + 0.036);
	double turn = -90.0 + 900.0 * phase;

	ID2D1DeviceContext *dc = static_cast<ID2D1DeviceContext *>(surface->BeginDrawD2D(96.0f));
	ComPtr<ID2D1Factory> factory;
	dc->GetFactory(&factory);
	ComPtr<ID2D1PathGeometry> path;
	must(factory->CreatePathGeometry(&path), "CreatePathGeometry");
	ComPtr<ID2D1GeometrySink> sink;
	must(path->Open(&sink), "ID2D1PathGeometry::Open");
	sink->BeginFigure(onCircle(centre, radius, turn + from), D2D1_FIGURE_BEGIN_HOLLOW);
	sink->AddArc(D2D1::ArcSegment(onCircle(centre, radius, turn + to), D2D1::SizeF(radius, radius), 0.0f,
		D2D1_SWEEP_DIRECTION_CLOCKWISE, to - from >= 180.0 ? D2D1_ARC_SIZE_LARGE : D2D1_ARC_SIZE_SMALL));
	sink->EndFigure(D2D1_FIGURE_END_OPEN);
	must(sink->Close(), "ID2D1GeometrySink::Close");
	ComPtr<ID2D1StrokeStyle> round;
	must(factory->CreateStrokeStyle(D2D1::StrokeStyleProperties(D2D1_CAP_STYLE_ROUND, D2D1_CAP_STYLE_ROUND, D2D1_CAP_STYLE_ROUND, D2D1_LINE_JOIN_ROUND),
		nullptr, 0, &round), "CreateStrokeStyle");
	ComPtr<ID2D1SolidColorBrush> brush;
	must(dc->CreateSolidColorBrush(D2D1::ColorF(color.r, color.g, color.b, color.a), &brush), "CreateSolidColorBrush");
	dc->Clear(D2D1::ColorF(0, 0, 0, 0));
	dc->DrawGeometry(path.Get(), brush.Get(), kStroke * scale, round.Get());
	surface->EndDraw();
}
