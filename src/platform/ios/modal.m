#import "component.h"
#include "../native/components.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// A Modal's layer: VoiceOver stays inside it, and its escape gesture asks the
// app to close it (control phase 7, RN's onRequestClose).
@interface NeonModalView : NeonTouchView <NeonComponentView>
@property (nonatomic, copy) NSString *neonAnimation;
@end

@implementation NeonModalView

- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self) self.accessibilityViewIsModal = YES;
	return self;
}

- (BOOL)accessibilityPerformEscape {
	neonEmitControl((int)self.tag, 7, @"", 0, 0);
	return YES;
}

- (void)didMoveToWindow {
	[super didMoveToWindow];
	if (!self.window) return;
	if ([self.neonAnimation isEqualToString:@"fade"]) {
		self.alpha = 0;
		[UIView animateWithDuration:0.3 animations:^{ self.alpha = 1; }];
	} else if ([self.neonAnimation isEqualToString:@"slide"]) {
		CGFloat height = self.window.bounds.size.height;
		self.transform = CGAffineTransformMakeTranslation(0, height);
		[UIView animateWithDuration:0.3 animations:^{ self.transform = CGAffineTransformIdentity; }];
	}
	UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, self);
}

- (void)neonSetProp:(const char *)name value:(const char *)text {
	if (strcmp(name, "animationType") == 0) self.neonAnimation = [NSString stringWithUTF8String:text];
}

@end

void *niModalCreate(void) {
	return CFBridgingRetain([[NeonModalView alloc] initWithFrame:CGRectZero]);
}
