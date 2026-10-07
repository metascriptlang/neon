#import "modules.h"

static NSMutableDictionary<NSString *, NSString *> *g_items;

static NSURL *storeURL(void) {
	NSFileManager *files = NSFileManager.defaultManager;
	NSURL *support = [files URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
	[files createDirectoryAtURL:support withIntermediateDirectories:YES attributes:nil error:nil];
	return [support URLByAppendingPathComponent:@"NeonAsyncStorage.plist"];
}

static NSMutableDictionary<NSString *, NSString *> *items(void) {
	if (!g_items) {
		NSDictionary *saved = [NSDictionary dictionaryWithContentsOfURL:storeURL() error:nil];
		g_items = saved ? [saved mutableCopy] : [NSMutableDictionary dictionary];
	}
	return g_items;
}

static void save(void) {
	NSError *error = nil;
	if (![items() writeToURL:storeURL() error:&error]) {
		NSLog(@"Neon AsyncStorage: cannot write %@: %@", storeURL().path, error);
		abort();
	}
}

NSString *niStorageCall(NSString *name, NSString *arg) {
	if ([name isEqualToString:@"storage.get"]) {
		NSString *value = items()[arg];
		return value ? [@"=" stringByAppendingString:value] : @"";
	}
	if ([name isEqualToString:@"storage.set"]) {
		NSRange split = [arg rangeOfString:NIField];
		if (split.location == NSNotFound) {
			NSLog(@"Neon storage.set: no value separator in the argument");
			abort();
		}
		items()[[arg substringToIndex:split.location]] = [arg substringFromIndex:split.location + 1];
		save();
		return @"";
	}
	if ([name isEqualToString:@"storage.remove"]) {
		[items() removeObjectForKey:arg];
		save();
		return @"";
	}
	if ([name isEqualToString:@"storage.clear"]) {
		[items() removeAllObjects];
		save();
		return @"";
	}
	if ([name isEqualToString:@"storage.keys"]) return [items().allKeys componentsJoinedByString:NIField];
	NSLog(@"Neon niAppCall: unknown command %@", name);
	abort();
}
