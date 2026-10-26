#import "component.h"
#include "../native/components.h"
#import <objc/runtime.h>
#include <string.h>

// RN RCTInputAccessoryViewContent: the view UIKit shows above the keyboard. Its children sit in
// a container pinned to the safe area, which is as tall as the Neon-laid-out accessory.
@interface NeonAccessoryContent : UIView
@property (nonatomic, strong) UIView *safeAreaContainer;
@property (nonatomic, strong) NSLayoutConstraint *heightConstraint;
- (void)neonSetSize:(CGSize)size;
@end

@implementation NeonAccessoryContent

- (instancetype)init {
	self = [super init];
	if (self) {
		_safeAreaContainer = [UIView new];
		[super addSubview:_safeAreaContainer];
		self.autoresizingMask = UIViewAutoresizingFlexibleHeight;
		_safeAreaContainer.translatesAutoresizingMaskIntoConstraints = NO;
		_heightConstraint = [_safeAreaContainer.heightAnchor constraintEqualToConstant:0];
		_heightConstraint.active = YES;
		[_safeAreaContainer.bottomAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.bottomAnchor].active = YES;
		[_safeAreaContainer.topAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.topAnchor].active = YES;
		[_safeAreaContainer.leadingAnchor constraintEqualToAnchor:self.leadingAnchor].active = YES;
		[_safeAreaContainer.trailingAnchor constraintEqualToAnchor:self.trailingAnchor].active = YES;
	}
	return self;
}

// The size comes from the autolayout constraints, as in RN.
- (CGSize)intrinsicContentSize {
	return CGSizeZero;
}

// Set the frame at once: left until the keyboard opens, the height would animate from 0.
- (void)neonSetSize:(CGSize)size {
	CGRect frame = CGRectMake(0, 0, size.width, size.height);
	[self setFrame:frame];
	[self.safeAreaContainer setFrame:frame];
	self.heightConstraint.constant = size.height;
	[self layoutIfNeeded];
}

- (void)neonAdd:(UIView *)view {
	[self.safeAreaContainer addSubview:view];
}

@end

@class NeonInputAccessoryView;

// An accessory looked up by `nativeID`; the inputs holding an `inputAccessoryViewID`, so a
// registration after the input still reaches it. RN resolves the ID through the UIManager when
// the input's props change (RCTBaseTextInputView.mm:691).
static NSMapTable<NSString *, NeonInputAccessoryView *> *accessories(void) {
	static NSMapTable *table;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ table = [NSMapTable strongToWeakObjectsMapTable]; });
	return table;
}

@interface NeonInputAccessoryView : NeonTouchView <NeonComponentView>
@property (nonatomic, strong) NeonAccessoryContent *neonContent;
@property (nonatomic, copy) NSString *neonID;
@property (nonatomic) BOOL neonClaimed;
@end

static void applyAccessory(UIView *input) {
	NSString *key = neonInputAccessoryID(input);
	UIView *content = key ? [accessories() objectForKey:key].neonContent : nil;
	if ([input isKindOfClass:UITextField.class]) ((UITextField *)input).inputAccessoryView = content;
	else if ([input isKindOfClass:UITextView.class]) ((UITextView *)input).inputAccessoryView = content;
	else return;
	if (input.isFirstResponder) [input reloadInputViews];
}

static void refreshAccessoryInputs(NSString *key) {
	for (UIView *input in neonAccessoryInputs().allObjects) {
		if ([neonInputAccessoryID(input) isEqualToString:key]) applyAccessory(input);
	}
}

@implementation NeonInputAccessoryView

- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		_neonContent = [NeonAccessoryContent new];
		neonAttachTouchHandler(_neonContent);
		self.alpha = 0;
		self.userInteractionEnabled = NO;
	}
	return self;
}

- (BOOL)canBecomeFirstResponder {
	return YES;
}

- (UIView *)inputAccessoryView {
	return self.neonContent;
}

- (void)addSubview:(UIView *)view {
	[self.neonContent neonAdd:view];
}

// RN RCTInputAccessoryView.mm:44 reactSetFrame, and :73 didSetProps: an accessory with no
// nativeID is not for an input; it takes first responder status once it has its size.
- (void)setBounds:(CGRect)bounds {
	[super setBounds:bounds];
	[self.neonContent neonSetSize:bounds.size];
	if (self.neonID == nil && !self.neonClaimed && bounds.size.height > 0) {
		self.neonClaimed = YES;
		dispatch_async(dispatch_get_main_queue(), ^{ if (self.window) [self becomeFirstResponder]; });
	}
}

- (void)neonSetProp:(const char *)name value:(const char *)text {
	if (strcmp(name, "nativeID") == 0) {
		NSString *old = self.neonID;
		if (old && [accessories() objectForKey:old] == self) [accessories() removeObjectForKey:old];
		self.neonID = text[0] ? [NSString stringWithUTF8String:text] : nil;
		if (self.neonID) [accessories() setObject:self forKey:self.neonID];
		if (old) refreshAccessoryInputs(old);
		if (self.neonID) refreshAccessoryInputs(self.neonID);
	} else if (strcmp(name, "backgroundColor") == 0) {
		self.neonContent.backgroundColor = text[0] ? neonCssColor(text, nil) : nil;
	}
}

- (void)neonRelease {
	NSString *key = self.neonID;
	if (key && [accessories() objectForKey:key] == self) [accessories() removeObjectForKey:key];
	if (self.isFirstResponder) [self resignFirstResponder];
	if (key) refreshAccessoryInputs(key);
}

@end

void *niInputAccessoryViewCreate(void) {
	neonApplyInputAccessory = applyAccessory;
	return CFBridgingRetain([[NeonInputAccessoryView alloc] initWithFrame:CGRectZero]);
}
