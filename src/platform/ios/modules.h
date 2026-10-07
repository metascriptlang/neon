#ifndef NEON_IOS_MODULES_H
#define NEON_IOS_MODULES_H

#import <Foundation/Foundation.h>

extern NSString *const NIField;
extern NSString *const NIRecord;

void niAppEmit(int kind, NSString *value);
NSString *niModuleCall(NSString *name, NSString *arg);

NSString *niStorageCall(NSString *name, NSString *arg);
NSString *niNetInfoCall(NSString *name, NSString *arg);
NSString *niPermissionCall(NSString *name, NSString *arg);

NSString *niLocationPermission(void);
void niLocationAuthorize(void (^done)(void));

#endif
