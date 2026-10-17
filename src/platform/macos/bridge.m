#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#include "../native/bridge.h"
#include "../native/loop.h"
#include "handoff.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static msClosure s_mount, s_resize, s_teardown, s_loop, s_frame, s_touch, s_scroll, s_control, s_environment, s_app;
static msClosure s_requester;
static float g_scale = 1, g_width = 0, g_height = 0;
static float g_measuredW = 0, g_measuredH = 0;
static int g_touchTag = 0, g_touchPhase = 0;
static float g_touchX = 0, g_touchY = 0;
static double g_touchTime = 0;
static int g_scrollTag = 0, g_scrollPhase = 0;
static float g_scrollX = 0, g_scrollY = 0, g_scrollW = 0, g_scrollH = 0, g_scrollContentW = 0, g_scrollContentH = 0;
static int g_controlTag = 0, g_controlPhase = 0;
static char *g_controlValue = NULL;
static BOOL g_frameRequested = NO, g_frameWanted = NO, g_inFrame = NO;
static int g_layoutsBuilt = 0;

static void invoke(msClosure c) {
	if (c.env) ((void (*)(void *))c.fn)(c.env);
	else ((void (*)(void))c.fn)();
}

static void fail(const char *message) {
	fprintf(stderr, "neon macos bridge: %s\n", message);
	fflush(stderr);
	abort();
}

static void unimplemented(const char *what) {
	char message[192];
	snprintf(message, sizeof message, "%s is not implemented on macOS yet", what);
	fail(message);
}

static void requestHostFrame(void) {
	if (g_frameRequested || g_inFrame || !s_requester.fn) return;
	g_frameRequested = YES;
	invoke(s_requester);
}

static NSColor *rgba(float r, float g, float b, float a) {
	return [NSColor colorWithSRGBRed:r green:g blue:b alpha:a];
}

// --- views ---

@interface NeonView : NSView
@property(nonatomic) int32_t neonTag;
@property(nonatomic) BOOL pressable;
@property(nonatomic) float x, y, w, h;
@property(nonatomic) float scaleX, scaleY, translateX, translateY, rotation, radius;
@property(nonatomic, strong) NSColor *neonBackground;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *accessibility;
@end

@implementation NeonView

- (instancetype)initWithFrame:(NSRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		self.wantsLayer = YES;
		self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawOnSetNeedsDisplay;
		_scaleX = 1;
		_scaleY = 1;
		_accessibility = [NSMutableDictionary dictionary];
	}
	return self;
}

- (BOOL)isFlipped { return YES; }
- (BOOL)wantsUpdateLayer { return YES; }
- (BOOL)acceptsFirstResponder { return NO; }
- (NSView *)hitTest:(NSPoint)point { (void)point; return nil; }

- (CATransform3D)neonTransform {
	float radians = self.rotation * (float)M_PI / 180.0f;
	CATransform3D t = CATransform3DMakeTranslation(self.w / 2 + self.translateX, self.h / 2 + self.translateY, 0);
	t = CATransform3DRotate(t, radians, 0, 0, 1);
	t = CATransform3DScale(t, self.scaleX, self.scaleY, 1);
	return CATransform3DTranslate(t, -self.w / 2, -self.h / 2, 0);
}

// RN macOS RCTUIView: AppKit resets layer.transform during its display cycle and its layers anchor at
// (0, 0), so the centred transform is rebuilt and re-applied on every update.
- (void)updateLayer {
	CALayer *layer = self.layer;
	layer.backgroundColor = self.neonBackground ? self.neonBackground.CGColor : NULL;
	layer.cornerRadius = self.radius;
	layer.masksToBounds = self.radius > 0;
	CATransform3D t = [self neonTransform];
	if (!CATransform3DEqualToTransform(layer.transform, t)) layer.transform = t;
}

- (void)neonApply {
	[CATransaction begin];
	[CATransaction setDisableActions:YES];
	[self updateLayer];
	[CATransaction commit];
	self.needsDisplay = YES;
}

- (void)setFrameSize:(NSSize)size {
	[super setFrameSize:size];
	[self neonApply];
}

- (NSView *)neonChildHost { return self; }
@end

static NeonView *as(void *view) { return (__bridge NeonView *)view; }

static NeonView *g_root = nil;

static void requireAttached(const char *what) {
	if (g_root) return;
	char message[192];
	snprintf(message, sizeof message, "%s before nimAttach", what);
	fail(message);
}

// --- pointer: Neon's own hit test, the one bridge.cpp ports from RNW, over the view tree ---

static BOOL toLocal(NeonView *view, float px, float py, float *lx, float *ly) {
	float radians = view.rotation * (float)M_PI / 180.0f;
	float c = cosf(radians), s = sinf(radians);
	float m11 = view.scaleX * c, m12 = view.scaleX * s, m21 = -view.scaleY * s, m22 = view.scaleY * c;
	float det = m11 * m22 - m12 * m21;
	if (det == 0) return NO;
	float cx = view.w / 2, cy = view.h / 2;
	float dx = px - (view.x + cx + view.translateX), dy = py - (view.y + cy + view.translateY);
	*lx = cx + (dx * m22 - dy * m21) / det;
	*ly = cy + (dy * m11 - dx * m12) / det;
	return YES;
}

static NSArray<NeonView *> *neonChildren(NeonView *view) {
	NSMutableArray<NeonView *> *out = [NSMutableArray array];
	for (NSView *child in [view neonChildHost].subviews) {
		if ([child isKindOfClass:NeonView.class]) [out addObject:(NeonView *)child];
	}
	return out;
}

static NSPoint childOffset(NeonView *view);
static BOOL isLabel(NeonView *view);

static NeonView *hitIn(NeonView *view, float px, float py, float *foundX, float *foundY) {
	float lx, ly;
	if (!toLocal(view, px, py, &lx, &ly)) return nil;
	BOOL inside = lx >= 0 && lx <= view.w && ly >= 0 && ly <= view.h;
	NSPoint offset = childOffset(view);
	BOOL clipsChildren = view.radius > 0 || offset.x != 0 || offset.y != 0 || [view neonChildHost] != view;
	if (inside || !clipsChildren) {
		for (NeonView *child in neonChildren(view).reverseObjectEnumerator) {
			NeonView *found = hitIn(child, lx + (float)offset.x, ly + (float)offset.y, foundX, foundY);
			if (found) return found;
		}
	}
	if (!inside || (isLabel(view) && !view.pressable)) return nil;
	*foundX = lx;
	*foundY = ly;
	return view;
}

static NeonView *hitTest(float x, float y, float *localX, float *localY) {
	float lx = 0, ly = 0;
	for (NeonView *child in neonChildren(g_root).reverseObjectEnumerator) {
		NeonView *found = hitIn(child, x, y, &lx, &ly);
		if (found) {
			if (localX) *localX = lx;
			if (localY) *localY = ly;
			return found;
		}
	}
	return nil;
}

static BOOL within(NSView *at, NSView *ancestor) {
	for (; at; at = at.superview) {
		if (at == ancestor) return YES;
	}
	return NO;
}

static NeonView *parentOf(NeonView *view) {
	for (NSView *at = view.superview; at; at = at.superview) {
		if ([at isKindOfClass:NeonView.class]) return (NeonView *)at;
	}
	return nil;
}

static int32_t spanTagAt(NeonView *view, float lx, float ly);

static void reportTag(int32_t tag, int32_t phase, float x, float y, double time) {
	g_touchTag = tag;
	g_touchPhase = phase;
	g_touchX = x;
	g_touchY = y;
	g_touchTime = time;
	invoke(s_touch);
}

static struct {
	BOOL active;
	int32_t spanTag;
	NeonView *spanLabel;
	NSMutableArray<NeonView *> *chain;
} g_touch;

static void endTouch(void) {
	g_touch.active = NO;
	g_touch.spanTag = 0;
	g_touch.spanLabel = nil;
	g_touch.chain = nil;
}

static void pointerDown(float x, float y, double time) {
	if (g_touch.active || !s_touch.fn) return;
	float lx = 0, ly = 0;
	NeonView *top = hitTest(x, y, &lx, &ly);
	g_touch.spanTag = spanTagAt(top, lx, ly);
	g_touch.spanLabel = g_touch.spanTag != 0 ? top : nil;
	g_touch.chain = [NSMutableArray array];
	for (NeonView *at = top; at && at != g_root; at = parentOf(at)) {
		if (at.neonTag != 0) [g_touch.chain addObject:at];
	}
	g_touch.active = g_touch.chain.count > 0 || g_touch.spanTag != 0;
	if (!g_touch.active) return;
	if (g_touch.spanTag != 0) reportTag(g_touch.spanTag, 0, x, y, time);
	for (NeonView *view in [g_touch.chain copy]) reportTag(view.neonTag, 0, x, y, time);
}

static void pointerMove(float x, float y, double time) {
	if (!g_touch.active) return;
	if (g_touch.spanTag != 0) reportTag(g_touch.spanTag, 4, x, y, time);
	for (NeonView *view in [g_touch.chain copy]) reportTag(view.neonTag, 4, x, y, time);
}

static void pointerUp(float x, float y, double time) {
	if (!g_touch.active) return;
	float lx = 0, ly = 0;
	NeonView *at = hitTest(x, y, &lx, &ly);
	if (g_touch.spanTag != 0) {
		if (at == g_touch.spanLabel && spanTagAt(at, lx, ly) == g_touch.spanTag) {
			reportTag(g_touch.spanTag, 1, x, y, time);
			reportTag(g_touch.spanTag, 2, x, y, time);
		} else {
			reportTag(g_touch.spanTag, 3, x, y, time);
		}
	}
	for (NeonView *view in [g_touch.chain copy]) {
		if (within(at, view)) {
			reportTag(view.neonTag, 1, x, y, time);
			reportTag(view.neonTag, 2, x, y, time);
		} else {
			reportTag(view.neonTag, 3, x, y, time);
		}
	}
	endTouch();
}

static void pointerCancel(void) {
	if (!g_touch.active) return;
	if (g_touch.spanTag != 0) reportTag(g_touch.spanTag, 3, g_touchX, g_touchY, g_touchTime);
	for (NeonView *view in [g_touch.chain copy]) reportTag(view.neonTag, 3, g_touchX, g_touchY, g_touchTime);
	endTouch();
}

// The root takes every mouse event over Neon's views and routes it through hitTest above; a view
// AppKit edits itself (a text field) gets its own events.
@interface NeonRoot : NeonView
@end

static NSView *nativeTarget(NeonView *view, NSPoint pointInRoot);

@implementation NeonRoot
- (NSView *)hitTest:(NSPoint)point {
	NSPoint local = [self convertPoint:point fromView:self.superview];
	if (!NSPointInRect(local, self.bounds)) return nil;
	NeonView *top = hitTest((float)local.x, (float)local.y, NULL, NULL);
	if (!top) return nil;
	NSView *native = nativeTarget(top, local);
	return native ? native : self;
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event { (void)event; return YES; }

- (NSPoint)neonPoint:(NSEvent *)event { return [self convertPoint:event.locationInWindow fromView:nil]; }

- (void)mouseDown:(NSEvent *)event {
	NSPoint p = [self neonPoint:event];
	pointerDown((float)p.x, (float)p.y, event.timestamp * 1000.0);
	requestHostFrame();
}

- (void)mouseDragged:(NSEvent *)event {
	NSPoint p = [self neonPoint:event];
	pointerMove((float)p.x, (float)p.y, event.timestamp * 1000.0);
	requestHostFrame();
}

- (void)mouseUp:(NSEvent *)event {
	NSPoint p = [self neonPoint:event];
	pointerUp((float)p.x, (float)p.y, event.timestamp * 1000.0);
	requestHostFrame();
}
@end

// --- text: one NSLayoutManager per label, the shape RN macOS's RCTTextLayoutManager keeps ---

@interface NeonRun : NSObject
@property(nonatomic) NSUInteger start, length;
@property(nonatomic, strong) NSColor *color;
@property(nonatomic) CGFloat size;
@property(nonatomic) BOOL bold, italic, underline, strike;
@property(nonatomic) int32_t tag;
@end

@implementation NeonRun
- (BOOL)sameShape:(NeonRun *)other {
	return self.start == other.start && self.length == other.length && self.size == other.size && self.bold == other.bold &&
		self.italic == other.italic && self.underline == other.underline && self.strike == other.strike;
}
@end

@interface NeonLabel : NeonView
@property(nonatomic, copy) NSString *text;
@property(nonatomic, strong) NSArray<NeonRun *> *runs;
@property(nonatomic, strong) NSColor *color;
@property(nonatomic) CGFloat fontSize;
@property(nonatomic) BOOL bold;
@property(nonatomic, copy) NSString *family;
@property(nonatomic) NSTextAlignment alignment;
@property(nonatomic) BOOL layoutStale;
@property(nonatomic, strong) NSTextStorage *storage;
@property(nonatomic, strong) NSLayoutManager *layoutManager;
@property(nonatomic, strong) NSTextContainer *container;
@end

static NSFont *labelFont(NSString *family, CGFloat size, BOOL bold, BOOL italic) {
	NSFont *font;
	if (family.length) {
		font = [NSFont fontWithName:family size:size];
		if (!font) {
			char message[192];
			snprintf(message, sizeof message, "fontFamily \"%s\" names no installed font", family.UTF8String);
			fail(message);
		}
		if (bold) font = [NSFontManager.sharedFontManager convertFont:font toHaveTrait:NSBoldFontMask];
	} else {
		font = [NSFont systemFontOfSize:size weight:bold ? NSFontWeightBold : NSFontWeightRegular];
	}
	if (italic) font = [NSFontManager.sharedFontManager convertFont:font toHaveTrait:NSItalicFontMask];
	return font;
}

@implementation NeonLabel

- (instancetype)initWithFrame:(NSRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		_text = @"";
		_runs = @[];
		_color = rgba(0, 0, 0, 1);
		_fontSize = 17;
		_alignment = NSTextAlignmentNatural;
		_storage = [[NSTextStorage alloc] init];
		_layoutManager = [[NSLayoutManager alloc] init];
		_container = [[NSTextContainer alloc] initWithSize:NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX)];
		_container.lineFragmentPadding = 0;
		[_layoutManager addTextContainer:_container];
		[_storage addLayoutManager:_layoutManager];
		self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawOnSetNeedsDisplay;
	}
	return self;
}

- (BOOL)wantsUpdateLayer { return NO; }

- (void)updateLayer {}

- (void)neonApply {
	[CATransaction begin];
	[CATransaction setDisableActions:YES];
	CALayer *layer = self.layer;
	layer.cornerRadius = self.radius;
	layer.masksToBounds = self.radius > 0;
	CATransform3D t = [self neonTransform];
	if (!CATransform3DEqualToTransform(layer.transform, t)) layer.transform = t;
	[CATransaction commit];
	self.needsDisplay = YES;
}

- (NSArray<NeonRun *> *)effectiveRuns {
	if (self.runs.count) return self.runs;
	NeonRun *run = [NeonRun new];
	run.length = self.text.length;
	run.size = self.fontSize;
	run.bold = self.bold;
	return @[run];
}

- (void)rebuild {
	NSMutableParagraphStyle *paragraph = [NSMutableParagraphStyle new];
	paragraph.alignment = self.alignment;
	NSMutableAttributedString *out = [[NSMutableAttributedString alloc] initWithString:self.text];
	for (NeonRun *run in [self effectiveRuns]) {
		NSMutableDictionary<NSAttributedStringKey, id> *attributes = [NSMutableDictionary dictionary];
		attributes[NSFontAttributeName] = labelFont(self.family, run.size, run.bold, run.italic);
		attributes[NSParagraphStyleAttributeName] = paragraph;
		if (run.underline) attributes[NSUnderlineStyleAttributeName] = @(NSUnderlineStyleSingle);
		if (run.strike) attributes[NSStrikethroughStyleAttributeName] = @(NSUnderlineStyleSingle);
		[out setAttributes:attributes range:NSMakeRange(run.start, run.length)];
	}
	[self.storage setAttributedString:out];
	self.layoutStale = NO;
	g_layoutsBuilt += 1;
}

// Colour is a temporary attribute: NSLayoutManager draws it and lays nothing out again for it.
- (void)recolour {
	NSRange all = NSMakeRange(0, self.storage.length);
	[self.layoutManager removeTemporaryAttribute:NSForegroundColorAttributeName forCharacterRange:all];
	[self.layoutManager addTemporaryAttribute:NSForegroundColorAttributeName value:self.color forCharacterRange:all];
	for (NeonRun *run in self.runs) {
		if (run.color) [self.layoutManager addTemporaryAttribute:NSForegroundColorAttributeName value:run.color forCharacterRange:NSMakeRange(run.start, run.length)];
	}
}

- (void)ensureAt:(CGFloat)width {
	if (self.layoutStale) [self rebuild];
	if (self.container.size.width != width) self.container.size = NSMakeSize(width, CGFLOAT_MAX);
	[self.layoutManager ensureLayoutForTextContainer:self.container];
}

- (void)changed:(BOOL)shape {
	if (shape) self.layoutStale = YES;
	self.needsDisplay = YES;
	requestHostFrame();
}

- (void)drawRect:(NSRect)dirty {
	(void)dirty;
	[self ensureAt:self.bounds.size.width];
	[self recolour];
	NSRange glyphs = [self.layoutManager glyphRangeForTextContainer:self.container];
	[self.layoutManager drawBackgroundForGlyphRange:glyphs atPoint:NSZeroPoint];
	[self.layoutManager drawGlyphsForGlyphRange:glyphs atPoint:NSZeroPoint];
}

- (int32_t)tagAt:(NSPoint)point {
	if (self.runs.count == 0 || self.storage.length == 0) return 0;
	[self ensureAt:self.bounds.size.width];
	CGFloat fraction = 0;
	NSUInteger glyph = [self.layoutManager glyphIndexForPoint:point inTextContainer:self.container fractionOfDistanceThroughGlyph:&fraction];
	NSRect box = [self.layoutManager boundingRectForGlyphRange:NSMakeRange(glyph, 1) inTextContainer:self.container];
	if (!NSPointInRect(point, box)) return 0;
	NSUInteger index = [self.layoutManager characterIndexForGlyphAtIndex:glyph];
	for (NeonRun *run in self.runs) {
		if (run.tag != 0 && NSLocationInRange(index, NSMakeRange(run.start, run.length))) return run.tag;
	}
	return 0;
}
@end

static BOOL isLabel(NeonView *view) { return [view isKindOfClass:NeonLabel.class]; }

static int32_t spanTagAt(NeonView *view, float lx, float ly) {
	return isLabel(view) ? [(NeonLabel *)view tagAt:NSMakePoint(lx, ly)] : 0;
}

static NeonLabel *labelOf(void *view, const char *what) {
	if (isLabel(as(view))) return (NeonLabel *)as(view);
	char message[192];
	snprintf(message, sizeof message, "%s on a view that is not a Text", what);
	fail(message);
	return nil;
}

static NSColor *cssColor(NSString *css) {
	if (![css hasPrefix:@"#"] || (css.length != 4 && css.length != 7)) {
		char message[192];
		snprintf(message, sizeof message, "textSpans colour \"%s\" is not #rgb or #rrggbb", css.UTF8String);
		fail(message);
	}
	NSString *hex = [css substringFromIndex:1];
	if (hex.length == 3) hex = [NSString stringWithFormat:@"%C%C%C%C%C%C", [hex characterAtIndex:0], [hex characterAtIndex:0], [hex characterAtIndex:1],
		[hex characterAtIndex:1], [hex characterAtIndex:2], [hex characterAtIndex:2]];
	unsigned rgb = 0;
	[[NSScanner scannerWithString:hex] scanHexInt:&rgb];
	return rgba(((rgb >> 16) & 0xff) / 255.0f, ((rgb >> 8) & 0xff) / 255.0f, (rgb & 0xff) / 255.0f, 1);
}

// textSpans: records split by 0x1e, fields by 0x1f: text, colour, size, bold, italic, underline, line-through, press tag.
static void setRuns(NeonLabel *label, const char *encoded) {
	NSMutableString *text = [NSMutableString string];
	NSMutableArray<NeonRun *> *runs = [NSMutableArray array];
	for (NSString *record in [@(encoded) componentsSeparatedByString:@"\x1e"]) {
		if (record.length == 0) continue;
		NSArray<NSString *> *f = [record componentsSeparatedByString:@"\x1f"];
		if (f.count != 8) {
			char message[256];
			snprintf(message, sizeof message, "textSpans record does not have 8 fields: %s", record.UTF8String);
			fail(message);
		}
		NeonRun *run = [NeonRun new];
		run.start = text.length;
		run.length = f[0].length;
		[text appendString:f[0]];
		if (f[1].length) run.color = cssColor(f[1]);
		run.size = f[2].doubleValue;
		run.bold = [f[3] isEqualToString:@"1"];
		run.italic = [f[4] isEqualToString:@"1"];
		run.underline = [f[5] isEqualToString:@"1"];
		run.strike = [f[6] isEqualToString:@"1"];
		run.tag = f[7].intValue;
		[runs addObject:run];
	}
	BOOL shapeKept = [text isEqualToString:label.text] && runs.count == label.runs.count;
	for (NSUInteger i = 0; shapeKept && i < runs.count; i++) shapeKept = [runs[i] sameShape:label.runs[i]];
	label.text = text;
	label.runs = runs;
	[label changed:!shapeKept];
}

static NSTextAlignment alignmentOf(const char *value) {
	if (!strcmp(value, "") || !strcmp(value, "auto")) return NSTextAlignmentNatural;
	if (!strcmp(value, "left")) return NSTextAlignmentLeft;
	if (!strcmp(value, "right")) return NSTextAlignmentRight;
	if (!strcmp(value, "center")) return NSTextAlignmentCenter;
	if (!strcmp(value, "justify")) return NSTextAlignmentJustified;
	char message[128];
	snprintf(message, sizeof message, "textAlign \"%s\"", value);
	unimplemented(message);
	return NSTextAlignmentNatural;
}

// --- placeholders the later slices replace ---

static NSPoint childOffset(NeonView *view) { (void)view; return NSZeroPoint; }
static NSView *nativeTarget(NeonView *view, NSPoint pointInRoot) { (void)view; (void)pointInRoot; return nil; }

// --- handoff ---

void nimAttach(void *root, float scale, float logicalWidth, float logicalHeight) {
	if (g_root) fail("nimAttach called twice");
	if (!root) fail("nimAttach without a root view");
	NSView *parent = (__bridge NSView *)root;
	g_root = [[NeonRoot alloc] initWithFrame:parent.bounds];
	g_root.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
	g_root.w = (float)parent.bounds.size.width;
	g_root.h = (float)parent.bounds.size.height;
	[parent addSubview:g_root positioned:NSWindowAbove relativeTo:nil];
	g_scale = scale;
	g_width = logicalWidth;
	g_height = logicalHeight;
}

void nimResize(float scale, float logicalWidth, float logicalHeight) {
	requireAttached("nimResize");
	g_scale = scale;
	g_width = logicalWidth;
	g_height = logicalHeight;
	g_root.w = logicalWidth;
	g_root.h = logicalHeight;
	if (s_resize.fn) invoke(s_resize);
	requestHostFrame();
}

void nimFrame(void) {
	requireAttached("nimFrame");
	g_frameRequested = NO;
	g_inFrame = YES;
	if (s_loop.fn) invoke(s_loop);
	else niLoopRun();
	if (g_frameWanted) {
		g_frameWanted = NO;
		if (s_frame.fn) invoke(s_frame);
	}
	g_inFrame = NO;
}

void nimSetFrameRequester(msClosure requester) { s_requester = requester; }

static int countStored(NeonView *view, NSString *name, NSString *value) {
	int count = [view.accessibility[name] isEqualToString:value] ? 1 : 0;
	for (NeonView *child in neonChildren(view)) count += countStored(child, name, value);
	return count;
}

int nimStoredAccessibility(const char *name, const char *value) {
	requireAttached("nimStoredAccessibility");
	return countStored(g_root, @(name), @(value));
}

int nimLayoutsBuilt(void) { return g_layoutsBuilt; }

void nimShutdown(void) {
	if (s_teardown.fn) invoke(s_teardown);
}

// --- bridge.h: views ---

void *niViewCreate(void) {
	requireAttached("niViewCreate");
	return (void *)CFBridgingRetain([[NeonView alloc] initWithFrame:NSZeroRect]);
}

void niViewSetTag(void *view, int32_t tag) { as(view).neonTag = tag; }
void niViewSetPressable(void *view) { as(view).pressable = YES; }

void niAddChild(void *parent, void *child) {
	[[as(parent) neonChildHost] addSubview:as(child)];
	requestHostFrame();
}

void niBringChildToFront(void *child) {
	NeonView *c = as(child);
	NSView *parent = c.superview;
	if (!parent) return;
	[c removeFromSuperviewWithoutNeedingDisplay];
	[parent addSubview:c];
	requestHostFrame();
}

void niRemoveFromParent(void *child) {
	[as(child) removeFromSuperview];
	requestHostFrame();
}

void niViewRelease(void *view) {
	if (view) CFRelease(view);
}

void niSetFrame(void *view, float x, float y, float w, float h) {
	NeonView *v = as(view);
	v.x = x;
	v.y = y;
	v.w = w;
	v.h = h;
	v.frame = NSMakeRect(x, y, w, h);
	[v neonApply];
	requestHostFrame();
}

void niSetTransform(void *view, float scaleX, float scaleY, float translateX, float translateY) {
	NeonView *v = as(view);
	v.scaleX = scaleX;
	v.scaleY = scaleY;
	v.translateX = translateX;
	v.translateY = translateY;
	[v neonApply];
	requestHostFrame();
}

void niSetRotation(void *view, float degrees) {
	as(view).rotation = degrees;
	[as(view) neonApply];
	requestHostFrame();
}

void niSetBackgroundColor(void *view, float r, float g, float b, float a) {
	if (isLabel(as(view))) fail("niSetBackgroundColor on a Text: the native host gives a Text no background");
	as(view).neonBackground = rgba(r, g, b, a);
	[as(view) neonApply];
	requestHostFrame();
}

void niSetCornerRadius(void *view, float radius) {
	as(view).radius = radius;
	[as(view) neonApply];
	requestHostFrame();
}

void niSetOpacity(void *view, float opacity) {
	as(view).alphaValue = opacity;
	requestHostFrame();
}

// --- bridge.h: lifecycle ---

void niRegisterApp(msClosure mount) { s_mount = mount; }
void niSetResizeHandler(msClosure handler) { s_resize = handler; }
void niSetTeardownHandler(msClosure handler) { s_teardown = handler; }
void niSetLoopHandler(msClosure handler) { s_loop = handler; }
void niSetFrameHandler(msClosure handler) { s_frame = handler; }
void niSetTouchHandler(msClosure handler) { s_touch = handler; }
void niSetScrollHandler(msClosure handler) { s_scroll = handler; }
void niSetControlHandler(msClosure handler) { s_control = handler; }
void niSetEnvironmentHandler(msClosure handler) { s_environment = handler; }
void niSetAppHandler(msClosure handler) { s_app = handler; }

int niRequestFrame(void) {
	if (!s_requester.fn) return 0;
	g_frameWanted = YES;
	requestHostFrame();
	return 1;
}

int niRunApp(void) {
	requireAttached("niRunApp");
	if (!s_mount.fn) fail("niRunApp before niRegisterApp");
	invoke(s_mount);
	requestHostFrame();
	return 0;
}

void *niContainerView(void) {
	requireAttached("niContainerView");
	return (__bridge void *)g_root;
}

float niScreenWidth(void) { return g_width; }
float niScreenHeight(void) { return g_height; }
float niSafeAreaInset(int edge) { (void)edge; return 0; }
float niKeyboardHeight(void) { return 0; }
int niColorScheme(void) { return 0; }

void niInvokeClosure(msClosure c) { invoke(c); }

const char *niAppCall(const char *name, const char *arg) {
	static char reply[64];
	(void)arg;
	if (!strcmp(name, "platform")) {
		NSOperatingSystemVersion v = NSProcessInfo.processInfo.operatingSystemVersion;
		snprintf(reply, sizeof reply, "%ld.%ld.%ld", (long)v.majorVersion, (long)v.minorVersion, (long)v.patchVersion);
	} else if (!strcmp(name, "isPad") || !strcmp(name, "a11y.screenReader") || !strcmp(name, "a11y.reduceMotion")) {
		snprintf(reply, sizeof reply, "0");
	} else if (!strcmp(name, "pixelRatio")) {
		snprintf(reply, sizeof reply, "%g", g_scale);
	} else if (!strcmp(name, "fontScale")) {
		snprintf(reply, sizeof reply, "1");
	} else if (!strcmp(name, "screen")) {
		snprintf(reply, sizeof reply, "%g\x1f" "%g", g_width, g_height);
	} else if (!strcmp(name, "appState")) {
		snprintf(reply, sizeof reply, "active");
	} else if (!strcmp(name, "notification.install")) {
		reply[0] = '\0';
	} else {
		char what[128];
		snprintf(what, sizeof what, "niAppCall(%s)", name);
		unimplemented(what);
	}
	return reply;
}

// --- bridge.h: event reads ---

int niLastTouchTag(void) { return g_touchTag; }
int niLastTouchPhase(void) { return g_touchPhase; }
float niLastTouchX(void) { return g_touchX; }
float niLastTouchY(void) { return g_touchY; }
double niLastTouchTime(void) { return g_touchTime; }
void niSetResponder(void *view, int blockNativeResponder) { (void)view; (void)blockNativeResponder; }
void niClearResponder(void) {}
int niLastScrollTag(void) { return g_scrollTag; }
int niLastScrollPhase(void) { return g_scrollPhase; }
float niLastScrollX(void) { return g_scrollX; }
float niLastScrollY(void) { return g_scrollY; }
float niLastScrollWidth(void) { return g_scrollW; }
float niLastScrollHeight(void) { return g_scrollH; }
float niLastScrollContentWidth(void) { return g_scrollContentW; }
float niLastScrollContentHeight(void) { return g_scrollContentH; }
int niLastControlTag(void) { return g_controlTag; }
int niLastControlPhase(void) { return g_controlPhase; }
const char *niLastControlValue(void) { return g_controlValue ? g_controlValue : ""; }
float niLastControlWidth(void) { return 0; }
float niLastControlHeight(void) { return 0; }

static BOOL isAccessibilityProp(const char *name) {
	return !strcmp(name, "accessible") || !strcmp(name, "accessibilityLabel") || !strcmp(name, "accessibilityHint") ||
		!strcmp(name, "accessibilityRole") || !strcmp(name, "accessibilityState");
}

void niSetProp(void *view, const char *name, const char *value) {
	const char *text = value ? value : "";
	if (isLabel(as(view)) && !strcmp(name, "textSpans")) {
		setRuns((NeonLabel *)as(view), text);
		return;
	}
	if (isLabel(as(view)) && !strcmp(name, "fontFamily")) {
		NeonLabel *l = (NeonLabel *)as(view);
		l.family = @(text);
		[l changed:YES];
		return;
	}
	if (isLabel(as(view)) && !strcmp(name, "textAlign")) {
		NeonLabel *l = (NeonLabel *)as(view);
		l.alignment = alignmentOf(text);
		[l changed:YES];
		return;
	}
	if (isAccessibilityProp(name)) {
		as(view).accessibility[@(name)] = @(text);
		return;
	}
	char what[128];
	snprintf(what, sizeof what, "niSetProp(%s)", name);
	unimplemented(what);
}

#define UNIMPLEMENTED(ret, name, params) \
	ret name params { unimplemented(#name); return (ret)0; }
#define UNIMPLEMENTED_VOID(name, params) \
	void name params { unimplemented(#name); }

// --- bridge.h: text ---

void *niTextCreate(void) {
	requireAttached("niTextCreate");
	return (void *)CFBridgingRetain([[NeonLabel alloc] initWithFrame:NSZeroRect]);
}

void niSetText(void *label, const char *s) {
	NeonLabel *l = labelOf(label, "niSetText");
	NSString *text = s ? @(s) : @"";
	if (!text) fail("niSetText: the text is not valid UTF-8");
	BOOL shape = l.runs.count > 0 || ![text isEqualToString:l.text];
	l.text = text;
	l.runs = @[];
	[l changed:shape];
}

void niSetTextColor(void *label, float r, float g, float b, float a) {
	NeonLabel *l = labelOf(label, "niSetTextColor");
	NSColor *color = rgba(r, g, b, a);
	if ([color isEqual:l.color]) return;
	l.color = color;
	[l changed:NO];
}

void niSetFont(void *label, float size, int bold) {
	NeonLabel *l = labelOf(label, "niSetFont");
	if (l.fontSize == size && l.bold == (bold != 0)) return;
	l.fontSize = size;
	l.bold = bold != 0;
	[l changed:YES];
}

void niMeasureText(void *label, float maxWidth) {
	requireAttached("niMeasureText");
	NeonLabel *l = labelOf(label, "niMeasureText");
	[l ensureAt:maxWidth];
	NSRect used = [l.layoutManager usedRectForTextContainer:l.container];
	g_measuredW = ceilf((float)used.size.width);
	g_measuredH = ceilf((float)used.size.height);
}

float niMeasuredW(void) { return g_measuredW; }
float niMeasuredH(void) { return g_measuredH; }

UNIMPLEMENTED(void *, niScrollCreate, (void))
UNIMPLEMENTED_VOID(niScrollSetTag, (void *scroll, int32_t tag))
UNIMPLEMENTED_VOID(niScrollSetContentSize, (void *scroll, float w, float h))
UNIMPLEMENTED_VOID(niScrollTo, (void *scroll, float x, float y, int animated))
UNIMPLEMENTED_VOID(niScrollSetOption, (void *scroll, const char *name, const char *value))
UNIMPLEMENTED_VOID(niScrollShift, (void *scroll, float dx, float dy))
UNIMPLEMENTED(float, niScrollOffsetX, (void *scroll))
UNIMPLEMENTED(float, niScrollOffsetY, (void *scroll))
UNIMPLEMENTED(void *, niInputCreate, (void))
UNIMPLEMENTED(void *, niTextAreaCreate, (void))
UNIMPLEMENTED_VOID(niControlSetTag, (void *control, int32_t tag))
UNIMPLEMENTED_VOID(niSetFocused, (void *control, int focused))
UNIMPLEMENTED(void *, niSwitchCreate, (void))
UNIMPLEMENTED(void *, niIndicatorCreate, (void))
UNIMPLEMENTED(void *, niImageCreate, (void))
UNIMPLEMENTED(void *, niModalCreate, (void))
UNIMPLEMENTED(void *, niControlCreate, (const char *kind))
UNIMPLEMENTED_VOID(niSetReloadPoll, (msClosure poll))
UNIMPLEMENTED(int, niLastAppEvent, (void))
UNIMPLEMENTED(const char *, niLastAppValue, (void))
UNIMPLEMENTED_VOID(niSetAppEventResult, (int result))
