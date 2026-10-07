#import "modules.h"
#import <UserNotifications/UserNotifications.h>

enum { REPLY_EVENT = 9, NOTIFICATION_EVENT = 12 };

static NSString *const DEFAULT_ACTION = @"expo.modules.notifications.actions.DEFAULT";
static const double PRESENT_WAIT = 3.0;

@interface NeonNotifications : NSObject <UNUserNotificationCenterDelegate>
@property(nonatomic, strong) NSMutableDictionary<NSString *, void (^)(UNNotificationPresentationOptions)> *awaiting;
@property(nonatomic) BOOL decides;
@property(nonatomic, copy) NSString *lastResponse;
@end

static NeonNotifications *g_notifications;

static NeonNotifications *notifications(void) {
	if (!g_notifications) {
		g_notifications = [NeonNotifications new];
		g_notifications.awaiting = [NSMutableDictionary dictionary];
		g_notifications.lastResponse = @"";
		UNUserNotificationCenter.currentNotificationCenter.delegate = g_notifications;
	}
	return g_notifications;
}

static NSString *record(NSString *kind, UNNotification *notification) {
	UNNotificationContent *content = notification.request.content;
	id data = content.userInfo[@"data"];
	return [@[
		kind, notification.request.identifier, content.title ?: @"", content.subtitle ?: @"", content.body ?: @"",
		[data isKindOfClass:NSString.class] ? data : @"",
		[NSString stringWithFormat:@"%.0f", notification.date.timeIntervalSince1970 * 1000.0],
	] componentsJoinedByString:NIField];
}

static NSString *schedule(NSString *requestId, NSArray<NSString *> *spec) {
	if (spec.count != 10) return @"!Notifications: malformed request";
	UNMutableNotificationContent *content = [UNMutableNotificationContent new];
	content.title = spec[1];
	content.subtitle = spec[2];
	content.body = spec[3];
	content.userInfo = @{ @"data": spec[4] };
	if ([spec[5] isEqualToString:@"1"]) content.sound = UNNotificationSound.defaultSound;
	if (spec[6].doubleValue >= 0) content.badge = @((NSInteger)spec[6].doubleValue);
	double seconds = spec[7].doubleValue;
	BOOL repeats = [spec[8] isEqualToString:@"1"];
	double date = spec[9].doubleValue;
	UNNotificationTrigger *trigger = nil;
	if (date >= 0) {
		NSDate *when = [NSDate dateWithTimeIntervalSince1970:date / 1000.0];
		NSDateComponents *parts = [NSCalendar.currentCalendar components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay |
			NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond fromDate:when];
		trigger = [UNCalendarNotificationTrigger triggerWithDateMatchingComponents:parts repeats:NO];
	} else if (seconds >= 0) {
		trigger = [UNTimeIntervalNotificationTrigger triggerWithTimeInterval:MAX(seconds, 0.1) repeats:repeats];
	}
	NSString *identifier = spec[0];
	UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:identifier content:content trigger:trigger];
	[UNUserNotificationCenter.currentNotificationCenter addNotificationRequest:request withCompletionHandler:^(NSError *error) {
		NSString *reply = error ? [@"!" stringByAppendingString:error.localizedDescription] : identifier;
		dispatch_async(dispatch_get_main_queue(), ^{
			niAppEmit(REPLY_EVENT, [@[requestId, reply] componentsJoinedByString:NIField]);
		});
	}];
	return @"";
}

static void present(NSArray<NSString *> *answer) {
	void (^complete)(UNNotificationPresentationOptions) = notifications().awaiting[answer[0]];
	if (!complete) return;
	[notifications().awaiting removeObjectForKey:answer[0]];
	UNNotificationPresentationOptions options = 0;
	if ([answer[1] isEqualToString:@"1"]) options |= UNNotificationPresentationOptionBanner | UNNotificationPresentationOptionList;
	if ([answer[2] isEqualToString:@"1"]) options |= UNNotificationPresentationOptionSound;
	if ([answer[3] isEqualToString:@"1"]) options |= UNNotificationPresentationOptionBadge;
	complete(options);
}

NSString *niNotificationCall(NSString *name, NSString *arg) {
	UNUserNotificationCenter *center = UNUserNotificationCenter.currentNotificationCenter;
	if ([name isEqualToString:@"notification.install"]) {
		notifications();
		return @"";
	}
	if ([name isEqualToString:@"notification.schedule"]) {
		NSRange split = [arg rangeOfString:NIField];
		return schedule([arg substringToIndex:split.location], [[arg substringFromIndex:split.location + 1] componentsSeparatedByString:NIField]);
	}
	if ([name isEqualToString:@"notification.cancel"]) {
		[center removePendingNotificationRequestsWithIdentifiers:@[arg]];
		return @"";
	}
	if ([name isEqualToString:@"notification.cancelAll"]) {
		[center removeAllPendingNotificationRequests];
		return @"";
	}
	if ([name isEqualToString:@"notification.dismissAll"]) {
		[center removeAllDeliveredNotifications];
		return @"";
	}
	if ([name isEqualToString:@"notification.handler"]) {
		notifications().decides = [arg isEqualToString:@"1"];
		return @"";
	}
	if ([name isEqualToString:@"notification.present"]) {
		present([arg componentsSeparatedByString:NIField]);
		return @"";
	}
	if ([name isEqualToString:@"notification.last"]) return notifications().lastResponse;
	NSLog(@"Neon niAppCall: unknown command %@", name);
	abort();
}

@implementation NeonNotifications

- (void)userNotificationCenter:(UNUserNotificationCenter *)center willPresentNotification:(UNNotification *)notification
	withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler {
	NSString *identifier = notification.request.identifier;
	if (self.decides) {
		self.awaiting[identifier] = completionHandler;
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(PRESENT_WAIT * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
			void (^waiting)(UNNotificationPresentationOptions) = self.awaiting[identifier];
			if (!waiting) return;
			[self.awaiting removeObjectForKey:identifier];
			waiting(0);
		});
	} else {
		completionHandler(0);
	}
	niAppEmit(NOTIFICATION_EVENT, record(@"received", notification));
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center didReceiveNotificationResponse:(UNNotificationResponse *)response
	withCompletionHandler:(void (^)(void))completionHandler {
	NSString *action = [response.actionIdentifier isEqualToString:UNNotificationDefaultActionIdentifier] ? DEFAULT_ACTION : response.actionIdentifier;
	NSString *value = [@[record(@"response", response.notification), action] componentsJoinedByString:NIField];
	self.lastResponse = value;
	niAppEmit(NOTIFICATION_EVENT, value);
	completionHandler();
}

@end
