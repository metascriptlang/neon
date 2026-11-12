#import <Cocoa/Cocoa.h>
#include "../../src/platform/native/bridge.h"
#include "../../src/platform/macos/handoff.h"
#import "../../src/platform/macos/view.h"
#include "macosPointerInput.h"

static NSView *baseParent, *parent, *root;
static int moves, order, requests;
static float lastX;
static double lastTime;
static BOOL reenter, reenterScroll, stopFromScroll;
static void *scroll;
static int scrolls;
static float scrollY;

static NSEvent *mouse(NSEventType type, float x, double time) {
	return [NSEvent mouseEventWithType:type location:NSMakePoint(x, 50)
		modifierFlags:0 timestamp:time / 1000 windowNumber:0 context:nil
		eventNumber:0 clickCount:1 pressure:1];
}

void npiDrag(float x, double time) {
	[root mouseDragged:mouse(NSEventTypeLeftMouseDragged, x, time)];
}

static void touched(void) {
	int phase = niLastTouchPhase();
	if (phase == 4) {
		moves++;
		order = order * 10 + 4;
		lastX = niLastTouchX();
		lastTime = niLastTouchTime();
		if (reenter) {
			reenter = NO;
			npiDrag(70, 21);
		}
	} else if (phase == 1) {
		order = order * 10 + 1;
	}
}

static void requested(void) { requests++; }
static void frame(void) { order = order * 10 + 8; }
static void loop(void) {}
static void control(void) { order = order * 10 + 5; }
static void scrolled(void) {
	scrolls++;
	scrollY = niLastScrollY();
	order = order * 10 + 6;
	if (reenterScroll) {
		reenterScroll = NO;
		npiScroll(80);
	}
	if (stopFromScroll) {
		stopFromScroll = NO;
		nimShutdown();
	}
}

void npiBegin(void) {
	niSetScrollHandler((msClosure){0});
	if (scroll) { niViewRelease(scroll); scroll = NULL; }
	reenterScroll = stopFromScroll = NO;
	if (!baseParent) {
		baseParent = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 200, 100)];
		nimAttach((__bridge void *)baseParent, 1, 200, 100);
	}
	if (root) nimDetach((__bridge void *)root);
	parent = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 200, 100)];
	root = (__bridge NSView *)nimAttach((__bridge void *)parent, 1, 200, 100);
	nimSetFrameRequester((msClosure){(void *)requested, NULL});
	niSetFrameHandler((msClosure){(void *)frame, NULL});
	niSetLoopHandler((msClosure){(void *)loop, NULL});
	niSetTouchHandler((msClosure){(void *)touched, NULL});
	niSetControlHandler((msClosure){(void *)control, NULL});
	void *view = niViewCreate();
	niViewSetTag(view, 7);
	niViewSetPressable(view);
	niSetFrame(view, 0, 0, 200, 100);
	niAddChild((__bridge void *)root, view);
	niViewRelease(view);
	nimFrame(1000);
	moves = order = requests = scrolls = 0;
	scrollY = 0;
	lastX = 0;
	lastTime = 0;
	reenter = NO;
	[root mouseDown:mouse(NSEventTypeLeftMouseDown, 10, 1)];
}

void npiTick(void) { niRequestFrame(); nimFrame(2000); }
void npiUp(void) { [root mouseUp:mouse(NSEventTypeLeftMouseUp, 50, 20)]; }
void npiResize(void) { nimResize((__bridge void *)root, 1, 150, 100); }
void npiDetach(void) { nimDetach((__bridge void *)root); root = nil; }
void npiControl(void) { neonEmitControl(7, 2, @"", 0, 0); }
void npiReenter(void) { reenter = YES; }
void npiUnregister(void) { niSetTouchHandler((msClosure){0}); }
void npiShutdown(void) { nimShutdown(); }
int32_t npiMoves(void) { return moves; }
int32_t npiOrder(void) { return order; }
int32_t npiRequests(void) { return requests; }
float npiLastX(void) { return lastX; }
double npiLastTime(void) { return lastTime; }

void npiScroll(float y) {
	if (!scroll) {
		scroll = niScrollCreate();
		niScrollSetTag(scroll, 17);
		niSetFrame(scroll, 100, 0, 100, 100);
		niScrollSetContentSize(scroll, 100, 1000);
		niAddChild((__bridge void *)root, scroll);
		niSetScrollHandler((msClosure){(void *)scrolled, NULL});
	}
	niScrollTo(scroll, 0, y, 0);
}

void npiUnregisterScroll(void) { niSetScrollHandler((msClosure){0}); }
void npiReenterScroll(void) { reenterScroll = YES; }
void npiStopFromScroll(void) { stopFromScroll = YES; }
int32_t npiScrolls(void) { return scrolls; }
float npiScrollY(void) { return scrollY; }
float npiOffsetY(void) { return niScrollOffsetY(scroll); }
int32_t npiReleaseScroll(void) {
	__weak id released;
	@autoreleasepool {
		npiBegin();
		npiScroll(20);
		released = (__bridge id)scroll;
		niRemoveFromParent(scroll);
		niViewRelease(scroll);
		scroll = NULL;
	}
	return released == nil;
}
