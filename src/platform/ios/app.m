#import <UIKit/UIKit.h>
#include "../native/app.h"
#import "modules.h"
#include <stdlib.h>
#include <string.h>

static msClosure s_app;
static int g_event;
static char *g_value;
static int g_started;
static NSString *g_state = @"active";
static NSString *g_initialUrl = @"";
static BOOL g_launched;

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

UIViewController *niPresenter(void) {
	UIViewController *top = keyWindow().rootViewController;
	while (top.presentedViewController) top = top.presentedViewController;
	return top;
}

static NSString *flagText(BOOL on) {
	return on ? @"1" : @"0";
}

// RCTAccessibilityManager.mm: one observer per status notification, the event carries the new state.
static void observeFlag(NSString *name, NSNotificationName notification, BOOL (^state)(void)) {
	[NSNotificationCenter.defaultCenter addObserverForName:notification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
		emit(NI_APP_ACCESSIBILITY, [@[name, flagText(state())] componentsJoinedByString:FIELD]);
	}];
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
	observeFlag(@"boldTextChanged", UIAccessibilityBoldTextStatusDidChangeNotification, ^BOOL { return UIAccessibilityIsBoldTextEnabled(); });
	observeFlag(@"grayscaleChanged", UIAccessibilityGrayscaleStatusDidChangeNotification, ^BOOL { return UIAccessibilityIsGrayscaleEnabled(); });
	observeFlag(@"invertColorsChanged", UIAccessibilityInvertColorsStatusDidChangeNotification, ^BOOL { return UIAccessibilityIsInvertColorsEnabled(); });
	observeFlag(@"reduceTransparencyChanged", UIAccessibilityReduceTransparencyStatusDidChangeNotification, ^BOOL { return UIAccessibilityIsReduceTransparencyEnabled(); });
	observeFlag(@"darkerSystemColorsChanged", UIAccessibilityDarkerSystemColorsStatusDidChangeNotification, ^BOOL { return UIAccessibilityDarkerSystemColorsEnabled(); });
	[center addObserverForName:UIAccessibilityAnnouncementDidFinishNotification object:nil queue:main usingBlock:^(NSNotification *n) {
		NSString *text = n.userInfo[UIAccessibilityAnnouncementKeyStringValue] ?: @"";
		BOOL success = [n.userInfo[UIAccessibilityAnnouncementKeyWasSuccessful] boolValue];
		emit(NI_APP_ACCESSIBILITY, [@[@"announcementFinished", text, flagText(success)] componentsJoinedByString:FIELD]);
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
	[niPresenter() presentViewController:controller animated:YES completion:nil];
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
	UIViewController *top = niPresenter();
	controller.popoverPresentationController.sourceView = top.view;
	controller.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(top.view.bounds), CGRectGetMidY(top.view.bounds), 0, 0);
	[top presentViewController:controller animated:YES completion:nil];
	return @"";
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

NSString *niLinkingInitial(void) {
	return g_initialUrl;
}

void niLinkingLaunched(NSDictionary *launchOptions) {
	NSURL *url = launchOptions[UIApplicationLaunchOptionsURLKey];
	if (url == nil) {
		NSDictionary *activity = launchOptions[UIApplicationLaunchOptionsUserActivityDictionaryKey];
		url = ((NSUserActivity *)activity[@"UIApplicationLaunchOptionsUserActivityKey"]).webpageURL;
	}
	g_initialUrl = url ? url.absoluteString : @"";
}

void niLinkingOpened(NSURL *url) {
	if (!g_launched && [url.absoluteString isEqualToString:g_initialUrl]) return;
	emit(NI_APP_URL, url.absoluteString);
}

void niLinkingActive(void) {
	g_launched = YES;
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
	if ([name isEqualToString:@"share"]) return share(arg);
	if ([name isEqualToString:@"a11y.announce"]) {
		UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, arg);
		return @"";
	}
	if ([name isEqualToString:@"exitApp"]) return @"";
	return niModuleCall(name, arg);
}

const char *niAppCall(const char *name, const char *arg) {
	start();
	return niAppReply(call(@(name), @(arg ? arg : "")));
}

void niSetAppHandler(msClosure handler) { s_app = handler; }
int niLastAppEvent(void) { return g_event; }
const char *niLastAppValue(void) { return g_value ? g_value : ""; }
void niSetAppEventResult(int result) { (void)result; }
