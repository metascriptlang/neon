#import <Cocoa/Cocoa.h>
#import "view.h"
#include "../native/components.h"
#include <stdio.h>
#include <string.h>

// RN macOS's RCTUISwitch : NSSwitch inside a NeonView.

static void centre(NSView *child, NSSize size, NSSize in) {
	child.frame = NSMakeRect(floor((in.width - size.width) / 2), floor((in.height - size.height) / 2), size.width, size.height);
}

@interface NeonSwitchControl : NSSwitch
@end

@implementation NeonSwitchControl
- (BOOL)acceptsFirstMouse:(NSEvent *)event { (void)event; return YES; }
@end

@interface NeonSwitch : NeonView <NeonComponentView>
@property(nonatomic) BOOL value;
@property(nonatomic, strong) NeonSwitchControl *control;
@end

@implementation NeonSwitch
- (instancetype)initWithFrame:(NSRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		_control = [[NeonSwitchControl alloc] initWithFrame:NSZeroRect];
		_control.target = self;
		_control.action = @selector(changed);
		[self addSubview:_control];
	}
	return self;
}

- (void)setFrameSize:(NSSize)size {
	[super setFrameSize:size];
	centre(self.control, self.control.fittingSize, size);
}

- (void)show { self.control.state = self.value ? NSControlStateValueOn : NSControlStateValueOff; }

// RN Switch is controlled: the event reports the flip, then the switch returns to `value` unless the handler changed it.
- (void)changed {
	neonEmitControl(self.neonTag, 4, self.control.state == NSControlStateValueOn ? @"true" : @"false", 0, 0);
	[self show];
}

- (void)setProp:(const char *)name value:(const char *)value {
	if (!strcmp(name, "value")) {
		self.value = !strcmp(value, "true");
		[self show];
	} else if (!strcmp(name, "disabled")) {
		self.control.enabled = strcmp(value, "true") != 0;
	} else if (!strcmp(name, "thumbColor") || !strcmp(name, "trackColorOn") || !strcmp(name, "trackColorOff")) {
		// NSSwitch draws in the system accent colour and has no tint API.
	} else {
		char what[128];
		snprintf(what, sizeof what, "Switch niSetProp(%s)", name);
		neonUnimplemented(what);
	}
}

- (NSView *)neonNativeTarget { return self.control; }

- (NSSize)neonFittingSize { return self.control.fittingSize; }
@end

void *niSwitchCreate(void) {
	neonRequireRoot("niSwitchCreate");
	return (void *)CFBridgingRetain([[NeonSwitch alloc] initWithFrame:NSZeroRect]);
}
