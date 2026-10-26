#ifndef NEON_IOS_COMPONENT_H
#define NEON_IOS_COMPONENT_H

#import <UIKit/UIKit.h>

@protocol NeonComponentView
- (void)neonSetProp:(const char *)name value:(const char *)value;
@optional
- (void)neonRelease;
@end

// Touch-forwarding view: every phase of a touch fires the one handler, with
// the tag + phase readable via niLastTouchTag/Phase.
@interface NeonTouchView : UIView
@property (nonatomic) BOOL neonHandlesPress;
@property (nonatomic) BOOL neonAccessibleSet;
@property (nonatomic) UIEdgeInsets neonHitSlop;
@end

void neonEmitControl(int tag, int phase, NSString *value, float width, float height);
// Attach the renderer's touch recognizer to a view outside the root's hierarchy.
void neonAttachTouchHandler(UIView *view);
// Point a text input at the accessory whose nativeID is `value` ("" clears it).
void neonSetInputAccessoryID(UIView *input, const char *value);
UIColor *neonCssColor(const char *css, UIColor *fallback);

#endif
