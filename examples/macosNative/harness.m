#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#import <WebKit/WebKit.h>
#include "harness.h"
#include <stdio.h>
#include <stdlib.h>

typedef struct {
	char name[64];
	int x, y, width, height, r, g, b, tolerance, minCount, maxCount;
	BOOL count;
} Expectation;

static const int kTolerance = 3;
static Expectation g_expectations[64];
static int g_expectationCount = 0;
static NSMutableDictionary<NSString *, NSValue *> *g_layouts;
static NSMutableArray<NSArray *> *g_centres, *g_sizes;

void harnessLayout(const char *name, float width, float height) {
	if (!g_layouts) g_layouts = [NSMutableDictionary dictionary];
	g_layouts[@(name)] = [NSValue valueWithSize:NSMakeSize(width, height)];
}

void harnessExpectCentre(const char *name, const char *layout, int left, int top, int r, int g, int b) {
	if (!g_centres) g_centres = [NSMutableArray array];
	[g_centres addObject:@[@(name), @(layout), @(left), @(top), @(r), @(g), @(b)]];
}

void harnessExpectSize(const char *layout, const char *text, float fontSize, int bold, float maxWidth) {
	if (!g_sizes) g_sizes = [NSMutableArray array];
	[g_sizes addObject:@[@(layout), @(text), @(fontSize), @(bold), @(maxWidth)]];
}

static int checkSize(NSArray *c) {
	NSValue *found = g_layouts[c[0]];
	if (!found) {
		printf("FAIL %-28s no layout was reported for it\n", [c[0] UTF8String]);
		return 1;
	}
	NSFont *font = [NSFont systemFontOfSize:[c[2] doubleValue] weight:[c[3] intValue] ? NSFontWeightBold : NSFontWeightRegular];
	NSTextStorage *storage = [[NSTextStorage alloc] initWithString:c[1] attributes:@{NSFontAttributeName: font}];
	NSLayoutManager *manager = [NSLayoutManager new];
	NSTextContainer *container = [[NSTextContainer alloc] initWithSize:NSMakeSize([c[4] doubleValue], CGFLOAT_MAX)];
	container.lineFragmentPadding = 0;
	[manager addTextContainer:container];
	[storage addLayoutManager:manager];
	[manager ensureLayoutForTextContainer:container];
	NSSize want = [manager usedRectForTextContainer:container].size, got = found.sizeValue;
	CGFloat point = 1, slack = 0.01;
	BOOL ok = got.width >= want.width - slack && got.width <= want.width + point + slack && got.height >= want.height - slack && got.height <= want.height + point + slack;
	printf("%s %-28s layout %.2fx%.2f, NSLayoutManager %.2fx%.2f, allowed up to one point above\n", ok ? "ok  " : "FAIL", [c[0] UTF8String],
		got.width, got.height, want.width, want.height);
	return ok ? 0 : 1;
}

int harnessIsCheck(void) { return [NSProcessInfo.processInfo.arguments containsObject:@"--check"] ? 1 : 0; }

static Expectation *push(const char *name) {
	if (g_expectationCount == 64) {
		fprintf(stderr, "harness: more than 64 expectations\n");
		exit(2);
	}
	Expectation *e = &g_expectations[g_expectationCount++];
	memset(e, 0, sizeof *e);
	snprintf(e->name, sizeof e->name, "%s", name);
	return e;
}

void harnessExpect(const char *name, int x, int y, int r, int g, int b) {
	Expectation *e = push(name);
	e->x = x;
	e->y = y;
	e->r = r;
	e->g = g;
	e->b = b;
}

void harnessExpectCount(const char *name, int x, int y, int width, int height, int r, int g, int b, int tolerance, int minCount, int maxCount) {
	Expectation *e = push(name);
	*e = (Expectation){.x = x, .y = y, .width = width, .height = height, .r = r, .g = g, .b = b, .tolerance = tolerance, .minCount = minCount, .maxCount = maxCount, .count = YES};
	snprintf(e->name, sizeof e->name, "%s", name);
}

static NSWindow *windowTitled(const char *title) {
	NSString *wanted = @(title);
	for (NSWindow *window in NSApp.windows) {
		if ([window.title isEqualToString:wanted]) return window;
	}
	fprintf(stderr, "harness: no window titled \"%s\"\n", title);
	exit(2);
}

// The content's layers rendered by Core Animation into a bitmap at the backing scale: what the
// views draw, not what the window server composited.
static CGContextRef capture(NSWindow *window, CGFloat *scaleOut) {
	NSView *content = window.contentView;
	CGFloat scale = window.backingScaleFactor;
	size_t width = (size_t)ceil(content.bounds.size.width * scale), height = (size_t)ceil(content.bounds.size.height * scale);
	CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
	CGContextRef ctx = CGBitmapContextCreate(NULL, width, height, 8, width * 4, space, kCGImageAlphaPremultipliedLast);
	CGColorSpaceRelease(space);
	CGContextTranslateCTM(ctx, 0, (CGFloat)height);
	CGContextScaleCTM(ctx, scale, -scale);
	for (NSView *child in content.subviews) {
		if (!child.layer || child.hidden) continue;
		CGContextSaveGState(ctx);
		CGContextTranslateCTM(ctx, child.frame.origin.x, content.bounds.size.height - NSMaxY(child.frame));
		[child.layer renderInContext:ctx];
		CGContextRestoreGState(ctx);
	}
	*scaleOut = scale;
	return ctx;
}

static void pixel(CGContextRef ctx, CGFloat scale, int x, int y, int *r, int *g, int *b) {
	size_t width = CGBitmapContextGetWidth(ctx), height = CGBitmapContextGetHeight(ctx);
	size_t px = (size_t)((x + 0.5) * scale), py = (size_t)((y + 0.5) * scale);
	if (px >= width || py >= height) {
		*r = *g = *b = -1;
		return;
	}
	const unsigned char *data = CGBitmapContextGetData(ctx);
	const unsigned char *p = data + py * CGBitmapContextGetBytesPerRow(ctx) + px * 4;
	*r = p[0];
	*g = p[1];
	*b = p[2];
}

int harnessSample(const char *title) {
	NSWindow *window = windowTitled(title);
	printf("harness: window %ld\n", (long)window.windowNumber);
	CGFloat scale = 1;
	CGContextRef ctx = capture(window, &scale);
	int failures = 0;
	for (int i = 0; i < g_expectationCount; i++) {
		Expectation *e = &g_expectations[i];
		if (e->count) {
			int matched = 0;
			for (int y = e->y; y < e->y + e->height; y++) {
				for (int x = e->x; x < e->x + e->width; x++) {
					int r, g, b;
					pixel(ctx, scale, x, y, &r, &g, &b);
					if (abs(r - e->r) <= e->tolerance && abs(g - e->g) <= e->tolerance && abs(b - e->b) <= e->tolerance) matched++;
				}
			}
			BOOL ok = matched >= e->minCount && matched <= e->maxCount;
			if (!ok) failures++;
			printf("%s %-28s %d points near (%d,%d,%d), want %d..%d\n", ok ? "ok  " : "FAIL", e->name, matched, e->r, e->g, e->b, e->minCount, e->maxCount);
			continue;
		}
		int r, g, b;
		pixel(ctx, scale, e->x, e->y, &r, &g, &b);
		BOOL ok = abs(r - e->r) <= kTolerance && abs(g - e->g) <= kTolerance && abs(b - e->b) <= kTolerance;
		if (!ok) failures++;
		printf("%s %-28s (%3d,%3d) = %3d %3d %3d, want %3d %3d %3d\n", ok ? "ok  " : "FAIL", e->name, e->x, e->y, r, g, b, e->r, e->g, e->b);
	}
	for (NSArray *c in g_centres) {
		NSValue *found = g_layouts[c[1]];
		if (!found) {
			printf("FAIL %-28s no layout was reported for %s\n", [c[0] UTF8String], [c[1] UTF8String]);
			failures++;
			continue;
		}
		int x = [c[2] intValue] + (int)(found.sizeValue.width / 2), y = [c[3] intValue] + (int)(found.sizeValue.height / 2);
		int r, g, b;
		pixel(ctx, scale, x, y, &r, &g, &b);
		BOOL ok = abs(r - [c[4] intValue]) <= kTolerance && abs(g - [c[5] intValue]) <= kTolerance && abs(b - [c[6] intValue]) <= kTolerance;
		if (!ok) failures++;
		printf("%s %-28s (%3d,%3d) = %3d %3d %3d, want %3d %3d %3d\n", ok ? "ok  " : "FAIL", [c[0] UTF8String], x, y, r, g, b, [c[4] intValue], [c[5] intValue], [c[6] intValue]);
	}
	for (NSArray *c in g_sizes) failures += checkSize(c);
	fflush(stdout);
	CGContextRelease(ctx);
	g_expectationCount = 0;
	[g_centres removeAllObjects];
	[g_sizes removeAllObjects];
	return failures;
}

static NSPoint windowPoint(NSWindow *window, int x, int y) {
	return NSMakePoint(x, window.contentView.bounds.size.height - y);
}

static void post(NSWindow *window, NSEventType type, int x, int y) {
	NSEvent *event = [NSEvent mouseEventWithType:type location:windowPoint(window, x, y) modifierFlags:0 timestamp:NSProcessInfo.processInfo.systemUptime
		windowNumber:window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:type == NSEventTypeLeftMouseUp ? 0 : 1];
	[NSApp postEvent:event atStart:NO];
}

void harnessPointer(const char *title, int kind, int x, int y) {
	NSWindow *window = windowTitled(title);
	NSEventType type = kind == 0 ? NSEventTypeLeftMouseDown : kind == 1 ? NSEventTypeLeftMouseUp : NSEventTypeLeftMouseDragged;
	post(window, type, x, y);
}

void harnessClick(const char *title, int x, int y) {
	harnessPointer(title, 0, x, y);
	harnessPointer(title, 1, x, y);
}

// An NSEvent made from a CGEvent has no window, so its locationInWindow is the CG location in screen
// space; placing that location at the window point lets -[NSWindow sendEvent:] hit-test the right view.
void harnessWheel(const char *title, int x, int y, int points) {
	NSWindow *window = windowTitled(title);
	NSPoint at = windowPoint(window, x, y);
	CGFloat top = NSMaxY(NSScreen.screens.firstObject.frame);
	CGEventRef cg = CGEventCreateScrollWheelEvent(NULL, kCGScrollEventUnitPixel, 1, points);
	CGEventSetLocation(cg, CGPointMake(at.x, top - at.y));
	NSEvent *event = [NSEvent eventWithCGEvent:cg];
	CFRelease(cg);
	[window sendEvent:event];
}

int harnessPostKeys(const char *title, const char *keys) {
	NSWindow *window = windowTitled(title);
	NSString *all = @(keys);
	for (NSUInteger i = 0; i < all.length; i++) {
		NSString *ch = [all substringWithRange:NSMakeRange(i, 1)];
		unichar c = [ch characterAtIndex:0];
		unsigned short code = c == '\n' ? 36 : c == '\b' ? 51 : c == 0x1b ? 53 : 0;
		NSString *chars = c == '\n' ? @"\r" : c == '\b' ? [NSString stringWithFormat:@"%C", (unichar)NSDeleteCharacter] : ch;
		for (int down = 1; down >= 0; down--) {
			NSEvent *event = [NSEvent keyEventWithType:down ? NSEventTypeKeyDown : NSEventTypeKeyUp location:NSZeroPoint modifierFlags:0
				timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:window.windowNumber context:nil characters:chars
				charactersIgnoringModifiers:chars isARepeat:NO keyCode:code];
			[NSApp postEvent:event atStart:NO];
		}
	}
	return (int)all.length;
}

static NSTextView *focusedText(NSWindow *window) {
	NSResponder *at = window.firstResponder;
	return [at isKindOfClass:NSTextView.class] ? (NSTextView *)at : nil;
}

static NSTextView *requireFocusedText(const char *title) {
	NSTextView *view = focusedText(windowTitled(title));
	if (!view) {
		fprintf(stderr, "harness: no text view has the focus in \"%s\"\n", title);
		exit(2);
	}
	return view;
}

void harnessCompose(const char *title, const char *marked) {
	NSString *text = @(marked);
	[requireFocusedText(title) setMarkedText:text selectedRange:NSMakeRange(text.length, 0) replacementRange:NSMakeRange(NSNotFound, 0)];
}

void harnessCommit(const char *title, const char *text) {
	[requireFocusedText(title) insertText:@(text) replacementRange:NSMakeRange(NSNotFound, 0)];
}

int harnessFocusedText(const char *title) { return focusedText(windowTitled(title)) ? 1 : 0; }

static void collectSwitches(NSView *view, NSMutableString *out) {
	if ([view isKindOfClass:NSSwitch.class]) [out appendString:((NSSwitch *)view).state == NSControlStateValueOn ? @"1" : @"0"];
	for (NSView *child in view.subviews) collectSwitches(child, out);
}

const char *harnessSwitchStates(const char *title) {
	static char states[64];
	NSMutableString *out = [NSMutableString string];
	collectSwitches(windowTitled(title).contentView, out);
	snprintf(states, sizeof states, "%s", out.UTF8String);
	return states;
}

static WKWebView *findWeb(NSView *view) {
	if ([view isKindOfClass:WKWebView.class]) return (WKWebView *)view;
	for (NSView *child in view.subviews) {
		WKWebView *found = findWeb(child);
		if (found) return found;
	}
	return nil;
}

int32_t niMeasureInWindow(void *view);
double niMeasurementX(void);
double niMeasurementY(void);
double niMeasurementW(void);
double niMeasurementH(void);

static NSView *labelled(NSView *view, NSString *label) {
	if ([view respondsToSelector:NSSelectorFromString(@"accessibility")] &&
		[[[view valueForKey:@"accessibility"] objectForKey:@"accessibilityLabel"] isEqualToString:label]) return view;
	for (NSView *child in view.subviews) {
		NSView *found = labelled(child, label);
		if (found) return found;
	}
	return nil;
}

static NSBitmapImageRep *g_webShot = nil;
static NSSize g_webShotSize;

// A web view draws in WebKit's own process, so renderInContext does not see the page: WebKit snapshots it.
void harnessSnapshotWeb(const char *title) {
	g_webShot = nil;
	WKWebView *web = findWeb(windowTitled(title).contentView);
	if (!web) {
		fprintf(stderr, "harness: no WKWebView in \"%s\"\n", title);
		exit(2);
	}
	[web takeSnapshotWithConfiguration:nil completionHandler:^(NSImage *image, NSError *error) {
		(void)error;
		if (!image) return;
		g_webShotSize = image.size;
		g_webShot = [[NSBitmapImageRep alloc] initWithData:image.TIFFRepresentation];
	}];
}

int harnessWebPixel(int x, int y) {
	if (!g_webShot || g_webShotSize.width <= 0) return -1;
	NSInteger px = (NSInteger)(x * g_webShot.pixelsWide / g_webShotSize.width);
	NSInteger py = (NSInteger)(y * g_webShot.pixelsHigh / g_webShotSize.height);
	NSColor *color = [[g_webShot colorAtX:px y:py] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
	if (!color) return -1;
	return ((int)lround(color.redComponent * 255) << 16) | ((int)lround(color.greenComponent * 255) << 8) | (int)lround(color.blueComponent * 255);
}

const char *harnessMeasure(const char *title, const char *label) {
	static char out[128];
	NSView *view = labelled(windowTitled(title).contentView, @(label));
	if (!view) {
		snprintf(out, sizeof out, "no view labelled %s", label);
		return out;
	}
	int32_t got = niMeasureInWindow((__bridge void *)view);
	if (got != 1) snprintf(out, sizeof out, "%d", got);
	else snprintf(out, sizeof out, "%g,%g,%g,%g", niMeasurementX(), niMeasurementY(), niMeasurementW(), niMeasurementH());
	return out;
}

int harnessMeasureDetached(void) {
	NSView *view = [[NSClassFromString(@"NeonView") alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)];
	return niMeasureInWindow((__bridge void *)view);
}

void harnessHide(const char *title, const char *label) { labelled(windowTitled(title).contentView, @(label)).hidden = YES; }

static NSView *neonRoot(NSView *view) {
	if ([view isKindOfClass:NSClassFromString(@"NeonRoot")]) return view;
	for (NSView *child in view.subviews) {
		NSView *found = neonRoot(child);
		if (found) return found;
	}
	return nil;
}

const char *harnessMeasureRoot(const char *title) {
	static char out[128];
	if (niMeasureInWindow((__bridge void *)neonRoot(windowTitled(title).contentView)) != 1) return "failed";
	snprintf(out, sizeof out, "%g,%g,%g,%g", niMeasurementX(), niMeasurementY(), niMeasurementW(), niMeasurementH());
	return out;
}
