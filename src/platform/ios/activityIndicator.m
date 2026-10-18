#import "component.h"
#include "../native/components.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

@interface NeonIndicator : UIActivityIndicatorView <NeonComponentView>
@property (nonatomic) BOOL neonAnimating;
@end

@implementation NeonIndicator
- (void)neonApply {
	if (self.neonAnimating) [self startAnimating];
	else [self stopAnimating];
}
- (void)neonSetProp:(const char *)name value:(const char *)text {
	if (strcmp(name, "animating") == 0) { self.neonAnimating = strcmp(text, "false") != 0; [self neonApply]; }
	else if (strcmp(name, "hidesWhenStopped") == 0) self.hidesWhenStopped = strcmp(text, "false") != 0;
	else if (strcmp(name, "color") == 0) self.color = text[0] ? neonCssColor(text, UIColor.grayColor) : UIColor.grayColor;
}
@end

void *niIndicatorCreate(void) {
	NeonIndicator *indicator = [[NeonIndicator alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
	indicator.hidesWhenStopped = YES;
	indicator.neonAnimating = YES;
	[indicator neonApply];
	return CFBridgingRetain(indicator);
}
