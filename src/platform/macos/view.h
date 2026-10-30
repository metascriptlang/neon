#ifndef NEON_MACOS_VIEW_H
#define NEON_MACOS_VIEW_H

#import <Cocoa/Cocoa.h>

// The view every Neon node is on macOS (bridge.m); a component view subclasses it and answers setProp:value:.
@interface NeonView : NSView
@property(nonatomic) int32_t neonTag;
@property(nonatomic) BOOL pressable;
@property(nonatomic) float x, y, w, h;
@property(nonatomic) float scaleX, scaleY, translateX, translateY, rotation, radius;
@property(nonatomic) BOOL clips;
@property(nonatomic, strong) NSColor *neonBackground;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *accessibility;
@end

@protocol NeonComponentView
- (void)setProp:(const char *)name value:(const char *)value;
@optional
// The host released the node: stop what keeps running after the view leaves (a player, a capture session).
- (void)neonRelease;
// Where AppKit delivers a click on the view, nil to let Neon's own hit test take it.
- (NSView *)neonNativeTarget;
- (NSSize)neonFittingSize;
@end

// A control event to the host (bridge.h niSetControlHandler): tag, phase (src/platform/native/contract.ms), value, size.
void neonEmitControl(int32_t tag, int phase, NSString *value, float width, float height);
void neonRequireRoot(const char *what);
NeonView *neonRootInWindow(NSWindow *window);
void neonUnimplemented(const char *what);
NSColor *neonCssColor(NSString *css);

#endif
