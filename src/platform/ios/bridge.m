#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#include "../native/bridge.h"

static msClosure s_mount;
static msClosure s_touch;
static msClosure s_resize;
static msClosure s_scroll;
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

@interface NeonScrollView : UIScrollView <UIScrollViewDelegate>
- (void)neonSetContentSize:(CGSize)size;
@end

@implementation NeonScrollView {
	BOOL _isUserTriggeredScrolling;
	BOOL _isSetContentOffsetDisabled;
}

- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		self.delegate = self;
		self.delaysContentTouches = NO;
		self.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
		// React Native's vertical ScrollView default (ScrollView.js: alwaysBounceVertical = !horizontal).
		self.alwaysBounceVertical = YES;
	}
	return self;
}

// React Native keeps a drag's offset while the content size changes under it
// (RCTScrollViewComponentView.mm _preserveContentOffsetIfNeededWithBlock, RCTEnhancedScrollView.mm).
- (void)setContentOffset:(CGPoint)contentOffset {
	if (_isSetContentOffsetDisabled) return;
	[super setContentOffset:contentOffset];
}

- (void)neonSetContentSize:(CGSize)size {
	if (!_isUserTriggeredScrolling) {
		self.contentSize = size;
		return;
	}
	_isSetContentOffsetDisabled = YES;
	self.contentSize = size;
	_isSetContentOffsetDisabled = NO;
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
	_isUserTriggeredScrolling = YES;
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
	if (!decelerate) _isUserTriggeredScrolling = NO;
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
	_isUserTriggeredScrolling = NO;
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
	if (!self.window && (self.isDecelerating || !self.isTracking)) _isUserTriggeredScrolling = NO;
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
	if (self.tag == 0) return;
	g_scrollTag = (int)self.tag;
	g_scrollX = (float)scrollView.contentOffset.x;
	g_scrollY = (float)scrollView.contentOffset.y;
	g_scrollW = (float)scrollView.bounds.size.width;
	g_scrollH = (float)scrollView.bounds.size.height;
	g_scrollContentW = (float)scrollView.contentSize.width;
	g_scrollContentH = (float)scrollView.contentSize.height;
	call0(s_scroll);
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
void niRemoveFromParent(void *child) {
	UIView *c = (__bridge UIView *)child;
	[c removeFromSuperview];
}

void niViewRelease(void *view) {
	if (view) CFRelease((CFTypeRef)view);
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

void niScrollTo(void *scroll, float x, float y, int animated) {
	UIScrollView *s = (__bridge UIScrollView *)scroll;
	CGFloat maxX = MAX(0, s.contentSize.width - s.bounds.size.width);
	CGFloat maxY = MAX(0, s.contentSize.height - s.bounds.size.height);
	CGPoint to = CGPointMake(MIN(MAX(0, x), maxX), MIN(MAX(0, y), maxY));
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
float niLastScrollX(void) { return g_scrollX; }
float niLastScrollY(void) { return g_scrollY; }
float niLastScrollWidth(void) { return g_scrollW; }
float niLastScrollHeight(void) { return g_scrollH; }
float niLastScrollContentWidth(void) { return g_scrollContentW; }
float niLastScrollContentHeight(void) { return g_scrollContentH; }

void niSetTeardownHandler(msClosure handler) {
	(void)handler;
}
