#import "modules.h"
#import <CoreLocation/CoreLocation.h>

@interface NeonLocation : NSObject <CLLocationManagerDelegate>
@property(nonatomic, strong) CLLocationManager *manager;
@property(nonatomic, strong) NSMutableArray<void (^)(void)> *authorizing;
@end

static NeonLocation *g_location;

static NeonLocation *location(void) {
	if (!g_location) {
		g_location = [NeonLocation new];
		g_location.authorizing = [NSMutableArray array];
		g_location.manager = [CLLocationManager new];
		g_location.manager.delegate = g_location;
	}
	return g_location;
}

static CLAuthorizationStatus authorization(void) {
	return location().manager.authorizationStatus;
}

NSString *niLocationPermission(void) {
	switch (authorization()) {
	case kCLAuthorizationStatusNotDetermined: return [@[@"undetermined", @"1"] componentsJoinedByString:NIField];
	case kCLAuthorizationStatusAuthorizedAlways:
	case kCLAuthorizationStatusAuthorizedWhenInUse: return [@[@"granted", @"0"] componentsJoinedByString:NIField];
	default: return [@[@"denied", @"0"] componentsJoinedByString:NIField];
	}
}

void niLocationAuthorize(void (^done)(void)) {
	if (authorization() != kCLAuthorizationStatusNotDetermined) {
		done();
		return;
	}
	[location().authorizing addObject:done];
	[location().manager requestWhenInUseAuthorization];
}

@implementation NeonLocation

- (void)locationManagerDidChangeAuthorization:(CLLocationManager *)manager {
	if (manager.authorizationStatus == kCLAuthorizationStatusNotDetermined) return;
	NSArray<void (^)(void)> *waiting = [self.authorizing copy];
	[self.authorizing removeAllObjects];
	for (void (^done)(void) in waiting) done();
}

@end
