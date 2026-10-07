#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>
#include <string.h>
#include <stdlib.h>

void neonMediaEmit(int tag, int phase, NSString *value, float width, float height);
void *neonCameraCreate(void);
int neonCameraSetProp(UIView *view, const char *name, const char *text);
void neonCameraRelease(UIView *view);

static NSString *mediaText(const char *text) { return [NSString stringWithUTF8String:text ? text : ""]; }

static NSString *field(NSArray<NSString *> *fields, NSUInteger at) { return at < fields.count ? fields[at] : @""; }

static NSString *jsonString(NSString *text) {
	NSData *data = [NSJSONSerialization dataWithJSONObject:text options:NSJSONWritingFragmentsAllowed error:nil];
	return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"\"\"";
}

// Native players take files, not data: URIs, and the app bundles no asset files, so a data: URI is
// decoded once into the temporary directory.
static NSURL *playableURL(NSString *uri) {
	if (![uri hasPrefix:@"data:"]) {
		if ([uri hasPrefix:@"/"]) return [NSURL fileURLWithPath:uri];
		return [NSURL URLWithString:uri];
	}
	NSRange comma = [uri rangeOfString:@","];
	if (comma.location == NSNotFound) return nil;
	NSString *header = [uri substringToIndex:comma.location];
	if (![header hasSuffix:@";base64"]) return nil;
	NSData *bytes = [[NSData alloc] initWithBase64EncodedString:[uri substringFromIndex:comma.location + 1] options:NSDataBase64DecodingIgnoreUnknownCharacters];
	if (!bytes) return nil;
	NSString *mime = [[header substringFromIndex:5] componentsSeparatedByString:@";"].firstObject;
	NSString *extension = [mime isEqualToString:@"video/quicktime"] ? @"mov" :
		[mime isEqualToString:@"audio/mpeg"] ? @"mp3" :
		[mime hasPrefix:@"audio/"] ? @"m4a" : @"mp4";
	NSString *name = [NSString stringWithFormat:@"neon-media-%lx-%lu.%@", (unsigned long)uri.hash, (unsigned long)bytes.length, extension];
	NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
	if (![[NSFileManager defaultManager] fileExistsAtPath:path] && ![bytes writeToFile:path atomically:YES]) return nil;
	return [NSURL fileURLWithPath:path];
}

// --- WebView ---

@interface NeonScriptProxy : NSObject <WKScriptMessageHandler>
@property (nonatomic, weak) id<WKScriptMessageHandler> target;
@end

@implementation NeonScriptProxy
- (void)userContentController:(WKUserContentController *)controller didReceiveScriptMessage:(WKScriptMessage *)message {
	[self.target userContentController:controller didReceiveScriptMessage:message];
}
@end

@interface NeonWebView : WKWebView <WKNavigationDelegate, WKScriptMessageHandler, WKUIDelegate>
@property (nonatomic) BOOL neonIntercept;
@property (nonatomic) BOOL neonNoScripts;
@property (nonatomic, copy) NSString *neonDecision;
@end

@implementation NeonWebView

+ (instancetype)neonWebView {
	WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
	configuration.allowsInlineMediaPlayback = YES;
	WKUserContentController *content = [[WKUserContentController alloc] init];
	NSString *bridge = @"window.ReactNativeWebView = { postMessage: function (data) { window.webkit.messageHandlers.ReactNativeWebView.postMessage(String(data)); } };";
	[content addUserScript:[[WKUserScript alloc] initWithSource:bridge injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:YES]];
	NeonScriptProxy *proxy = [NeonScriptProxy new];
	[content addScriptMessageHandler:proxy name:@"ReactNativeWebView"];
	configuration.userContentController = content;
	NeonWebView *view = [[NeonWebView alloc] initWithFrame:CGRectZero configuration:configuration];
	proxy.target = view;
	view.navigationDelegate = view;
	view.UIDelegate = view;
	view.neonDecision = @"allow";
	view.opaque = NO;
	view.backgroundColor = UIColor.whiteColor;
	return view;
}

- (NSString *)neonNavigation {
	return [NSString stringWithFormat:@"%@\x1f%@\x1f%@\x1f%@\x1f%@",
		self.URL.absoluteString ?: @"about:blank", self.title ?: @"",
		self.isLoading ? @"true" : @"false", self.canGoBack ? @"true" : @"false", self.canGoForward ? @"true" : @"false"];
}

- (void)userContentController:(WKUserContentController *)controller didReceiveScriptMessage:(WKScriptMessage *)message {
	(void)controller;
	NSString *data = [message.body isKindOfClass:NSString.class] ? message.body : [NSString stringWithFormat:@"%@", message.body];
	neonMediaEmit((int)self.tag, 11, data, 0, 0);
}

static NSString *navigationTypeName(WKNavigationType type) {
	switch (type) {
		case WKNavigationTypeLinkActivated: return @"click";
		case WKNavigationTypeFormSubmitted: return @"formsubmit";
		case WKNavigationTypeBackForward: return @"backforward";
		case WKNavigationTypeReload: return @"reload";
		case WKNavigationTypeFormResubmitted: return @"formresubmit";
		default: return @"other";
	}
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)action preferences:(WKWebpagePreferences *)preferences decisionHandler:(void (^)(WKNavigationActionPolicy, WKWebpagePreferences *))decisionHandler {
	(void)webView;
	preferences.allowsContentJavaScript = !self.neonNoScripts;
	BOOL top = action.targetFrame == nil || action.targetFrame.isMainFrame;
	if (!self.neonIntercept || !top || self.tag == 0) {
		decisionHandler(WKNavigationActionPolicyAllow, preferences);
		return;
	}
	self.neonDecision = @"allow";
	NSString *request = [NSString stringWithFormat:@"%@\x1f%@\x1ftrue", action.request.URL.absoluteString ?: @"", navigationTypeName(action.navigationType)];
	neonMediaEmit((int)self.tag, 12, request, 0, 0);
	BOOL allow = ![self.neonDecision isEqualToString:@"block"];
	decisionHandler(allow ? WKNavigationActionPolicyAllow : WKNavigationActionPolicyCancel, preferences);
}

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation {
	(void)webView; (void)navigation;
	neonMediaEmit((int)self.tag, 10, [self neonNavigation], 0, 0);
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
	(void)webView; (void)navigation;
	neonMediaEmit((int)self.tag, 5, [self neonNavigation], 0, 0);
}

- (void)neonFailed:(NSError *)error {
	// RN ignores a navigation cancelled by a newer one or by the policy decision (WebKit 102).
	if ([error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorCancelled) return;
	if ([error.domain isEqualToString:@"WebKitErrorDomain"] && error.code == 102) return;
	NSString *url = error.userInfo[NSURLErrorFailingURLStringErrorKey] ?: self.URL.absoluteString ?: @"";
	neonMediaEmit((int)self.tag, 6, [NSString stringWithFormat:@"%ld\x1f%@\x1f%@", (long)error.code, error.localizedDescription ?: @"", url], 0, 0);
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
	(void)webView; (void)navigation;
	[self neonFailed:error];
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
	(void)webView; (void)navigation;
	[self neonFailed:error];
}

- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView { [webView reload]; }

- (WKWebView *)webView:(WKWebView *)webView createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration forNavigationAction:(WKNavigationAction *)action windowFeatures:(WKWindowFeatures *)features {
	(void)configuration; (void)features;
	if (action.targetFrame == nil) [webView loadRequest:action.request];
	return nil;
}

- (void)neonSource:(NSString *)value {
	NSArray<NSString *> *fields = [value componentsSeparatedByString:@"\x1f"];
	if ([field(fields, 0) isEqualToString:@"html"]) {
		NSString *base = field(fields, 2);
		[self loadHTMLString:field(fields, 1) baseURL:base.length ? [NSURL URLWithString:base] : nil];
		return;
	}
	NSURL *url = [NSURL URLWithString:field(fields, 1)];
	if (!url) return;
	if (url.isFileURL) [self loadFileURL:url allowingReadAccessToURL:url.URLByDeletingLastPathComponent];
	else [self loadRequest:[NSURLRequest requestWithURL:url]];
}

- (void)neonCommand:(NSString *)value {
	NSRange cut = [value rangeOfString:@"\x1f"];
	NSString *name = cut.location == NSNotFound ? value : [value substringToIndex:cut.location];
	NSString *argument = cut.location == NSNotFound ? @"" : [value substringFromIndex:cut.location + 1];
	if ([name isEqualToString:@"goBack"]) [self goBack];
	else if ([name isEqualToString:@"goForward"]) [self goForward];
	else if ([name isEqualToString:@"reload"]) [self reload];
	else if ([name isEqualToString:@"stopLoading"]) [self stopLoading];
	else if ([name isEqualToString:@"requestFocus"]) [self becomeFirstResponder];
	else if ([name isEqualToString:@"injectJavaScript"]) [self evaluateJavaScript:argument completionHandler:nil];
	else if ([name isEqualToString:@"postMessage"]) {
		NSString *script = [NSString stringWithFormat:@"(function () { window.dispatchEvent(new MessageEvent('message', { data: %@ })); })();", jsonString(argument)];
		[self evaluateJavaScript:script completionHandler:nil];
	} else {
		fprintf(stderr, "neon: WebView has no command \"%s\"\n", name.UTF8String);
		abort();
	}
}

- (void)neonSetProp:(const char *)name value:(const char *)text {
	if (strcmp(name, "source") == 0) [self neonSource:mediaText(text)];
	else if (strcmp(name, "javaScriptEnabled") == 0) self.neonNoScripts = strcmp(text, "false") == 0;
	else if (strcmp(name, "interceptLoads") == 0) self.neonIntercept = strcmp(text, "true") == 0;
	else if (strcmp(name, "loadDecision") == 0) self.neonDecision = mediaText(text);
	else if (strcmp(name, "command") == 0) [self neonCommand:mediaText(text)];
}
@end

// --- Video ---

@interface NeonVideoView : UIView
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) AVPlayerItem *item;
@property (nonatomic, strong) id timeObserver;
@property (nonatomic, strong) AVPlayerViewController *controlsController;
@property (nonatomic, copy) NSString *source;
@property (nonatomic) BOOL paused;
@property (nonatomic) BOOL repeats;
@property (nonatomic) float rate;
@property (nonatomic) double progressEvery;
@property (nonatomic, copy) NSString *gravity;
@end

static void *kNeonItemStatus = &kNeonItemStatus;

@implementation NeonVideoView

+ (Class)layerClass { return AVPlayerLayer.class; }

- (AVPlayerLayer *)playerLayer { return (AVPlayerLayer *)self.layer; }

- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		_player = [[AVPlayer alloc] init];
		_player.actionAtItemEnd = AVPlayerActionAtItemEndPause;
		_rate = 1;
		_progressEvery = 250;
		_gravity = AVLayerVideoGravityResizeAspect;
		self.playerLayer.player = _player;
		self.playerLayer.videoGravity = _gravity;
		self.backgroundColor = UIColor.blackColor;
		[self neonObserveTime];
	}
	return self;
}

- (void)dealloc {
	[self neonStop];
}

- (void)neonStop {
	if (self.timeObserver) {
		[self.player removeTimeObserver:self.timeObserver];
		self.timeObserver = nil;
	}
	[self neonForgetItem];
	[self.player pause];
}

- (void)neonForgetItem {
	if (!self.item) return;
	[self.item removeObserver:self forKeyPath:@"status" context:kNeonItemStatus];
	[[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:self.item];
	self.item = nil;
}

- (double)neonPlayable {
	NSValue *last = self.item.loadedTimeRanges.lastObject;
	if (!last) return 0;
	CMTimeRange range = last.CMTimeRangeValue;
	return CMTimeGetSeconds(CMTimeRangeGetEnd(range));
}

- (double)neonDuration {
	double d = self.item ? CMTimeGetSeconds(self.item.duration) : 0;
	return isfinite(d) ? d : 0;
}

- (void)neonReportProgress {
	if (!self.item || self.item.status != AVPlayerItemStatusReadyToPlay) return;
	NSString *value = [NSString stringWithFormat:@"%g\x1f%g\x1f%g", CMTimeGetSeconds(self.player.currentTime), [self neonPlayable], [self neonDuration]];
	neonMediaEmit((int)self.tag, 13, value, 0, 0);
}

- (void)neonObserveTime {
	if (self.timeObserver) [self.player removeTimeObserver:self.timeObserver];
	__weak NeonVideoView *weakSelf = self;
	CMTime every = CMTimeMakeWithSeconds(MAX(self.progressEvery, 16) / 1000.0, 600);
	self.timeObserver = [self.player addPeriodicTimeObserverForInterval:every queue:dispatch_get_main_queue() usingBlock:^(CMTime time) {
		(void)time;
		NeonVideoView *me = weakSelf;
		if (me && me.player.rate > 0) [me neonReportProgress];
	}];
}

- (void)neonApplyPlayback {
	if (self.paused || !self.item) [self.player pause];
	else [self.player playImmediatelyAtRate:self.rate];
}

- (void)neonLoad:(NSString *)uri {
	[self neonForgetItem];
	self.source = uri;
	NSInteger tag = self.tag;
	__weak NeonVideoView *weakSelf = self;
	dispatch_async(dispatch_get_main_queue(), ^{
		NeonVideoView *me = weakSelf;
		if (me) neonMediaEmit((int)(me.tag ? me.tag : tag), 10, uri, 0, 0);
	});
	NSURL *url = playableURL(uri);
	if (!url) {
		dispatch_async(dispatch_get_main_queue(), ^{
			NeonVideoView *me = weakSelf;
			if (me) neonMediaEmit((int)me.tag, 6, [NSString stringWithFormat:@"0\x1f%@", @"the video source is not a playable url"], 0, 0);
		});
		[self.player replaceCurrentItemWithPlayerItem:nil];
		return;
	}
	self.item = [AVPlayerItem playerItemWithURL:url];
	[self.item addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:kNeonItemStatus];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(neonEnded:) name:AVPlayerItemDidPlayToEndTimeNotification object:self.item];
	[self.player replaceCurrentItemWithPlayerItem:self.item];
	[self neonApplyPlayback];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
	if (context != kNeonItemStatus) {
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
		return;
	}
	dispatch_async(dispatch_get_main_queue(), ^{
		AVPlayerItem *item = self.item;
		if (object != item) return;
		if (item.status == AVPlayerItemStatusReadyToPlay) {
			CGSize size = item.presentationSize;
			NSString *value = [NSString stringWithFormat:@"%g\x1f%g\x1f%g\x1f%g", [self neonDuration], CMTimeGetSeconds(self.player.currentTime), size.width, size.height];
			neonMediaEmit((int)self.tag, 5, value, 0, 0);
			[self neonApplyPlayback];
		} else if (item.status == AVPlayerItemStatusFailed) {
			NSError *error = item.error;
			neonMediaEmit((int)self.tag, 6, [NSString stringWithFormat:@"%ld\x1f%@", (long)error.code, error.localizedDescription ?: @"the video failed"], 0, 0);
		}
	});
}

- (void)neonEnded:(NSNotification *)note {
	(void)note;
	if (self.repeats) {
		[self.player seekToTime:kCMTimeZero];
		[self neonApplyPlayback];
		return;
	}
	[self neonReportProgress];
	neonMediaEmit((int)self.tag, 14, @"", 0, 0);
}

- (void)neonControls:(BOOL)shown {
	if (shown && !self.controlsController) {
		AVPlayerViewController *controller = [[AVPlayerViewController alloc] init];
		controller.player = self.player;
		controller.videoGravity = self.gravity;
		controller.view.frame = self.bounds;
		controller.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
		[self addSubview:controller.view];
		self.controlsController = controller;
	} else if (!shown && self.controlsController) {
		[self.controlsController.view removeFromSuperview];
		self.controlsController.player = nil;
		self.controlsController = nil;
	}
}

- (void)neonSeek:(double)seconds {
	__weak NeonVideoView *weakSelf = self;
	[self.player seekToTime:CMTimeMakeWithSeconds(seconds, 600) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL finished) {
		if (!finished) return;
		dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf neonReportProgress]; });
	}];
}

- (void)neonSetProp:(const char *)name value:(const char *)text {
	if (strcmp(name, "source") == 0) [self neonLoad:mediaText(text)];
	else if (strcmp(name, "paused") == 0) { self.paused = strcmp(text, "true") == 0; [self neonApplyPlayback]; }
	else if (strcmp(name, "muted") == 0) self.player.muted = strcmp(text, "true") == 0;
	else if (strcmp(name, "volume") == 0) self.player.volume = (float)MAX(0, MIN(1, atof(text)));
	else if (strcmp(name, "rate") == 0) {
		self.rate = (float)atof(text);
		if (self.player.rate > 0) self.player.rate = self.rate;
	}
	else if (strcmp(name, "repeat") == 0) self.repeats = strcmp(text, "true") == 0;
	else if (strcmp(name, "controls") == 0) [self neonControls:strcmp(text, "true") == 0];
	else if (strcmp(name, "progressUpdateInterval") == 0) { self.progressEvery = atof(text); [self neonObserveTime]; }
	else if (strcmp(name, "resizeMode") == 0) {
		self.gravity = strcmp(text, "cover") == 0 ? AVLayerVideoGravityResizeAspectFill :
			strcmp(text, "stretch") == 0 ? AVLayerVideoGravityResize : AVLayerVideoGravityResizeAspect;
		self.playerLayer.videoGravity = self.gravity;
		self.controlsController.videoGravity = self.gravity;
	}
	else if (strcmp(name, "command") == 0) {
		NSString *value = mediaText(text);
		NSRange cut = [value rangeOfString:@"\x1f"];
		NSString *command = cut.location == NSNotFound ? value : [value substringToIndex:cut.location];
		if ([command isEqualToString:@"seek"]) [self neonSeek:[value substringFromIndex:cut.location + 1].doubleValue];
		else if ([command isEqualToString:@"pause"]) [self.player pause];
		else if ([command isEqualToString:@"resume"]) [self.player playImmediatelyAtRate:self.rate];
		else {
			fprintf(stderr, "neon: Video has no command \"%s\"\n", command.UTF8String);
			abort();
		}
	}
}
@end

void *neonMediaCreate(const char *kind) {
	if (strcmp(kind, "webview") == 0) return CFBridgingRetain([NeonWebView neonWebView]);
	if (strcmp(kind, "video") == 0) return CFBridgingRetain([[NeonVideoView alloc] initWithFrame:CGRectZero]);
	if (strcmp(kind, "camera") == 0) return neonCameraCreate();
	return NULL;
}

int neonMediaSetProp(UIView *view, const char *name, const char *text) {
	if ([view isKindOfClass:NeonWebView.class]) { [(NeonWebView *)view neonSetProp:name value:text]; return 1; }
	if ([view isKindOfClass:NeonVideoView.class]) { [(NeonVideoView *)view neonSetProp:name value:text]; return 1; }
	return neonCameraSetProp(view, name, text);
}

void neonMediaRelease(UIView *view) {
	neonCameraRelease(view);
	if ([view isKindOfClass:NeonVideoView.class]) [(NeonVideoView *)view neonStop];
	else if ([view isKindOfClass:NeonWebView.class]) {
		NeonWebView *web = (NeonWebView *)view;
		[web stopLoading];
		web.navigationDelegate = nil;
		[web.configuration.userContentController removeScriptMessageHandlerForName:@"ReactNativeWebView"];
		web.tag = 0;
	}
}
