#import "modules.h"
#import <UIKit/UIKit.h>

const char *niAccessibilityCommand(const char *name, const char *arg) {
	NSString *command = @(name);
	if ([command isEqualToString:@"a11y.screenReader"]) return niAppReply(UIAccessibilityIsVoiceOverRunning() ? @"1" : @"0");
	if ([command isEqualToString:@"a11y.reduceMotion"]) return niAppReply(UIAccessibilityIsReduceMotionEnabled() ? @"1" : @"0");
	NSLog(@"Neon niAppCall: unknown command %@", command);
	abort();
}
