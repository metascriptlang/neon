#include <windows.h>
#include <atomic>
#include <string>
#include <thread>
#include "motionHarness.h"

static int g_blue[2];
static double g_atMs[2];
static std::atomic<int> g_ready{0};

static double nowMs() {
	LARGE_INTEGER frequency, counter;
	QueryPerformanceFrequency(&frequency);
	QueryPerformanceCounter(&counter);
	return (double)counter.QuadPart * 1000.0 / (double)frequency.QuadPart;
}

static void sample(POINT at, int index) {
	HDC screen = GetDC(nullptr);
	COLORREF color = GetPixel(screen, at.x, at.y);
	ReleaseDC(nullptr, screen);
	g_blue[index] = color == CLR_INVALID ? -1 : (int)GetBValue(color);
	g_atMs[index] = nowMs();
}

extern "C" void motionSampleScreenLater(const char *title, int32_t clientX, int32_t clientY, double firstMs, double secondMs) {
	g_ready = 0;
	HWND window = FindWindowA(nullptr, title);
	double scale = window ? GetDpiForWindow(window) / 96.0 : 1.0;
	POINT at = {(LONG)(clientX * scale), (LONG)(clientY * scale)};
	if (window) ClientToScreen(window, &at);
	std::thread([at, firstMs, secondMs]() {
		Sleep((DWORD)firstMs);
		sample(at, 0);
		Sleep((DWORD)(secondMs - firstMs));
		sample(at, 1);
		g_ready = 1;
	}).detach();
}

extern "C" int32_t motionSamplesReady(void) { return g_ready; }
extern "C" int32_t motionSampledBlue(int32_t index) { return g_blue[index & 1]; }
extern "C" double motionSampledAtMs(int32_t index) { return g_atMs[index & 1]; }
