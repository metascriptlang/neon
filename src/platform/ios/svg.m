#import "component.h"
#include "../native/components.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// --- <Svg>: draws the display list of src/components/svg/scene.ms (encodeScene) ---

typedef struct {
	int kind; // 0 none, 1 colour, 2 linear, 3 radial
	CGFloat rgba[4];
	CGAffineTransform space;
	CGFloat coords[5];
	int stops;
	CGFloat offsets[32];
	CGFloat colors[128];
} NeonSvgPaint;

@interface NeonSvgView : UIView <NeonComponentView>
@property (nonatomic, copy) NSArray<NSString *> *neonTokens;
@end

static CGFloat svgNumber(NSArray<NSString *> *t, NSUInteger *i) {
	if (*i >= t.count) return 0;
	return (CGFloat)[t[(*i)++] doubleValue];
}

static void svgReadPaint(NSArray<NSString *> *t, NSUInteger *i, NeonSvgPaint *p) {
	NSString *kind = *i < t.count ? t[(*i)++] : @"n";
	p->kind = 0;
	if ([kind isEqualToString:@"c"]) {
		p->kind = 1;
		for (int k = 0; k < 3; k++) p->rgba[k] = svgNumber(t, i) / 255.0;
		p->rgba[3] = svgNumber(t, i);
		return;
	}
	if (![kind isEqualToString:@"l"] && ![kind isEqualToString:@"r"]) return;
	BOOL linear = [kind isEqualToString:@"l"];
	p->kind = linear ? 2 : 3;
	CGFloat a = svgNumber(t, i), b = svgNumber(t, i), c = svgNumber(t, i), d = svgNumber(t, i), e = svgNumber(t, i), f = svgNumber(t, i);
	p->space = CGAffineTransformMake(a, b, c, d, e, f);
	for (int k = 0; k < (linear ? 4 : 5); k++) p->coords[k] = svgNumber(t, i);
	int count = (int)svgNumber(t, i);
	p->stops = 0;
	for (int s = 0; s < count; s++) {
		CGFloat offset = svgNumber(t, i);
		CGFloat r = svgNumber(t, i) / 255.0, g = svgNumber(t, i) / 255.0, bl = svgNumber(t, i) / 255.0, al = svgNumber(t, i);
		if (p->stops == 32) continue;
		p->offsets[p->stops] = offset;
		p->colors[p->stops * 4] = r;
		p->colors[p->stops * 4 + 1] = g;
		p->colors[p->stops * 4 + 2] = bl;
		p->colors[p->stops * 4 + 3] = al;
		p->stops++;
	}
}

// Fills the current clip with the gradient (the caller has clipped to the shape).
static void svgDrawGradient(CGContextRef ctx, const NeonSvgPaint *p) {
	CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
	CGGradientRef gradient = CGGradientCreateWithColorComponents(space, p->colors, p->offsets, p->stops);
	CGContextConcatCTM(ctx, p->space);
	CGGradientDrawingOptions extend = kCGGradientDrawsBeforeStartLocation | kCGGradientDrawsAfterEndLocation;
	if (p->kind == 2) {
		CGContextDrawLinearGradient(ctx, gradient, CGPointMake(p->coords[0], p->coords[1]), CGPointMake(p->coords[2], p->coords[3]), extend);
	} else {
		CGContextDrawRadialGradient(ctx, gradient, CGPointMake(p->coords[3], p->coords[4]), 0, CGPointMake(p->coords[0], p->coords[1]), p->coords[2], extend);
	}
	CGGradientRelease(gradient);
	CGColorSpaceRelease(space);
}

// The viewBox to view mapping of SVG 1.1 §7.8 (align 0 none, 1..9 xMinYMin..xMaxYMax).
static CGAffineTransform svgViewBox(CGSize size, CGFloat vx, CGFloat vy, CGFloat vw, CGFloat vh, int align, int slice) {
	CGFloat sx = size.width / vw, sy = size.height / vh;
	if (align == 0) return CGAffineTransformMake(sx, 0, 0, sy, -vx * sx, -vy * sy);
	CGFloat s = slice ? MAX(sx, sy) : MIN(sx, sy);
	int ax = (align - 1) % 3, ay = (align - 1) / 3;
	return CGAffineTransformMake(s, 0, 0, s, -vx * s + (size.width - vw * s) * ax / 2.0, -vy * s + (size.height - vh * s) * ay / 2.0);
}

@implementation NeonSvgView
- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		self.opaque = NO;
		self.backgroundColor = UIColor.clearColor;
		self.contentMode = UIViewContentModeRedraw;
		self.clipsToBounds = YES;
		self.userInteractionEnabled = NO;
		self.accessibilityTraits = UIAccessibilityTraitImage;
	}
	return self;
}
- (CGSize)sizeThatFits:(CGSize)size { (void)size; return CGSizeZero; }
- (BOOL)isAccessibilityElement { return self.accessibilityLabel.length > 0; }
- (void)neonSetList:(const char *)text {
	NSString *list = [NSString stringWithUTF8String:text];
	self.neonTokens = list.length ? [list componentsSeparatedByString:@" "] : @[];
	[self setNeedsDisplay];
}

- (void)neonText:(CGContextRef)ctx tokens:(NSArray<NSString *> *)t at:(NSUInteger *)i matrix:(CGAffineTransform)m {
	int anchor = (int)svgNumber(t, i);
	int count = (int)svgNumber(t, i);
	NSMutableArray<NSAttributedString *> *texts = [NSMutableArray array];
	NSMutableArray<NSArray<NSNumber *> *> *places = [NSMutableArray array];
	NSMutableArray<UIFont *> *fonts = [NSMutableArray array];
	for (int r = 0; r < count; r++) {
		CGFloat hasX = svgNumber(t, i), x = svgNumber(t, i), hasY = svgNumber(t, i), y = svgNumber(t, i);
		CGFloat dx = svgNumber(t, i), dy = svgNumber(t, i), size = svgNumber(t, i), bold = svgNumber(t, i);
		CGFloat red = svgNumber(t, i) / 255.0, green = svgNumber(t, i) / 255.0, blue = svgNumber(t, i) / 255.0, alpha = svgNumber(t, i);
		NSString *raw = *i < t.count ? t[(*i)++] : @"";
		NSString *text = [raw stringByRemovingPercentEncoding] ?: raw;
		UIFont *font = bold > 0 ? [UIFont boldSystemFontOfSize:size] : [UIFont systemFontOfSize:size];
		UIColor *color = [UIColor colorWithRed:red green:green blue:blue alpha:alpha];
		[texts addObject:[[NSAttributedString alloc] initWithString:text attributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: color}]];
		[places addObject:@[@(hasX), @(x), @(hasY), @(y), @(dx), @(dy)]];
		[fonts addObject:font];
	}
	// A chunk starts at every run with its own x; the anchor shifts the whole chunk.
	CGFloat shifts[count > 0 ? count : 1];
	int start = 0;
	for (int r = 0; r <= count; r++) {
		if (r == count || (r > start && places[r][0].doubleValue > 0)) {
			CGFloat width = 0;
			for (int k = start; k < r; k++) width += texts[k].size.width;
			CGFloat shift = anchor == 1 ? width / 2 : anchor == 2 ? width : 0;
			for (int k = start; k < r; k++) shifts[k] = shift;
			start = r;
		}
	}
	CGContextSaveGState(ctx);
	CGContextConcatCTM(ctx, m);
	CGFloat penX = 0, penY = 0;
	for (int r = 0; r < count; r++) {
		NSArray<NSNumber *> *p = places[r];
		if (p[0].doubleValue > 0) penX = p[1].doubleValue;
		if (p[2].doubleValue > 0) penY = p[3].doubleValue;
		penX += p[4].doubleValue;
		penY += p[5].doubleValue;
		[texts[r] drawAtPoint:CGPointMake(penX - shifts[r], penY - fonts[r].ascender)];
		penX += texts[r].size.width;
	}
	CGContextRestoreGState(ctx);
}

- (void)drawRect:(CGRect)rect {
	(void)rect;
	NSArray<NSString *> *t = self.neonTokens;
	if (t.count == 0) return;
	CGContextRef ctx = UIGraphicsGetCurrentContext();
	CGContextSaveGState(ctx);
	CGAffineTransform m = CGAffineTransformIdentity;
	CGMutablePathRef path = CGPathCreateMutable();
	NeonSvgPaint fill = {0}, stroke = {0};
	int evenOdd = 0;
	CGFloat width = 1, miter = 4, dashOffset = 0;
	CGLineCap cap = kCGLineCapButt;
	CGLineJoin join = kCGLineJoinMiter;
	CGFloat dashes[64];
	int dashCount = 0;
	NSUInteger i = 0;
	while (i < t.count) {
		NSString *op = t[i++];
		if (op.length != 1) continue;
		switch ([op characterAtIndex:0]) {
			case 'V': {
				CGFloat vx = svgNumber(t, &i), vy = svgNumber(t, &i), vw = svgNumber(t, &i), vh = svgNumber(t, &i);
				int align = (int)svgNumber(t, &i), slice = (int)svgNumber(t, &i);
				CGContextConcatCTM(ctx, svgViewBox(self.bounds.size, vx, vy, vw, vh, align, slice));
				break;
			}
			case 'X': {
				CGFloat a = svgNumber(t, &i), b = svgNumber(t, &i), c = svgNumber(t, &i), d = svgNumber(t, &i), e = svgNumber(t, &i), f = svgNumber(t, &i);
				m = CGAffineTransformMake(a, b, c, d, e, f);
				break;
			}
			case 'M': { CGFloat x = svgNumber(t, &i), y = svgNumber(t, &i); CGPathMoveToPoint(path, NULL, x, y); break; }
			case 'L': { CGFloat x = svgNumber(t, &i), y = svgNumber(t, &i); CGPathAddLineToPoint(path, NULL, x, y); break; }
			case 'C': {
				CGFloat x1 = svgNumber(t, &i), y1 = svgNumber(t, &i), x2 = svgNumber(t, &i), y2 = svgNumber(t, &i), x = svgNumber(t, &i), y = svgNumber(t, &i);
				CGPathAddCurveToPoint(path, NULL, x1, y1, x2, y2, x, y);
				break;
			}
			case 'Q': {
				CGFloat x1 = svgNumber(t, &i), y1 = svgNumber(t, &i), x = svgNumber(t, &i), y = svgNumber(t, &i);
				CGPathAddQuadCurveToPoint(path, NULL, x1, y1, x, y);
				break;
			}
			case 'Z': CGPathCloseSubpath(path); break;
			case 'F': svgReadPaint(t, &i, &fill); break;
			case 'S': svgReadPaint(t, &i, &stroke); break;
			case 'E': evenOdd = (int)svgNumber(t, &i); break;
			case 'W': {
				width = svgNumber(t, &i);
				int c = (int)svgNumber(t, &i), j = (int)svgNumber(t, &i);
				cap = c == 1 ? kCGLineCapRound : c == 2 ? kCGLineCapSquare : kCGLineCapButt;
				join = j == 1 ? kCGLineJoinRound : j == 2 ? kCGLineJoinBevel : kCGLineJoinMiter;
				miter = svgNumber(t, &i);
				break;
			}
			case 'D': {
				int count = (int)svgNumber(t, &i);
				dashCount = 0;
				for (int k = 0; k < count; k++) {
					CGFloat d = svgNumber(t, &i);
					if (dashCount < 64) dashes[dashCount++] = d;
				}
				dashOffset = svgNumber(t, &i);
				break;
			}
			case 'O': {
				if (fill.kind != 0) {
					CGContextSaveGState(ctx);
					CGContextConcatCTM(ctx, m);
					CGContextAddPath(ctx, path);
					if (fill.kind == 1) {
						CGContextSetRGBFillColor(ctx, fill.rgba[0], fill.rgba[1], fill.rgba[2], fill.rgba[3]);
						if (evenOdd) CGContextEOFillPath(ctx); else CGContextFillPath(ctx);
					} else {
						if (evenOdd) CGContextEOClip(ctx); else CGContextClip(ctx);
						svgDrawGradient(ctx, &fill);
					}
					CGContextRestoreGState(ctx);
				}
				if (stroke.kind != 0 && width > 0) {
					CGContextSaveGState(ctx);
					CGContextConcatCTM(ctx, m);
					CGContextAddPath(ctx, path);
					CGContextSetLineWidth(ctx, width);
					CGContextSetLineCap(ctx, cap);
					CGContextSetLineJoin(ctx, join);
					CGContextSetMiterLimit(ctx, miter);
					CGContextSetLineDash(ctx, dashOffset, dashCount ? dashes : NULL, dashCount);
					if (stroke.kind == 1) {
						CGContextSetRGBStrokeColor(ctx, stroke.rgba[0], stroke.rgba[1], stroke.rgba[2], stroke.rgba[3]);
						CGContextStrokePath(ctx);
					} else {
						CGContextReplacePathWithStrokedPath(ctx);
						CGContextClip(ctx);
						svgDrawGradient(ctx, &stroke);
					}
					CGContextRestoreGState(ctx);
				}
				CGPathRelease(path);
				path = CGPathCreateMutable();
				break;
			}
			case 'K': {
				CGPathRef placed = CGPathCreateCopyByTransformingPath(path, &m);
				CGContextSaveGState(ctx);
				CGContextAddPath(ctx, placed);
				if (CGPathIsEmpty(placed)) CGContextClipToRect(ctx, CGRectZero);
				else if (evenOdd) CGContextEOClip(ctx);
				else CGContextClip(ctx);
				CGPathRelease(placed);
				CGPathRelease(path);
				path = CGPathCreateMutable();
				break;
			}
			case 'k': CGContextRestoreGState(ctx); break;
			case 'G': {
				CGFloat alpha = svgNumber(t, &i);
				CGContextSaveGState(ctx);
				CGContextSetAlpha(ctx, alpha);
				CGContextBeginTransparencyLayer(ctx, NULL);
				break;
			}
			case 'g':
				CGContextEndTransparencyLayer(ctx);
				CGContextRestoreGState(ctx);
				break;
			case 'T': [self neonText:ctx tokens:t at:&i matrix:m]; break;
			default:
				fprintf(stderr, "neon: <Svg> display list has an unknown op \"%s\"\n", op.UTF8String);
				abort();
		}
	}
	CGPathRelease(path);
	CGContextRestoreGState(ctx);
}

- (void)neonSetProp:(const char *)name value:(const char *)text {
	if (strcmp(name, "displayList") == 0) [self neonSetList:text];
}
@end

void *niSvgCreate(void) { return CFBridgingRetain([[NeonSvgView alloc] initWithFrame:CGRectZero]); }
