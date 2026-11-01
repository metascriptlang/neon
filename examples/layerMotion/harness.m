#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#include <stdatomic.h>
#include <unistd.h>
#include "harness.h"
#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
typedef UIView PlatformView;
#else
#import <AppKit/AppKit.h>
typedef NSView PlatformView;
#endif

static double g_opacity[2], g_atMs[2];
static atomic_int g_ready;

static void sample(CALayer *layer, int index) {
	[CATransaction begin];
	g_opacity[index] = layer.presentationLayer.opacity;
	g_atMs[index] = CACurrentMediaTime() * 1000.0;
	[CATransaction commit];
}

void motionSampleLater(void *view, double firstMs, double secondMs) {
	CALayer *layer = [(__bridge id)view layer];
	atomic_store(&g_ready, 0);
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0), ^{
		usleep((useconds_t)(firstMs * 1000.0));
		sample(layer, 0);
		usleep((useconds_t)((secondMs - firstMs) * 1000.0));
		sample(layer, 1);
		atomic_store(&g_ready, 1);
	});
}

int32_t motionSamplesReady(void) { return atomic_load(&g_ready); }
double motionSampledOpacity(int32_t index) { return g_opacity[index & 1]; }
double motionSampledAtMs(int32_t index) { return g_atMs[index & 1]; }

// Stops the layer's own clock and sets its time, so every sublayer's animations are evaluated at a
// time the caller steps (CAMediaTiming: a layer with speed 0 holds its children at its timeOffset).
void motionLayerClock(void *view, double ms) {
	CALayer *layer = [(__bridge id)view layer];
	[CATransaction begin];
	[CATransaction setDisableActions:YES];
	layer.speed = 0;
	layer.timeOffset = ms / 1000.0;
	[CATransaction commit];
	[CATransaction flush];
}

void motionCommit(void) { [CATransaction flush]; }

static PlatformView *g_detachedParent;

void motionDetach(void *view) {
	PlatformView *v = (__bridge PlatformView *)view;
	g_detachedParent = v.superview;
	[v removeFromSuperview];
	[CATransaction flush];
}

void motionReattach(void *view) {
	[g_detachedParent addSubview:(__bridge PlatformView *)view];
	g_detachedParent = nil;
	[CATransaction flush];
}

int32_t motionHasAnimation(void *view, int32_t property) {
	CALayer *layer = [(__bridge PlatformView *)view layer];
	return [layer animationForKey:property == 0 ? @"neon.opacity" : @"neon.transform"] != nil;
}
