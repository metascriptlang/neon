#ifndef NEON_NATIVE_APP_H
#define NEON_NATIVE_APP_H

#include "bridge.h"

enum {
	NI_APP_STATE = 0,
	NI_APP_BACK_PRESS = 1,
	NI_APP_ALERT = 2,
	NI_APP_SCREEN_READER = 3,
	NI_APP_URL = 4,
	NI_APP_SHARE = 5,
	NI_APP_MEMORY_WARNING = 6,
	NI_APP_REDUCE_MOTION = 7,
};

const char *niAppCall(const char *name, const char *arg);
void niSetAppHandler(msClosure handler);
int niLastAppEvent(void);
const char *niLastAppValue(void);
void niSetAppEventResult(int result);

void niInvokeClosure(msClosure c);

#endif
