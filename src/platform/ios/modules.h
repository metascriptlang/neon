#ifndef NEON_IOS_MODULES_H
#define NEON_IOS_MODULES_H

#import <Foundation/Foundation.h>
#include "../native/commands.h"

extern NSString *const NIField;
extern NSString *const NIRecord;

void niAppEmit(int kind, NSString *value);
const char *niAppReply(NSString *reply);
NSString *niModuleCall(NSString *name, NSString *arg);

NSString *niCaptureCall(NSString *name, NSString *arg);
NSString *niAudioCall(NSString *name, NSString *arg);

NSString *niLocationPermission(void);
void niLocationAuthorize(void (^done)(void));

#endif
