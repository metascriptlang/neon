#import "modules.h"
#import <AVFoundation/AVFoundation.h>
#import <UserNotifications/UserNotifications.h>

enum { REPLY_EVENT = 9 };

static NSString *reply(NSString *status, BOOL canAskAgain) {
	return [@[status, canAskAgain ? @"1" : @"0"] componentsJoinedByString:NIField];
}

static NSString *mediaStatus(AVMediaType type) {
	switch ([AVCaptureDevice authorizationStatusForMediaType:type]) {
	case AVAuthorizationStatusNotDetermined: return reply(@"undetermined", YES);
	case AVAuthorizationStatusAuthorized: return reply(@"granted", NO);
	default: return reply(@"denied", NO);
	}
}

static NSString *missingUsage(NSString *name, NSString *key) {
	if ([NSBundle.mainBundle objectForInfoDictionaryKey:key]) return nil;
	return [NSString stringWithFormat:@"!Permissions.request(%@): add %@ to the app's Info.plist", name, key];
}

static void answer(NSString *requestId, NSString *value) {
	dispatch_async(dispatch_get_main_queue(), ^{
		niAppEmit(REPLY_EVENT, [@[requestId, value] componentsJoinedByString:NIField]);
	});
}

static NSString *notificationStatus(UNAuthorizationStatus status) {
	switch (status) {
	case UNAuthorizationStatusNotDetermined: return reply(@"undetermined", YES);
	case UNAuthorizationStatusDenied: return reply(@"denied", NO);
	default: return reply(@"granted", NO);
	}
}

static NSString *check(NSString *requestId, NSString *name) {
	if ([name isEqualToString:@"camera"]) return mediaStatus(AVMediaTypeVideo);
	if ([name isEqualToString:@"microphone"]) return mediaStatus(AVMediaTypeAudio);
	if ([name isEqualToString:@"location"]) return niLocationPermission();
	if ([name isEqualToString:@"notifications"]) {
		[UNUserNotificationCenter.currentNotificationCenter getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings) {
			answer(requestId, notificationStatus(settings.authorizationStatus));
		}];
		return @"";
	}
	return [NSString stringWithFormat:@"!Permissions: unknown permission %@", name];
}

static NSString *requestMedia(NSString *requestId, NSString *name, AVMediaType type, NSString *key) {
	NSString *now = mediaStatus(type);
	if (![now hasPrefix:@"undetermined"]) return now;
	NSString *missing = missingUsage(name, key);
	if (missing) return missing;
	[AVCaptureDevice requestAccessForMediaType:type completionHandler:^(BOOL granted) {
		answer(requestId, mediaStatus(type));
	}];
	return @"";
}

static NSString *request(NSString *requestId, NSString *name) {
	if ([name isEqualToString:@"camera"]) return requestMedia(requestId, name, AVMediaTypeVideo, @"NSCameraUsageDescription");
	if ([name isEqualToString:@"microphone"]) return requestMedia(requestId, name, AVMediaTypeAudio, @"NSMicrophoneUsageDescription");
	if ([name isEqualToString:@"location"]) {
		NSString *now = niLocationPermission();
		if (![now hasPrefix:@"undetermined"]) return now;
		NSString *missing = missingUsage(name, @"NSLocationWhenInUseUsageDescription");
		if (missing) return missing;
		niLocationAuthorize(^{ answer(requestId, niLocationPermission()); });
		return @"";
	}
	if ([name isEqualToString:@"notifications"]) {
		UNAuthorizationOptions options = UNAuthorizationOptionAlert | UNAuthorizationOptionSound | UNAuthorizationOptionBadge;
		[UNUserNotificationCenter.currentNotificationCenter requestAuthorizationWithOptions:options completionHandler:^(BOOL granted, NSError *error) {
			[UNUserNotificationCenter.currentNotificationCenter getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings) {
				answer(requestId, notificationStatus(settings.authorizationStatus));
			}];
		}];
		return @"";
	}
	return [NSString stringWithFormat:@"!Permissions: unknown permission %@", name];
}

NSString *niPermissionCall(NSString *name, NSString *arg) {
	NSRange split = [arg rangeOfString:NIField];
	NSString *requestId = split.location == NSNotFound ? arg : [arg substringToIndex:split.location];
	NSString *rest = split.location == NSNotFound ? @"" : [arg substringFromIndex:split.location + 1];
	if ([name isEqualToString:@"permission.check"]) return check(requestId, rest);
	if ([name isEqualToString:@"permission.request"]) return request(requestId, rest);
	if ([name isEqualToString:@"permissionsAndroid.check"]) return @"0";
	if ([name isEqualToString:@"permissionsAndroid.rationale"]) return @"0";
	if ([name isEqualToString:@"permissionsAndroid.request"]) {
		NSUInteger count = [rest componentsSeparatedByString:@","].count;
		NSMutableArray *denied = [NSMutableArray array];
		for (NSUInteger i = 0; i < count; i++) [denied addObject:@"denied"];
		return [denied componentsJoinedByString:NIField];
	}
	NSLog(@"Neon niAppCall: unknown command %@", name);
	abort();
}
