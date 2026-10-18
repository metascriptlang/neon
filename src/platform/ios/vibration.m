#import "modules.h"
#import <AudioToolbox/AudioToolbox.h>

static NSUInteger g_vibration;

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
	NSArray<NSString *> *fields = [arg componentsSeparatedByString:NIField];
	NSArray<NSString *> *steps = fields[1].length ? [fields[1] componentsSeparatedByString:@","] : @[];
	g_vibration += 1;
	vibrateStep(steps, 0, [fields[0] isEqualToString:@"1"], g_vibration);
}

const char *niVibrationCommand(const char *name, const char *arg) {
	NSString *command = @(name);
	if ([command isEqualToString:@"vibrate"]) {
		vibrate(@(arg ? arg : ""));
		return niAppReply(@"");
	}
	if ([command isEqualToString:@"vibrate.cancel"]) {
		g_vibration += 1;
		return niAppReply(@"");
	}
	NSLog(@"Neon niAppCall: unknown command %@", command);
	abort();
}
