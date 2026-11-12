#import <Cocoa/Cocoa.h>
#include "../../src/platform/native/bridge.h"
#include "../../src/platform/macos/handoff.h"

static NSView *parent;
static int order, requests, loopRequests;

static void requested(void) { requests++; }
static void frame(void) { order = order * 10 + 1; }
static void loop(void) {
	order = order * 10 + 2;
	if (loopRequests) niRequestFrame();
}

int nfmOrder(int requestFromLoop) {
	if (!parent) {
		parent = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 200, 100)];
		nimAttach((__bridge void *)parent, 1, 200, 100);
	}
	order = requests = 0;
	loopRequests = requestFromLoop;
	nimSetFrameRequester((msClosure){(void *)requested, NULL});
	niSetFrameHandler((msClosure){(void *)frame, NULL});
	niSetLoopHandler((msClosure){(void *)loop, NULL});
	niRequestFrame();
	nimFrame(1234);
	niSetFrameHandler((msClosure){0});
	niSetLoopHandler((msClosure){0});
	return order;
}

int nfmRequests(void) { return requests; }
