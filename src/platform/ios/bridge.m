#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <Foundation/Foundation.h>
#include "runtime/promise/dispatch.h"
#include "../native/bridge.h"
#include "../native/loop.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static msClosure s_mount;
static msClosure s_touch;
static msClosure s_resize;
static msClosure s_scroll;
static msClosure s_teardown;
static msClosure s_loop;
static int g_scrollPhase = 0;
static int g_lastTag = 0;
static int g_scrollTag = 0;
static float g_scrollX = 0, g_scrollY = 0, g_scrollW = 0, g_scrollH = 0, g_scrollContentW = 0, g_scrollContentH = 0;
static int g_lastPhase = 0;
static float g_touchX = 0, g_touchY = 0;
static double g_touchTime = 0;
static __weak UIView *g_responderView = nil;
static UIView *g_container = nil;
static float g_measuredW = 0;
static float g_measuredH = 0;
static CFRunLoopTimerRef g_loopTimer = NULL;
static msClosure s_control;
static msClosure s_environment;
static int g_controlTag = 0, g_controlPhase = 0;
static char *g_controlValue = NULL;
static float g_controlW = 0, g_controlH = 0;
static float g_keyboardH = 0;
static int g_dark = 0;

static void loopArm(int ms) {
	if (!g_loopTimer) return;
	CFAbsoluteTime at = ms < 0 ? [[NSDate distantFuture] timeIntervalSinceReferenceDate] : CFAbsoluteTimeGetCurrent() + ms / 1000.0;
	CFRunLoopTimerSetNextFireDate(g_loopTimer, at);
}

static void invoke(msClosure c) {
	if (c.env) ((void (*)(void *))c.fn)(c.env);
	else ((void (*)(void))c.fn)();
}

static void loopPump(CFRunLoopTimerRef timer, void *info) {
	(void)timer;
	(void)info;
	if (s_loop.fn) invoke(s_loop);
	else niLoopRun();
	loopArm(niLoopNext());
}

static void loopStart(void) {
	(void)msGetDispatcher();
	CFTimeInterval never = [[NSDate distantFuture] timeIntervalSinceReferenceDate];
	g_loopTimer = CFRunLoopTimerCreate(kCFAllocatorDefault, never, never, 0, 0, loopPump, NULL);
	CFRunLoopAddTimer(CFRunLoopGetMain(), g_loopTimer, kCFRunLoopCommonModes);
}

static void call0(msClosure c) {
	if (!c.fn) return;
	invoke(c);
	loopArm(0);
}

// Touch-forwarding view: every phase of a touch fires the one handler, with
// the tag + phase readable via niLastTouchTag/Phase.
@interface NeonTouchView : UIView
@property (nonatomic) BOOL neonHandlesPress;
@property (nonatomic) BOOL neonAccessibleSet;
@end

@implementation NeonTouchView

- (void)neonReport:(NSSet<UITouch *> *)touches phase:(int)phase {
	UITouch *touch = touches.anyObject;
	CGPoint at = [touch locationInView:nil];
	g_lastTag = (int)self.tag;
	g_lastPhase = phase;
	g_touchX = (float)at.x;
	g_touchY = (float)at.y;
	g_touchTime = touch.timestamp * 1000.0;
	call0(s_touch);
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
	[self neonReport:touches phase:0];
	[super touchesBegan:touches withEvent:event];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
	[self neonReport:touches phase:4];
	[super touchesMoved:touches withEvent:event];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
	[self neonReport:touches phase:1];
	g_lastPhase = 2; // the press itself, after the up
	call0(s_touch);
	[super touchesEnded:touches withEvent:event];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
	[self neonReport:touches phase:3];
	[super touchesCancelled:touches withEvent:event];
}

// RN RCTViewComponentView: an accessible view without its own label speaks the
// labels of its subviews, joined with ", " (RCTRecursiveAccessibilityLabel).
static NSString *recursiveAccessibilityLabel(UIView *view) {
	NSMutableString *result = nil;
	for (UIView *subview in view.subviews) {
		if (subview.hidden) continue;
		NSString *label = subview.accessibilityLabel;
		if (!label) label = recursiveAccessibilityLabel(subview);
		if (label.length == 0) continue;
		if (!result) result = [NSMutableString string];
		if (result.length > 0) [result appendString:@", "];
		[result appendString:label];
	}
	return result;
}

- (NSString *)accessibilityLabel {
	NSString *label = super.accessibilityLabel;
	if (label) return label;
	if (self.isAccessibilityElement) return recursiveAccessibilityLabel(self);
	return nil;
}

@end

// RN Text: a label whose text or span has onPress takes touches; a touch on a pressable
// span reports with the span's tag, so the span's press fires and the label's bubbles.
@interface NeonLabel : UILabel
@property (nonatomic, copy) NSArray<NSValue *> *neonSpanRanges;
@property (nonatomic, copy) NSArray<NSNumber *> *neonSpanTags;
@property (nonatomic) int neonTouchTag;
@end

@implementation NeonLabel

- (int)neonTagAt:(CGPoint)point {
	if (self.neonSpanTags.count == 0 || self.attributedText.length == 0) return (int)self.tag;
	NSTextStorage *storage = [[NSTextStorage alloc] initWithAttributedString:self.attributedText];
	NSLayoutManager *layout = [[NSLayoutManager alloc] init];
	NSTextContainer *container = [[NSTextContainer alloc] initWithSize:self.bounds.size];
	container.lineFragmentPadding = 0;
	container.maximumNumberOfLines = (NSUInteger)self.numberOfLines;
	container.lineBreakMode = self.lineBreakMode;
	[layout addTextContainer:container];
	[storage addLayoutManager:layout];
	CGRect used = [layout usedRectForTextContainer:container];
	CGPoint at = CGPointMake(point.x, point.y - MAX(0, (self.bounds.size.height - used.size.height) / 2));
	NSUInteger glyph = [layout glyphIndexForPoint:at inTextContainer:container];
	CGRect box = [layout boundingRectForGlyphRange:NSMakeRange(glyph, 1) inTextContainer:container];
	if (!CGRectContainsPoint(CGRectInset(box, -4, -4), at)) return (int)self.tag;
	NSUInteger index = [layout characterIndexForGlyphAtIndex:glyph];
	for (NSUInteger i = 0; i < self.neonSpanTags.count; i++) {
		if (NSLocationInRange(index, self.neonSpanRanges[i].rangeValue)) return self.neonSpanTags[i].intValue;
	}
	return (int)self.tag;
}

- (void)neonReport:(NSSet<UITouch *> *)touches phase:(int)phase {
	UITouch *touch = touches.anyObject;
	CGPoint at = [touch locationInView:nil];
	g_lastTag = self.neonTouchTag;
	g_lastPhase = phase;
	g_touchX = (float)at.x;
	g_touchY = (float)at.y;
	g_touchTime = touch.timestamp * 1000.0;
	call0(s_touch);
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
	self.neonTouchTag = [self neonTagAt:[touches.anyObject locationInView:self]];
	[self neonReport:touches phase:0];
	[super touchesBegan:touches withEvent:event];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
	[self neonReport:touches phase:4];
	[super touchesMoved:touches withEvent:event];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
	[self neonReport:touches phase:1];
	g_lastPhase = 2;
	call0(s_touch);
	[super touchesEnded:touches withEvent:event];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
	[self neonReport:touches phase:3];
	[super touchesCancelled:touches withEvent:event];
}

@end

static void emitControl(int tag, int phase, NSString *value, float width, float height) {
	if (tag == 0) return;
	free(g_controlValue);
	g_controlValue = strdup(value ? value.UTF8String : "");
	g_controlTag = tag;
	g_controlPhase = phase;
	g_controlW = width;
	g_controlH = height;
	call0(s_control);
}

static void publishEnvironment(float keyboard, int dark) {
	if (keyboard == g_keyboardH && dark == g_dark) return;
	g_keyboardH = keyboard;
	g_dark = dark;
	call0(s_environment);
}

// A Modal's layer: VoiceOver stays inside it, and its escape gesture asks the
// app to close it (control phase 7, RN's onRequestClose).
@interface NeonModalView : NeonTouchView
@property (nonatomic, copy) NSString *neonAnimation;
@end

@implementation NeonModalView

- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self) self.accessibilityViewIsModal = YES;
	return self;
}

- (BOOL)accessibilityPerformEscape {
	emitControl((int)self.tag, 7, @"", 0, 0);
	return YES;
}

- (void)didMoveToWindow {
	[super didMoveToWindow];
	if (!self.window) return;
	if ([self.neonAnimation isEqualToString:@"fade"]) {
		self.alpha = 0;
		[UIView animateWithDuration:0.3 animations:^{ self.alpha = 1; }];
	} else if ([self.neonAnimation isEqualToString:@"slide"]) {
		CGFloat height = self.window.bounds.size.height;
		self.transform = CGAffineTransformMakeTranslation(0, height);
		[UIView animateWithDuration:0.3 animations:^{ self.transform = CGAffineTransformIdentity; }];
	}
	UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, self);
}

@end

@interface NeonInput : UITextField <UITextFieldDelegate>
@property (nonatomic) BOOL neonWriting;
@property (nonatomic) BOOL neonBlurOnSubmit;
@property (nonatomic) BOOL neonAutoFocus;
@property (nonatomic) NSInteger neonMaxLength;
@property (nonatomic) UIEdgeInsets neonInsets;
@end

@implementation NeonInput

- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		self.delegate = self;
		self.neonBlurOnSubmit = YES;
		self.neonMaxLength = -1;
		self.textColor = [UIColor whiteColor];
		self.font = [UIFont systemFontOfSize:17];
		[self addTarget:self action:@selector(neonChanged) forControlEvents:UIControlEventEditingChanged];
	}
	return self;
}

- (CGRect)textRectForBounds:(CGRect)bounds { return UIEdgeInsetsInsetRect([super textRectForBounds:bounds], self.neonInsets); }
- (CGRect)editingRectForBounds:(CGRect)bounds { return UIEdgeInsetsInsetRect([super editingRectForBounds:bounds], self.neonInsets); }
- (CGRect)placeholderRectForBounds:(CGRect)bounds { return UIEdgeInsetsInsetRect([super placeholderRectForBounds:bounds], self.neonInsets); }

- (CGSize)sizeThatFits:(CGSize)size {
	CGSize fit = [super sizeThatFits:size];
	return CGSizeMake(fit.width + self.neonInsets.left + self.neonInsets.right, fit.height + self.neonInsets.top + self.neonInsets.bottom);
}

- (void)neonChanged {
	if (!self.neonWriting) emitControl((int)self.tag, 0, self.text, 0, 0);
}

- (void)didMoveToWindow {
	[super didMoveToWindow];
	if (self.window && self.neonAutoFocus) dispatch_async(dispatch_get_main_queue(), ^{ [self becomeFirstResponder]; });
}

- (void)textFieldDidBeginEditing:(UITextField *)field { emitControl((int)self.tag, 1, self.text, 0, 0); }
- (void)textFieldDidEndEditing:(UITextField *)field { emitControl((int)self.tag, 2, self.text, 0, 0); }

- (BOOL)textFieldShouldReturn:(UITextField *)field {
	emitControl((int)self.tag, 3, self.text, 0, 0);
	if (self.neonBlurOnSubmit) [self resignFirstResponder];
	return NO;
}

- (BOOL)textField:(UITextField *)field shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
	if (self.neonMaxLength < 0) return YES;
	return (NSInteger)(field.text.length - range.length + string.length) <= self.neonMaxLength;
}

@end

@interface NeonSwitch : UISwitch
@property (nonatomic) BOOL neonValue;
@end

@implementation NeonSwitch
- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self) [self addTarget:self action:@selector(neonChanged) forControlEvents:UIControlEventValueChanged];
	return self;
}
- (void)neonChanged {
	emitControl((int)self.tag, 4, self.isOn ? @"true" : @"false", 0, 0);
	if (self.isOn != self.neonValue) [self setOn:self.neonValue animated:YES];
}
@end

@interface NeonIndicator : UIActivityIndicatorView
@property (nonatomic) BOOL neonAnimating;
@end

@implementation NeonIndicator
- (void)neonApply {
	if (self.neonAnimating) [self startAnimating];
	else [self stopAnimating];
}
@end

@interface NeonImage : UIImageView
@property (nonatomic, copy) NSString *neonUri;
@end

@implementation NeonImage

+ (NSCache *)neonCache {
	static NSCache *cache;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ cache = [[NSCache alloc] init]; });
	return cache;
}

- (void)neonLoad:(NSString *)uri {
	if ([uri isEqualToString:self.neonUri ?: @""]) return;
	self.neonUri = uri;
	self.image = nil;
	if (uri.length == 0) return;
	UIImage *cached = [NeonImage.neonCache objectForKey:uri];
	if (cached) {
		self.image = cached;
		dispatch_async(dispatch_get_main_queue(), ^{
			if ([self.neonUri isEqualToString:uri]) emitControl((int)self.tag, 5, @"", (float)cached.size.width, (float)cached.size.height);
		});
		return;
	}
	NSURL *url = [NSURL URLWithString:uri];
	if (!url) { emitControl((int)self.tag, 6, @"malformed URI", 0, 0); return; }
	__weak NeonImage *weakSelf = self;
	[[NSURLSession.sharedSession dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
		UIImage *image = data ? [UIImage imageWithData:data] : nil;
		NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 200;
		NSString *failure = error ? error.localizedDescription : (status < 200 || status >= 300) ? [NSString stringWithFormat:@"HTTP %ld", (long)status] : image ? nil : @"cannot decode image";
		dispatch_async(dispatch_get_main_queue(), ^{
			NeonImage *view = weakSelf;
			if (!view || ![view.neonUri isEqualToString:uri]) return;
			if (failure) { emitControl((int)view.tag, 6, failure, 0, 0); return; }
			[NeonImage.neonCache setObject:image forKey:uri];
			view.image = image;
			emitControl((int)view.tag, 5, @"", (float)image.size.width, (float)image.size.height);
		});
	}] resume];
}
@end

static NSString *neonText(const char *text) { return [NSString stringWithUTF8String:text ? text : ""]; }

static UIColor *cssColor(const char *css, UIColor *fallback) {
	if (!css || css[0] != '#') return fallback;
	char hex[7];
	size_t n = strlen(css + 1);
	if (n == 3) {
		for (int i = 0; i < 3; i++) hex[2 * i] = hex[2 * i + 1] = css[1 + i];
	} else if (n == 6) memcpy(hex, css + 1, 6);
	else return fallback;
	hex[6] = '\0';
	char *end = NULL;
	unsigned long rgb = strtoul(hex, &end, 16);
	if (end != hex + 6) return fallback;
	return [UIColor colorWithRed:((rgb >> 16) & 0xff) / 255.0 green:((rgb >> 8) & 0xff) / 255.0 blue:(rgb & 0xff) / 255.0 alpha:1];
}

// textSpans: records split by 0x1e, fields by 0x1f: text, colour, size, bold, italic,
// underline, line-through, press tag.
static void setLabelSpans(NeonLabel *label, const char *text) {
	NSMutableAttributedString *out = [[NSMutableAttributedString alloc] init];
	NSMutableArray<NSValue *> *ranges = [NSMutableArray array];
	NSMutableArray<NSNumber *> *tags = [NSMutableArray array];
	NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
	paragraph.alignment = label.textAlignment;
	for (NSString *record in [neonText(text) componentsSeparatedByString:@"\x1e"]) {
		NSArray<NSString *> *f = [record componentsSeparatedByString:@"\x1f"];
		if (f.count < 8) continue;
		CGFloat size = f[2].doubleValue > 0 ? f[2].doubleValue : 17;
		UIFontDescriptorSymbolicTraits traits = 0;
		if ([f[3] isEqualToString:@"1"]) traits |= UIFontDescriptorTraitBold;
		if ([f[4] isEqualToString:@"1"]) traits |= UIFontDescriptorTraitItalic;
		UIFont *font = [UIFont systemFontOfSize:size];
		if (traits) {
			UIFontDescriptor *styled = [font.fontDescriptor fontDescriptorWithSymbolicTraits:traits];
			if (styled) font = [UIFont fontWithDescriptor:styled size:size];
		}
		NSMutableDictionary<NSAttributedStringKey, id> *attributes = [NSMutableDictionary dictionary];
		attributes[NSFontAttributeName] = font;
		attributes[NSParagraphStyleAttributeName] = paragraph;
		attributes[NSForegroundColorAttributeName] = cssColor(f[1].UTF8String, label.textColor);
		if ([f[5] isEqualToString:@"1"]) attributes[NSUnderlineStyleAttributeName] = @(NSUnderlineStyleSingle);
		if ([f[6] isEqualToString:@"1"]) attributes[NSStrikethroughStyleAttributeName] = @(NSUnderlineStyleSingle);
		NSRange range = NSMakeRange(out.length, f[0].length);
		[out appendAttributedString:[[NSAttributedString alloc] initWithString:f[0] attributes:attributes]];
		if (f[7].intValue != 0) {
			[ranges addObject:[NSValue valueWithRange:range]];
			[tags addObject:@(f[7].intValue)];
		}
	}
	label.attributedText = out;
	label.neonSpanRanges = ranges;
	label.neonSpanTags = tags;
}

static UIAccessibilityTraits roleTraits(const char *role) {
	if (strcmp(role, "button") == 0) return UIAccessibilityTraitButton;
	if (strcmp(role, "link") == 0) return UIAccessibilityTraitLink;
	if (strcmp(role, "header") == 0) return UIAccessibilityTraitHeader;
	if (strcmp(role, "image") == 0) return UIAccessibilityTraitImage;
	if (strcmp(role, "search") == 0) return UIAccessibilityTraitSearchField;
	if (strcmp(role, "adjustable") == 0) return UIAccessibilityTraitAdjustable;
	if (strcmp(role, "text") == 0 || strcmp(role, "summary") == 0) return UIAccessibilityTraitStaticText;
	if (strcmp(role, "progressbar") == 0) return UIAccessibilityTraitUpdatesFrequently;
	if (strcmp(role, "checkbox") == 0 || strcmp(role, "radio") == 0 || strcmp(role, "tab") == 0 || strcmp(role, "togglebutton") == 0 ||
		strcmp(role, "combobox") == 0 || strcmp(role, "menuitem") == 0) return UIAccessibilityTraitButton;
	return UIAccessibilityTraitNone;
}

static char kNeonRoleTraits;
static char kNeonStateTraits;
static char kNeonGroup;

static BOOL groupRole(const char *role) {
	return strcmp(role, "tablist") == 0 || strcmp(role, "radiogroup") == 0 || strcmp(role, "menu") == 0 || strcmp(role, "alert") == 0;
}

static BOOL isGroup(UIView *v) { return [objc_getAssociatedObject(v, &kNeonGroup) boolValue]; }

static void applyTraits(UIView *v) {
	NSNumber *role = objc_getAssociatedObject(v, &kNeonRoleTraits);
	NSNumber *state = objc_getAssociatedObject(v, &kNeonStateTraits);
	v.accessibilityTraits = (UIAccessibilityTraits)(role.unsignedLongLongValue | state.unsignedLongLongValue);
}

static BOOL hasToken(NSArray<NSString *> *tokens, NSString *token) { return [tokens containsObject:token]; }

static void setAccessibilityState(UIView *v, const char *text) {
	NSArray<NSString *> *tokens = text[0] ? [neonText(text) componentsSeparatedByString:@","] : @[];
	UIAccessibilityTraits traits = UIAccessibilityTraitNone;
	if (hasToken(tokens, @"selected")) traits |= UIAccessibilityTraitSelected;
	if (hasToken(tokens, @"disabled")) traits |= UIAccessibilityTraitNotEnabled;
	objc_setAssociatedObject(v, &kNeonStateTraits, @(traits), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	v.accessibilityValue = hasToken(tokens, @"checked") ? @"checked" : hasToken(tokens, @"unchecked") ? @"unchecked" :
		hasToken(tokens, @"mixed") ? @"mixed" : hasToken(tokens, @"expanded") ? @"expanded" : hasToken(tokens, @"collapsed") ? @"collapsed" : nil;
	applyTraits(v);
}

static UIKeyboardType keyboardType(const char *value) {
	if (strcmp(value, "numeric") == 0 || strcmp(value, "number-pad") == 0) return UIKeyboardTypeNumberPad;
	if (strcmp(value, "decimal-pad") == 0) return UIKeyboardTypeDecimalPad;
	if (strcmp(value, "phone-pad") == 0) return UIKeyboardTypePhonePad;
	if (strcmp(value, "email-address") == 0) return UIKeyboardTypeEmailAddress;
	if (strcmp(value, "url") == 0) return UIKeyboardTypeURL;
	return UIKeyboardTypeDefault;
}

static UIReturnKeyType returnKeyType(const char *value) {
	if (strcmp(value, "go") == 0) return UIReturnKeyGo;
	if (strcmp(value, "next") == 0) return UIReturnKeyNext;
	if (strcmp(value, "search") == 0) return UIReturnKeySearch;
	if (strcmp(value, "send") == 0) return UIReturnKeySend;
	return UIReturnKeyDone;
}

static void setInputProp(NeonInput *input, const char *name, const char *value) {
	BOOL yes = strcmp(value, "true") == 0;
	BOOL defaultYes = value[0] == '\0' || yes;
	NSString *text = [NSString stringWithUTF8String:value];
	if (strcmp(name, "value") == 0) {
		if (![input.text isEqualToString:text]) { input.neonWriting = YES; input.text = text; input.neonWriting = NO; }
	} else if (strcmp(name, "defaultValue") == 0) {
		if (input.text.length == 0) input.text = text;
	} else if (strcmp(name, "placeholder") == 0) input.placeholder = text;
	else if (strcmp(name, "placeholderTextColor") == 0) {
		input.attributedPlaceholder = [[NSAttributedString alloc] initWithString:input.placeholder ?: @"" attributes:@{ NSForegroundColorAttributeName: cssColor(value, UIColor.placeholderTextColor) }];
	} else if (strcmp(name, "editable") == 0) input.enabled = defaultYes;
	else if (strcmp(name, "secureTextEntry") == 0) input.secureTextEntry = yes;
	else if (strcmp(name, "keyboardType") == 0) input.keyboardType = keyboardType(value);
	else if (strcmp(name, "returnKeyType") == 0) input.returnKeyType = returnKeyType(value);
	else if (strcmp(name, "autoCorrect") == 0) input.autocorrectionType = value[0] == '\0' ? UITextAutocorrectionTypeDefault : yes ? UITextAutocorrectionTypeYes : UITextAutocorrectionTypeNo;
	else if (strcmp(name, "autoCapitalize") == 0) {
		input.autocapitalizationType = strcmp(value, "none") == 0 ? UITextAutocapitalizationTypeNone :
			strcmp(value, "words") == 0 ? UITextAutocapitalizationTypeWords :
			strcmp(value, "characters") == 0 ? UITextAutocapitalizationTypeAllCharacters : UITextAutocapitalizationTypeSentences;
	} else if (strcmp(name, "blurOnSubmit") == 0) input.neonBlurOnSubmit = defaultYes;
	else if (strcmp(name, "autoFocus") == 0) {
		input.neonAutoFocus = yes;
		if (yes && input.window) [input becomeFirstResponder];
	} else if (strcmp(name, "textInsets") == 0) {
		float left = 0, top = 0, right = 0, bottom = 0;
		if (sscanf(value, "%f,%f,%f,%f", &left, &top, &right, &bottom) == 4) {
			input.neonInsets = UIEdgeInsetsMake(top, left, bottom, right);
			[input setNeedsLayout];
		}
	} else if (strcmp(name, "maxLength") == 0) input.neonMaxLength = value[0] == '\0' ? -1 : atoi(value);
}

// RN's multiline TextInput (RCTMultilineTextInputView): a UITextView with a
// placeholder label, the same control phases as the single-line field.
@interface NeonTextArea : UITextView <UITextViewDelegate>
@property (nonatomic) BOOL neonWriting;
@property (nonatomic) BOOL neonBlurOnSubmit;
@property (nonatomic) NSInteger neonMaxLength;
@property (nonatomic, strong) UILabel *neonPlaceholder;
@end

@implementation NeonTextArea

- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame textContainer:nil];
	if (self) {
		self.delegate = self;
		self.neonMaxLength = -1;
		self.backgroundColor = [UIColor clearColor];
		self.textColor = [UIColor whiteColor];
		self.font = [UIFont systemFontOfSize:17];
		self.textContainer.lineFragmentPadding = 0;
		self.textContainerInset = UIEdgeInsetsZero;
		_neonPlaceholder = [[UILabel alloc] initWithFrame:CGRectZero];
		_neonPlaceholder.textColor = UIColor.placeholderTextColor;
		_neonPlaceholder.numberOfLines = 0;
		[self addSubview:_neonPlaceholder];
	}
	return self;
}

- (void)layoutSubviews {
	[super layoutSubviews];
	UIEdgeInsets inset = self.textContainerInset;
	CGFloat width = MAX(0, self.bounds.size.width - inset.left - inset.right);
	CGSize fit = [self.neonPlaceholder sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)];
	self.neonPlaceholder.frame = CGRectMake(inset.left, inset.top, width, fit.height);
	self.neonPlaceholder.font = self.font;
	self.neonPlaceholder.hidden = self.text.length > 0;
}

- (void)neonSetText:(NSString *)text {
	if ([self.text isEqualToString:text]) return;
	self.neonWriting = YES;
	self.text = text;
	self.neonWriting = NO;
	[self setNeedsLayout];
}

- (void)textViewDidChange:(UITextView *)view {
	[self setNeedsLayout];
	if (!self.neonWriting) emitControl((int)self.tag, 0, self.text, 0, 0);
}

- (void)textViewDidBeginEditing:(UITextView *)view { emitControl((int)self.tag, 1, self.text, 0, 0); }
- (void)textViewDidEndEditing:(UITextView *)view { emitControl((int)self.tag, 2, self.text, 0, 0); }

- (BOOL)textView:(UITextView *)view shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text {
	if (self.neonBlurOnSubmit && [text isEqualToString:@"\n"]) {
		emitControl((int)self.tag, 3, self.text, 0, 0);
		[self resignFirstResponder];
		return NO;
	}
	if (self.neonMaxLength < 0) return YES;
	return (NSInteger)(view.text.length - range.length + text.length) <= self.neonMaxLength;
}

@end

static void setTextAreaProp(NeonTextArea *area, const char *name, const char *value) {
	BOOL yes = strcmp(value, "true") == 0;
	BOOL defaultYes = value[0] == '\0' || yes;
	NSString *text = [NSString stringWithUTF8String:value];
	if (strcmp(name, "value") == 0) [area neonSetText:text];
	else if (strcmp(name, "defaultValue") == 0) { if (area.text.length == 0) [area neonSetText:text]; }
	else if (strcmp(name, "placeholder") == 0) { area.neonPlaceholder.text = text; [area setNeedsLayout]; }
	else if (strcmp(name, "placeholderTextColor") == 0) area.neonPlaceholder.textColor = cssColor(value, UIColor.placeholderTextColor);
	else if (strcmp(name, "editable") == 0) area.editable = defaultYes;
	else if (strcmp(name, "secureTextEntry") == 0) area.secureTextEntry = yes;
	else if (strcmp(name, "keyboardType") == 0) area.keyboardType = keyboardType(value);
	else if (strcmp(name, "returnKeyType") == 0) area.returnKeyType = value[0] ? returnKeyType(value) : UIReturnKeyDefault;
	else if (strcmp(name, "autoCorrect") == 0) area.autocorrectionType = value[0] == '\0' ? UITextAutocorrectionTypeDefault : yes ? UITextAutocorrectionTypeYes : UITextAutocorrectionTypeNo;
	else if (strcmp(name, "autoCapitalize") == 0) {
		area.autocapitalizationType = strcmp(value, "none") == 0 ? UITextAutocapitalizationTypeNone :
			strcmp(value, "words") == 0 ? UITextAutocapitalizationTypeWords :
			strcmp(value, "characters") == 0 ? UITextAutocapitalizationTypeAllCharacters : UITextAutocapitalizationTypeSentences;
	} else if (strcmp(name, "blurOnSubmit") == 0) area.neonBlurOnSubmit = yes;
	else if (strcmp(name, "autoFocus") == 0) { if (yes) dispatch_async(dispatch_get_main_queue(), ^{ [area becomeFirstResponder]; }); }
	else if (strcmp(name, "textInsets") == 0) {
		float left = 0, top = 0, right = 0, bottom = 0;
		if (sscanf(value, "%f,%f,%f,%f", &left, &top, &right, &bottom) == 4) {
			area.textContainerInset = UIEdgeInsetsMake(top, left, bottom, right);
			[area setNeedsLayout];
		}
	} else if (strcmp(name, "maxLength") == 0) area.neonMaxLength = value[0] == '\0' ? -1 : atoi(value);
}

static UIView *focusedInput(UIView *view) {
	if (view.isFirstResponder && ([view isKindOfClass:UITextField.class] || [view isKindOfClass:UITextView.class])) return view;
	for (UIView *child in view.subviews) {
		UIView *focused = focusedInput(child);
		if (focused) return focused;
	}
	return nil;
}

@interface NeonScrollView : UIScrollView <UIScrollViewDelegate, UIGestureRecognizerDelegate>
@property (nonatomic) NSInteger neonPersistTaps;
@property (nonatomic, strong) UITapGestureRecognizer *neonKeyboardTap;
@property (nonatomic) BOOL neonRefreshingDesired;
@property (nonatomic, strong) UIColor *neonRefreshTint;
@property (nonatomic, copy) NSString *neonRefreshTitle;
- (void)neonSetContentSize:(CGSize)size;
- (void)neonEmit:(int)phase;
- (void)neonSetRefreshing:(BOOL)refreshing;
- (void)neonRefresh:(UIRefreshControl *)control;
@end

@implementation NeonScrollView {
	BOOL _isUserTriggeredScrolling;
	BOOL _isSetContentOffsetDisabled;
	BOOL _keyboardVisible;
	BOOL _refreshingProgrammatically;
}

- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		self.delegate = self;
		self.delaysContentTouches = NO;
		self.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
		self.alwaysBounceVertical = YES;
		_neonKeyboardTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(neonDismissKeyboard:)];
		_neonKeyboardTap.delegate = self;
		[self addGestureRecognizer:_neonKeyboardTap];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(neonKeyboardFrame:) name:UIKeyboardWillChangeFrameNotification object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(neonKeyboardHidden:) name:UIKeyboardWillHideNotification object:nil];
	}
	return self;
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
- (void)neonKeyboardFrame:(NSNotification *)notification {
	CGRect frame = [notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
	CGRect screen = self.window ? self.window.screen.bounds : UIScreen.mainScreen.bounds;
	_keyboardVisible = CGRectIntersectsRect(screen, frame) && CGRectGetHeight(CGRectIntersection(screen, frame)) > 0;
}
- (void)neonKeyboardHidden:(NSNotification *)notification { _keyboardVisible = NO; }

- (void)layoutSubviews {
	[super layoutSubviews];
	if (_neonRefreshingDesired && !_refreshingProgrammatically && self.window && self.refreshControl && !self.refreshControl.isRefreshing) {
		_refreshingProgrammatically = YES;
		[self.refreshControl sizeToFit];
		CGFloat height = self.refreshControl.bounds.size.height;
		[self setContentOffset:CGPointMake(self.contentOffset.x, self.contentOffset.y - height) animated:NO];
		[self.refreshControl beginRefreshing];
	}
}

- (void)neonSetRefreshing:(BOOL)refreshing {
	self.neonRefreshingDesired = refreshing;
	if (refreshing) { [self setNeedsLayout]; return; }
	if (_refreshingProgrammatically && self.contentOffset.y < -self.contentInset.top) {
		[self setContentOffset:CGPointMake(self.contentOffset.x, -self.contentInset.top) animated:NO];
	}
	_refreshingProgrammatically = NO;
	[self.refreshControl endRefreshing];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldReceiveTouch:(UITouch *)touch {
	if (recognizer != _neonKeyboardTap) return YES;
	if (_neonPersistTaps == 1 || !_keyboardVisible || !focusedInput(self.window)) return NO;
	BOOL handled = NO;
	for (UIView *target = touch.view; target && target != self; target = target.superview) {
		if ([target isKindOfClass:UITextField.class] || [target isKindOfClass:UITextView.class]) return NO;
		if ([target isKindOfClass:UIControl.class] || ([target isKindOfClass:NeonTouchView.class] && ((NeonTouchView *)target).neonHandlesPress)) handled = YES;
	}
	return _neonPersistTaps == 0 || !handled;
}

// RN RCTScrollView _shouldDisableScrollInteraction: a blocking responder inside keeps the
// touch. The pan recognizer begins before the content view sees this move, so report it first.
- (BOOL)touchesShouldCancelInContentView:(UIView *)view {
	UIView *tagged = view;
	while (tagged && tagged != self && !([tagged isKindOfClass:NeonTouchView.class] && tagged.tag != 0)) tagged = tagged.superview;
	if (tagged && tagged != self) {
		CGPoint at = [self.panGestureRecognizer locationInView:nil];
		g_lastTag = (int)tagged.tag;
		g_lastPhase = 4;
		g_touchX = (float)at.x;
		g_touchY = (float)at.y;
		g_touchTime = g_touchTime + 0.5;
		call0(s_touch);
	}
	UIView *holder = g_responderView;
	if (holder && [holder isDescendantOfView:self]) return NO;
	return [super touchesShouldCancelInContentView:view];
}

- (void)neonDismissKeyboard:(UITapGestureRecognizer *)recognizer {
	if (recognizer.state == UIGestureRecognizerStateEnded) [self.window endEditing:YES];
}

// RN Fabric preserves the actual user offset during content-size and frame writes.
- (void)setContentOffset:(CGPoint)contentOffset {
	if (!_isSetContentOffsetDisabled) [super setContentOffset:contentOffset];
}

- (void)setFrame:(CGRect)frame {
	BOOL previous = _isSetContentOffsetDisabled;
	_isSetContentOffsetDisabled = _isUserTriggeredScrolling;
	[super setFrame:frame];
	_isSetContentOffsetDisabled = previous;
}

- (void)neonSetContentSize:(CGSize)size {
	if (CGSizeEqualToSize(self.contentSize, size)) return;
	BOOL previous = _isSetContentOffsetDisabled;
	_isSetContentOffsetDisabled = _isUserTriggeredScrolling;
	self.contentSize = size;
	_isSetContentOffsetDisabled = previous;
}

- (void)neonEmit:(int)phase {
	if (self.tag == 0) return;
	g_scrollTag = (int)self.tag;
	g_scrollPhase = phase;
	g_scrollX = (float)self.contentOffset.x;
	g_scrollY = (float)self.contentOffset.y;
	g_scrollW = (float)self.bounds.size.width;
	g_scrollH = (float)self.bounds.size.height;
	g_scrollContentW = (float)self.contentSize.width;
	g_scrollContentH = (float)self.contentSize.height;
	call0(s_scroll);
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
	_isUserTriggeredScrolling = YES;
	[self neonEmit:1];
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
	[self neonEmit:2];
	if (decelerate) [self neonEmit:3];
	else _isUserTriggeredScrolling = NO;
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
	_isUserTriggeredScrolling = NO;
	[self neonEmit:4];
}

- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView {
	[self neonEmit:4];
}

- (BOOL)scrollViewShouldScrollToTop:(UIScrollView *)scrollView {
	_isUserTriggeredScrolling = YES;
	return YES;
}

- (void)scrollViewDidScrollToTop:(UIScrollView *)scrollView {
	_isUserTriggeredScrolling = NO;
}

- (void)didMoveToWindow {
	[super didMoveToWindow];
	if (!self.window) _isUserTriggeredScrolling = NO;
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView { [self neonEmit:0]; }
- (void)neonRefresh:(UIRefreshControl *)control {
	[self neonEmit:5];
	if (!self.neonRefreshingDesired) [control endRefreshing];
}
@end

@interface NeonVC : UIViewController
@end

static NeonVC *g_vc = nil;
static UIStatusBarStyle g_statusBarStyle = UIStatusBarStyleDefault;
static BOOL g_statusBarHidden = NO;

// RN StatusBar on iOS: bar style and visibility through the view controller;
// iOS has no status bar background, so that prop does nothing here.
static BOOL g_edgeToEdge = NO;

// The container fills the safe area; a translucent StatusBar takes it to the window's edges,
// where RN iOS always draws, and SafeAreaView pads by what niSafeAreaInset reports.
static CGRect containerFrame(UIView *root) {
	return g_edgeToEdge ? root.bounds : root.safeAreaLayoutGuide.layoutFrame;
}

static void setStatusBar(const char *name, const char *value) {
	if (strcmp(name, "statusBarTranslucent") == 0) {
		g_edgeToEdge = strcmp(value, "true") == 0;
		if (g_vc && g_container) g_container.frame = containerFrame(g_vc.view);
		return;
	}
	if (strcmp(name, "statusBarStyle") == 0) {
		g_statusBarStyle = strcmp(value, "light-content") == 0 ? UIStatusBarStyleLightContent :
			strcmp(value, "dark-content") == 0 ? UIStatusBarStyleDarkContent : UIStatusBarStyleDefault;
	} else if (strcmp(name, "statusBarHidden") == 0) g_statusBarHidden = strcmp(value, "true") == 0;
	else return;
	[g_vc setNeedsStatusBarAppearanceUpdate];
}

@implementation NeonVC

- (UIStatusBarStyle)preferredStatusBarStyle { return g_statusBarStyle; }
- (BOOL)prefersStatusBarHidden { return g_statusBarHidden; }

- (void)viewDidLoad {
	[super viewDidLoad];
	g_vc = self;
	g_dark = self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? 1 : 0;
	if (@available(iOS 17.0, *)) {
		[self registerForTraitChanges:@[UITraitUserInterfaceStyle.class] withHandler:^(__kindof id<UITraitEnvironment> env, UITraitCollection *previous) {
			publishEnvironment(g_keyboardH, env.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? 1 : 0);
		}];
	}
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(neonKeyboard:) name:UIKeyboardWillChangeFrameNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(neonKeyboardHide:) name:UIKeyboardWillHideNotification object:nil];
	self.view.backgroundColor = [UIColor blackColor];
	g_container = [[UIView alloc] initWithFrame:containerFrame(self.view)];
	g_container.userInteractionEnabled = YES;
	[self.view addSubview:g_container];
	call0(s_mount);
}

- (void)neonKeyboard:(NSNotification *)notification {
	CGRect frame = [notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
	CGRect screen = self.view.window ? self.view.window.screen.bounds : UIScreen.mainScreen.bounds;
	CGFloat height = CGRectGetHeight(CGRectIntersection(screen, frame));
	CGFloat bottomInset = self.view.safeAreaInsets.bottom;
	publishEnvironment((float)MAX(0, height - bottomInset), g_dark);
}

- (void)neonKeyboardHide:(NSNotification *)notification { publishEnvironment(0, g_dark); }

- (void)traitCollectionDidChange:(UITraitCollection *)previous {
	[super traitCollectionDidChange:previous];
	publishEnvironment(g_keyboardH, self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? 1 : 0);
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	static CGRect lastSafe;
	CGRect frame = containerFrame(self.view);
	CGRect safe = self.view.safeAreaLayoutGuide.layoutFrame;
	if (CGRectEqualToRect(g_container.frame, frame) && CGRectEqualToRect(lastSafe, safe)) return;
	g_container.frame = frame;
	lastSafe = safe;
	call0(s_resize);
}

@end

@interface NeonAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation NeonAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
	self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
	self.window.rootViewController = [[NeonVC alloc] init];
	[self.window makeKeyAndVisible];
	return YES;
}

- (void)applicationWillTerminate:(UIApplication *)application { call0(s_teardown); }
@end

void niRegisterApp(msClosure mount) {
	s_mount = mount;
}

void niSetResizeHandler(msClosure handler) {
	s_resize = handler;
}

int niRunApp(void) {
	loopStart();
	@autoreleasepool {
		return UIApplicationMain(0, nil, nil, NSStringFromClass([NeonAppDelegate class]));
	}
}

void *niContainerView(void) {
	return (__bridge void *)g_container;
}

float niScreenWidth(void) {
	return (float)g_container.bounds.size.width;
}

float niScreenHeight(void) {
	return (float)g_container.bounds.size.height;
}

float niSafeAreaInset(int edge) {
	if (!g_vc || !g_container) return 0;
	CGRect safe = g_vc.view.safeAreaLayoutGuide.layoutFrame;
	CGRect c = g_container.frame;
	CGFloat inset = edge == 0 ? CGRectGetMinY(safe) - CGRectGetMinY(c)
		: edge == 1 ? CGRectGetMaxX(c) - CGRectGetMaxX(safe)
		: edge == 2 ? CGRectGetMaxY(c) - CGRectGetMaxY(safe)
		: CGRectGetMinX(safe) - CGRectGetMinX(c);
	return (float)MAX(0, inset);
}

// --- views ---

void *niViewCreate(void) {
	return CFBridgingRetain([[NeonTouchView alloc] initWithFrame:CGRectZero]);
}

void *niTextCreate(void) {
	NeonLabel *label = [[NeonLabel alloc] initWithFrame:CGRectZero];
	label.textColor = [UIColor whiteColor];
	label.font = [UIFont systemFontOfSize:17];
	label.backgroundColor = [UIColor clearColor];
	label.numberOfLines = 0;
	return CFBridgingRetain(label);
}

void niAddChild(void *parent, void *child) {
	UIView *p = (__bridge UIView *)parent;
	UIView *c = (__bridge UIView *)child;
	[p addSubview:c];
}

void niBringChildToFront(void *child) {
	UIView *c = (__bridge UIView *)child;
	[c.superview bringSubviewToFront:c];
}


void niViewSetTag(void *view, int32_t tag) {
	UIView *v = (__bridge UIView *)view;
	v.tag = tag;
}

// --- controls created by name (niControlCreate) ---

@interface NeonSlider : UISlider
@property (nonatomic) float neonStep;
@end

@implementation NeonSlider
- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		self.minimumValue = 0;
		self.maximumValue = 1;
		[self addTarget:self action:@selector(neonChanged) forControlEvents:UIControlEventValueChanged];
		[self addTarget:self action:@selector(neonDone) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
	}
	return self;
}
- (CGSize)sizeThatFits:(CGSize)size { (void)size; return CGSizeMake(0, 31); }
- (float)neonSnapped {
	float v = self.value;
	if (self.neonStep > 0) v = self.minimumValue + roundf((v - self.minimumValue) / self.neonStep) * self.neonStep;
	return v;
}
- (void)neonChanged {
	float v = [self neonSnapped];
	if (v != self.value) self.value = v;
	emitControl((int)self.tag, 4, [NSString stringWithFormat:@"%g", v], 0, 0);
}
- (void)neonDone { emitControl((int)self.tag, 8, [NSString stringWithFormat:@"%g", [self neonSnapped]], 0, 0); }
@end

@interface NeonPicker : UIButton
@property (nonatomic, copy) NSArray<NSString *> *neonLabels;
@property (nonatomic) NSInteger neonSelected;
@property (nonatomic, copy) NSString *neonPrompt;
@end

@implementation NeonPicker
+ (instancetype)neonPicker {
	NeonPicker *p = [NeonPicker buttonWithType:UIButtonTypeSystem];
	UIButtonConfiguration *c = [UIButtonConfiguration grayButtonConfiguration];
	c.image = [UIImage systemImageNamed:@"chevron.up.chevron.down"];
	c.imagePlacement = NSDirectionalRectEdgeTrailing;
	c.imagePadding = 6;
	p.configuration = c;
	p.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
	p.showsMenuAsPrimaryAction = YES;
	p.neonLabels = @[];
	p.neonSelected = -1;
	return p;
}
- (CGSize)sizeThatFits:(CGSize)size { (void)size; return CGSizeMake(0, 44); }
- (NSString *)accessibilityValue {
	return self.neonSelected >= 0 && self.neonSelected < (NSInteger)self.neonLabels.count ? self.neonLabels[self.neonSelected] : nil;
}
- (void)neonRebuild {
	NSMutableArray<UIMenuElement *> *actions = [NSMutableArray array];
	__weak NeonPicker *weakSelf = self;
	for (NSUInteger i = 0; i < self.neonLabels.count; i++) {
		UIAction *a = [UIAction actionWithTitle:self.neonLabels[i] image:nil identifier:nil handler:^(UIAction *action) {
			(void)action;
			NeonPicker *me = weakSelf;
			if (!me) return;
			emitControl((int)me.tag, 4, [NSString stringWithFormat:@"%lu", (unsigned long)i], 0, 0);
			[me neonRebuild];
		}];
		a.state = (NSInteger)i == self.neonSelected ? UIMenuElementStateOn : UIMenuElementStateOff;
		[actions addObject:a];
	}
	self.menu = [UIMenu menuWithTitle:self.neonPrompt ?: @"" children:actions];
	UIButtonConfiguration *c = self.configuration;
	c.title = [self accessibilityValue] ?: @"";
	self.configuration = c;
}
@end

@interface NeonDatePicker : UIDatePicker
@property (nonatomic, copy) NSString *neonMode;
@end

@implementation NeonDatePicker
- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		self.neonMode = @"date";
		self.datePickerMode = UIDatePickerModeDate;
		self.preferredDatePickerStyle = UIDatePickerStyleCompact;
		self.locale = [NSLocale currentLocale];
		[self addTarget:self action:@selector(neonChanged) forControlEvents:UIControlEventValueChanged];
	}
	return self;
}
- (NSDateFormatter *)neonFormatter {
	NSDateFormatter *f = [[NSDateFormatter alloc] init];
	f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
	f.dateFormat = [self.neonMode isEqualToString:@"time"] ? @"HH:mm" : [self.neonMode isEqualToString:@"datetime"] ? @"yyyy-MM-dd'T'HH:mm" : @"yyyy-MM-dd";
	return f;
}
- (NSDate *)neonParse:(const char *)text {
	if (!text || !text[0]) return nil;
	return [[self neonFormatter] dateFromString:neonText(text)];
}
- (CGSize)sizeThatFits:(CGSize)size {
	CGSize fit = [self systemLayoutSizeFittingSize:UILayoutFittingCompressedSize];
	if (fit.width <= 0 || fit.width >= size.width || fit.height <= 0) {
		CGFloat width = [self.neonMode isEqualToString:@"time"] ? 96 : [self.neonMode isEqualToString:@"datetime"] ? 230 : 136;
		fit = CGSizeMake(width, 35);
	}
	return CGSizeMake(MIN(fit.width, size.width), fit.height);
}
- (void)neonChanged { emitControl((int)self.tag, 4, [[self neonFormatter] stringFromDate:self.date], 0, 0); }
- (void)neonSetProp:(const char *)name value:(const char *)text {
	if (strcmp(name, "mode") == 0) {
		self.neonMode = neonText(text);
		self.datePickerMode = strcmp(text, "time") == 0 ? UIDatePickerModeTime : strcmp(text, "datetime") == 0 ? UIDatePickerModeDateAndTime : UIDatePickerModeDate;
	} else if (strcmp(name, "display") == 0) {
		self.preferredDatePickerStyle = strcmp(text, "inline") == 0 ? UIDatePickerStyleInline : strcmp(text, "spinner") == 0 ? UIDatePickerStyleWheels : UIDatePickerStyleCompact;
	} else if (strcmp(name, "value") == 0) {
		NSDate *d = [self neonParse:text];
		if (d && ![d isEqualToDate:self.date]) [self setDate:d animated:NO];
	} else if (strcmp(name, "minimumDate") == 0) self.minimumDate = [self neonParse:text];
	else if (strcmp(name, "maximumDate") == 0) self.maximumDate = [self neonParse:text];
	else if (strcmp(name, "disabled") == 0) self.enabled = strcmp(text, "true") != 0;
	else if (strcmp(name, "accentColor") == 0) self.tintColor = text[0] ? cssColor(text, nil) : nil;
}
@end

static void setSliderProp(NeonSlider *s, const char *name, const char *text) {
	if (strcmp(name, "minimumValue") == 0) s.minimumValue = (float)atof(text);
	else if (strcmp(name, "maximumValue") == 0) s.maximumValue = (float)atof(text);
	else if (strcmp(name, "step") == 0) s.neonStep = (float)atof(text);
	else if (strcmp(name, "value") == 0) { if (!s.isTracking) [s setValue:(float)atof(text) animated:NO]; }
	else if (strcmp(name, "disabled") == 0) s.enabled = strcmp(text, "true") != 0;
	else if (strcmp(name, "inverted") == 0) s.transform = strcmp(text, "true") == 0 ? CGAffineTransformMakeScale(-1, 1) : CGAffineTransformIdentity;
	else if (strcmp(name, "minimumTrackTintColor") == 0) s.minimumTrackTintColor = text[0] ? cssColor(text, nil) : nil;
	else if (strcmp(name, "maximumTrackTintColor") == 0) s.maximumTrackTintColor = text[0] ? cssColor(text, nil) : nil;
	else if (strcmp(name, "thumbTintColor") == 0) s.thumbTintColor = text[0] ? cssColor(text, nil) : nil;
}

static void setPickerProp(NeonPicker *p, const char *name, const char *text) {
	if (strcmp(name, "items") == 0) {
		NSMutableArray<NSString *> *labels = [NSMutableArray array];
		if (text[0]) {
			for (NSString *record in [neonText(text) componentsSeparatedByString:@"\x1e"]) {
				[labels addObject:[record componentsSeparatedByString:@"\x1f"].firstObject ?: @""];
			}
		}
		p.neonLabels = labels;
		[p neonRebuild];
	} else if (strcmp(name, "selectedIndex") == 0) {
		p.neonSelected = atoi(text);
		[p neonRebuild];
	} else if (strcmp(name, "prompt") == 0) {
		p.neonPrompt = text[0] ? neonText(text) : nil;
		[p neonRebuild];
	} else if (strcmp(name, "disabled") == 0) p.enabled = strcmp(text, "true") != 0;
	else if (strcmp(name, "color") == 0) p.tintColor = text[0] ? cssColor(text, nil) : nil;
}

void *niControlCreate(const char *kind) {
	if (strcmp(kind, "slider") == 0) return CFBridgingRetain([[NeonSlider alloc] initWithFrame:CGRectZero]);
	if (strcmp(kind, "picker") == 0) return CFBridgingRetain([NeonPicker neonPicker]);
	if (strcmp(kind, "datetimepicker") == 0) return CFBridgingRetain([[NeonDatePicker alloc] initWithFrame:CGRectZero]);
	fprintf(stderr, "neon: niControlCreate has no control \"%s\"\n", kind);
	abort();
}

void *niInputCreate(void) {
	return CFBridgingRetain([[NeonInput alloc] initWithFrame:CGRectZero]);
}

void *niSwitchCreate(void) {
	return CFBridgingRetain([[NeonSwitch alloc] initWithFrame:CGRectZero]);
}

void *niIndicatorCreate(void) {
	NeonIndicator *indicator = [[NeonIndicator alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
	indicator.hidesWhenStopped = YES;
	indicator.neonAnimating = YES;
	[indicator neonApply];
	return CFBridgingRetain(indicator);
}

void *niImageCreate(void) {
	NeonImage *image = [[NeonImage alloc] initWithFrame:CGRectZero];
	image.contentMode = UIViewContentModeScaleAspectFill;
	image.clipsToBounds = YES;
	return CFBridgingRetain(image);
}

void *niTextAreaCreate(void) {
	return CFBridgingRetain([[NeonTextArea alloc] initWithFrame:CGRectZero]);
}

void *niModalCreate(void) {
	return CFBridgingRetain([[NeonModalView alloc] initWithFrame:CGRectZero]);
}

void niControlSetTag(void *control, int32_t tag) {
	UIView *v = (__bridge UIView *)control;
	v.tag = tag;
}

void niSetProp(void *view, const char *name, const char *value) {
	UIView *v = (__bridge UIView *)view;
	const char *text = value ? value : "";
	if (strncmp(name, "statusBar", 9) == 0) { setStatusBar(name, text); return; }
	if (strcmp(name, "accessibilityLabel") == 0) {
		v.accessibilityLabel = text[0] ? [NSString stringWithUTF8String:text] : nil;
		if ([v isKindOfClass:NeonTouchView.class] && !((NeonTouchView *)v).neonAccessibleSet && !isGroup(v)) v.isAccessibilityElement = text[0] != '\0';
	}
	else if (strcmp(name, "accessibilityHint") == 0) v.accessibilityHint = text[0] ? [NSString stringWithUTF8String:text] : nil;
	else if (strcmp(name, "accessible") == 0) {
		v.isAccessibilityElement = strcmp(text, "true") == 0;
		if ([v isKindOfClass:NeonTouchView.class]) ((NeonTouchView *)v).neonAccessibleSet = text[0] != '\0';
	}
	else if (strcmp(name, "accessibilityRole") == 0) {
		objc_setAssociatedObject(v, &kNeonRoleTraits, @(roleTraits(text)), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		applyTraits(v);
		BOOL group = groupRole(text);
		objc_setAssociatedObject(v, &kNeonGroup, @(group), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		if (group) {
			v.accessibilityContainerType = UIAccessibilityContainerTypeSemanticGroup;
			if ([v isKindOfClass:NeonTouchView.class] && !((NeonTouchView *)v).neonAccessibleSet) v.isAccessibilityElement = NO;
		}
	}
	else if (strcmp(name, "accessibilityState") == 0) setAccessibilityState(v, text);
	else if (strcmp(name, "overflow") == 0) v.clipsToBounds = strcmp(text, "hidden") == 0;
	else if (strcmp(name, "textAlign") == 0 && [v respondsToSelector:@selector(setTextAlignment:)]) {
		NSTextAlignment alignment = strcmp(text, "left") == 0 ? NSTextAlignmentLeft :
			strcmp(text, "center") == 0 ? NSTextAlignmentCenter :
			strcmp(text, "right") == 0 ? NSTextAlignmentRight :
			strcmp(text, "justify") == 0 ? NSTextAlignmentJustified : NSTextAlignmentNatural;
		[(id)v setTextAlignment:alignment];
	}
	else if ([v isKindOfClass:UILabel.class]) {
		UILabel *label = (UILabel *)v;
		if (strcmp(name, "textSpans") == 0 && [v isKindOfClass:NeonLabel.class]) setLabelSpans((NeonLabel *)v, text);
		else if (strcmp(name, "numberOfLines") == 0) label.numberOfLines = text[0] ? atoi(text) : 0;
		else if (strcmp(name, "ellipsizeMode") == 0) {
			label.lineBreakMode = strcmp(text, "head") == 0 ? NSLineBreakByTruncatingHead :
				strcmp(text, "middle") == 0 ? NSLineBreakByTruncatingMiddle :
				strcmp(text, "clip") == 0 ? NSLineBreakByClipping : NSLineBreakByTruncatingTail;
		}
	}
	else if ([v isKindOfClass:NeonModalView.class]) {
		if (strcmp(name, "animationType") == 0) ((NeonModalView *)v).neonAnimation = [NSString stringWithUTF8String:text];
	}
	else if ([v isKindOfClass:NeonInput.class]) setInputProp((NeonInput *)v, name, text);
	else if ([v isKindOfClass:NeonTextArea.class]) setTextAreaProp((NeonTextArea *)v, name, text);
	else if ([v isKindOfClass:NeonSwitch.class]) {
		NeonSwitch *s = (NeonSwitch *)v;
		if (strcmp(name, "value") == 0) { s.neonValue = strcmp(text, "true") == 0; if (s.isOn != s.neonValue) [s setOn:s.neonValue animated:YES]; }
		else if (strcmp(name, "disabled") == 0) s.enabled = strcmp(text, "true") != 0;
		else if (strcmp(name, "thumbColor") == 0) s.thumbTintColor = text[0] ? cssColor(text, nil) : nil;
		else if (strcmp(name, "trackColorOn") == 0) s.onTintColor = text[0] ? cssColor(text, nil) : nil;
		else if (strcmp(name, "trackColorOff") == 0) { s.backgroundColor = text[0] ? cssColor(text, nil) : nil; s.layer.cornerRadius = 15.5; }
	} else if ([v isKindOfClass:NeonIndicator.class]) {
		NeonIndicator *i = (NeonIndicator *)v;
		if (strcmp(name, "animating") == 0) { i.neonAnimating = strcmp(text, "false") != 0; [i neonApply]; }
		else if (strcmp(name, "hidesWhenStopped") == 0) i.hidesWhenStopped = strcmp(text, "false") != 0;
		else if (strcmp(name, "color") == 0) i.color = text[0] ? cssColor(text, UIColor.grayColor) : UIColor.grayColor;
	} else if ([v isKindOfClass:NeonSlider.class]) setSliderProp((NeonSlider *)v, name, text);
	else if ([v isKindOfClass:NeonPicker.class]) setPickerProp((NeonPicker *)v, name, text);
	else if ([v isKindOfClass:NeonDatePicker.class]) [(NeonDatePicker *)v neonSetProp:name value:text];
	else if ([v isKindOfClass:NeonImage.class]) {
		NeonImage *image = (NeonImage *)v;
		if (strcmp(name, "source") == 0) [image neonLoad:[NSString stringWithUTF8String:text]];
		else if (strcmp(name, "resizeMode") == 0) {
			image.contentMode = strcmp(text, "contain") == 0 ? UIViewContentModeScaleAspectFit :
				strcmp(text, "stretch") == 0 ? UIViewContentModeScaleToFill :
				strcmp(text, "center") == 0 ? UIViewContentModeCenter : UIViewContentModeScaleAspectFill;
		}
	}
}

void niSetFocused(void *control, int focused) {
	UIView *v = (__bridge UIView *)control;
	if (focused) [v becomeFirstResponder];
	else [v resignFirstResponder];
}

void niSetControlHandler(msClosure handler) { s_control = handler; }
int niLastControlTag(void) { return g_controlTag; }
int niLastControlPhase(void) { return g_controlPhase; }
const char *niLastControlValue(void) { return g_controlValue ? g_controlValue : ""; }
float niLastControlWidth(void) { return g_controlW; }
float niLastControlHeight(void) { return g_controlH; }
void niSetEnvironmentHandler(msClosure handler) { s_environment = handler; }
float niKeyboardHeight(void) { return g_keyboardH; }
int niColorScheme(void) { return g_dark; }

void niViewSetPressable(void *view) {
	UIView *v = (__bridge UIView *)view;
	if ([v isKindOfClass:NeonLabel.class]) v.userInteractionEnabled = YES;
	if (![v isKindOfClass:NeonTouchView.class]) return;
	NeonTouchView *touch = (NeonTouchView *)v;
	touch.neonHandlesPress = YES;
}
void niRemoveFromParent(void *child) {
	UIView *c = (__bridge UIView *)child;
	[c removeFromSuperview];
}

void niViewRelease(void *view) {
	if (view) {
		UIView *v = (__bridge UIView *)view;
		if ([v isKindOfClass:NeonScrollView.class]) { ((NeonScrollView *)v).delegate = nil; v.tag = 0; }
		CFRelease((CFTypeRef)view);
	}
}

void niSetFrame(void *view, float x, float y, float w, float h) {
	UIView *v = (__bridge UIView *)view;
	// Set bounds and centre: UIKit leaves frame undefined under non-identity transforms.
	// Preserve bounds.origin; UIScrollView stores its contentOffset there.
	CGRect bounds = v.bounds;
	bounds.size = CGSizeMake(w, h);
	v.bounds = bounds;
	v.center = CGPointMake(x + w * 0.5f, y + h * 0.5f);
}

static const void *kNeonRotationKey = &kNeonRotationKey;
static const void *kNeonAffineKey = &kNeonAffineKey;

static void neonApplyTransform(UIView *v) {
	NSArray<NSNumber *> *affine = objc_getAssociatedObject(v, kNeonAffineKey);
	NSNumber *rotation = objc_getAssociatedObject(v, kNeonRotationKey);
	CGFloat sx = affine ? affine[0].doubleValue : 1, sy = affine ? affine[1].doubleValue : 1;
	CGFloat tx = affine ? affine[2].doubleValue : 0, ty = affine ? affine[3].doubleValue : 0;
	CGAffineTransform t = CGAffineTransformMakeTranslation(tx, ty);
	t = CGAffineTransformRotate(t, (rotation ? rotation.doubleValue : 0) * M_PI / 180.0);
	v.transform = CGAffineTransformScale(t, sx, sy);
}

void niSetTransform(void *view, float scaleX, float scaleY, float translateX, float translateY) {
	UIView *v = (__bridge UIView *)view;
	objc_setAssociatedObject(v, kNeonAffineKey, @[@(scaleX), @(scaleY), @(translateX), @(translateY)], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	neonApplyTransform(v);
}

void niSetRotation(void *view, float degrees) {
	UIView *v = (__bridge UIView *)view;
	objc_setAssociatedObject(v, kNeonRotationKey, @(degrees), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	neonApplyTransform(v);
}

void *niScrollCreate(void) {
	return CFBridgingRetain([[NeonScrollView alloc] initWithFrame:CGRectZero]);
}

void niScrollSetTag(void *scroll, int32_t tag) {
	UIScrollView *s = (__bridge UIScrollView *)scroll;
	s.tag = tag;
}

void niScrollSetContentSize(void *scroll, float w, float h) {
	NeonScrollView *s = (__bridge NeonScrollView *)scroll;
	[s neonSetContentSize:CGSizeMake(w, h)];
}

void niScrollSetOption(void *scroll, const char *name, const char *value) {
	NeonScrollView *s = (__bridge NeonScrollView *)scroll;
	BOOL yes = strcmp(value, "true") == 0;
	BOOL defaultYes = value[0] == '\0' || yes;
	if (strcmp(name, "horizontal") == 0) {
		s.alwaysBounceHorizontal = yes;
		s.alwaysBounceVertical = !yes;
	} else if (strcmp(name, "scrollEnabled") == 0) s.scrollEnabled = defaultYes;
	else if (strcmp(name, "showsHorizontalScrollIndicator") == 0) s.showsHorizontalScrollIndicator = defaultYes;
	else if (strcmp(name, "showsVerticalScrollIndicator") == 0) s.showsVerticalScrollIndicator = defaultYes;
	else if (strcmp(name, "pagingEnabled") == 0) s.pagingEnabled = yes;
	else if (strcmp(name, "keyboardDismissMode") == 0) {
		s.keyboardDismissMode = strcmp(value, "interactive") == 0 ? UIScrollViewKeyboardDismissModeInteractive :
			strcmp(value, "on-drag") == 0 ? UIScrollViewKeyboardDismissModeOnDrag : UIScrollViewKeyboardDismissModeNone;
	} else if (strcmp(name, "keyboardShouldPersistTaps") == 0) {
		s.neonPersistTaps = strcmp(value, "always") == 0 ? 1 : strcmp(value, "handled") == 0 ? 2 : 0;
	} else if (strcmp(name, "refreshTintColor") == 0) {
		s.neonRefreshTint = value[0] ? cssColor(value, nil) : nil;
		s.refreshControl.tintColor = s.neonRefreshTint;
	} else if (strcmp(name, "refreshTitle") == 0) {
		s.neonRefreshTitle = value[0] ? [NSString stringWithUTF8String:value] : nil;
		s.refreshControl.attributedTitle = s.neonRefreshTitle ? [[NSAttributedString alloc] initWithString:s.neonRefreshTitle] : nil;
	} else if (strcmp(name, "refreshEnabled") == 0) {
		if (yes && !s.refreshControl) {
			UIRefreshControl *control = [[UIRefreshControl alloc] init];
			[control addTarget:s action:@selector(neonRefresh:) forControlEvents:UIControlEventValueChanged];
			control.tintColor = s.neonRefreshTint;
			if (s.neonRefreshTitle) control.attributedTitle = [[NSAttributedString alloc] initWithString:s.neonRefreshTitle];
			s.refreshControl = control;
		} else if (!yes) s.refreshControl = nil;
	} else if (strcmp(name, "refreshing") == 0) {
		if (!s.refreshControl && yes) {
			s.refreshControl = [[UIRefreshControl alloc] init];
			[s.refreshControl addTarget:s action:@selector(neonRefresh:) forControlEvents:UIControlEventValueChanged];
		}
		[s neonSetRefreshing:yes];
	}
}

void niScrollTo(void *scroll, float x, float y, int animated) {
	NeonScrollView *s = (__bridge NeonScrollView *)scroll;
	CGFloat maxX = MAX(0, s.contentSize.width - s.bounds.size.width);
	CGFloat maxY = MAX(0, s.contentSize.height - s.bounds.size.height);
	CGPoint to = CGPointMake(MIN(MAX(0, x), maxX), MIN(MAX(0, y), maxY));
	if (animated && !CGPointEqualToPoint(s.contentOffset, to)) [s neonEmit:3];
	[s setContentOffset:to animated:animated != 0];
}

void niScrollShift(void *scroll, float dx, float dy) {
	NeonScrollView *s = (__bridge NeonScrollView *)scroll;
	s.contentOffset = CGPointMake(s.contentOffset.x + dx, s.contentOffset.y + dy);
}

float niScrollOffsetX(void *scroll) {
	return (float)((__bridge UIScrollView *)scroll).contentOffset.x;
}

float niScrollOffsetY(void *scroll) {
	return (float)((__bridge UIScrollView *)scroll).contentOffset.y;
}

void niSetBackgroundColor(void *view, float r, float g, float b, float a) {
	UIView *v = (__bridge UIView *)view;
	v.backgroundColor = [UIColor colorWithRed:r green:g blue:b alpha:a];
}

void niSetCornerRadius(void *view, float radius) {
	UIView *v = (__bridge UIView *)view;
	v.layer.cornerRadius = radius;
	v.layer.masksToBounds = radius > 0;
}

void niSetOpacity(void *view, float opacity) {
	UIView *v = (__bridge UIView *)view;
	v.alpha = opacity;
}

// --- text ---

void niSetText(void *label, const char *s) {
	UILabel *l = (__bridge UILabel *)label;
	l.text = [NSString stringWithUTF8String:s ? s : ""];
	if ([l isKindOfClass:NeonLabel.class]) {
		((NeonLabel *)l).neonSpanRanges = @[];
		((NeonLabel *)l).neonSpanTags = @[];
	}
}

void niSetTextColor(void *label, float r, float g, float b, float a) {
	UILabel *l = (__bridge UILabel *)label;
	l.textColor = [UIColor colorWithRed:r green:g blue:b alpha:a];
}

void niSetFont(void *label, float size, int bold) {
	UILabel *l = (__bridge UILabel *)label;
	l.font = bold ? [UIFont boldSystemFontOfSize:size] : [UIFont systemFontOfSize:size];
}

void niMeasureText(void *label, float maxWidth) {
	UILabel *l = (__bridge UILabel *)label;
	CGSize fit = [l sizeThatFits:CGSizeMake(maxWidth, CGFLOAT_MAX)];
	g_measuredW = (float)ceil(fit.width);
	g_measuredH = (float)ceil(fit.height);
}

float niMeasuredW(void) { return g_measuredW; }
float niMeasuredH(void) { return g_measuredH; }

// --- events ---

void niSetTouchHandler(msClosure handler) {
	s_touch = handler;
}

int niLastTouchTag(void) { return g_lastTag; }
int niLastTouchPhase(void) { return g_lastPhase; }
float niLastTouchX(void) { return g_touchX; }
float niLastTouchY(void) { return g_touchY; }
double niLastTouchTime(void) { return g_touchTime; }

void niSetResponder(void *view, int blockNativeResponder) {
	g_responderView = blockNativeResponder ? (__bridge UIView *)view : nil;
}

void niClearResponder(void) { g_responderView = nil; }

void niSetScrollHandler(msClosure handler) {
	s_scroll = handler;
}

int niLastScrollTag(void) { return g_scrollTag; }
int niLastScrollPhase(void) { return g_scrollPhase; }
float niLastScrollX(void) { return g_scrollX; }
float niLastScrollY(void) { return g_scrollY; }
float niLastScrollWidth(void) { return g_scrollW; }
float niLastScrollHeight(void) { return g_scrollH; }
float niLastScrollContentWidth(void) { return g_scrollContentW; }
float niLastScrollContentHeight(void) { return g_scrollContentH; }

void niSetTeardownHandler(msClosure handler) {
	s_teardown = handler;
}

void niSetLoopHandler(msClosure handler) {
	s_loop = handler;
}

void niInvokeClosure(msClosure c) { call0(c); }
static msClosure s_frame;

@interface NeonFrameTarget : NSObject
@end

@implementation NeonFrameTarget
- (void)tick:(CADisplayLink *)link {
	link.paused = YES;
	call0(s_frame);
}
@end

static CADisplayLink *g_frameLink;
static NeonFrameTarget *g_frameTarget;

void niSetFrameHandler(msClosure handler) { s_frame = handler; }

int niRequestFrame(void) {
	if (!g_frameLink) {
		g_frameTarget = [NeonFrameTarget new];
		g_frameLink = [CADisplayLink displayLinkWithTarget:g_frameTarget selector:@selector(tick:)];
		g_frameLink.paused = YES;
		[g_frameLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
	}
	g_frameLink.paused = NO;
	return 1;
}
