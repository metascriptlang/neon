#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreImage/CoreImage.h>
#include "../native/app.h"
#include "../native/components.h"
#include "../native/loop.h"
#include "handoff.h"
#import "view.h"
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
static float g_controlW = 0, g_controlH = 0;
static char *g_controlValue = NULL;
static int g_appEvent = 0;
static char *g_appValue = NULL;
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

void neonUnimplemented(const char *what) { unimplemented(what); }

static void requestHostFrame(void) {
	if (g_frameRequested || g_inFrame || !s_requester.fn) return;
	g_frameRequested = YES;
	invoke(s_requester);
}

static NSColor *rgba(float r, float g, float b, float a) {
	return [NSColor colorWithSRGBRed:r green:g blue:b alpha:a];
}

// --- views ---

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
	layer.masksToBounds = self.radius > 0 || self.clips;
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

NeonView *neonRequireRoot(const char *what) {
	requireAttached(what);
	return g_root;
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
	BOOL clipsChildren = view.radius > 0 || view.clips || offset.x != 0 || offset.y != 0 || [view neonChildHost] != view;
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
static void routeWheel(NSEvent *event, NSPoint pointInRoot);

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

- (void)scrollWheel:(NSEvent *)event { routeWheel(event, [self neonPoint:event]); }
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
@property(nonatomic) NSWritingDirection direction;
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
	layer.masksToBounds = self.radius > 0 || self.clips;
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
	paragraph.baseWritingDirection = self.direction;
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

// --- accessibility: the stored props answer NSAccessibility, as RN macOS's RCTView and RCTTextView ---

// RCTConvert.mm accessibilityRoleFromAriaRole: `role`; a role it lacks falls to the trait table.
static NSAccessibilityRole ariaRole(NSString *role) {
	static NSDictionary<NSString *, NSAccessibilityRole> *map;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		map = @{
			@"alert": NSAccessibilityGroupRole, @"alertdialog": NSAccessibilityGroupRole, @"application": NSAccessibilityGroupRole,
			@"article": NSAccessibilityGroupRole, @"banner": NSAccessibilityGroupRole, @"button": NSAccessibilityButtonRole,
			@"cell": NSAccessibilityCellRole, @"checkbox": NSAccessibilityCheckBoxRole, @"columnheader": NSAccessibilityCellRole,
			@"combobox": NSAccessibilityComboBoxRole, @"complementary": NSAccessibilityGroupRole, @"contentinfo": NSAccessibilityGroupRole,
			@"definition": NSAccessibilityGroupRole, @"dialog": NSAccessibilityGroupRole, @"directory": NSAccessibilityListRole,
			@"document": NSAccessibilityGroupRole, @"feed": NSAccessibilityGroupRole, @"figure": NSAccessibilityGroupRole,
			@"form": NSAccessibilityGroupRole, @"grid": NSAccessibilityTableRole, @"gridcell": NSAccessibilityCellRole,
			@"group": NSAccessibilityGroupRole, @"heading": NSAccessibilityStaticTextRole, @"image": NSAccessibilityImageRole,
			@"img": NSAccessibilityImageRole, @"link": NSAccessibilityLinkRole, @"list": NSAccessibilityListRole,
			@"listbox": NSAccessibilityListRole, @"listitem": NSAccessibilityGroupRole, @"log": NSAccessibilityGroupRole,
			@"main": NSAccessibilityGroupRole, @"marquee": NSAccessibilityGroupRole, @"math": NSAccessibilityGroupRole,
			@"menu": NSAccessibilityMenuRole, @"menubar": NSAccessibilityMenuBarRole, @"menuitem": NSAccessibilityMenuItemRole,
			@"menuitemcheckbox": NSAccessibilityMenuItemRole, @"menuitemradio": NSAccessibilityMenuItemRole,
			@"meter": NSAccessibilityLevelIndicatorRole, @"navigation": NSAccessibilityGroupRole, @"none": NSAccessibilityGroupRole,
			@"note": NSAccessibilityGroupRole, @"option": NSAccessibilityStaticTextRole, @"presentation": NSAccessibilityGroupRole,
			@"progressbar": NSAccessibilityProgressIndicatorRole, @"radio": NSAccessibilityRadioButtonRole,
			@"radiogroup": NSAccessibilityRadioGroupRole, @"region": NSAccessibilityGroupRole, @"row": NSAccessibilityRowRole,
			@"rowheader": NSAccessibilityCellRole, @"scrollbar": NSAccessibilityScrollBarRole, @"search": NSAccessibilityGroupRole,
			@"searchbox": NSAccessibilityTextFieldRole, @"separator": NSAccessibilitySplitterRole, @"slider": NSAccessibilitySliderRole,
			@"spinbutton": NSAccessibilityIncrementorRole, @"status": NSAccessibilityGroupRole, @"switch": NSAccessibilityCheckBoxRole,
			@"tab": NSAccessibilityRadioButtonRole, @"table": NSAccessibilityTableRole, @"tablist": NSAccessibilityTabGroupRole,
			@"tabpanel": NSAccessibilityGroupRole, @"term": NSAccessibilityGroupRole, @"textbox": NSAccessibilityTextFieldRole,
			@"timer": NSAccessibilityGroupRole, @"toolbar": NSAccessibilityToolbarRole, @"tooltip": NSAccessibilityGroupRole,
			@"tree": NSAccessibilityOutlineRole, @"treegrid": NSAccessibilityTableRole, @"treeitem": NSAccessibilityRowRole,
		};
	});
	return map[role];
}

// RCTConvert.mm accessibilityRoleFromTrait: `accessibilityRole`.
static NSAccessibilityRole traitRole(NSString *role) {
	static NSDictionary<NSString *, NSAccessibilityRole> *map;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		map = @{
			@"adjustable": NSAccessibilitySliderRole, @"alert": NSAccessibilityStaticTextRole, @"button": NSAccessibilityButtonRole,
			@"checkbox": NSAccessibilityCheckBoxRole, @"combobox": NSAccessibilityComboBoxRole, @"header": NSAccessibilityStaticTextRole,
			@"image": NSAccessibilityImageRole, @"imagebutton": NSAccessibilityButtonRole, @"keyboardkey": NSAccessibilityButtonRole,
			@"link": NSAccessibilityLinkRole, @"menu": NSAccessibilityMenuRole, @"menubar": NSAccessibilityMenuBarRole,
			@"menuitem": NSAccessibilityMenuItemRole, @"none": NSAccessibilityUnknownRole,
			@"progressbar": NSAccessibilityProgressIndicatorRole, @"radio": NSAccessibilityRadioButtonRole,
			@"radiogroup": NSAccessibilityRadioGroupRole, @"scrollbar": NSAccessibilityScrollBarRole,
			@"search": NSAccessibilityTextFieldRole, @"spinbutton": NSAccessibilityIncrementorRole,
			@"summary": NSAccessibilityStaticTextRole, @"switch": NSAccessibilityCheckBoxRole, @"tab": NSAccessibilityButtonRole,
			@"tablist": NSAccessibilityTabGroupRole, @"text": NSAccessibilityStaticTextRole, @"timer": NSAccessibilityStaticTextRole,
			@"toolbar": NSAccessibilityToolbarRole, @"disclosure": NSAccessibilityDisclosureTriangleRole,
			@"group": NSAccessibilityGroupRole, @"list": NSAccessibilityListRole, @"popupbutton": NSAccessibilityPopUpButtonRole,
			@"menubutton": NSAccessibilityMenuButtonRole, @"table": NSAccessibilityTableRole,
		};
	});
	return map[role] ?: NSAccessibilityUnknownRole;
}

static NSString *recursiveLabel(NSView *view);

// RCTView.m RCTRecursiveAccessibilityLabel: a Text answers its value, any other child its label or its own children's.
static NSString *recursiveLabel(NSView *view) {
	NSMutableString *out = nil;
	for (NSView *sub in view.subviews) {
		NSString *label = [sub isKindOfClass:NeonView.class] && isLabel((NeonView *)sub) ? sub.accessibilityValue : sub.accessibilityLabel;
		if (!label) label = recursiveLabel(sub);
		if (label.length == 0) continue;
		if (!out) out = [NSMutableString string];
		if (out.length) [out appendString:@" "];
		[out appendString:label];
	}
	return out;
}

@interface NeonView (NeonAccessibility)
- (NSString *)neonAXProp:(NSString *)name;
- (BOOL)neonAXState:(NSString *)token;
- (NSArray<NSArray<NSString *> *> *)neonAXActions;
- (BOOL)neonPerformAction:(NSString *)name;
@end

static NSArray<NSView *> *axChildren(NSView *view);

@implementation NeonView (NeonAccessibility)

- (NSString *)neonAXProp:(NSString *)name {
	NSString *value = self.accessibility[name];
	return value.length ? value : nil;
}

- (BOOL)neonAXState:(NSString *)token {
	return [[[self neonAXProp:@"accessibilityState"] componentsSeparatedByString:@","] containsObject:token];
}

- (BOOL)neonAXFlag:(NSString *)name { return [[self neonAXProp:name] isEqualToString:@"true"]; }

// importantForAccessibility is Android's (BaseViewConfig.android.js:219); RN macOS has no handler, so "no" and
// "no-hide-descendants" follow RN Android and iOS's accessibilityElementsHidden.
- (BOOL)neonAXHidesSubtree {
	return [self neonAXFlag:@"accessibilityElementsHidden"] || [[self neonAXProp:@"importantForAccessibility"] isEqualToString:@"no-hide-descendants"];
}

// RCTViewManager.m:313-345: `role` wins, then `accessibilityRole`, then the view's own role.
- (NSAccessibilityRole)accessibilityRole {
	NSString *role = [self neonAXProp:@"role"];
	NSAccessibilityRole mapped = role && ![role isEqualToString:@"rowgroup"] ? (ariaRole(role) ?: traitRole(role)) : nil;
	if (mapped) return mapped;
	NSString *trait = [self neonAXProp:@"accessibilityRole"];
	if (trait) return traitRole(trait);
	return isLabel(self) ? NSAccessibilityStaticTextRole : NSAccessibilityUnknownRole;
}

// RCTViewManager.m:203-205 `accessible`; RCTTextView.mm:82 a Text is an element unless told otherwise.
- (BOOL)isAccessibilityElement {
	if ([self neonAXHidesSubtree]) return NO;
	NSString *important = [self neonAXProp:@"importantForAccessibility"];
	if ([important isEqualToString:@"no"]) return NO;
	NSString *accessible = [self neonAXProp:@"accessible"];
	if (accessible) return [accessible isEqualToString:@"true"];
	return [important isEqualToString:@"yes"] || isLabel(self);
}

// RCTView.m:295-309; a Text keeps its words in the value, as RCTTextView.mm:339-357 does for VoiceOver.
- (NSString *)accessibilityLabel {
	if (isLabel(self)) return nil;
	NSString *label = [self neonAXProp:@"accessibilityLabel"];
	if (label) return label;
	return self.isAccessibilityElement ? recursiveLabel(self) : nil;
}

- (NSString *)accessibilityHelp { return [self neonAXProp:@"accessibilityHint"]; }

- (NSArray<NSString *> *)neonAXValueParts {
	NSString *raw = [self neonAXProp:@"accessibilityValue"];
	if (!raw) return nil;
	NSMutableArray<NSString *> *parts = [NSMutableArray array];
	NSString *rest = raw;
	for (int i = 0; i < 3; i++) {
		NSRange comma = [rest rangeOfString:@","];
		if (comma.location == NSNotFound) break;
		[parts addObject:[rest substringToIndex:comma.location]];
		rest = [rest substringFromIndex:NSMaxRange(comma)];
	}
	[parts addObject:rest];
	return parts.count == 4 ? parts : nil;
}

- (NSNumber *)neonAXNumber:(NSUInteger)index {
	NSString *part = [self neonAXValueParts][index];
	if (part.length == 0) return nil;
	return @(part.doubleValue);
}

// RCTView.m:463-501.
- (id)accessibilityValue {
	id value = nil;
	NSAccessibilityRole role = self.accessibilityRole;
	if ([role isEqual:NSAccessibilityCheckBoxRole] || [role isEqual:NSAccessibilityRadioButtonRole] || [role isEqual:NSAccessibilityDisclosureTriangleRole]) {
		if ([self neonAXState:@"mixed"]) value = @2;
		else if ([self neonAXState:@"checked"] || [self neonAXState:@"selected"]) value = @1;
		else if ([self neonAXState:@"unchecked"]) value = @0;
	} else if ([role isEqual:NSAccessibilityStaticTextRole]) {
		if (isLabel(self)) value = [self neonAXProp:@"accessibilityLabel"] ?: ((NeonLabel *)self).text;
		else value = self.accessibilityLabel;
	}
	NSArray<NSString *> *parts = [self neonAXValueParts];
	if (parts && parts[3].length) return parts[3];
	if (parts && parts[2].length) return [self neonAXNumber:2];
	return value;
}

- (id)accessibilityMinValue { return [self neonAXValueParts] ? [self neonAXNumber:0] : nil; }
- (id)accessibilityMaxValue { return [self neonAXValueParts] ? [self neonAXNumber:1] : nil; }

// RCTView.m:565-596: the state tokens answer the three flags.
- (BOOL)isAccessibilityEnabled { return ![self neonAXState:@"disabled"]; }
- (BOOL)isAccessibilitySelected { return [self neonAXState:@"selected"]; }
- (BOOL)isAccessibilityExpanded { return [self neonAXState:@"expanded"]; }

- (BOOL)isAccessibilityModal { return [self neonAXFlag:@"accessibilityViewIsModal"]; }

// RCTView.m:312-335: a line is "name" or "name\tlabel"; a labelled one becomes an NSAccessibilityCustomAction.
- (NSArray<NSArray<NSString *> *> *)neonAXActions {
	NSString *raw = [self neonAXProp:@"accessibilityActions"];
	if (!raw) return @[];
	NSMutableArray<NSArray<NSString *> *> *out = [NSMutableArray array];
	for (NSString *line in [raw componentsSeparatedByString:@"\n"]) {
		NSArray<NSString *> *fields = [line componentsSeparatedByString:@"\t"];
		[out addObject:@[fields[0], fields.count > 1 ? fields[1] : @""]];
	}
	return out;
}

- (BOOL)neonHasAction:(NSString *)name {
	for (NSArray<NSString *> *action in [self neonAXActions]) {
		if ([action[0] isEqualToString:name]) return YES;
	}
	return NO;
}

- (NSArray<NSAccessibilityCustomAction *> *)accessibilityCustomActions {
	NSMutableArray<NSAccessibilityCustomAction *> *out = [NSMutableArray array];
	for (NSArray<NSString *> *action in [self neonAXActions]) {
		if (action[1].length == 0) continue;
		NSString *name = action[0];
		[out addObject:[[NSAccessibilityCustomAction alloc] initWithName:action[1] handler:^BOOL {
			return [self neonPerformAction:name];
		}]];
	}
	return out.count ? out : nil;
}

// RCTView.m:636-642: the action reaches onAccessibilityAction (control phase 15) only when the view declared it.
- (BOOL)neonPerformAction:(NSString *)name {
	if (self.neonTag == 0 || ![self neonHasAction:name]) return NO;
	neonEmitControl(self.neonTag, 15, name, 0, 0);
	return YES;
}

// RCTView.m:646-663: "activate", else the press the view already answers to a click.
- (BOOL)accessibilityPerformPress {
	if (![self isAccessibilityEnabled]) return NO;
	if ([self neonPerformAction:@"activate"]) return YES;
	if (!self.pressable || self.neonTag == 0) return NO;
	NSPoint at = [self convertPoint:NSMakePoint(NSMidX(self.bounds), NSMidY(self.bounds)) toView:g_root];
	double time = NSProcessInfo.processInfo.systemUptime * 1000.0;
	reportTag(self.neonTag, 0, (float)at.x, (float)at.y, time);
	reportTag(self.neonTag, 1, (float)at.x, (float)at.y, time);
	reportTag(self.neonTag, 2, (float)at.x, (float)at.y, time);
	requestHostFrame();
	return YES;
}

- (BOOL)accessibilityPerformEscape { return [self neonPerformAction:@"escape"]; }
- (BOOL)accessibilityPerformIncrement { return [self neonPerformAction:@"increment"]; }
- (BOOL)accessibilityPerformDecrement { return [self neonPerformAction:@"decrement"]; }
- (BOOL)accessibilityPerformShowMenu { return [self neonPerformAction:@"showMenu"]; }

// RCTView.m:504-551: an action is offered to VoiceOver only when the view can perform it.
- (BOOL)isAccessibilitySelectorAllowed:(SEL)selector {
	if (selector == @selector(accessibilityPerformPress)) return [self neonHasAction:@"activate"] || self.pressable;
	if (selector == @selector(accessibilityPerformIncrement)) return [self neonHasAction:@"increment"];
	if (selector == @selector(accessibilityPerformDecrement)) return [self neonHasAction:@"decrement"];
	if (selector == @selector(accessibilityPerformShowMenu)) return [self neonHasAction:@"showMenu"];
	if (selector == @selector(accessibilityPerformEscape)) return [self neonHasAction:@"escape"];
	return YES;
}

- (NSArray *)accessibilityChildren { return axChildren(self); }
@end

// The children VoiceOver walks: an element stands for itself, a plain view for what it holds, and a hidden subtree for nothing.
static NSArray<NSView *> *axChildren(NSView *view) {
	NSMutableArray<NSView *> *out = [NSMutableArray array];
	if ([view isKindOfClass:NeonView.class] && [(NeonView *)view neonAXHidesSubtree]) return out;
	for (NSView *sub in view.subviews) {
		if ([sub isKindOfClass:NeonView.class] && [(NeonView *)sub neonAXHidesSubtree]) continue;
		if (sub.isAccessibilityElement) [out addObject:sub];
		else [out addObjectsFromArray:axChildren(sub)];
	}
	return out;
}

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
		snprintf(message, sizeof message, "colour \"%s\" is not #rgb or #rrggbb", css.UTF8String);
		fail(message);
	}
	NSString *hex = [css substringFromIndex:1];
	if (hex.length == 3) hex = [NSString stringWithFormat:@"%C%C%C%C%C%C", [hex characterAtIndex:0], [hex characterAtIndex:0], [hex characterAtIndex:1],
		[hex characterAtIndex:1], [hex characterAtIndex:2], [hex characterAtIndex:2]];
	unsigned rgb = 0;
	[[NSScanner scannerWithString:hex] scanHexInt:&rgb];
	return rgba(((rgb >> 16) & 0xff) / 255.0f, ((rgb >> 8) & 0xff) / 255.0f, (rgb & 0xff) / 255.0f, 1);
}

NSColor *neonCssColor(NSString *css) { return cssColor(css); }

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

// RN macOS RCTTextPrimitivesConversions.h:30 (react-native-macos 8941740): auto is Natural, and RN falls back to Natural
// for a value it does not know (conversions.h:630); RCTAttributedTextUtils.mm:224 puts it on the paragraph style.
static NSWritingDirection writingDirectionOf(const char *value) {
	if (!strcmp(value, "ltr")) return NSWritingDirectionLeftToRight;
	if (!strcmp(value, "rtl")) return NSWritingDirectionRightToLeft;
	return NSWritingDirectionNatural;
}

// --- ScrollView: an NSScrollView over a flipped document view, as RN macOS's RCTScrollViewComponentView ---

@interface NeonDocument : NSView
@end

@implementation NeonDocument
- (BOOL)isFlipped { return YES; }
- (NSView *)hitTest:(NSPoint)point { (void)point; return nil; }
@end

@interface NeonScrollView : NSScrollView
@property(nonatomic) BOOL enabled;
@end

@implementation NeonScrollView
- (NSView *)hitTest:(NSPoint)point { (void)point; return nil; }
- (void)scrollWheel:(NSEvent *)event {
	if (self.enabled) [super scrollWheel:event];
	else [self.nextResponder scrollWheel:event];
}
@end

@interface NeonScroll : NeonView
@property(nonatomic, strong) NeonScrollView *scrollView;
@property(nonatomic, strong) NeonDocument *document;
@property(nonatomic) float contentWidth, contentHeight;
@property(nonatomic) BOOL horizontal;
@end

@implementation NeonScroll

- (instancetype)initWithFrame:(NSRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		_scrollView = [[NeonScrollView alloc] initWithFrame:self.bounds];
		_scrollView.enabled = YES;
		_scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
		_scrollView.drawsBackground = NO;
		_scrollView.automaticallyAdjustsContentInsets = NO;
		_scrollView.scrollerStyle = NSScrollerStyleOverlay;
		_scrollView.hasVerticalScroller = YES;
		_scrollView.hasHorizontalScroller = YES;
		_scrollView.autohidesScrollers = YES;
		_document = [[NeonDocument alloc] initWithFrame:NSZeroRect];
		_scrollView.documentView = _document;
		_scrollView.contentView.postsBoundsChangedNotifications = YES;
		[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(scrolled:) name:NSViewBoundsDidChangeNotification object:_scrollView.contentView];
		[self addSubview:_scrollView];
	}
	return self;
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

- (NSView *)neonChildHost { return self.document; }

- (NSPoint)offset { return self.scrollView.contentView.bounds.origin; }

- (NSPoint)clamp:(NSPoint)p {
	float maxX = fmaxf(0, self.contentWidth - self.w), maxY = fmaxf(0, self.contentHeight - self.h);
	return NSMakePoint(fminf(fmaxf(0, (float)p.x), maxX), fminf(fmaxf(0, (float)p.y), maxY));
}

- (void)moveTo:(NSPoint)p animated:(BOOL)animated {
	NSClipView *clip = self.scrollView.contentView;
	p = [self clamp:p];
	if (animated) {
		[NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
			context.duration = 0.25;
			[clip.animator setBoundsOrigin:p];
		} completionHandler:nil];
	} else {
		[clip scrollToPoint:p];
	}
	[self.scrollView reflectScrolledClipView:clip];
}

- (void)fitDocument {
	self.document.frame = NSMakeRect(0, 0, self.contentWidth, self.contentHeight);
	NSPoint now = [self offset], clamped = [self clamp:now];
	if (!NSEqualPoints(now, clamped)) [self moveTo:clamped animated:NO];
}

- (void)setFrameSize:(NSSize)size {
	[super setFrameSize:size];
	[self fitDocument];
}

- (void)scrolled:(NSNotification *)note {
	(void)note;
	if (!s_scroll.fn || self.neonTag == 0) return;
	NSPoint p = [self offset];
	g_scrollTag = self.neonTag;
	g_scrollPhase = 0;
	g_scrollX = (float)p.x;
	g_scrollY = (float)p.y;
	g_scrollW = self.w;
	g_scrollH = self.h;
	g_scrollContentW = fmaxf(self.contentWidth, self.w);
	g_scrollContentH = fmaxf(self.contentHeight, self.h);
	invoke(s_scroll);
	requestHostFrame();
}
@end

static NeonScroll *scrollOf(void *view, const char *what) {
	if ([as(view) isKindOfClass:NeonScroll.class]) return (NeonScroll *)as(view);
	char message[192];
	snprintf(message, sizeof message, "%s on a view that is not a ScrollView", what);
	fail(message);
	return nil;
}

static NSPoint childOffset(NeonView *view) {
	return [view isKindOfClass:NeonScroll.class] ? [(NeonScroll *)view offset] : NSZeroPoint;
}

// A wheel goes to the innermost ScrollView under the pointer; one that does not take it hands it back
// through its responder chain to the root, which carries it on from the ScrollView above.
static NeonView *g_wheelFrom = nil;

static void routeWheel(NSEvent *event, NSPoint pointInRoot) {
	NeonView *start = g_wheelFrom ? parentOf(g_wheelFrom) : hitTest((float)pointInRoot.x, (float)pointInRoot.y, NULL, NULL);
	for (NeonView *at = start; at && at != g_root; at = parentOf(at)) {
		if (![at isKindOfClass:NeonScroll.class]) continue;
		NeonView *previous = g_wheelFrom;
		g_wheelFrom = at;
		[((NeonScroll *)at).scrollView scrollWheel:event];
		g_wheelFrom = previous;
		return;
	}
}

// --- TextInput: RN macOS's RCTUITextField (an NSTextField over the window's field editor, a secure cell
// for secureTextEntry) and RCTUITextView (an NSTextView in an NSScrollView) inside a NeonView ---

static __weak NSResponder *g_restingResponder = nil;

static void emitControlSized(int32_t tag, int phase, NSString *value, float width, float height) {
	if (tag == 0 || !s_control.fn) return;
	free(g_controlValue);
	g_controlValue = strdup(value.UTF8String);
	g_controlTag = tag;
	g_controlPhase = phase;
	g_controlW = width;
	g_controlH = height;
	invoke(s_control);
	requestHostFrame();
}

static void emitControl(int32_t tag, int phase, NSString *value) { emitControlSized(tag, phase, value, 0, 0); }

void neonEmitControl(int32_t tag, int phase, NSString *value, float width, float height) {
	emitControlSized(tag, phase, value, width, height);
}

@class NeonInput;

@interface NeonFieldCell : NSTextFieldCell
@property(nonatomic) BOOL autoCorrect;
@end

@implementation NeonFieldCell
- (NSText *)setUpFieldEditorAttributes:(NSText *)text {
	NSTextView *editor = (NSTextView *)[super setUpFieldEditorAttributes:text];
	editor.automaticSpellingCorrectionEnabled = self.autoCorrect;
	return editor;
}
@end

@interface NeonSecureFieldCell : NSSecureTextFieldCell
@end

@implementation NeonSecureFieldCell
- (NSText *)setUpFieldEditorAttributes:(NSText *)text {
	NSTextView *editor = (NSTextView *)[super setUpFieldEditorAttributes:text];
	editor.automaticSpellingCorrectionEnabled = NO;
	return editor;
}
@end

@interface NeonField : NSTextField
@property(nonatomic, weak) NeonInput *owner;
@end

// AppKit requires a secure field editor's delegate to be an NSSecureTextField.
@interface NeonSecureField : NSSecureTextField
@property(nonatomic, weak) NeonInput *owner;
@end

@interface NeonTextView : NSTextView
@property(nonatomic, weak) NeonInput *owner;
@end

@interface NeonInput : NeonView <NSTextViewDelegate>
@property(nonatomic) BOOL multiline, blurOnSubmit, upper, autoFocus, editable;
@property(nonatomic) BOOL autoCorrect, defaultAutoCorrect;
@property(nonatomic) int writing;
@property(nonatomic) NSInteger maxLength;
@property(nonatomic) NSEdgeInsets insets;
@property(nonatomic, copy) NSString *family, *placeholder, *pendingSelection;
@property(nonatomic) CGFloat fontSize;
@property(nonatomic) BOOL bold;
@property(nonatomic, strong) NSColor *color, *placeholderColor;
@property(nonatomic) NSTextAlignment alignment;
@property(nonatomic) NSWritingDirection direction;
@property(nonatomic, strong) NSTextField *field;
@property(nonatomic, strong) NSScrollView *scroll;
@property(nonatomic, strong) NeonTextView *textView;
@end

static BOOL flagValue(const char *value, const char *name) {
	if (!strcmp(value, "true")) return YES;
	if (!strcmp(value, "false") || value[0] == '\0') return NO;
	char message[160];
	snprintf(message, sizeof message, "TextInput %s is not true or false: %s", name, value);
	fail(message);
	return NO;
}

@implementation NeonInput

- (instancetype)initMultiline:(BOOL)multiline {
	self = [super initWithFrame:NSZeroRect];
	if (self) {
		_multiline = multiline;
		_blurOnSubmit = !multiline;
		_editable = YES;
		_maxLength = -1;
		_fontSize = 17;
		_color = rgba(0, 0, 0, 1);
		_alignment = NSTextAlignmentNatural;
		_placeholder = @"";
		if (multiline) {
			_scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
			_scroll.drawsBackground = NO;
			_scroll.hasVerticalScroller = YES;
			_scroll.autohidesScrollers = YES;
			_scroll.scrollerStyle = NSScrollerStyleOverlay;
			_scroll.automaticallyAdjustsContentInsets = NO;
			_textView = [[NeonTextView alloc] initWithFrame:NSZeroRect];
			_textView.owner = self;
			_textView.delegate = self;
			_defaultAutoCorrect = _textView.automaticSpellingCorrectionEnabled;
			_autoCorrect = _defaultAutoCorrect;
			_textView.drawsBackground = NO;
			_textView.richText = NO;
			_textView.verticallyResizable = YES;
			_textView.autoresizingMask = NSViewWidthSizable;
			_textView.textContainerInset = NSZeroSize;
			_textView.textContainer.lineFragmentPadding = 0;
			_textView.textContainer.widthTracksTextView = YES;
			_scroll.documentView = _textView;
			[self addSubview:_scroll];
		} else {
			_defaultAutoCorrect = [[NSTextView alloc] initWithFrame:NSZeroRect].automaticSpellingCorrectionEnabled;
			_autoCorrect = _defaultAutoCorrect;
			[self makeField:NO];
		}
		[self applyStyle];
	}
	return self;
}

- (void)makeField:(BOOL)secure {
	NSString *text = self.field ? self.field.stringValue : @"";
	[self.field removeFromSuperview];
	if (secure) {
		NeonSecureField *field = [[NeonSecureField alloc] initWithFrame:NSZeroRect];
		field.owner = self;
		self.field = (NSTextField *)field;
	} else {
		NeonField *field = [[NeonField alloc] initWithFrame:NSZeroRect];
		field.owner = self;
		self.field = field;
	}
	self.field.bordered = NO;
	self.field.bezeled = NO;
	self.field.drawsBackground = NO;
	self.field.focusRingType = NSFocusRingTypeNone;
	self.field.usesSingleLineMode = YES;
	self.field.cell.scrollable = YES;
	self.field.cell.wraps = NO;
	self.field.stringValue = text;
	[self addSubview:self.field];
	[self applyAutoCorrect];
	[self applyStyle];
	[self layoutContent];
}

- (NSFont *)font { return labelFont(self.family, self.fontSize, self.bold, NO); }

- (NSString *)text { return self.multiline ? self.textView.string : self.field.stringValue; }

- (NSTextView *)editor {
	if (self.multiline) return self.window.firstResponder == self.textView ? self.textView : nil;
	return (NSTextView *)self.field.currentEditor;
}

- (NSView *)editingView { return self.multiline ? self.textView : self.field; }

- (void)applyAutoCorrect {
	if (self.multiline) {
		self.textView.automaticSpellingCorrectionEnabled = self.autoCorrect;
	} else {
		BOOL secure = [self.field isKindOfClass:NeonSecureField.class];
		if (!secure) ((NeonFieldCell *)self.field.cell).autoCorrect = self.autoCorrect;
		NSTextView *editor = [self editor];
		if (editor) editor.automaticSpellingCorrectionEnabled = secure ? NO : self.autoCorrect;
	}
}

- (void)applyStyle {
	NSFont *font = [self font];
	self.writing += 1;
	if (self.multiline) {
		self.textView.font = font;
		self.textView.textColor = self.color;
		self.textView.alignment = self.alignment;
		self.textView.baseWritingDirection = self.direction;
		self.textView.editable = self.editable;
		self.textView.typingAttributes = @{NSFontAttributeName: font, NSForegroundColorAttributeName: self.color};
		self.textView.needsDisplay = YES;
	} else {
		self.field.font = font;
		self.field.textColor = self.color;
		self.field.alignment = self.alignment;
		self.field.baseWritingDirection = self.direction;
		self.field.editable = self.editable;
		self.field.selectable = YES;
		self.field.placeholderAttributedString = [[NSAttributedString alloc] initWithString:self.placeholder attributes:@{
			NSFontAttributeName: font, NSForegroundColorAttributeName: self.placeholderColor ?: NSColor.placeholderTextColor}];
	}
	self.writing -= 1;
	[self layoutContent];
	requestHostFrame();
}

- (NSRect)contentRect {
	NSEdgeInsets i = self.insets;
	return NSMakeRect(i.left, i.top, fmax(0, self.w - i.left - i.right), fmax(0, self.h - i.top - i.bottom));
}

- (void)layoutContent {
	if (self.multiline) {
		self.scroll.frame = [self contentRect];
		self.textView.minSize = NSMakeSize(0, self.scroll.contentSize.height);
		self.textView.maxSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
		self.textView.frame = NSMakeRect(0, 0, self.scroll.contentSize.width, fmax(self.textView.frame.size.height, self.scroll.contentSize.height));
	} else {
		self.field.frame = [self contentRect];
	}
}

- (void)setFrameSize:(NSSize)size {
	[super setFrameSize:size];
	[self layoutContent];
}

- (void)viewDidMoveToWindow {
	[super viewDidMoveToWindow];
	if (self.window && self.autoFocus) dispatch_async(dispatch_get_main_queue(), ^{ [self focus:YES]; });
}

- (void)write:(NSString *)text {
	if ([text isEqualToString:[self text]]) return;
	self.writing += 1;
	if (self.multiline) self.textView.string = text;
	else self.field.stringValue = text;
	NSTextView *editor = [self editor];
	if (editor) editor.selectedRange = NSMakeRange(text.length, 0);
	self.writing -= 1;
	requestHostFrame();
}

- (void)select:(NSString *)value {
	long start = 0, end = 0;
	if (sscanf(value.UTF8String, "%ld,%ld", &start, &end) != 2) {
		char message[160];
		snprintf(message, sizeof message, "TextInput selection is not start,end: %s", value.UTF8String);
		fail(message);
	}
	NSTextView *editor = [self editor];
	if (!editor) {
		self.pendingSelection = value;
		return;
	}
	NSUInteger length = [self text].length;
	NSUInteger from = MIN((NSUInteger)MAX(0, start), length), to = MIN((NSUInteger)MAX((long)from, end), length);
	self.writing += 1;
	editor.selectedRange = NSMakeRange(from, to - from);
	self.writing -= 1;
	self.pendingSelection = nil;
}

- (void)focus:(BOOL)focused {
	NSWindow *window = self.window;
	if (!window) return;
	if (focused) {
		if (![self editor]) [window makeFirstResponder:[self editingView]];
	} else if ([self editor]) {
		[window makeFirstResponder:g_restingResponder];
	}
}

- (void)didFocus {
	emitControl(self.neonTag, 1, [self text]);
	if (self.pendingSelection) [self select:self.pendingSelection];
}

- (void)didBlur {
	if (self.writing == 0) emitControl(self.neonTag, 2, [self text]);
}

// An IME composition is no change until it commits, as on Windows.
- (void)didChange {
	if (self.writing > 0 || [self editor].hasMarkedText) return;
	emitControl(self.neonTag, 0, [self text]);
	if (self.multiline) requestHostFrame();
}

- (void)didChangeSelection {
	NSTextView *editor = [self editor];
	if (self.writing > 0 || !editor) return;
	NSRange r = editor.selectedRange;
	emitControl(self.neonTag, 9, [NSString stringWithFormat:@"%lu,%lu", (unsigned long)r.location, (unsigned long)NSMaxRange(r)]);
}

- (BOOL)allowChange:(NSTextView *)editor range:(NSRange)range replacement:(NSString *)replacement {
	if (!replacement) return YES;
	NSString *wanted = self.upper ? replacement.uppercaseString : replacement;
	if (self.maxLength >= 0 && !editor.hasMarkedText) {
		NSInteger room = self.maxLength - (NSInteger)([self text].length - range.length);
		if (room <= 0 && wanted.length > 0) return NO;
		if ((NSInteger)wanted.length > room) wanted = [wanted substringToIndex:(NSUInteger)room];
	}
	if ([wanted isEqualToString:replacement]) return YES;
	[editor insertText:wanted replacementRange:range];
	return NO;
}

- (BOOL)command:(SEL)selector {
	if (selector != @selector(insertNewline:)) return NO;
	if (self.multiline && !self.blurOnSubmit) return NO;
	emitControl(self.neonTag, 3, [self text]);
	if (self.blurOnSubmit) [self focus:NO];
	return YES;
}

- (void)measure:(float)maxWidth {
	NSFont *font = [self font];
	NSEdgeInsets i = self.insets;
	NSLayoutManager *manager = [NSLayoutManager new];
	CGFloat height = [manager defaultLineHeightForFont:font];
	if (self.multiline && [self text].length) {
		NSTextStorage *storage = [[NSTextStorage alloc] initWithString:[self text] attributes:@{NSFontAttributeName: font}];
		NSTextContainer *container = [[NSTextContainer alloc] initWithSize:NSMakeSize(fmax(0, maxWidth - i.left - i.right), CGFLOAT_MAX)];
		container.lineFragmentPadding = 0;
		[manager addTextContainer:container];
		[storage addLayoutManager:manager];
		[manager ensureLayoutForTextContainer:container];
		NSRect used = NSUnionRect([manager usedRectForTextContainer:container], manager.extraLineFragmentUsedRect);
		height = used.size.height;
	}
	g_measuredW = maxWidth;
	g_measuredH = ceilf((float)height) + (float)(i.top + i.bottom);
}

- (void)setProp:(const char *)name value:(const char *)value {
	NSString *text = @(value);
	if (!strcmp(name, "value")) [self write:text];
	else if (!strcmp(name, "defaultValue")) { if ([self text].length == 0) [self write:text]; }
	else if (!strcmp(name, "placeholder")) {
		self.placeholder = text;
		[self applyStyle];
	} else if (!strcmp(name, "placeholderTextColor")) {
		self.placeholderColor = value[0] ? cssColor(text) : nil;
		[self applyStyle];
	} else if (!strcmp(name, "editable")) {
		self.editable = value[0] == '\0' || flagValue(value, name);
		[self applyStyle];
	} else if (!strcmp(name, "secureTextEntry")) {
		BOOL secure = flagValue(value, name);
		if (self.multiline) { if (secure) fail("TextInput secureTextEntry on a multiline input"); }
		else if (secure != [self.field isKindOfClass:NeonSecureField.class]) [self makeField:secure];
	} else if (!strcmp(name, "multiline")) {
		if (flagValue(value, name) != self.multiline) fail("TextInput multiline changed after the input was created");
	} else if (!strcmp(name, "autoFocus")) {
		self.autoFocus = flagValue(value, name);
		if (self.autoFocus && self.window) [self focus:YES];
	} else if (!strcmp(name, "blurOnSubmit")) self.blurOnSubmit = value[0] == '\0' ? !self.multiline : flagValue(value, name);
	else if (!strcmp(name, "autoCapitalize")) {
		if (strcmp(value, "characters") && strcmp(value, "none") && strcmp(value, "sentences") && strcmp(value, "words") && value[0]) {
			char message[160];
			snprintf(message, sizeof message, "TextInput autoCapitalize is not none, sentences, words or characters: %s", value);
			fail(message);
		}
		self.upper = !strcmp(value, "characters");
	} else if (!strcmp(name, "maxLength")) self.maxLength = value[0] ? atol(value) : -1;
	else if (!strcmp(name, "autoCorrect")) {
		self.autoCorrect = value[0] == '\0' ? self.defaultAutoCorrect : flagValue(value, name);
		[self applyAutoCorrect];
	} else if (!strcmp(name, "keyboardType") || !strcmp(name, "returnKeyType") || !strcmp(name, "inputAccessoryViewID")) {}
	else if (!strcmp(name, "selection")) [self select:text];
	else if (!strcmp(name, "textInsets")) {
		float left = 0, top = 0, right = 0, bottom = 0;
		if (sscanf(value, "%f,%f,%f,%f", &left, &top, &right, &bottom) != 4) {
			char message[160];
			snprintf(message, sizeof message, "TextInput textInsets is not l,t,r,b: %s", value);
			fail(message);
		}
		self.insets = NSEdgeInsetsMake(top, left, bottom, right);
		[self layoutContent];
	} else if (!strcmp(name, "fontFamily")) {
		self.family = text;
		[self applyStyle];
	} else if (!strcmp(name, "textAlign")) {
		self.alignment = alignmentOf(value);
		[self applyStyle];
	} else if (!strcmp(name, "writingDirection")) {
		self.direction = writingDirectionOf(value);
		[self applyStyle];
	} else {
		char what[128];
		snprintf(what, sizeof what, "niSetProp(%s) on a TextInput", name);
		unimplemented(what);
	}
}

- (void)textDidChange:(NSNotification *)note { (void)note; [self didChange]; }
- (void)textDidEndEditing:(NSNotification *)note { (void)note; [self didBlur]; }
- (void)textViewDidChangeSelection:(NSNotification *)note { (void)note; [self didChangeSelection]; }
- (BOOL)textView:(NSTextView *)view shouldChangeTextInRange:(NSRange)range replacementString:(NSString *)replacement {
	return [self allowChange:view range:range replacement:replacement];
}
- (BOOL)textView:(NSTextView *)view doCommandBySelector:(SEL)selector { (void)view; return [self command:selector]; }
@end

// AppKit sends a field's editing callbacks to the field itself as the field editor's delegate; both field
// classes hand them to their NeonInput.
#define NEON_FIELD_METHODS \
	- (BOOL)becomeFirstResponder { \
		BOOL became = [super becomeFirstResponder]; \
		if (became) [self.owner didFocus]; \
		return became; \
	} \
	- (void)textDidChange:(NSNotification *)note { \
		[super textDidChange:note]; \
		[self.owner didChange]; \
	} \
	- (void)textDidEndEditing:(NSNotification *)note { \
		[super textDidEndEditing:note]; \
		[self.owner didBlur]; \
	} \
	- (void)textViewDidChangeSelection:(NSNotification *)note { (void)note; [self.owner didChangeSelection]; } \
	- (BOOL)textView:(NSTextView *)view shouldChangeTextInRange:(NSRange)range replacementString:(NSString *)replacement { \
		return [self.owner allowChange:view range:range replacement:replacement]; \
	} \
	- (BOOL)textView:(NSTextView *)view doCommandBySelector:(SEL)selector { (void)view; return [self.owner command:selector]; }

@implementation NeonField
+ (Class)cellClass { return NeonFieldCell.class; }
NEON_FIELD_METHODS
@end

@implementation NeonSecureField
+ (Class)cellClass { return NeonSecureFieldCell.class; }
NEON_FIELD_METHODS
@end

@implementation NeonTextView
// A single-line NSTextField takes an inactive window's first click and NSTextView does not; taking it here
// focuses every TextInput on that click, as the root presses a Pressable on it.
- (BOOL)acceptsFirstMouse:(NSEvent *)event { (void)event; return YES; }
- (BOOL)becomeFirstResponder {
	BOOL became = [super becomeFirstResponder];
	if (became) [self.owner didFocus];
	return became;
}
- (void)drawRect:(NSRect)dirty {
	[super drawRect:dirty];
	NeonInput *owner = self.owner;
	if (self.string.length || !owner.placeholder.length) return;
	[owner.placeholder drawAtPoint:self.textContainerOrigin withAttributes:@{
		NSFontAttributeName: [owner font], NSForegroundColorAttributeName: owner.placeholderColor ?: NSColor.placeholderTextColor}];
}
@end

// --- Image: RN macOS's RCTUIImageView drawing through its layer's contents, inside a NeonView ---

// RN blurRadius: a Gaussian blur of the decoded image, cropped back to its own extent.
static CGImageRef blurredImage(CGImageRef image, CGFloat radius) {
	CIImage *input = [CIImage imageWithCGImage:image];
	CIFilter *blur = [CIFilter filterWithName:@"CIGaussianBlur"];
	[blur setValue:[input imageByClampingToExtent] forKey:kCIInputImageKey];
	[blur setValue:@(radius) forKey:kCIInputRadiusKey];
	CIImage *output = [blur.outputImage imageByCroppingToRect:input.extent];
	return [[CIContext contextWithOptions:nil] createCGImage:output fromRect:input.extent];
}

static NSString *loadFailure(NSData *data, NSURLResponse *response, NSError *error, NSImage *image) {
	NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 200;
	if (error) return error.localizedDescription;
	if (status < 200 || status >= 300) return [NSString stringWithFormat:@"HTTP %ld", (long)status];
	return data && image ? nil : @"cannot decode image";
}

// The views' cache, shared with Image.getSize and Image.prefetch (niAppCall "image.size").
static NSCache<NSString *, NSImage *> *imageCache(void) {
	static NSCache *cache;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ cache = [[NSCache alloc] init]; });
	return cache;
}

static void fetchImage(NSString *uri, void (^done)(NSImage *image, NSString *error)) {
	NSImage *cached = [imageCache() objectForKey:uri];
	if (cached) {
		dispatch_async(dispatch_get_main_queue(), ^{ done(cached, nil); });
		return;
	}
	NSURL *url = [NSURL URLWithString:uri];
	if (!url) {
		dispatch_async(dispatch_get_main_queue(), ^{ done(nil, @"malformed URI"); });
		return;
	}
	[[NSURLSession.sharedSession dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
		NSImage *image = data ? [[NSImage alloc] initWithData:data] : nil;
		NSString *failure = loadFailure(data, response, error, image);
		dispatch_async(dispatch_get_main_queue(), ^{
			if (!failure) [imageCache() setObject:image forKey:uri];
			done(failure ? nil : image, failure);
		});
	}] resume];
}

static CGImageRef pixelsOf(NSImage *image) { return [image CGImageForProposedRect:NULL context:nil hints:nil]; }

@interface NeonImage : NeonView
@property(nonatomic, copy) NSString *uri;
@property(nonatomic, strong) NSImage *raw;
@property(nonatomic) CGFloat blur;
@property(nonatomic) BOOL repeat;
@property(nonatomic, strong) NSView *picture;
@end

@implementation NeonImage
- (instancetype)initWithFrame:(NSRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		_uri = @"";
		_picture = [[NSView alloc] initWithFrame:NSZeroRect];
		_picture.layer = [CALayer layer];
		_picture.wantsLayer = YES;
		_picture.layer.contentsGravity = kCAGravityResizeAspectFill;
		_picture.layer.masksToBounds = YES;
		_picture.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
		[self addSubview:_picture];
	}
	return self;
}

- (void)setFrameSize:(NSSize)size {
	[super setFrameSize:size];
	self.picture.frame = NSMakeRect(0, 0, size.width, size.height);
}

// A decoded image is drawn at one point per pixel, as iOS's UIImage imageWithData: is.
- (void)show {
	CALayer *layer = self.picture.layer;
	[CATransaction begin];
	[CATransaction setDisableActions:YES];
	layer.contents = nil;
	layer.backgroundColor = NULL;
	if (self.raw && self.repeat) {
		layer.backgroundColor = [NSColor colorWithPatternImage:self.raw].CGColor;
	} else if (self.raw && self.blur > 0) {
		CGImageRef blurred = blurredImage(pixelsOf(self.raw), self.blur);
		layer.contents = (__bridge id)blurred;
		CGImageRelease(blurred);
	} else if (self.raw) {
		layer.contents = (__bridge id)pixelsOf(self.raw);
	}
	layer.contentsScale = 1;
	[CATransaction commit];
}

- (void)load:(NSString *)uri {
	if ([uri isEqualToString:self.uri]) return;
	self.uri = uri;
	self.raw = nil;
	[self show];
	if (uri.length == 0) return;
	__weak NeonImage *weakSelf = self;
	fetchImage(uri, ^(NSImage *image, NSString *error) {
		NeonImage *view = weakSelf;
		if (!view || ![view.uri isEqualToString:uri]) return;
		if (error) {
			emitControl(view.neonTag, 6, error);
			return;
		}
		view.raw = image;
		[view show];
		CGImageRef pixels = pixelsOf(image);
		emitControlSized(view.neonTag, 5, @"", (float)CGImageGetWidth(pixels), (float)CGImageGetHeight(pixels));
	});
}

- (void)setProp:(const char *)name value:(const char *)value {
	if (!strcmp(name, "source")) {
		[self load:@(value)];
	} else if (!strcmp(name, "resizeMode")) {
		NSString *mode = @(value);
		self.picture.layer.contentsGravity = [mode isEqualToString:@"contain"] ? kCAGravityResizeAspect :
			[mode isEqualToString:@"stretch"] ? kCAGravityResize :
			[mode isEqualToString:@"center"] ? kCAGravityCenter : kCAGravityResizeAspectFill;
		self.repeat = [mode isEqualToString:@"repeat"];
		[self show];
	} else if (!strcmp(name, "blurRadius")) {
		self.blur = (CGFloat)atof(value);
		[self show];
	} else {
		char what[128];
		snprintf(what, sizeof what, "Image niSetProp(%s)", name);
		unimplemented(what);
	}
}
@end

static BOOL isControl(NeonView *view) {
	return [view isKindOfClass:NeonImage.class] || [view conformsToProtocol:@protocol(NeonComponentView)];
}

static BOOL isInput(NeonView *view) { return [view isKindOfClass:NeonInput.class]; }

static NeonInput *inputOf(void *view, const char *what) {
	if (isInput(as(view))) return (NeonInput *)as(view);
	char message[192];
	snprintf(message, sizeof message, "%s on a view that is not a TextInput", what);
	fail(message);
	return nil;
}

// A click on a TextInput goes to the view AppKit edits in: the field, or its field editor once editing.
static NSView *nativeTarget(NeonView *view, NSPoint pointInRoot) {
	NSView *target = isInput(view) ? [(NeonInput *)view editingView] :
		[view respondsToSelector:@selector(neonNativeTarget)] ? [(id<NeonComponentView>)view neonNativeTarget] : nil;
	if (!target) return nil;
	NSView *hit = [target hitTest:[target.superview convertPoint:pointInRoot fromView:g_root]];
	return hit ? hit : target;
}

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
	g_restingResponder = parent.window.firstResponder;
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
	if (!view) return;
	if ([as(view) respondsToSelector:@selector(neonRelease)]) [(id<NeonComponentView>)as(view) neonRelease];
	CFRelease(view);
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

// --- bridge.h: geometry, the bounds of a view in the window's content, through the same model the hit test
// inverts (frame, centred transform, scroll offset), since AppKit's own conversion misses the layer transforms ---

static double g_measurement[4];

static NSPoint toParent(NeonView *view, NSPoint p) {
	CATransform3D t = [view neonTransform];
	NSPoint out = NSMakePoint(view.x + t.m11 * p.x + t.m21 * p.y + t.m41, view.y + t.m12 * p.x + t.m22 * p.y + t.m42);
	NeonView *parent = parentOf(view);
	if (parent) {
		NSPoint offset = childOffset(parent);
		out.x -= offset.x;
		out.y -= offset.y;
	}
	return out;
}

int32_t niMeasureInWindow(void *view) {
	NeonView *v = as(view);
	if (!g_root || !v.window || !within(v, g_root)) return -1;
	if (v.isHiddenOrHasHiddenAncestor) return 0;
	NSPoint corners[4] = {NSMakePoint(0, 0), NSMakePoint(v.w, 0), NSMakePoint(0, v.h), NSMakePoint(v.w, v.h)};
	NSView *content = v.window.contentView;
	double minX = INFINITY, minY = INFINITY, maxX = -INFINITY, maxY = -INFINITY;
	for (int i = 0; i < 4; i++) {
		NSPoint p = corners[i];
		for (NeonView *at = v; at && at != g_root; at = parentOf(at)) p = toParent(at, p);
		p = [g_root convertPoint:p toView:content];
		if (!content.isFlipped) p.y = content.bounds.size.height - p.y;
		minX = MIN(minX, p.x);
		minY = MIN(minY, p.y);
		maxX = MAX(maxX, p.x);
		maxY = MAX(maxY, p.y);
	}
	g_measurement[0] = minX;
	g_measurement[1] = minY;
	g_measurement[2] = maxX - minX;
	g_measurement[3] = maxY - minY;
	return 1;
}

double niMeasurementX(void) { return g_measurement[0]; }
double niMeasurementY(void) { return g_measurement[1]; }
double niMeasurementW(void) { return g_measurement[2]; }
double niMeasurementH(void) { return g_measurement[3]; }

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

static void emitApp(int kind, NSString *value) {
	if (!s_app.fn) return;
	free(g_appValue);
	g_appValue = strdup(value.UTF8String);
	g_appEvent = kind;
	invoke(s_app);
	requestHostFrame();
}

// Image.getSize / Image.prefetch: "id 0x1f uri" in, NI_APP_IMAGE_SIZE "id 0x1f w 0x1f h 0x1f error" out, in pixels.
static void imageSize(const char *arg) {
	NSArray<NSString *> *fields = [@(arg) componentsSeparatedByString:@"\x1f"];
	if (fields.count != 2) {
		char message[256];
		snprintf(message, sizeof message, "niAppCall(image.size) wants \"id 0x1f uri\": %s", arg);
		fail(message);
	}
	NSString *request = fields[0];
	fetchImage(fields[1], ^(NSImage *image, NSString *error) {
		CGImageRef pixels = image ? pixelsOf(image) : NULL;
		NSString *w = @(pixels ? CGImageGetWidth(pixels) : 0).stringValue, *h = @(pixels ? CGImageGetHeight(pixels) : 0).stringValue;
		emitApp(NI_APP_IMAGE_SIZE, [@[request, w, h, error ?: @""] componentsJoinedByString:@"\x1f"]);
	});
}

const char *niAppCall(const char *name, const char *arg) {
	static char reply[64];
	if (!strcmp(name, "image.size")) {
		imageSize(arg ? arg : "");
		reply[0] = '\0';
	} else if (!strcmp(name, "platform")) {
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
float niLastControlWidth(void) { return g_controlW; }
float niLastControlHeight(void) { return g_controlH; }

static BOOL isAccessibilityProp(const char *name) {
	static const char *names[] = {
		"accessible", "accessibilityLabel", "accessibilityHint", "accessibilityRole", "accessibilityState", "role",
		"accessibilityValue", "accessibilityLiveRegion", "importantForAccessibility", "accessibilityElementsHidden",
		"accessibilityViewIsModal", "accessibilityLabelledBy", "accessibilityActions", "focusable",
	};
	for (size_t i = 0; i < sizeof names / sizeof *names; i++) {
		if (!strcmp(name, names[i])) return YES;
	}
	return NO;
}

void niSetProp(void *view, const char *name, const char *value) {
	const char *text = value ? value : "";
	if (!strcmp(name, "overflow")) {
		as(view).clips = !strcmp(text, "hidden");
		[as(view) neonApply];
		requestHostFrame();
		return;
	}
	if (isInput(as(view)) && !isAccessibilityProp(name)) {
		[(NeonInput *)as(view) setProp:name value:text];
		return;
	}
	if (isControl(as(view)) && !isAccessibilityProp(name)) {
		[(id)as(view) setProp:name value:text];
		return;
	}
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
	if (isLabel(as(view)) && !strcmp(name, "writingDirection")) {
		NeonLabel *l = (NeonLabel *)as(view);
		l.direction = writingDirectionOf(text);
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
	if (isInput(as(label))) {
		((NeonInput *)as(label)).color = rgba(r, g, b, a);
		[(NeonInput *)as(label) applyStyle];
		return;
	}
	NeonLabel *l = labelOf(label, "niSetTextColor");
	NSColor *color = rgba(r, g, b, a);
	if ([color isEqual:l.color]) return;
	l.color = color;
	[l changed:NO];
}

void niSetFont(void *label, float size, int bold) {
	if (isInput(as(label))) {
		NeonInput *input = (NeonInput *)as(label);
		if (input.fontSize == size && input.bold == (bold != 0)) return;
		input.fontSize = size;
		input.bold = bold != 0;
		[input applyStyle];
		return;
	}
	NeonLabel *l = labelOf(label, "niSetFont");
	if (l.fontSize == size && l.bold == (bold != 0)) return;
	l.fontSize = size;
	l.bold = bold != 0;
	[l changed:YES];
}

void niMeasureText(void *label, float maxWidth) {
	requireAttached("niMeasureText");
	if (isInput(as(label))) {
		[(NeonInput *)as(label) measure:maxWidth];
		return;
	}
	if ([as(label) respondsToSelector:@selector(neonFittingSize)]) {
		NSSize fit = [(id<NeonComponentView>)as(label) neonFittingSize];
		g_measuredW = ceilf((float)fit.width);
		g_measuredH = ceilf((float)fit.height);
		return;
	}
	NeonLabel *l = labelOf(label, "niMeasureText");
	[l ensureAt:maxWidth];
	NSRect used = [l.layoutManager usedRectForTextContainer:l.container];
	g_measuredW = ceilf((float)used.size.width);
	g_measuredH = ceilf((float)used.size.height);
}

float niMeasuredW(void) { return g_measuredW; }
float niMeasuredH(void) { return g_measuredH; }

// --- bridge.h: ScrollView ---

void *niScrollCreate(void) {
	requireAttached("niScrollCreate");
	return (void *)CFBridgingRetain([[NeonScroll alloc] initWithFrame:NSZeroRect]);
}

void niScrollSetTag(void *scroll, int32_t tag) { scrollOf(scroll, "niScrollSetTag").neonTag = tag; }

void niScrollSetContentSize(void *scroll, float w, float h) {
	NeonScroll *s = scrollOf(scroll, "niScrollSetContentSize");
	s.contentWidth = w;
	s.contentHeight = h;
	[s fitDocument];
	requestHostFrame();
}

void niScrollTo(void *scroll, float x, float y, int animated) {
	[scrollOf(scroll, "niScrollTo") moveTo:NSMakePoint(x, y) animated:animated != 0];
	requestHostFrame();
}

void niScrollShift(void *scroll, float dx, float dy) {
	NeonScroll *s = scrollOf(scroll, "niScrollShift");
	NSPoint now = [s offset];
	[s moveTo:NSMakePoint(now.x + dx, now.y + dy) animated:NO];
}

float niScrollOffsetX(void *scroll) { return (float)[scrollOf(scroll, "niScrollOffsetX") offset].x; }
float niScrollOffsetY(void *scroll) { return (float)[scrollOf(scroll, "niScrollOffsetY") offset].y; }

void niScrollSetOption(void *scroll, const char *name, const char *value) {
	NeonScroll *s = scrollOf(scroll, "niScrollSetOption");
	BOOL yes = !strcmp(value, "true");
	if (!strcmp(name, "horizontal")) s.horizontal = yes;
	else if (!strcmp(name, "scrollEnabled")) s.scrollView.enabled = strcmp(value, "false") != 0;
	else if (!strcmp(name, "showsVerticalScrollIndicator")) s.scrollView.hasVerticalScroller = strcmp(value, "false") != 0;
	else if (!strcmp(name, "showsHorizontalScrollIndicator")) s.scrollView.hasHorizontalScroller = strcmp(value, "false") != 0;
	else if (!strcmp(name, "keyboardShouldPersistTaps") || !strcmp(name, "keyboardDismissMode")) {}
	else if ((!strcmp(name, "pagingEnabled") || !strcmp(name, "refreshEnabled") || !strcmp(name, "refreshing")) && !yes) {}
	else {
		char what[160];
		snprintf(what, sizeof what, "niScrollSetOption(%s=%s)", name, value);
		unimplemented(what);
	}
}

// --- bridge.h: Image ---

void *niImageCreate(void) {
	requireAttached("niImageCreate");
	return (void *)CFBridgingRetain([[NeonImage alloc] initWithFrame:NSZeroRect]);
}

// --- bridge.h: TextInput ---

void *niInputCreate(void) {
	requireAttached("niInputCreate");
	return (void *)CFBridgingRetain([[NeonInput alloc] initMultiline:NO]);
}

void *niTextAreaCreate(void) {
	requireAttached("niTextAreaCreate");
	return (void *)CFBridgingRetain([[NeonInput alloc] initMultiline:YES]);
}

void niControlSetTag(void *control, int32_t tag) {
	if (isControl(as(control))) as(control).neonTag = tag;
	else inputOf(control, "niControlSetTag").neonTag = tag;
}
void niSetFocused(void *control, int focused) { [inputOf(control, "niSetFocused") focus:focused != 0]; }

UNIMPLEMENTED_VOID(niSetReloadPoll, (msClosure poll))
int niLastAppEvent(void) { return g_appEvent; }
const char *niLastAppValue(void) { return g_appValue ? g_appValue : ""; }
void niSetAppEventResult(int result) { (void)result; }

