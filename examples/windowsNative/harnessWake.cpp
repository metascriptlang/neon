#include <windows.h>

static const DWORD g_loopThread = GetCurrentThreadId();

// A post fails only on a full queue, which wakes the loop anyway, or after the loop thread has ended.
extern "C" void ionWakeLoop(void) { (void)PostThreadMessageW(g_loopThread, WM_NULL, 0, 0); }
