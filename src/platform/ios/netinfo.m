#import "modules.h"
#import <Network/Network.h>

enum { NETINFO_EVENT = 10 };

static nw_path_monitor_t g_monitor;
static NSString *g_state;

static NSString *unknownState(void) {
	return [@[@"unknown", @"", @"", @"0"] componentsJoinedByString:NIField];
}

static NSString *describe(nw_path_t path) {
	if (nw_path_get_status(path) != nw_path_status_satisfied) {
		return [@[@"none", @"0", @"0", @"0"] componentsJoinedByString:NIField];
	}
	NSString *type = @"other";
	if (nw_path_uses_interface_type(path, nw_interface_type_wifi)) type = @"wifi";
	else if (nw_path_uses_interface_type(path, nw_interface_type_cellular)) type = @"cellular";
	else if (nw_path_uses_interface_type(path, nw_interface_type_wired)) type = @"ethernet";
	NSString *expensive = nw_path_is_expensive(path) ? @"1" : @"0";
	return [@[type, @"1", @"1", expensive] componentsJoinedByString:NIField];
}

static void watch(void) {
	g_monitor = nw_path_monitor_create();
	nw_path_monitor_set_queue(g_monitor, dispatch_get_main_queue());
	nw_path_monitor_set_update_handler(g_monitor, ^(nw_path_t path) {
		NSString *next = describe(path);
		if ([next isEqualToString:g_state]) return;
		g_state = next;
		niAppEmit(NETINFO_EVENT, next);
	});
	nw_path_monitor_start(g_monitor);
}

NSString *niNetInfoCall(NSString *name, NSString *arg) {
	if (!g_state) g_state = unknownState();
	if ([name isEqualToString:@"netinfo.watch"]) {
		if (!g_monitor) watch();
		return g_state;
	}
	if ([name isEqualToString:@"netinfo.fetch"]) return g_state;
	NSLog(@"Neon niAppCall: unknown command %@", name);
	abort();
}
