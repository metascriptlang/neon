#import "modules.h"
#import <UIKit/UIKit.h>

static NSString *call(NSString *name, NSString *arg) {
	if ([name isEqualToString:@"linking.open"] || [name isEqualToString:@"linking.settings"]) {
		NSURL *url = [name isEqualToString:@"linking.settings"] ? [NSURL URLWithString:UIApplicationOpenSettingsURLString] : [NSURL URLWithString:arg];
		if (!url || ![UIApplication.sharedApplication canOpenURL:url]) return @"0";
		[UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
		return @"1";
	}
	if ([name isEqualToString:@"linking.canOpen"]) {
		NSURL *url = [NSURL URLWithString:arg];
		return url && [UIApplication.sharedApplication canOpenURL:url] ? @"1" : @"0";
	}
	if ([name isEqualToString:@"linking.initial"]) return niLinkingInitial();
	NSLog(@"Neon niAppCall: unknown command %@", name);
	abort();
}

const char *niLinkingCommand(const char *name, const char *arg) {
	return niAppReply(call(@(name), @(arg ? arg : "")));
}
