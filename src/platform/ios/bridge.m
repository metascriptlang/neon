#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#include "../native/bridge.h"
#include <string.h>

static msClosure s_mount;
static msClosure s_touch;
static msClosure s_resize;
static msClosure s_scroll;
static msClosure s_teardown;
static int g_scrollPhase = 0;
static int g_lastTag = 0;
static int g_scrollTag = 0;
static float g_scrollX = 0, g_scrollY = 0, g_scrollW = 0, g_scrollH = 0, g_scrollContentW = 0, g_scrollContentH = 0;
static int g_lastPhase = 0;
static UIView *g_container = nil;
static float g_measuredW = 0;
static float g_measuredH = 0;

static void call0(msClosure c) {
	if (!c.fn) return;
	if (c.env) ((void (*)(void *))c.fn)(c.env);
	else ((void (*)(void))c.fn)();
}

// Touch-forwarding view: every phase of a touch fires the one handler, with
// the tag + phase readable via niLastTouchTag/Phase.
@interface NeonTouchView : UIView
@property (nonatomic) BOOL neonHandlesPress;
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
	self.view.backgroundColor = [UIColor blackColor];
	g_container = [[UIView alloc] initWithFrame:self.view.safeAreaLayoutGuide.layoutFrame];
	g_container.userInteractionEnabled = YES;
	[self.view addSubview:g_container];
	call0(s_mount);
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
	return CFBridgingRetain(label);
}

void niAddChild(void *parent, void *child) {
	UIView *p = (__bridge UIView *)parent;
	UIView *c = (__bridge UIView *)child;
	[p addSubview:c];
}


void niViewSetTag(void *view, int32_t tag) {
	UIView *v = (__bridge UIView *)view;
	v.tag = tag;
}

void niViewSetPressable(void *view) {
	UIView *v = (__bridge UIView *)view;
	if ([v isKindOfClass:NeonTouchView.class]) ((NeonTouchView *)v).neonHandlesPress = YES;
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
	v.frame = CGRectMake(x, y, w, h);
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
