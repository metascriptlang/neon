#include <windows.h>
#include <dwmapi.h>
#include <stdio.h>
#include "../../../ion/src/platform/common/inputEvents.h"
#include "windowsModalFrame.h"

static HHOOK showHook;
static HRESULT windowTransitionStatus = E_FAIL;

static LRESULT CALLBACK beforeWindowShow(int code, WPARAM wParam, LPARAM lParam) {
	if (code >= 0) {
		const CWPSTRUCT *message = (const CWPSTRUCT *)lParam;
		if (message->message == WM_WINDOWPOSCHANGING &&
			(((const WINDOWPOS *)message->lParam)->flags & SWP_SHOWWINDOW) &&
			GetAncestor(message->hwnd, GA_ROOT) == message->hwnd) {
			BOOL disable = TRUE;
			windowTransitionStatus = DwmSetWindowAttribute(message->hwnd,
				DWMWA_TRANSITIONS_FORCEDISABLED, &disable, sizeof disable);
			printf("modal pre-show transition hr=0x%08lx visible=%d\n",
				(unsigned long)windowTransitionStatus, IsWindowVisible(message->hwnd));
			fflush(stdout);
		}
	}
	return CallNextHookEx(showHook, code, wParam, lParam);
}

int32_t nmfPrepareWindow(void) {
	windowTransitionStatus = E_FAIL;
	showHook = SetWindowsHookExW(WH_CALLWNDPROC, beforeWindowShow, NULL, GetCurrentThreadId());
	return showHook ? 0 : 1;
}

double nmfQueueFrame(int32_t window) {
	if (showHook) {
		if (!UnhookWindowsHookEx(showHook)) return -1;
		showHook = NULL;
	}
	if (FAILED(windowTransitionStatus)) return -1;
	LARGE_INTEGER frequency, counter;
	if (!QueryPerformanceFrequency(&frequency) || !QueryPerformanceCounter(&counter)) return -1;
	IonInputRecord frame = {0};
	frame.type = ION_INPUT_FRAME;
	frame.window = window;
	frame.x = (double)counter.QuadPart * 1000.0 / (double)frequency.QuadPart + 10000.0;
	return ion_input_push_record(&frame) == 0 ? frame.x : -1;
}

extern HWND ionWinHwnd(int32_t window);

int32_t nmfSampleFrame(int32_t window, int32_t marker) {
	HWND hwnd = ionWinHwnd(window);
	if (!hwnd || marker < 1 || marker > 0xfffffe) return -1;
	UINT dpi = GetDpiForWindow(hwnd);
	POINT origin = {0, 0};
	if (!dpi || !ClientToScreen(hwnd, &origin)) return -1;
	POINT first = {origin.x + MulDiv(20, dpi, 96), origin.y + MulDiv(20, dpi, 96)};
	POINT last = {origin.x + MulDiv(200, dpi, 96), origin.y + MulDiv(200, dpi, 96)};
	if (GetAncestor(WindowFromPoint(first), GA_ROOT) != hwnd || GetAncestor(WindowFromPoint(last), GA_ROOT) != hwnd) {
		fprintf(stderr, "modal capture point is not over the harness window\n");
		return -1;
	}
	int width = last.x - first.x + 1, height = last.y - first.y + 1;
	BITMAPINFO info = {0};
	info.bmiHeader.biSize = sizeof info.bmiHeader;
	info.bmiHeader.biWidth = width;
	info.bmiHeader.biHeight = -height;
	info.bmiHeader.biPlanes = 1;
	info.bmiHeader.biBitCount = 32;
	info.bmiHeader.biCompression = BI_RGB;
	HDC screen = GetDC(NULL);
	if (!screen) return -1;
	HDC memory = CreateCompatibleDC(screen);
	unsigned char *bits = NULL;
	HBITMAP bitmap = memory ? CreateDIBSection(memory, &info, DIB_RGB_COLORS, (void **)&bits, NULL, 0) : NULL;
	int32_t result = -1;
	if (bitmap && bits) {
		HGDIOBJ previous = SelectObject(memory, bitmap);
		if (previous && previous != HGDI_ERROR) {
			if (BitBlt(memory, 0, 0, width, height, screen, first.x, first.y, SRCCOPY | CAPTUREBLT) && GdiFlush()) {
				unsigned char *stamp = bits + ((size_t)width * height - 1) * 4;
				result = 0;
				if (stamp[2] == ((marker >> 16) & 255) && stamp[1] == ((marker >> 8) & 255) && stamp[0] == (marker & 255)) {
					int r = bits[2], g = bits[1], b = bits[0];
					result = r == 0 && g == 255 && b == 0 ? 1 : 2;
					printf("modal frame marker observed rgb=%u,%u,%u\n", stamp[2], stamp[1], stamp[0]);
					printf("modal opaque at target     ( 20, 20) expected   0 255   0  actual %3d %3d %3d  %s\n", r, g, b, result == 1 ? "ok" : "FAIL");
					fflush(stdout);
				}
			}
			SelectObject(memory, previous);
		}
	}
	if (bitmap) DeleteObject(bitmap);
	if (memory) DeleteDC(memory);
	ReleaseDC(NULL, screen);
	return result;
}
