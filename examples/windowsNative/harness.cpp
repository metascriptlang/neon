#include <windows.h>
#include <d3d11.h>
#include <d2d1_1.h>
#include <dcomp.h>
#include <dwmapi.h>
#include <wrl/client.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
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

const int kTolerance = 3;

HWND g_window = nullptr;
bool g_check = false;
UINT g_dpi = 96;
std::vector<Expectation> g_expectations;
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

int sample() {
	POINT origin = {0, 0};
	ClientToScreen(g_window, &origin);
	HDC screen = GetDC(nullptr);
	int failures = 0;
	printf("dpi %u\n", g_dpi);
	for (const Expectation &e : g_expectations) {
		POINT at = {origin.x + MulDiv(e.x, g_dpi, 96), origin.y + MulDiv(e.y, g_dpi, 96)};
		if (GetAncestor(WindowFromPoint(at), GA_ROOT) != g_window) {
			printf("%-22s (%3d,%3d) the point is not over the harness window\n", e.name.c_str(), e.x, e.y);
			failures += 1;
			continue;
		}
		COLORREF c = GetPixel(screen, at.x, at.y);
		int r = GetRValue(c), g = GetGValue(c), b = GetBValue(c);
		bool ok = abs(r - e.r) <= kTolerance && abs(g - e.g) <= kTolerance && abs(b - e.b) <= kTolerance;
		printf("%-22s (%3d,%3d) expected %3d %3d %3d  actual %3d %3d %3d  %s\n", e.name.c_str(), e.x, e.y, e.r, e.g, e.b, r, g, b,
			ok ? "ok" : "FAIL");
		if (!ok) failures += 1;
	}
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

void harnessExpect(const char *name, int x, int y, int r, int g, int b) {
	g_expectations.push_back({name, x, y, r, g, b});
}

int harnessRun(void) {
	int status = 0;
	if (g_check) {
		SetForegroundWindow(g_window);
		for (int i = 0; i < 30; i++) {
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
