#import "modules.h"
#include <stdlib.h>
#include <string.h>

NSString *const NIField = @"\x1f";
NSString *const NIRecord = @"\x1e";

static char *g_reply;

const char *niAppReply(NSString *reply) {
	free(g_reply);
	g_reply = strdup(reply.UTF8String ?: "");
	return g_reply;
}
