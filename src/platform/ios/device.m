#import "modules.h"
#import <UIKit/UIKit.h>
#include <sys/utsname.h>

static NSString *joined(NSArray<NSString *> *fields) {
	return [fields componentsJoinedByString:NIField];
}

static NSString *haptic(NSString *name, NSString *style) {
	if ([name isEqualToString:@"haptics.impact"]) {
		UIImpactFeedbackStyle feedback = UIImpactFeedbackStyleMedium;
		if ([style isEqualToString:@"light"]) feedback = UIImpactFeedbackStyleLight;
		else if ([style isEqualToString:@"heavy"]) feedback = UIImpactFeedbackStyleHeavy;
		else if ([style isEqualToString:@"soft"]) feedback = UIImpactFeedbackStyleSoft;
		else if ([style isEqualToString:@"rigid"]) feedback = UIImpactFeedbackStyleRigid;
		UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:feedback];
		[generator prepare];
		[generator impactOccurred];
		return @"";
	}
	if ([name isEqualToString:@"haptics.notification"]) {
		UINotificationFeedbackType type = UINotificationFeedbackTypeSuccess;
		if ([style isEqualToString:@"warning"]) type = UINotificationFeedbackTypeWarning;
		else if ([style isEqualToString:@"error"]) type = UINotificationFeedbackTypeError;
		UINotificationFeedbackGenerator *generator = [UINotificationFeedbackGenerator new];
		[generator prepare];
		[generator notificationOccurred:type];
		return @"";
	}
	UISelectionFeedbackGenerator *generator = [UISelectionFeedbackGenerator new];
	[generator prepare];
	[generator selectionChanged];
	return @"";
}

static NSString *hardware(void) {
	NSString *simulated = NSProcessInfo.processInfo.environment[@"SIMULATOR_MODEL_IDENTIFIER"];
	if (simulated.length) return simulated;
	struct utsname system;
	uname(&system);
	return @(system.machine);
}

static NSString *bundleValue(NSString *key) {
	id value = [NSBundle.mainBundle objectForInfoDictionaryKey:key];
	return [value isKindOfClass:NSString.class] ? value : @"";
}

static NSString *info(void) {
	UIDevice *device = UIDevice.currentDevice;
	NSString *name = bundleValue(@"CFBundleDisplayName");
	if (!name.length) name = bundleValue(@"CFBundleName");
	return joined(@[
		@"Apple", @"Apple", device.model, hardware(), device.systemName, device.systemVersion, name,
		NSBundle.mainBundle.bundleIdentifier ?: @"", bundleValue(@"CFBundleShortVersionString"), bundleValue(@"CFBundleVersion"),
		TARGET_OS_SIMULATOR ? @"1" : @"0", device.userInterfaceIdiom == UIUserInterfaceIdiomPad ? @"1" : @"0",
	]);
}

static NSString *battery(void) {
	UIDevice *device = UIDevice.currentDevice;
	device.batteryMonitoringEnabled = YES;
	NSString *level = device.batteryLevel < 0 ? @"" : [NSString stringWithFormat:@"%g", device.batteryLevel];
	BOOL charging = device.batteryState == UIDeviceBatteryStateCharging || device.batteryState == UIDeviceBatteryStateFull;
	return joined(@[level, charging ? @"1" : @"0"]);
}

static NSString *measurement(NSLocale *locale) {
	NSString *system = [locale objectForKey:NSLocaleMeasurementSystem];
	if ([system isEqualToString:@"U.S."]) return @"us";
	if ([system isEqualToString:@"U.K."]) return @"uk";
	return system ? @"metric" : @"";
}

static NSString *localeRecord(NSString *tag, NSLocale *current) {
	NSLocale *locale = [NSLocale localeWithLocaleIdentifier:tag];
	NSString *language = [locale objectForKey:NSLocaleLanguageCode] ?: @"";
	NSString *script = [locale objectForKey:NSLocaleScriptCode] ?: @"";
	NSString *region = [locale objectForKey:NSLocaleCountryCode] ?: ([current objectForKey:NSLocaleCountryCode] ?: @"");
	NSLocale *regional = [NSLocale localeWithLocaleIdentifier:[NSString stringWithFormat:@"%@_%@", language, region]];
	BOOL rtl = [NSLocale characterDirectionForLanguage:language] == NSLocaleLanguageDirectionRightToLeft;
	NSArray<NSString *> *fahrenheit = @[@"US", @"BS", @"BZ", @"KY", @"PW", @"LR"];
	return joined(@[
		tag, language, script, region, rtl ? @"rtl" : @"ltr",
		[regional objectForKey:NSLocaleDecimalSeparator] ?: @"", [regional objectForKey:NSLocaleGroupingSeparator] ?: @"",
		measurement(regional), [regional objectForKey:NSLocaleCurrencyCode] ?: @"", [regional objectForKey:NSLocaleCurrencySymbol] ?: @"",
		region.length == 0 ? @"" : ([fahrenheit containsObject:region] ? @"fahrenheit" : @"celsius"),
	]);
}

static NSString *locales(void) {
	NSLocale *current = NSLocale.currentLocale;
	NSCalendar *calendar = NSCalendar.currentCalendar;
	NSString *hours = [NSDateFormatter dateFormatFromTemplate:@"j" options:0 locale:current];
	NSString *identifier = [calendar.calendarIdentifier isEqualToString:NSCalendarIdentifierGregorian] ? @"gregory" : calendar.calendarIdentifier;
	NSMutableArray<NSString *> *records = [NSMutableArray arrayWithObject:joined(@[
		identifier, NSTimeZone.localTimeZone.name, [hours containsString:@"a"] ? @"0" : @"1",
		[NSString stringWithFormat:@"%lu", (unsigned long)calendar.firstWeekday],
	])];
	for (NSString *tag in NSLocale.preferredLanguages) [records addObject:localeRecord(tag, current)];
	return [records componentsJoinedByString:NIRecord];
}

NSString *niDeviceCall(NSString *name, NSString *arg) {
	if ([name hasPrefix:@"haptics."]) return haptic(name, arg);
	if ([name isEqualToString:@"device.info"]) return info();
	if ([name isEqualToString:@"device.battery"]) return battery();
	if ([name isEqualToString:@"locale.info"]) return locales();
	NSLog(@"Neon niAppCall: unknown command %@", name);
	abort();
}
