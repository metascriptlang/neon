// WebView, Video and CameraView on AppKit: src/platform/ios/media.m and camera.m ported, each view hosted in a
// NeonView. WKWebView, AVPlayerView and AVCaptureVideoPreviewLayer are the macOS forms of the iOS views.
#ifndef NEON_MACOS_MEDIA_H
#define NEON_MACOS_MEDIA_H

#import <Cocoa/Cocoa.h>
#import "view.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum {
	MEDIA_LOAD = 5, MEDIA_ERROR = 6, MEDIA_LOAD_START = 10, MEDIA_MESSAGE = 11, MEDIA_SHOULD_START = 12, MEDIA_PROGRESS = 13,
	MEDIA_END = 14, CAMERA_READY = 30, CAMERA_MOUNT_ERROR = 31, CAMERA_PICTURE = 32,
};

static NSString *const FIELD = @"\x1f";

static inline void emit(int32_t tag, int phase, NSString *value) {
	if (tag != 0) neonEmitControl(tag, phase, value, 0, 0);
}

static inline void noCommand(const char *component, NSString *name) {
	fprintf(stderr, "neon macos bridge: %s has no command \"%s\"\n", component, name.UTF8String);
	fflush(stderr);
	abort();
}

static inline void noProp(const char *component, const char *name) {
	fprintf(stderr, "neon macos bridge: %s niSetProp(%s) is not implemented on macOS yet\n", component, name);
	fflush(stderr);
	abort();
}

static inline NSString *field(NSArray<NSString *> *fields, NSUInteger at) { return at < fields.count ? fields[at] : @""; }

static inline void splitCommand(NSString *value, NSString **name, NSString **argument) {
	NSRange cut = [value rangeOfString:FIELD];
	*name = cut.location == NSNotFound ? value : [value substringToIndex:cut.location];
	*argument = cut.location == NSNotFound ? @"" : [value substringFromIndex:cut.location + 1];
}

#endif
