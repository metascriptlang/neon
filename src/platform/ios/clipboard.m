#import "modules.h"
#import <UIKit/UIKit.h>

const char *niClipboardCommand(const char *name, const char *arg) {
	NSString *command = @(name);
	if ([command isEqualToString:@"clipboard.get"]) return niAppReply(UIPasteboard.generalPasteboard.string ?: @"");
	if ([command isEqualToString:@"clipboard.set"]) {
		UIPasteboard.generalPasteboard.string = @(arg ? arg : "");
		return niAppReply(@"");
	}
	NSLog(@"Neon niAppCall: unknown command %@", command);
	abort();
}
