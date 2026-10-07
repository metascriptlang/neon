#ifndef NEON_IOS_MODULES_H
#define NEON_IOS_MODULES_H

#import <Foundation/Foundation.h>

extern NSString *const NIField;
extern NSString *const NIRecord;

void niAppEmit(int kind, NSString *value);
NSString *niModuleCall(NSString *name, NSString *arg);

NSString *niStorageCall(NSString *name, NSString *arg);
NSString *niNetInfoCall(NSString *name, NSString *arg);

#endif
