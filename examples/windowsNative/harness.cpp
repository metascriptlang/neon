#include <windows.h>
#include <d3d11.h>
#include <d2d1_1.h>
#include <dcomp.h>
#include <dwmapi.h>
#include <dwrite.h>
#include <wrl/client.h>
#include <cstdio>
#include <cstdlib>
#include <cmath>
#include <cstring>
#include <map>
#include <string>
#include <vector>
#include "harness.h"
#include "../../src/platform/windows/handoff.h"

using Microsoft::WRL::ComPtr;

namespace {

struct Expectation {
	std::string name;
	int x, y, r, g, b;
};

struct Centre {
	std::string name, layout;
	int left, top, r, g, b;
};

struct Count {
	std::string name;
	int x, y, width, height, r, g, b, tolerance, minCount, maxCount;
};

struct SizeCheck {
	std::string layout, text;
	float fontSize;
	int bold;
	float maxWidth;
};

const int kTolerance = 3;

HWND g_window = nullptr;
bool g_check = false;
UINT g_dpi = 96;
std::vector<Expectation> g_expectations;
std::vector<Centre> g_centres;
std::vector<Count> g_counts;
std::vector<SizeCheck> g_sizes;
std::map<std::string, std::pair<float, float>> g_layouts;
ComPtr<ID3D11Device> g_d3d;
ComPtr<ID2D1Factory1> g_d2dFactory;
ComPtr<ID2D1Device> g_d2dDevice;
ComPtr<IDCompositionDesktopDevice> g_dcomp;
ComPtr<IDCompositionTarget> g_target;
ComPtr<IDCompositionVisual2> g_root;

void must(HRESULT hr, const char *what) {
	if (SUCCEEDED(hr)) return;
	fprintf(stderr, "harness: %s failed, HRESULT 0x%08lx\n", what, (unsigned long)hr);
	fflush(stderr);
	exit(2);
}

LRESULT CALLBACK windowProc(HWND window, UINT message, WPARAM wParam, LPARAM lParam) {
	if (message == WM_DESTROY) {
		PostQuitMessage(0);
		return 0;
	}
	return DefWindowProcW(window, message, wParam, lParam);
}

bool pumpMessages() {
	MSG message;
	while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
		if (message.message == WM_QUIT) return false;
		TranslateMessage(&message);
		DispatchMessageW(&message);
	}
	return true;
}

bool ownsPoint(POINT at) { return GetAncestor(WindowFromPoint(at), GA_ROOT) == g_window; }

int checkPoint(HDC screen, POINT origin, const std::string &name, int x, int y, int er, int eg, int eb) {
	POINT at = {origin.x + MulDiv(x, g_dpi, 96), origin.y + MulDiv(y, g_dpi, 96)};
	if (!ownsPoint(at)) {
		printf("%-26s (%3d,%3d) the point is not over the harness window\n", name.c_str(), x, y);
		return 1;
	}
	COLORREF c = GetPixel(screen, at.x, at.y);
	int r = GetRValue(c), g = GetGValue(c), b = GetBValue(c);
	bool ok = abs(r - er) <= kTolerance && abs(g - eg) <= kTolerance && abs(b - eb) <= kTolerance;
	printf("%-26s (%3d,%3d) expected %3d %3d %3d  actual %3d %3d %3d  %s\n", name.c_str(), x, y, er, eg, eb, r, g, b, ok ? "ok" : "FAIL");
	return ok ? 0 : 1;
}

int checkCount(HDC screen, POINT origin, const Count &c) {
	int left = origin.x + MulDiv(c.x, g_dpi, 96), top = origin.y + MulDiv(c.y, g_dpi, 96);
	int width = MulDiv(c.width, g_dpi, 96), height = MulDiv(c.height, g_dpi, 96);
	POINT corners[] = {{left, top}, {left + width - 1, top}, {left, top + height - 1}, {left + width - 1, top + height - 1}};
	for (POINT corner : corners) {
		if (!ownsPoint(corner)) {
			printf("%-26s box (%d,%d %dx%d) is not over the harness window\n", c.name.c_str(), c.x, c.y, c.width, c.height);
			return 1;
		}
	}
	BITMAPINFO info = {};
	info.bmiHeader.biSize = sizeof info.bmiHeader;
	info.bmiHeader.biWidth = width;
	info.bmiHeader.biHeight = -height;
	info.bmiHeader.biPlanes = 1;
	info.bmiHeader.biBitCount = 32;
	info.bmiHeader.biCompression = BI_RGB;
	unsigned char *bits = nullptr;
	HDC memory = CreateCompatibleDC(screen);
	HBITMAP bitmap = CreateDIBSection(memory, &info, DIB_RGB_COLORS, (void **)&bits, nullptr, 0);
	HGDIOBJ previous = SelectObject(memory, bitmap);
	BitBlt(memory, 0, 0, width, height, screen, left, top, SRCCOPY);
	int count = 0;
	for (int i = 0; i < width * height; i++) {
		const unsigned char *p = bits + i * 4;
		if (abs(p[2] - c.r) <= c.tolerance && abs(p[1] - c.g) <= c.tolerance && abs(p[0] - c.b) <= c.tolerance) count += 1;
	}
	SelectObject(memory, previous);
	DeleteObject(bitmap);
	DeleteDC(memory);
	bool ok = count >= c.minCount && count <= c.maxCount;
	printf("%-26s box (%3d,%3d %3dx%3d) pixels within %d of %3d %3d %3d: %5d, expected %d..%d  %s\n", c.name.c_str(), c.x, c.y, c.width, c.height,
		c.tolerance, c.r, c.g, c.b, count, c.minCount, c.maxCount, ok ? "ok" : "FAIL");
	return ok ? 0 : 1;
}

int checkSize(const SizeCheck &c) {
	auto found = g_layouts.find(c.layout);
	if (found == g_layouts.end()) {
		printf("%-26s no layout was reported for it\n", c.layout.c_str());
		return 1;
	}
	ComPtr<IDWriteFactory> factory;
	must(DWriteCreateFactory(DWRITE_FACTORY_TYPE_ISOLATED, __uuidof(IDWriteFactory), (IUnknown **)factory.GetAddressOf()), "DWriteCreateFactory");
	ComPtr<IDWriteTextFormat> format;
	must(factory->CreateTextFormat(L"Segoe UI", nullptr, c.bold ? DWRITE_FONT_WEIGHT_BOLD : DWRITE_FONT_WEIGHT_NORMAL, DWRITE_FONT_STYLE_NORMAL,
		DWRITE_FONT_STRETCH_NORMAL, c.fontSize, L"en-us", &format), "CreateTextFormat");
	std::wstring wide(c.text.begin(), c.text.end());
	ComPtr<IDWriteTextLayout> layout;
	must(factory->CreateTextLayout(wide.c_str(), (UINT32)wide.size(), format.Get(), c.maxWidth, 100000.0f, &layout), "CreateTextLayout");
	DWRITE_TEXT_METRICS metrics;
	must(layout->GetMetrics(&metrics), "GetMetrics");
	float pixel = 96.0f / g_dpi, slack = 0.01f;
	float w = found->second.first, h = found->second.second;
	bool ok = w >= metrics.width - slack && w <= metrics.width + pixel + slack && h >= metrics.height - slack && h <= metrics.height + pixel + slack;
	printf("%-26s layout %.2fx%.2f, DirectWrite %.2fx%.2f, allowed up to one device pixel above  %s\n", c.layout.c_str(), w, h, metrics.width,
		metrics.height, ok ? "ok" : "FAIL");
	return ok ? 0 : 1;
}

int sample() {
	POINT origin = {0, 0};
	ClientToScreen(g_window, &origin);
	HDC screen = GetDC(nullptr);
	int failures = 0;
	printf("dpi %u\n", g_dpi);
	for (const Expectation &e : g_expectations) failures += checkPoint(screen, origin, e.name, e.x, e.y, e.r, e.g, e.b);
	for (const Centre &c : g_centres) {
		auto found = g_layouts.find(c.layout);
		if (found == g_layouts.end()) {
			printf("%-26s no layout was reported for %s\n", c.name.c_str(), c.layout.c_str());
			failures += 1;
			continue;
		}
		failures += checkPoint(screen, origin, c.name, c.left + (int)(found->second.first / 2), c.top + (int)(found->second.second / 2), c.r, c.g, c.b);
	}
	for (const Count &c : g_counts) failures += checkCount(screen, origin, c);
	for (const SizeCheck &c : g_sizes) failures += checkSize(c);
	ReleaseDC(nullptr, screen);
	fflush(stdout);
	return failures;
}

}

extern "C" {

void harnessStart(int logicalWidth, int logicalHeight) {
	g_check = wcsstr(GetCommandLineW(), L"--check") != nullptr;
	SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);

	WNDCLASSW windowClass = {};
	windowClass.lpfnWndProc = windowProc;
	windowClass.hInstance = GetModuleHandleW(nullptr);
	windowClass.lpszClassName = L"NeonWindowsHarness";
	windowClass.hCursor = LoadCursorW(nullptr, (LPCWSTR)IDC_ARROW);
	RegisterClassW(&windowClass);

	DWORD style = WS_OVERLAPPEDWINDOW & ~(WS_THICKFRAME | WS_MAXIMIZEBOX);
	DWORD exStyle = WS_EX_NOREDIRECTIONBITMAP | (g_check ? WS_EX_TOPMOST : 0);
	UINT systemDpi = GetDpiForSystem();
	RECT frame = {0, 0, MulDiv(logicalWidth, systemDpi, 96), MulDiv(logicalHeight, systemDpi, 96)};
	AdjustWindowRectExForDpi(&frame, style, FALSE, exStyle, systemDpi);
	g_window = CreateWindowExW(exStyle, windowClass.lpszClassName, L"Neon on DirectComposition", style | WS_VISIBLE, 100, 100,
		frame.right - frame.left, frame.bottom - frame.top, nullptr, nullptr, windowClass.hInstance, nullptr);
	if (!g_window) must(HRESULT_FROM_WIN32(GetLastError()), "CreateWindowExW");
	g_dpi = GetDpiForWindow(g_window);

	must(D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, D3D11_CREATE_DEVICE_BGRA_SUPPORT, nullptr, 0, D3D11_SDK_VERSION,
		&g_d3d, nullptr, nullptr), "D3D11CreateDevice");
	ComPtr<IDXGIDevice> dxgi;
	must(g_d3d.As(&dxgi), "IDXGIDevice");
	must(D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED, __uuidof(ID2D1Factory1), nullptr, (void **)g_d2dFactory.GetAddressOf()),
		"D2D1CreateFactory");
	must(g_d2dFactory->CreateDevice(dxgi.Get(), &g_d2dDevice), "ID2D1Factory1::CreateDevice");
	must(DCompositionCreateDevice2(g_d2dDevice.Get(), __uuidof(IDCompositionDesktopDevice), (void **)g_dcomp.GetAddressOf()),
		"DCompositionCreateDevice2");
	must(g_dcomp->CreateTargetForHwnd(g_window, TRUE, &g_target), "CreateTargetForHwnd");
	must(g_dcomp->CreateVisual(&g_root), "CreateVisual");
	must(g_target->SetRoot(g_root.Get()), "SetRoot");

	RECT client;
	GetClientRect(g_window, &client);
	niwAttach(g_dcomp.Get(), g_root.Get(), (float)g_dpi, (float)MulDiv(client.right, 96, g_dpi), (float)MulDiv(client.bottom, 96, g_dpi));
}

int harnessIsCheck(void) { return wcsstr(GetCommandLineW(), L"--check") != nullptr; }

static HWND findOwnWindow(const char *title) {
	struct Search {
		const wchar_t *title;
		HWND found;
	} search = {nullptr, nullptr};
	std::wstring wide(title, title + strlen(title));
	search.title = wide.c_str();
	EnumWindows([](HWND window, LPARAM param) -> BOOL {
		Search *search = reinterpret_cast<Search *>(param);
		DWORD owner = 0;
		GetWindowThreadProcessId(window, &owner);
		wchar_t text[256];
		GetWindowTextW(window, text, 256);
		if (owner == GetCurrentProcessId() && IsWindowVisible(window) && wcscmp(text, search->title) == 0) search->found = window;
		return search->found ? FALSE : TRUE;
	}, reinterpret_cast<LPARAM>(&search));
	if (!search.found) must(E_FAIL, "no window of this process has the expected title");
	return search.found;
}

int harnessSample(const char *title) {
	g_window = findOwnWindow(title);
	g_dpi = GetDpiForWindow(g_window);
	SetForegroundWindow(g_window);
	DwmFlush();
	DwmFlush();
	int failures = sample();
	g_expectations.clear();
	g_centres.clear();
	g_counts.clear();
	g_sizes.clear();
	g_layouts.clear();
	return failures == 0 ? 0 : 1;
}

void harnessResizeClient(const char *title, int logicalWidth, int logicalHeight) {
	HWND window = findOwnWindow(title);
	UINT dpi = GetDpiForWindow(window);
	RECT frame = {0, 0, MulDiv(logicalWidth, dpi, 96), MulDiv(logicalHeight, dpi, 96)};
	AdjustWindowRectExForDpi(&frame, (DWORD)GetWindowLongW(window, GWL_STYLE), FALSE, (DWORD)GetWindowLongW(window, GWL_EXSTYLE), dpi);
	SetWindowPos(window, nullptr, 0, 0, frame.right - frame.left, frame.bottom - frame.top, SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
}

void harnessExpect(const char *name, int x, int y, int r, int g, int b) {
	g_expectations.push_back({name, x, y, r, g, b});
}

void harnessLayout(const char *name, float width, float height) { g_layouts[name] = {width, height}; }

void harnessExpectCentre(const char *name, const char *layout, int left, int top, int r, int g, int b) {
	g_centres.push_back({name, layout, left, top, r, g, b});
}

void harnessExpectCount(const char *name, int x, int y, int width, int height, int r, int g, int b, int tolerance, int minCount, int maxCount) {
	g_counts.push_back({name, x, y, width, height, r, g, b, tolerance, minCount, maxCount});
}

void harnessExpectSize(const char *layout, const char *text, float fontSize, int bold, float maxWidth) {
	g_sizes.push_back({layout, text, fontSize, bold, maxWidth});
}

int harnessRun(void) {
	int status = 0;
	if (g_check) {
		SetForegroundWindow(g_window);
		ULONGLONG settled = GetTickCount64() + 500;
		for (int i = 0; i < 30 || GetTickCount64() < settled; i++) {
			niwPump();
			pumpMessages();
			DwmFlush();
		}
		status = sample() == 0 ? 0 : 1;
	} else {
		for (;;) {
			int next = niwPump();
			MsgWaitForMultipleObjects(0, nullptr, FALSE, next < 0 ? INFINITE : (DWORD)next, QS_ALLINPUT);
			if (!pumpMessages()) break;
		}
	}
	niwShutdown();
	if (IsWindow(g_window)) DestroyWindow(g_window);
	return status;
}

}
