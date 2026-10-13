#pragma once
#include <windows.h>
#include <cstdio>
#include <cstdlib>

inline void must(HRESULT hr, const char *what) {
	if (SUCCEEDED(hr)) return;
	fprintf(stderr, "neon windows bridge: %s failed, HRESULT 0x%08lx\n", what, (unsigned long)hr);
	fflush(stderr);
	abort();
}
