#import "component.h"
#import <QuartzCore/CAMetalLayer.h>
#include "../native/app.h"
#include "../native/voidArea.h"

enum { MAX_AREA_TOUCHES = 32 };

static msClosure s_handler;
static void *g_view;
static int g_event, g_width, g_height;
static float g_scale;
static int g_touchCount;
static long long g_touchIds[MAX_AREA_TOUCHES];
static float g_touchX[MAX_AREA_TOUCHES], g_touchY[MAX_AREA_TOUCHES];
static int g_touchChanged[MAX_AREA_TOUCHES];

@interface NeonVoidAreaView : UIView <NeonComponentView>
@property (nonatomic) int neonWidth;
@property (nonatomic) int neonHeight;
@property (nonatomic) CGFloat neonScale;
@end

@implementation NeonVoidAreaView

+ (Class)layerClass { return CAMetalLayer.class; }

- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		self.opaque = YES;
		self.multipleTouchEnabled = YES;
	}
	return self;
}

- (void)neonSetProp:(const char *)name value:(const char *)value {}

- (void)neonEmit:(int)event {
	g_view = (__bridge void *)self;
	g_event = event;
	niInvokeClosure(s_handler);
}

- (void)layoutSubviews {
	[super layoutSubviews];
	CGFloat scale = self.window ? self.window.screen.scale : UIScreen.mainScreen.scale;
	self.layer.contentsScale = scale;
	int width = (int)lround(self.bounds.size.width * scale);
	int height = (int)lround(self.bounds.size.height * scale);
	if (width <= 0 || height <= 0) return;
	if (width == self.neonWidth && height == self.neonHeight && scale == self.neonScale) return;
	self.neonWidth = width;
	self.neonHeight = height;
	self.neonScale = scale;
	g_width = width;
	g_height = height;
	g_scale = (float)scale;
	[self neonEmit:0];
}

- (void)neonTouches:(NSSet<UITouch *> *)changed event:(UIEvent *)event phase:(int)phase {
	CGFloat scale = self.neonScale > 0 ? self.neonScale : self.contentScaleFactor;
	g_touchCount = 0;
	for (UITouch *touch in [event touchesForView:self]) {
		if (g_touchCount == MAX_AREA_TOUCHES) break;
		CGPoint at = [touch locationInView:self];
		g_touchIds[g_touchCount] = (long long)(uintptr_t)(__bridge void *)touch;
		g_touchX[g_touchCount] = (float)(at.x * scale);
		g_touchY[g_touchCount] = (float)(at.y * scale);
		g_touchChanged[g_touchCount] = [changed containsObject:touch] ? 1 : 0;
		g_touchCount++;
	}
	[self neonEmit:phase];
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { [self neonTouches:touches event:event phase:1]; }
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { [self neonTouches:touches event:event phase:2]; }
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { [self neonTouches:touches event:event phase:3]; }
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { [self neonTouches:touches event:event phase:4]; }

@end

void *niVoidAreaCreate(void) { return CFBridgingRetain([[NeonVoidAreaView alloc] initWithFrame:CGRectZero]); }
long long niVoidAreaLayer(void *view) { return (long long)(uintptr_t)(__bridge void *)((__bridge UIView *)view).layer; }
void niSetVoidAreaHandler(msClosure handler) { s_handler = handler; }
void *niLastVoidAreaView(void) { return g_view; }
int niLastVoidAreaEvent(void) { return g_event; }
int niLastVoidAreaWidth(void) { return g_width; }
int niLastVoidAreaHeight(void) { return g_height; }
float niLastVoidAreaScale(void) { return g_scale; }
int niLastVoidAreaTouchCount(void) { return g_touchCount; }
long long niLastVoidAreaTouchId(int index) { return g_touchIds[index]; }
float niLastVoidAreaTouchX(int index) { return g_touchX[index]; }
float niLastVoidAreaTouchY(int index) { return g_touchY[index]; }
int niLastVoidAreaTouchChanged(int index) { return g_touchChanged[index]; }
