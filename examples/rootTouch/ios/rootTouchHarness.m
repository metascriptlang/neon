#import <UIKit/UIKit.h>
#include "../../../src/platform/native/bridge.h"
#include "rootTouchHarness.h"

void rootTouchCancel(void) {
	UIView *root = (__bridge UIView *)niContainerView();
	for (UIGestureRecognizer *handler in root.gestureRecognizers) {
		if (![NSStringFromClass(handler.class) isEqualToString:@"NeonRootTouchHandler"]) continue;
		handler.enabled = NO;
		handler.enabled = YES;
		return;
	}
	[NSException raise:NSInternalInconsistencyException format:@"rootTouchCancel: missing renderer root touch handler"];
}
