#include "voidVisual.h"

#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>

// Ion's content host must stay first responder for key, text and IME records, and Ion reads pointer
// records from an event monitor (ion/src/platform/bridge.h): this view takes neither.
@interface NeonVoidView : NSView
@property(nonatomic, strong) CAMetalLayer *metalLayer;
@end

@implementation NeonVoidView
- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstResponder { return NO; }
- (NSView *)hitTest:(NSPoint)point { (void)point; return nil; }

- (void)fitLayer {
	[CATransaction begin];
	[CATransaction setDisableActions:YES];
	self.metalLayer.frame = self.bounds;
	CGSize drawable = self.metalLayer.drawableSize;
	if (self.bounds.size.width > 0 && drawable.width > 0) self.metalLayer.contentsScale = drawable.width / self.bounds.size.width;
	[CATransaction commit];
}

- (void)layout {
	[super layout];
	[self fitLayer];
}
@end

void *voidVisualAttach(void *device, void *root, long long swapChain) {
	(void)device;
	if (root == NULL || swapChain == 0) return NULL;
	NSView *parent = (__bridge NSView *)root;
	NeonVoidView *view = [[NeonVoidView alloc] initWithFrame:parent.bounds];
	view.wantsLayer = YES;
	view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
	view.metalLayer = (__bridge CAMetalLayer *)(void *)(intptr_t)swapChain;
	[view.layer addSublayer:view.metalLayer];
	[parent addSubview:view positioned:NSWindowAbove relativeTo:nil];
	[view fitLayer];
	return (void *)CFBridgingRetain(view);
}

void voidVisualDetach(void *root, void *visual) {
	(void)root;
	if (visual == NULL) return;
	NeonVoidView *view = (NeonVoidView *)CFBridgingRelease(visual);
	[view.metalLayer removeFromSuperlayer];
	[view removeFromSuperview];
}
