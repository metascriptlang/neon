#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#import "view.h"
#include "../native/components.h"
#include <stdio.h>
#include <string.h>

// --- Modal: src/components/modal.ms portals it into the root, filling it above the app, as on iOS. RN macOS compiles
// its Modal out (React/Views/RCTModalHostView.m is `#if !TARGET_OS_OSX`), so iOS's escape gesture becomes the Escape
// key: it asks the app to close the topmost Modal (control phase 7, RN's onRequestClose) ---

@interface NeonModal : NeonView <NeonComponentView>
@property(nonatomic, copy) NSString *animation;
@end

static NeonView *g_root = nil;

static NeonModal *topModal(void) {
	for (NSView *child in g_root.subviews.reverseObjectEnumerator) {
		if ([child isKindOfClass:NeonModal.class]) return (NeonModal *)child;
	}
	return nil;
}

static void watchEscape(void) {
	static id monitor = nil;
	if (monitor) return;
	monitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
		NeonModal *modal = event.keyCode == 53 && event.window == g_root.window ? topModal() : nil;
		if (!modal || modal.neonTag == 0) return event;
		neonEmitControl(modal.neonTag, 7, @"", 0, 0);
		return nil;
	}];
}

@implementation NeonModal
- (void)viewDidMoveToWindow {
	[super viewDidMoveToWindow];
	if (!self.window) return;
	if ([self.animation isEqualToString:@"fade"]) {
		self.alphaValue = 0;
		[NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
			context.duration = 0.3;
			self.animator.alphaValue = 1;
		}];
	} else if ([self.animation isEqualToString:@"slide"]) {
		CABasicAnimation *slide = [CABasicAnimation animationWithKeyPath:@"transform.translation.y"];
		slide.fromValue = @(self.window.contentView.bounds.size.height);
		slide.toValue = @0;
		slide.additive = YES;
		slide.duration = 0.3;
		[self.layer addAnimation:slide forKey:@"neonSlide"];
	}
}

- (void)setProp:(const char *)name value:(const char *)value {
	if (!strcmp(name, "animationType")) {
		self.animation = @(value);
		return;
	}
	char what[128];
	snprintf(what, sizeof what, "Modal niSetProp(%s)", name);
	neonUnimplemented(what);
}
@end

void *niModalCreate(void) {
	g_root = neonRequireRoot("niModalCreate");
	watchEscape();
	return (void *)CFBridgingRetain([[NeonModal alloc] initWithFrame:NSZeroRect]);
}
