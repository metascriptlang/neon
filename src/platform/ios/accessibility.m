#import "modules.h"
#import <UIKit/UIKit.h>

const char *niAccessibilityCommand(const char *name, const char *arg) {
	NSString *command = @(name);
	if ([command isEqualToString:@"a11y.screenReader"]) return niAppReply(UIAccessibilityIsVoiceOverRunning() ? @"1" : @"0");
	if ([command isEqualToString:@"a11y.reduceMotion"]) return niAppReply(UIAccessibilityIsReduceMotionEnabled() ? @"1" : @"0");
	if ([command isEqualToString:@"a11y.boldText"]) return niAppReply(UIAccessibilityIsBoldTextEnabled() ? @"1" : @"0");
	if ([command isEqualToString:@"a11y.grayscale"]) return niAppReply(UIAccessibilityIsGrayscaleEnabled() ? @"1" : @"0");
	if ([command isEqualToString:@"a11y.invertColors"]) return niAppReply(UIAccessibilityIsInvertColorsEnabled() ? @"1" : @"0");
	if ([command isEqualToString:@"a11y.reduceTransparency"]) return niAppReply(UIAccessibilityIsReduceTransparencyEnabled() ? @"1" : @"0");
	if ([command isEqualToString:@"a11y.darkerSystemColors"]) return niAppReply(UIAccessibilityDarkerSystemColorsEnabled() ? @"1" : @"0");
	if ([command isEqualToString:@"a11y.crossFade"]) {
		if (@available(iOS 14.0, *)) return niAppReply(UIAccessibilityPrefersCrossFadeTransitions() ? @"1" : @"0");
		return niAppReply(@"0");
	}
	if ([command isEqualToString:@"a11y.announceQueue"]) {
		NSArray<NSString *> *parts = [@(arg) componentsSeparatedByString:@"\x1f"];
		NSAttributedString *text = [[NSAttributedString alloc] initWithString:parts[1]
			attributes:@{UIAccessibilitySpeechAttributeQueueAnnouncement: @([parts[0] isEqualToString:@"1"])}];
		UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, text);
		return niAppReply(@"");
	}
	NSLog(@"Neon niAppCall: unknown command %@", command);
	abort();
}
