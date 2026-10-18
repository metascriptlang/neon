#import "modules.h"

NSString *const NIField = @"\x1f";
NSString *const NIRecord = @"\x1e";

NSString *niModuleCall(NSString *name, NSString *arg) {
	NSRange dot = [name rangeOfString:@"."];
	NSString *domain = dot.location == NSNotFound ? name : [name substringToIndex:dot.location];
	if ([domain isEqualToString:@"permission"] || [domain isEqualToString:@"permissionsAndroid"]) return niPermissionCall(name, arg);
	if ([domain isEqualToString:@"capture"]) return niCaptureCall(name, arg);
	if ([domain isEqualToString:@"sound"] || [domain isEqualToString:@"audio"] || [domain isEqualToString:@"recording"]) return niAudioCall(name, arg);
	NSLog(@"Neon niAppCall: unknown command %@", name);
	abort();
}
