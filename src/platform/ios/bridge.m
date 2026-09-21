// Neon iOS host bridge — UIKit first cut. MS main() calls niRegisterApp(mount)
// then niRunApp() -> UIApplicationMain (never returns); NeonVC builds the
// full-screen container and calls the mount closure, which renders into
// niContainerView(). Events flow back through niSetTouchHandler.
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#include "bridge.h"

static msClosure s_mount;
static msClosure s_touch;
static int g_lastTag = 0;
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

@interface NeonVC : UIViewController
@end

@implementation NeonVC

- (void)viewDidLoad {
	[super viewDidLoad];
	self.view.backgroundColor = [UIColor blackColor];
	g_container = [[UIView alloc] initWithFrame:self.view.bounds];
	g_container.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	g_container.userInteractionEnabled = YES;
	[self.view addSubview:g_container];
	call0(s_mount);
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
	FILE *marker = fopen("/tmp/neon_ran.txt", "a");
	if (marker) { fprintf(marker, "niRegisterApp fn=%p env=%p\n", mount.fn, mount.env); fclose(marker); }
	s_mount = mount;
}

int niRunApp(void) {
	FILE *marker = fopen("/tmp/neon_ran.txt", "a");
	if (marker) { fprintf(marker, "niRunApp enter\n"); fclose(marker); }
	@autoreleasepool {
		int rc = UIApplicationMain(0, nil, nil, NSStringFromClass([NeonAppDelegate class]));
		marker = fopen("/tmp/neon_ran.txt", "a");
		if (marker) { fprintf(marker, "UIApplicationMain returned %d\n", rc); fclose(marker); }
		return rc;
	}
}

void *niContainerView(void) {
	return (__bridge void *)g_container;
}

float niScreenWidth(void) {
	return (float)[UIScreen mainScreen].bounds.size.width;
}

float niScreenHeight(void) {
	return (float)[UIScreen mainScreen].bounds.size.height;
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

void niSetFrame(void *view, float x, float y, float w, float h) {
	UIView *v = (__bridge UIView *)view;
	v.frame = CGRectMake(x, y, w, h);
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
