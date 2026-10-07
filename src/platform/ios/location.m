#import "modules.h"
#import <CoreLocation/CoreLocation.h>

enum { REPLY_EVENT = 9, LOCATION_EVENT = 11 };

@interface NeonLocationRequest : NSObject
@property(nonatomic, copy) NSString *requestId;
@property(nonatomic) BOOL highAccuracy;
@property(nonatomic) double timeout;
@property(nonatomic) double maximumAge;
@property(nonatomic) double distanceFilter;
@property(nonatomic, strong) CLLocation *last;
@end

@implementation NeonLocationRequest
@end

@interface NeonLocation : NSObject <CLLocationManagerDelegate>
@property(nonatomic, strong) CLLocationManager *manager;
@property(nonatomic, strong) NSMutableArray<void (^)(void)> *authorizing;
@property(nonatomic, strong) NSMutableArray<NeonLocationRequest *> *pending;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NeonLocationRequest *> *watches;
@end

static NeonLocation *g_location;

static NeonLocation *location(void) {
	if (!g_location) {
		g_location = [NeonLocation new];
		g_location.authorizing = [NSMutableArray array];
		g_location.pending = [NSMutableArray array];
		g_location.watches = [NSMutableDictionary dictionary];
		g_location.manager = [CLLocationManager new];
		g_location.manager.delegate = g_location;
	}
	return g_location;
}

static CLAuthorizationStatus authorization(void) {
	return location().manager.authorizationStatus;
}

static BOOL denied(void) {
	CLAuthorizationStatus status = authorization();
	return status == kCLAuthorizationStatusDenied || status == kCLAuthorizationStatusRestricted;
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

static NSString *measured(BOOL present, double value) {
	return present ? [NSString stringWithFormat:@"%.17g", value] : @"";
}

static NSString *encode(CLLocation *l) {
	return [@[
		@"ok",
		[NSString stringWithFormat:@"%.17g", l.coordinate.latitude],
		[NSString stringWithFormat:@"%.17g", l.coordinate.longitude],
		measured(l.verticalAccuracy >= 0, l.altitude),
		measured(l.horizontalAccuracy >= 0, l.horizontalAccuracy),
		measured(l.verticalAccuracy >= 0, l.verticalAccuracy),
		measured(l.course >= 0, l.course),
		measured(l.speed >= 0, l.speed),
		[NSString stringWithFormat:@"%.0f", l.timestamp.timeIntervalSince1970 * 1000.0],
	] componentsJoinedByString:NIField];
}

static NSString *failure(NSInteger code, NSString *message) {
	return [@[@"error", [NSString stringWithFormat:@"%ld", (long)code], message] componentsJoinedByString:NIField];
}

static NeonLocationRequest *parse(NSString *requestId, NSString *encoded) {
	NSArray<NSString *> *fields = [encoded componentsSeparatedByString:NIField];
	if (fields.count != 5) {
		NSLog(@"Neon location: malformed request %@", encoded);
		abort();
	}
	NeonLocationRequest *request = [NeonLocationRequest new];
	request.requestId = requestId;
	request.highAccuracy = [fields[0] isEqualToString:@"1"];
	request.timeout = fields[1].doubleValue;
	request.maximumAge = fields[2].doubleValue;
	request.distanceFilter = fields[3].doubleValue;
	return request;
}

static void refresh(void) {
	NeonLocation *state = location();
	BOOL any = state.pending.count > 0 || state.watches.count > 0;
	if (!any || denied() || authorization() == kCLAuthorizationStatusNotDetermined) {
		[state.manager stopUpdatingLocation];
		return;
	}
	BOOL high = NO;
	double filter = state.pending.count > 0 ? 0 : DBL_MAX;
	for (NeonLocationRequest *request in state.pending) high |= request.highAccuracy;
	for (NeonLocationRequest *watch in state.watches.allValues) {
		high |= watch.highAccuracy;
		filter = MIN(filter, MAX(0, watch.distanceFilter));
	}
	state.manager.desiredAccuracy = high ? kCLLocationAccuracyBest : kCLLocationAccuracyHundredMeters;
	state.manager.distanceFilter = filter <= 0 ? kCLDistanceFilterNone : filter;
	[state.manager startUpdatingLocation];
}

static void reply(NSString *requestId, NSString *value) {
	niAppEmit(REPLY_EVENT, [@[requestId, value] componentsJoinedByString:NIField]);
}

static void report(NSString *watchId, NSString *value) {
	niAppEmit(LOCATION_EVENT, [@[watchId, value] componentsJoinedByString:NIField]);
}

static void failEverything(NSInteger code, NSString *message) {
	NeonLocation *state = location();
	NSArray<NeonLocationRequest *> *pending = [state.pending copy];
	[state.pending removeAllObjects];
	for (NeonLocationRequest *request in pending) reply(request.requestId, failure(code, message));
	for (NSString *watchId in state.watches.allKeys) report(watchId, failure(code, message));
	refresh();
}

static NSString *current(NSString *requestId, NeonLocationRequest *request) {
	if (denied()) return failure(1, @"Location permission was not granted.");
	CLLocation *cached = location().manager.location;
	if (cached && (request.maximumAge < 0 || -cached.timestamp.timeIntervalSinceNow * 1000.0 <= request.maximumAge)) return encode(cached);
	[location().pending addObject:request];
	niLocationAuthorize(^{ refresh(); });
	if (request.timeout >= 0) {
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(request.timeout * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
			if (![location().pending containsObject:request]) return;
			[location().pending removeObject:request];
			reply(requestId, failure(3, @"Location request timed out."));
			refresh();
		});
	}
	return @"";
}

static void watch(NSString *watchId, NeonLocationRequest *request) {
	if (denied()) {
		dispatch_async(dispatch_get_main_queue(), ^{ report(watchId, failure(1, @"Location permission was not granted.")); });
		return;
	}
	location().watches[watchId] = request;
	niLocationAuthorize(^{ refresh(); });
}

NSString *niLocationCall(NSString *name, NSString *arg) {
	NSRange split = [arg rangeOfString:NIField];
	NSString *requestId = split.location == NSNotFound ? arg : [arg substringToIndex:split.location];
	NSString *rest = split.location == NSNotFound ? @"" : [arg substringFromIndex:split.location + 1];
	if ([name isEqualToString:@"location.current"]) return current(requestId, parse(requestId, rest));
	if ([name isEqualToString:@"location.watch"]) {
		watch(requestId, parse(requestId, rest));
		return @"";
	}
	if ([name isEqualToString:@"location.clear"]) {
		[location().watches removeObjectForKey:requestId];
		refresh();
		return @"";
	}
	NSLog(@"Neon niAppCall: unknown command %@", name);
	abort();
}

@implementation NeonLocation

- (void)locationManagerDidChangeAuthorization:(CLLocationManager *)manager {
	if (manager.authorizationStatus == kCLAuthorizationStatusNotDetermined) return;
	NSArray<void (^)(void)> *waiting = [self.authorizing copy];
	[self.authorizing removeAllObjects];
	for (void (^done)(void) in waiting) done();
	if (denied()) failEverything(1, @"Location permission was not granted.");
	else refresh();
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
	CLLocation *latest = locations.lastObject;
	if (!latest) return;
	NSString *encoded = encode(latest);
	NSArray<NeonLocationRequest *> *pending = [self.pending copy];
	[self.pending removeAllObjects];
	for (NeonLocationRequest *request in pending) reply(request.requestId, encoded);
	for (NSString *watchId in self.watches.allKeys) {
		NeonLocationRequest *watch = self.watches[watchId];
		if (watch.last && [latest distanceFromLocation:watch.last] < watch.distanceFilter) continue;
		watch.last = latest;
		report(watchId, encoded);
	}
	refresh();
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
	if (error.code == kCLErrorLocationUnknown) return;
	failEverything(error.code == kCLErrorDenied ? 1 : 2, error.localizedDescription);
}

@end
