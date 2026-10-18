#import <Cocoa/Cocoa.h>
#import <CoreImage/CoreImage.h>
#import "view.h"
#include "../native/components.h"
#include <stdio.h>
#include <string.h>

// RN macOS's RCTUIActivityIndicatorView : NSProgressIndicator inside a NeonView.

static void centre(NSView *child, NSSize size, NSSize in) {
	child.frame = NSMakeRect(floor((in.width - size.width) / 2), floor((in.height - size.height) / 2), size.width, size.height);
}

@interface NeonIndicator : NeonView <NeonComponentView>
@property(nonatomic) BOOL animating, hidesWhenStopped;
@property(nonatomic, strong) NSColor *color;
@property(nonatomic, strong) NSProgressIndicator *spinner;
@end

@implementation NeonIndicator
- (instancetype)initWithFrame:(NSRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		_spinner = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
		_spinner.style = NSProgressIndicatorStyleSpinning;
		_spinner.indeterminate = YES;
		_spinner.wantsLayer = YES;
		_spinner.layerUsesCoreImageFilters = YES;
		_animating = YES;
		_hidesWhenStopped = YES;
		[self addSubview:_spinner];
		[self show];
	}
	return self;
}

- (void)setFrameSize:(NSSize)size {
	[super setFrameSize:size];
	CGFloat side = MIN(size.width, size.height);
	centre(self.spinner, NSMakeSize(side, side), size);
}

- (void)show {
	self.spinner.displayedWhenStopped = !self.hidesWhenStopped;
	if (self.animating) [self.spinner startAnimation:nil];
	else [self.spinner stopAnimation:nil];
	if (!self.color) {
		self.spinner.layer.filters = nil;
		return;
	}
	CGFloat r, g, b, a;
	[[self.color colorUsingColorSpace:NSColorSpace.sRGBColorSpace] getRed:&r green:&g blue:&b alpha:&a];
	CIFilter *tint = [CIFilter filterWithName:@"CIColorPolynomial"];
	[tint setDefaults];
	[tint setValue:[CIVector vectorWithX:r Y:0 Z:0 W:0] forKey:@"inputRedCoefficients"];
	[tint setValue:[CIVector vectorWithX:g Y:0 Z:0 W:0] forKey:@"inputGreenCoefficients"];
	[tint setValue:[CIVector vectorWithX:b Y:0 Z:0 W:0] forKey:@"inputBlueCoefficients"];
	self.spinner.layer.filters = @[tint];
}

- (void)setProp:(const char *)name value:(const char *)value {
	if (!strcmp(name, "animating")) self.animating = strcmp(value, "false") != 0;
	else if (!strcmp(name, "hidesWhenStopped")) self.hidesWhenStopped = strcmp(value, "false") != 0;
	else if (!strcmp(name, "color")) self.color = value[0] ? neonCssColor(@(value)) : nil;
	else {
		char what[128];
		snprintf(what, sizeof what, "ActivityIndicator niSetProp(%s)", name);
		neonUnimplemented(what);
	}
	[self show];
}
@end

void *niIndicatorCreate(void) {
	neonRequireRoot("niIndicatorCreate");
	return (void *)CFBridgingRetain([[NeonIndicator alloc] initWithFrame:NSZeroRect]);
}
