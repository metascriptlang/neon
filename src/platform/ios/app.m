#import <UIKit/UIKit.h>
#import <AudioToolbox/AudioToolbox.h>
#include "../native/app.h"
#import "modules.h"
#include <stdlib.h>
#include <string.h>

static msClosure s_app;
static int g_event;
static char *g_value;
static char *g_reply;
static int g_started;
static NSString *g_state = @"active";
static NSUInteger g_vibration;

static NSString *const FIELD = @"\x1f";
static NSString *const RECORD = @"\x1e";

static void emit(int kind, NSString *value) {
	if (!s_app.fn) return;
	free(g_value);
	g_value = strdup(value ? value.UTF8String : "");
	g_event = kind;
	niInvokeClosure(s_app);
}

void niAppEmit(int kind, NSString *value) {
	emit(kind, value);
}

static void publishState(NSString *next) {
	if ([next isEqualToString:g_state]) return;
	g_state = next;
	emit(NI_APP_STATE, next);
}

static UIWindow *keyWindow(void) {
	for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
		if (![scene isKindOfClass:UIWindowScene.class]) continue;
		for (UIWindow *window in ((UIWindowScene *)scene).windows) {
			if (window.isKeyWindow) return window;
		}
	}
	return UIApplication.sharedApplication.windows.firstObject;
}

static UIViewController *presenter(void) {
	UIViewController *top = keyWindow().rootViewController;
	while (top.presentedViewController) top = top.presentedViewController;
	return top;
}

static void start(void) {
	if (g_started) return;
	g_started = 1;
	UIApplicationState now = UIApplication.sharedApplication.applicationState;
	g_state = now == UIApplicationStateBackground ? @"background" : now == UIApplicationStateInactive ? @"inactive" : @"active";
	NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
	NSOperationQueue *main = NSOperationQueue.mainQueue;
	[center addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:main usingBlock:^(NSNotification *n) { publishState(@"active"); }];
	[center addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:main usingBlock:^(NSNotification *n) { publishState(@"inactive"); }];
	[center addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:main usingBlock:^(NSNotification *n) { publishState(@"background"); }];
	[center addObserverForName:UIApplicationDidReceiveMemoryWarningNotification object:nil queue:main usingBlock:^(NSNotification *n) { emit(NI_APP_MEMORY_WARNING, @""); }];
	[center addObserverForName:UIAccessibilityVoiceOverStatusDidChangeNotification object:nil queue:main usingBlock:^(NSNotification *n) {
		emit(NI_APP_SCREEN_READER, UIAccessibilityIsVoiceOverRunning() ? @"1" : @"0");
	}];
	[center addObserverForName:UIAccessibilityReduceMotionStatusDidChangeNotification object:nil queue:main usingBlock:^(NSNotification *n) {
		emit(NI_APP_REDUCE_MOTION, UIAccessibilityIsReduceMotionEnabled() ? @"1" : @"0");
	}];
}

static NSString *fontScale(void) {
	NSDictionary<UIContentSizeCategory, NSNumber *> *scales = @{
		UIContentSizeCategoryExtraSmall: @0.823,
		UIContentSizeCategorySmall: @0.882,
		UIContentSizeCategoryMedium: @0.941,
		UIContentSizeCategoryLarge: @1.0,
		UIContentSizeCategoryExtraLarge: @1.118,
		UIContentSizeCategoryExtraExtraLarge: @1.235,
		UIContentSizeCategoryExtraExtraExtraLarge: @1.353,
		UIContentSizeCategoryAccessibilityMedium: @1.786,
		UIContentSizeCategoryAccessibilityLarge: @2.143,
		UIContentSizeCategoryAccessibilityExtraLarge: @2.643,
		UIContentSizeCategoryAccessibilityExtraExtraLarge: @3.143,
		UIContentSizeCategoryAccessibilityExtraExtraExtraLarge: @3.571,
	};
	NSNumber *scale = scales[UIApplication.sharedApplication.preferredContentSizeCategory];
	return (scale ?: @1.0).stringValue;
}

static NSString *alert(NSString *arg) {
	NSArray<NSString *> *parts = [arg componentsSeparatedByString:RECORD];
	NSArray<NSString *> *head = [parts[0] componentsSeparatedByString:FIELD];
	NSString *alertId = head[0];
	UIAlertController *controller = [UIAlertController alertControllerWithTitle:head[1]
		message:head[2].length ? head[2] : nil preferredStyle:UIAlertControllerStyleAlert];
	for (NSUInteger i = 1; i < parts.count; i++) {
		NSArray<NSString *> *button = [parts[i] componentsSeparatedByString:FIELD];
		NSString *style = button.count > 1 ? button[1] : @"default";
		UIAlertActionStyle actionStyle = [style isEqualToString:@"cancel"] ? UIAlertActionStyleCancel
			: [style isEqualToString:@"destructive"] ? UIAlertActionStyleDestructive : UIAlertActionStyleDefault;
		NSString *index = [NSString stringWithFormat:@"%lu", (unsigned long)(i - 1)];
		[controller addAction:[UIAlertAction actionWithTitle:button[0] style:actionStyle handler:^(UIAlertAction *action) {
			emit(NI_APP_ALERT, [@[alertId, index] componentsJoinedByString:FIELD]);
		}]];
	}
	[presenter() presentViewController:controller animated:YES completion:nil];
	return @"";
}

static NSString *share(NSString *arg) {
	NSArray<NSString *> *fields = [arg componentsSeparatedByString:FIELD];
	NSMutableArray *items = [NSMutableArray array];
	if (fields[1].length) [items addObject:fields[1]];
	NSURL *url = fields[2].length ? [NSURL URLWithString:fields[2]] : nil;
	if (url) [items addObject:url];
	UIActivityViewController *controller = [[UIActivityViewController alloc] initWithActivityItems:items applicationActivities:nil];
	if (fields[0].length) [controller setValue:fields[0] forKey:@"subject"];
	controller.completionWithItemsHandler = ^(UIActivityType type, BOOL completed, NSArray *returned, NSError *error) {
		NSString *action = completed ? @"sharedAction" : @"dismissedAction";
		emit(NI_APP_SHARE, [@[action, completed && type ? type : @""] componentsJoinedByString:FIELD]);
	};
	UIViewController *top = presenter();
	controller.popoverPresentationController.sourceView = top.view;
	controller.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(top.view.bounds), CGRectGetMidY(top.view.bounds), 0, 0);
	[top presentViewController:controller animated:YES completion:nil];
	return @"";
}

static void vibrateStep(NSArray<NSString *> *steps, NSUInteger at, BOOL repeat, NSUInteger generation) {
	if (generation != g_vibration) return;
	if (at + 1 >= steps.count) {
		if (repeat && steps.count >= 2) vibrateStep(steps, 0, repeat, generation);
		return;
	}
	double pause = steps[at].doubleValue / 1000.0;
	double length = steps[at + 1].doubleValue / 1000.0;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(pause * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		if (generation != g_vibration) return;
		AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(length * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
			vibrateStep(steps, at + 2, repeat, generation);
		});
	});
}

static void vibrate(NSString *arg) {
	NSArray<NSString *> *fields = [arg componentsSeparatedByString:FIELD];
	NSArray<NSString *> *steps = fields[1].length ? [fields[1] componentsSeparatedByString:@","] : @[];
	g_vibration += 1;
	vibrateStep(steps, 0, [fields[0] isEqualToString:@"1"], g_vibration);
}

void niImageFetch(NSString *uri, void (^done)(UIImage *image, NSString *error));

// Image.getSize / Image.prefetch: "id 0x1f uri" in, NI_APP_IMAGE_SIZE "id 0x1f w 0x1f h 0x1f error" out, in pixels.
static NSString *imageSize(NSString *arg) {
	NSArray<NSString *> *fields = [arg componentsSeparatedByString:FIELD];
	if (fields.count < 2) return @"";
	NSString *requestId = fields[0];
	niImageFetch(fields[1], ^(UIImage *image, NSString *error) {
		CGFloat w = image ? image.size.width * image.scale : 0;
		CGFloat h = image ? image.size.height * image.scale : 0;
		emit(NI_APP_IMAGE_SIZE, [@[requestId, @(w).stringValue, @(h).stringValue, error ?: @""] componentsJoinedByString:FIELD]);
	});
	return @"";
}

static NSString *call(NSString *name, NSString *arg) {
	if ([name isEqualToString:@"image.size"]) return imageSize(arg);
	if ([name isEqualToString:@"platform"]) return UIDevice.currentDevice.systemVersion;
	if ([name isEqualToString:@"isPad"]) return UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad ? @"1" : @"0";
	if ([name isEqualToString:@"pixelRatio"]) return @(UIScreen.mainScreen.scale).stringValue;
	if ([name isEqualToString:@"fontScale"]) return fontScale();
	if ([name isEqualToString:@"screen"]) {
		CGSize size = UIScreen.mainScreen.bounds.size;
		return [NSString stringWithFormat:@"%g%@%g", size.width, FIELD, size.height];
	}
	if ([name isEqualToString:@"appState"]) return g_state;
	if ([name isEqualToString:@"keyboard.dismiss"]) {
		[keyWindow() endEditing:YES];
		return @"";
	}
	if ([name isEqualToString:@"alert"]) return alert(arg);
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
	if ([name isEqualToString:@"linking.initial"]) return @"";
	if ([name isEqualToString:@"share"]) return share(arg);
	if ([name isEqualToString:@"vibrate"]) {
		vibrate(arg);
		return @"";
	}
	if ([name isEqualToString:@"vibrate.cancel"]) {
		g_vibration += 1;
		return @"";
	}
	if ([name isEqualToString:@"clipboard.get"]) return UIPasteboard.generalPasteboard.string ?: @"";
	if ([name isEqualToString:@"clipboard.set"]) {
		UIPasteboard.generalPasteboard.string = arg;
		return @"";
	}
	if ([name isEqualToString:@"a11y.screenReader"]) return UIAccessibilityIsVoiceOverRunning() ? @"1" : @"0";
	if ([name isEqualToString:@"a11y.reduceMotion"]) return UIAccessibilityIsReduceMotionEnabled() ? @"1" : @"0";
	if ([name isEqualToString:@"a11y.announce"]) {
		UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, arg);
		return @"";
	}
	if ([name isEqualToString:@"exitApp"]) return @"";
	return niModuleCall(name, arg);
}

const char *niAppCall(const char *name, const char *arg) {
	start();
	NSString *reply = call(@(name), @(arg ? arg : ""));
	free(g_reply);
	g_reply = strdup(reply.UTF8String ?: "");
	return g_reply;
}

void niSetAppHandler(msClosure handler) { s_app = handler; }
int niLastAppEvent(void) { return g_event; }
const char *niLastAppValue(void) { return g_value ? g_value : ""; }
void niSetAppEventResult(int result) { (void)result; }
