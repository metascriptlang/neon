#ifndef NEON_IOS_MODULES_H
#define NEON_IOS_MODULES_H

#import <Foundation/Foundation.h>
#include "commands.h"

extern NSString *const NIField;
extern NSString *const NIRecord;

void niAppEmit(int kind, NSString *value);
const char *niAppReply(NSString *reply);
NSString *niModuleCall(NSString *name, NSString *arg);

NSString *niStorageCall(NSString *name, NSString *arg);
NSString *niNetInfoCall(NSString *name, NSString *arg);
NSString *niPermissionCall(NSString *name, NSString *arg);
NSString *niLocationCall(NSString *name, NSString *arg);
NSString *niDeviceCall(NSString *name, NSString *arg);
NSString *niCaptureCall(NSString *name, NSString *arg);
NSString *niAudioCall(NSString *name, NSString *arg);

NSString *niLocationPermission(void);
void niLocationAuthorize(void (^done)(void));

#endif
