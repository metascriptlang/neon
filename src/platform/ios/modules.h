#ifndef NEON_IOS_MODULES_H
#define NEON_IOS_MODULES_H

#import <UIKit/UIKit.h>
#include "../native/commands.h"

extern NSString *const NIField;
extern NSString *const NIRecord;

void niAppEmit(int kind, NSString *value);
NSString *niLinkingInitial(void);
void niLinkingLaunched(NSDictionary *launchOptions);
void niLinkingOpened(NSURL *url);
void niLinkingActive(void);
const char *niAppReply(NSString *reply);
NSString *niModuleCall(NSString *name, NSString *arg);

UIViewController *niPresenter(void);
NSString *niActionSheetCall(NSString *name, NSString *arg);
NSString *niSettingsCall(NSString *name, NSString *arg);

NSString *niCaptureCall(NSString *name, NSString *arg);
NSString *niAudioCall(NSString *name, NSString *arg);

NSString *niLocationPermission(void);
void niLocationAuthorize(void (^done)(void));

#endif
