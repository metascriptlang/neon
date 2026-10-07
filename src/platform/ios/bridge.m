#import <UIKit/UIKit.h>
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

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
	g_lastTag = (int)self.tag;
	g_lastPhase = 0;
	call0(s_touch);
	[super touchesBegan:touches withEvent:event];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
	g_lastTag = (int)self.tag;
	g_lastPhase = 1;
	call0(s_touch);
	g_lastPhase = 2; // the press itself, after the up
	call0(s_touch);
	[super touchesEnded:touches withEvent:event];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
	g_lastTag = (int)self.tag;
	g_lastPhase = 3;
	call0(s_touch);
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

static UIAccessibilityTraits roleTraits(const char *role) {
	if (strcmp(role, "button") == 0) return UIAccessibilityTraitButton;
	if (strcmp(role, "link") == 0) return UIAccessibilityTraitLink;
	if (strcmp(role, "header") == 0) return UIAccessibilityTraitHeader;
	if (strcmp(role, "image") == 0) return UIAccessibilityTraitImage;
	if (strcmp(role, "search") == 0) return UIAccessibilityTraitSearchField;
	if (strcmp(role, "adjustable") == 0) return UIAccessibilityTraitAdjustable;
	if (strcmp(role, "text") == 0 || strcmp(role, "summary") == 0) return UIAccessibilityTraitStaticText;
	if (strcmp(role, "progressbar") == 0) return UIAccessibilityTraitUpdatesFrequently;
	return UIAccessibilityTraitNone;
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

@implementation NeonVC

- (void)viewDidLoad {
	[super viewDidLoad];
	g_dark = self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? 1 : 0;
	if (@available(iOS 17.0, *)) {
		[self registerForTraitChanges:@[UITraitUserInterfaceStyle.class] withHandler:^(__kindof id<UITraitEnvironment> env, UITraitCollection *previous) {
			publishEnvironment(g_keyboardH, env.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? 1 : 0);
		}];
	}
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(neonKeyboard:) name:UIKeyboardWillChangeFrameNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(neonKeyboardHide:) name:UIKeyboardWillHideNotification object:nil];
	self.view.backgroundColor = [UIColor blackColor];
	g_container = [[UIView alloc] initWithFrame:self.view.safeAreaLayoutGuide.layoutFrame];
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
	CGRect frame = self.view.safeAreaLayoutGuide.layoutFrame;
	if (CGRectEqualToRect(g_container.frame, frame)) return;
	g_container.frame = frame;
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

// --- views ---

void *niViewCreate(void) {
	return CFBridgingRetain([[NeonTouchView alloc] initWithFrame:CGRectZero]);
}

void *niTextCreate(void) {
	UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
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

void niControlSetTag(void *control, int32_t tag) {
	UIView *v = (__bridge UIView *)control;
	v.tag = tag;
}

void niSetProp(void *view, const char *name, const char *value) {
	UIView *v = (__bridge UIView *)view;
	const char *text = value ? value : "";
	if (strcmp(name, "accessibilityLabel") == 0) {
		v.accessibilityLabel = text[0] ? [NSString stringWithUTF8String:text] : nil;
		if ([v isKindOfClass:NeonTouchView.class] && !((NeonTouchView *)v).neonAccessibleSet) v.isAccessibilityElement = text[0] != '\0';
	}
	else if (strcmp(name, "accessibilityHint") == 0) v.accessibilityHint = text[0] ? [NSString stringWithUTF8String:text] : nil;
	else if (strcmp(name, "accessible") == 0) {
		v.isAccessibilityElement = strcmp(text, "true") == 0;
		if ([v isKindOfClass:NeonTouchView.class]) ((NeonTouchView *)v).neonAccessibleSet = text[0] != '\0';
	}
	else if (strcmp(name, "accessibilityRole") == 0) v.accessibilityTraits = roleTraits(text);
	else if ([v isKindOfClass:NeonInput.class]) setInputProp((NeonInput *)v, name, text);
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
	} else if ([v isKindOfClass:NeonImage.class]) {
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

void niSetTransform(void *view, float scaleX, float scaleY, float translateX, float translateY) {
	UIView *v = (__bridge UIView *)view;
	v.transform = CGAffineTransformMake(scaleX, 0, 0, scaleY, translateX, translateY);
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
	} else if (strcmp(name, "refreshEnabled") == 0) {
		if (yes && !s.refreshControl) {
			UIRefreshControl *control = [[UIRefreshControl alloc] init];
			[control addTarget:s action:@selector(neonRefresh:) forControlEvents:UIControlEventValueChanged];
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
