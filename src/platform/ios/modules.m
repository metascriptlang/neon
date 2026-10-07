#import "modules.h"

NSString *const NIField = @"\x1f";
NSString *const NIRecord = @"\x1e";

NSString *niModuleCall(NSString *name, NSString *arg) {
	NSRange dot = [name rangeOfString:@"."];
	NSString *domain = dot.location == NSNotFound ? name : [name substringToIndex:dot.location];
	if ([domain isEqualToString:@"storage"]) return niStorageCall(name, arg);
	if ([domain isEqualToString:@"netinfo"]) return niNetInfoCall(name, arg);
	NSLog(@"Neon niAppCall: unknown command %@", name);
	abort();
}
