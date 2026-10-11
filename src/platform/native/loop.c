#include "runtime/promise/dispatch.h"
#include "loop.h"

static int g_next = -1;

void niLoopRun(void) {
	msDispatcher *d = msGetDispatcher();
	bool didWork = false;
	(void)msRunOnce(0);
	int next = msProcessTimers(d, &didWork);
	msProcessCallbacks(d, &didWork);
	g_next = didWork ? 0 : next;
}

int niLoopNext(void) { return g_next; }
