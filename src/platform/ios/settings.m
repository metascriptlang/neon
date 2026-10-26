#include "../native/app.h"
#import "modules.h"

static BOOL g_ignoring;
static id g_observer;

// react-native 693e9628e8c, Libraries/Settings/RCTSettingsManager.mm:40-110.
static void watch(void) {
	if (g_observer) return;
	g_observer = [NSNotificationCenter.defaultCenter addObserverForName:NSUserDefaultsDidChangeNotification
		object:NSUserDefaults.standardUserDefaults queue:nil usingBlock:^(NSNotification *note) {
		if (g_ignoring) return;
		if (NSThread.isMainThread) niAppEmit(NI_APP_SETTINGS, @"");
		else dispatch_async(dispatch_get_main_queue(), ^{ niAppEmit(NI_APP_SETTINGS, @""); });
	}];
}

static NSString *get(NSString *key) {
	id value = [NSUserDefaults.standardUserDefaults objectForKey:key];
	if (!value || ![NSJSONSerialization isValidJSONObject:@[value]]) return @"";
	NSData *json = [NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingFragmentsAllowed error:nil];
	return json ? [@"=" stringByAppendingString:[[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding]] : @"";
}

static void set(NSString *values) {
	NSError *error = nil;
	NSDictionary *parsed = [NSJSONSerialization JSONObjectWithData:[values dataUsingEncoding:NSUTF8StringEncoding] options:0 error:&error];
	if (![parsed isKindOfClass:NSDictionary.class]) {
		NSLog(@"Neon settings.set: not a JSON object: %@", error);
		abort();
	}
	NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
	g_ignoring = YES;
	[parsed enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
		if (value == NSNull.null) {
			[defaults removeObjectForKey:key];
		} else if ([NSPropertyListSerialization propertyList:value isValidForFormat:NSPropertyListBinaryFormat_v1_0]) {
			[defaults setObject:value forKey:key];
		} else {
			NSLog(@"Neon Settings.set: %@ holds a null inside an array or object, which a property list cannot store", key);
			abort();
		}
	}];
	[defaults synchronize];
	g_ignoring = NO;
}

NSString *niSettingsCall(NSString *name, NSString *arg) {
	if ([name isEqualToString:@"settings.get"]) return get(arg);
	if ([name isEqualToString:@"settings.set"]) {
		set(arg);
		return @"";
	}
	if ([name isEqualToString:@"settings.watch"]) {
		watch();
		return @"";
	}
	NSLog(@"Neon niAppCall: unknown command %@", name);
	abort();
}
