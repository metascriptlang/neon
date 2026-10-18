#import "component.h"
#include "../native/components.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

@interface NeonSwitch : UISwitch <NeonComponentView>
@property (nonatomic) BOOL neonValue;
@end

@implementation NeonSwitch
- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self) [self addTarget:self action:@selector(neonChanged) forControlEvents:UIControlEventValueChanged];
	return self;
}
- (void)neonChanged {
	neonEmitControl((int)self.tag, 4, self.isOn ? @"true" : @"false", 0, 0);
	if (self.isOn != self.neonValue) [self setOn:self.neonValue animated:YES];
}
- (void)neonSetProp:(const char *)name value:(const char *)text {
	if (strcmp(name, "value") == 0) { self.neonValue = strcmp(text, "true") == 0; if (self.isOn != self.neonValue) [self setOn:self.neonValue animated:YES]; }
	else if (strcmp(name, "disabled") == 0) self.enabled = strcmp(text, "true") != 0;
	else if (strcmp(name, "thumbColor") == 0) self.thumbTintColor = text[0] ? neonCssColor(text, nil) : nil;
	else if (strcmp(name, "trackColorOn") == 0) self.onTintColor = text[0] ? neonCssColor(text, nil) : nil;
	else if (strcmp(name, "trackColorOff") == 0) { self.backgroundColor = text[0] ? neonCssColor(text, nil) : nil; self.layer.cornerRadius = 15.5; }
}
@end

void *niSwitchCreate(void) {
	return CFBridgingRetain([[NeonSwitch alloc] initWithFrame:CGRectZero]);
}
