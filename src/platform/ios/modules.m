#import "modules.h"

NSString *niModuleCall(NSString *name, NSString *arg) {
	NSRange dot = [name rangeOfString:@"."];
	NSString *domain = dot.location == NSNotFound ? name : [name substringToIndex:dot.location];
	if ([domain isEqualToString:@"capture"]) return niCaptureCall(name, arg);
	if ([domain isEqualToString:@"sound"] || [domain isEqualToString:@"audio"] || [domain isEqualToString:@"recording"]) return niAudioCall(name, arg);
	NSLog(@"Neon niAppCall: unknown command %@", name);
	abort();
}
