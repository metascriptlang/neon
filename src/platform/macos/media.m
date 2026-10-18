// WebView, Video and CameraView on AppKit: src/platform/ios/media.m and camera.m ported, each view hosted in a
// NeonView. WKWebView, AVPlayerView and AVCaptureVideoPreviewLayer are the macOS forms of the iOS views.
#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>
#import "view.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum {
	MEDIA_LOAD = 5, MEDIA_ERROR = 6, MEDIA_LOAD_START = 10, MEDIA_MESSAGE = 11, MEDIA_SHOULD_START = 12, MEDIA_PROGRESS = 13,
	MEDIA_END = 14, CAMERA_READY = 30, CAMERA_MOUNT_ERROR = 31, CAMERA_PICTURE = 32,
};

static NSString *const FIELD = @"\x1f";

static void emit(int32_t tag, int phase, NSString *value) {
	if (tag != 0) neonEmitControl(tag, phase, value, 0, 0);
}

static void noCommand(const char *component, NSString *name) {
	fprintf(stderr, "neon macos bridge: %s has no command \"%s\"\n", component, name.UTF8String);
	fflush(stderr);
	abort();
}

static void noProp(const char *component, const char *name) {
	fprintf(stderr, "neon macos bridge: %s niSetProp(%s) is not implemented on macOS yet\n", component, name);
	fflush(stderr);
	abort();
}

static NSString *field(NSArray<NSString *> *fields, NSUInteger at) { return at < fields.count ? fields[at] : @""; }

static void splitCommand(NSString *value, NSString **name, NSString **argument) {
	NSRange cut = [value rangeOfString:FIELD];
	*name = cut.location == NSNotFound ? value : [value substringToIndex:cut.location];
	*argument = cut.location == NSNotFound ? @"" : [value substringFromIndex:cut.location + 1];
}

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

// --- WebView: react-native-webview's macOS RNCWebViewImpl is a WKWebView with the same ReactNativeWebView script
// bridge ---

@interface NeonScriptProxy : NSObject <WKScriptMessageHandler>
@property(nonatomic, weak) id<WKScriptMessageHandler> target;
@end

@implementation NeonScriptProxy
- (void)userContentController:(WKUserContentController *)controller didReceiveScriptMessage:(WKScriptMessage *)message {
	[self.target userContentController:controller didReceiveScriptMessage:message];
}
@end

// Like the root, a text view and a switch, the page takes an inactive window's first click.
@interface NeonWebKitView : WKWebView
@end

@implementation NeonWebKitView
- (BOOL)acceptsFirstMouse:(NSEvent *)event { (void)event; return YES; }
@end

@interface NeonWebView : NeonView <NeonComponentView, WKNavigationDelegate, WKScriptMessageHandler, WKUIDelegate>
@property(nonatomic, strong) WKWebView *web;
@property(nonatomic) BOOL intercept, noScripts;
@property(nonatomic, copy) NSString *decision;
@end

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

@implementation NeonWebView

- (instancetype)initWithFrame:(NSRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
		WKUserContentController *content = [[WKUserContentController alloc] init];
		NSString *bridge = @"window.ReactNativeWebView = { postMessage: function (data) { window.webkit.messageHandlers.ReactNativeWebView.postMessage(String(data)); } };";
		[content addUserScript:[[WKUserScript alloc] initWithSource:bridge injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:YES]];
		NeonScriptProxy *proxy = [NeonScriptProxy new];
		proxy.target = self;
		[content addScriptMessageHandler:proxy name:@"ReactNativeWebView"];
		configuration.userContentController = content;
		_web = [[NeonWebKitView alloc] initWithFrame:NSZeroRect configuration:configuration];
		_web.navigationDelegate = self;
		_web.UIDelegate = self;
		_web.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
		_decision = @"allow";
		[self addSubview:_web];
	}
	return self;
}

- (void)setFrameSize:(NSSize)size {
	[super setFrameSize:size];
	self.web.frame = NSMakeRect(0, 0, size.width, size.height);
}

- (NSString *)navigation {
	WKWebView *web = self.web;
	return [@[web.URL.absoluteString ?: @"about:blank", web.title ?: @"", web.isLoading ? @"true" : @"false",
		web.canGoBack ? @"true" : @"false", web.canGoForward ? @"true" : @"false"] componentsJoinedByString:FIELD];
}

- (void)userContentController:(WKUserContentController *)controller didReceiveScriptMessage:(WKScriptMessage *)message {
	(void)controller;
	emit(self.neonTag, MEDIA_MESSAGE, [message.body isKindOfClass:NSString.class] ? message.body : [NSString stringWithFormat:@"%@", message.body]);
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)action preferences:(WKWebpagePreferences *)preferences decisionHandler:(void (^)(WKNavigationActionPolicy, WKWebpagePreferences *))decisionHandler {
	(void)webView;
	preferences.allowsContentJavaScript = !self.noScripts;
	BOOL top = action.targetFrame == nil || action.targetFrame.isMainFrame;
	if (!self.intercept || !top || self.neonTag == 0) {
		decisionHandler(WKNavigationActionPolicyAllow, preferences);
		return;
	}
	// The handler answers through the loadDecision prop before emit returns.
	self.decision = @"allow";
	emit(self.neonTag, MEDIA_SHOULD_START, [@[action.request.URL.absoluteString ?: @"", navigationTypeName(action.navigationType), @"true"] componentsJoinedByString:FIELD]);
	decisionHandler([self.decision isEqualToString:@"block"] ? WKNavigationActionPolicyCancel : WKNavigationActionPolicyAllow, preferences);
}

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation {
	(void)webView; (void)navigation;
	emit(self.neonTag, MEDIA_LOAD_START, [self navigation]);
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
	(void)webView; (void)navigation;
	emit(self.neonTag, MEDIA_LOAD, [self navigation]);
}

- (void)failed:(NSError *)error {
	// RN ignores a navigation cancelled by a newer one or by the policy decision (WebKit 102).
	if ([error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorCancelled) return;
	if ([error.domain isEqualToString:@"WebKitErrorDomain"] && error.code == 102) return;
	NSURL *failing = error.userInfo[NSURLErrorFailingURLErrorKey];
	NSString *url = failing.absoluteString ?: self.web.URL.absoluteString ?: @"";
	emit(self.neonTag, MEDIA_ERROR, [NSString stringWithFormat:@"%ld\x1f%@\x1f%@", (long)error.code, error.localizedDescription ?: @"", url]);
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
	(void)webView; (void)navigation;
	[self failed:error];
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
	(void)webView; (void)navigation;
	[self failed:error];
}

- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView { [webView reload]; }

- (WKWebView *)webView:(WKWebView *)webView createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration forNavigationAction:(WKNavigationAction *)action windowFeatures:(WKWindowFeatures *)features {
	(void)configuration; (void)features;
	if (action.targetFrame == nil) [webView loadRequest:action.request];
	return nil;
}

- (void)source:(NSString *)value {
	NSArray<NSString *> *fields = [value componentsSeparatedByString:FIELD];
	if ([field(fields, 0) isEqualToString:@"html"]) {
		NSString *base = field(fields, 2);
		[self.web loadHTMLString:field(fields, 1) baseURL:base.length ? [NSURL URLWithString:base] : nil];
		return;
	}
	NSURL *url = [NSURL URLWithString:field(fields, 1)];
	if (!url) return;
	if (url.isFileURL) [self.web loadFileURL:url allowingReadAccessToURL:url.URLByDeletingLastPathComponent];
	else [self.web loadRequest:[NSURLRequest requestWithURL:url]];
}

- (void)command:(NSString *)value {
	NSString *name, *argument;
	splitCommand(value, &name, &argument);
	WKWebView *web = self.web;
	if ([name isEqualToString:@"goBack"]) [web goBack];
	else if ([name isEqualToString:@"goForward"]) [web goForward];
	else if ([name isEqualToString:@"reload"]) [web reload];
	else if ([name isEqualToString:@"stopLoading"]) [web stopLoading];
	else if ([name isEqualToString:@"requestFocus"]) [web.window makeFirstResponder:web];
	else if ([name isEqualToString:@"injectJavaScript"]) [web evaluateJavaScript:argument completionHandler:nil];
	else if ([name isEqualToString:@"postMessage"]) {
		NSString *script = [NSString stringWithFormat:@"(function () { window.dispatchEvent(new MessageEvent('message', { data: %@ })); })();", jsonString(argument)];
		[web evaluateJavaScript:script completionHandler:nil];
	} else {
		noCommand("WebView", name);
	}
}

- (void)setProp:(const char *)name value:(const char *)value {
	if (!strcmp(name, "source")) [self source:@(value)];
	else if (!strcmp(name, "javaScriptEnabled")) self.noScripts = !strcmp(value, "false");
	else if (!strcmp(name, "interceptLoads")) self.intercept = !strcmp(value, "true");
	else if (!strcmp(name, "loadDecision")) self.decision = @(value);
	else if (!strcmp(name, "command")) [self command:@(value)];
	else noProp("WebView", name);
}

- (void)neonRelease {
	[self.web stopLoading];
	self.web.navigationDelegate = nil;
	[self.web.configuration.userContentController removeScriptMessageHandlerForName:@"ReactNativeWebView"];
	self.neonTag = 0;
}
@end

// --- Video: an AVPlayer drawn by an AVPlayerLayer, with an AVPlayerView over it while `controls` is set ---

@interface NeonVideo : NeonView <NeonComponentView>
@property(nonatomic, strong) AVPlayer *player;
@property(nonatomic, strong) AVPlayerItem *item;
@property(nonatomic, strong) NSView *surface;
@property(nonatomic, strong) AVPlayerLayer *playerLayer;
@property(nonatomic, strong) AVPlayerView *playerView;
@property(nonatomic, strong) id timeObserver;
@property(nonatomic) BOOL paused, repeats;
@property(nonatomic) float rate;
@property(nonatomic) double progressEvery;
@end

static void *kItemStatus = &kItemStatus;

@implementation NeonVideo

- (instancetype)initWithFrame:(NSRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		_player = [[AVPlayer alloc] init];
		_player.actionAtItemEnd = AVPlayerActionAtItemEndPause;
		_rate = 1;
		_progressEvery = 250;
		_playerLayer = [AVPlayerLayer playerLayerWithPlayer:_player];
		_playerLayer.videoGravity = AVLayerVideoGravityResizeAspect;
		_surface = [[NSView alloc] initWithFrame:NSZeroRect];
		_surface.layer = _playerLayer;
		_surface.wantsLayer = YES;
		[self addSubview:_surface];
		[self observeTime];
	}
	return self;
}

- (void)setFrameSize:(NSSize)size {
	[super setFrameSize:size];
	self.surface.frame = NSMakeRect(0, 0, size.width, size.height);
	self.playerView.frame = self.surface.frame;
}

- (void)showControls:(BOOL)shown {
	if (shown && !self.playerView) {
		self.playerView = [[AVPlayerView alloc] initWithFrame:self.surface.frame];
		self.playerView.controlsStyle = AVPlayerViewControlsStyleInline;
		self.playerView.videoGravity = self.playerLayer.videoGravity;
		self.playerView.player = self.player;
		[self addSubview:self.playerView];
	} else if (!shown && self.playerView) {
		[self.playerView removeFromSuperview];
		self.playerView.player = nil;
		self.playerView = nil;
	}
}

- (void)dealloc { [self stop]; }

- (void)stop {
	if (self.timeObserver) {
		[self.player removeTimeObserver:self.timeObserver];
		self.timeObserver = nil;
	}
	[self forgetItem];
	[self.player pause];
}

- (void)forgetItem {
	if (!self.item) return;
	[self.item removeObserver:self forKeyPath:@"status" context:kItemStatus];
	[[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:self.item];
	self.item = nil;
}

- (double)playable {
	NSValue *last = self.item.loadedTimeRanges.lastObject;
	return last ? CMTimeGetSeconds(CMTimeRangeGetEnd(last.CMTimeRangeValue)) : 0;
}

- (double)duration {
	double d = self.item ? CMTimeGetSeconds(self.item.duration) : 0;
	return isfinite(d) ? d : 0;
}

- (void)reportProgress {
	if (!self.item || self.item.status != AVPlayerItemStatusReadyToPlay) return;
	emit(self.neonTag, MEDIA_PROGRESS, [NSString stringWithFormat:@"%g\x1f%g\x1f%g", CMTimeGetSeconds(self.player.currentTime), [self playable], [self duration]]);
}

- (void)observeTime {
	if (self.timeObserver) [self.player removeTimeObserver:self.timeObserver];
	__weak NeonVideo *weakSelf = self;
	CMTime every = CMTimeMakeWithSeconds(MAX(self.progressEvery, 16) / 1000.0, 600);
	self.timeObserver = [self.player addPeriodicTimeObserverForInterval:every queue:dispatch_get_main_queue() usingBlock:^(CMTime time) {
		(void)time;
		NeonVideo *me = weakSelf;
		if (me && me.player.rate > 0) [me reportProgress];
	}];
}

- (void)applyPlayback {
	if (self.paused || !self.item) [self.player pause];
	else [self.player playImmediatelyAtRate:self.rate];
}

- (void)load:(NSString *)uri {
	[self forgetItem];
	__weak NeonVideo *weakSelf = self;
	dispatch_async(dispatch_get_main_queue(), ^{ emit(weakSelf.neonTag, MEDIA_LOAD_START, uri); });
	NSURL *url = playableURL(uri);
	if (!url) {
		dispatch_async(dispatch_get_main_queue(), ^{ emit(weakSelf.neonTag, MEDIA_ERROR, @"0\x1fthe video source is not a playable url"); });
		[self.player replaceCurrentItemWithPlayerItem:nil];
		return;
	}
	self.item = [AVPlayerItem playerItemWithURL:url];
	[self.item addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:kItemStatus];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(ended:) name:AVPlayerItemDidPlayToEndTimeNotification object:self.item];
	[self.player replaceCurrentItemWithPlayerItem:self.item];
	[self applyPlayback];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
	if (context != kItemStatus) {
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
		return;
	}
	dispatch_async(dispatch_get_main_queue(), ^{
		AVPlayerItem *item = self.item;
		if (object != item) return;
		if (item.status == AVPlayerItemStatusReadyToPlay) {
			CGSize size = item.presentationSize;
			emit(self.neonTag, MEDIA_LOAD, [NSString stringWithFormat:@"%g\x1f%g\x1f%g\x1f%g", [self duration], CMTimeGetSeconds(self.player.currentTime), size.width, size.height]);
			[self applyPlayback];
		} else if (item.status == AVPlayerItemStatusFailed) {
			NSError *error = item.error;
			emit(self.neonTag, MEDIA_ERROR, [NSString stringWithFormat:@"%ld\x1f%@", (long)error.code, error.localizedDescription ?: @"the video failed"]);
		}
	});
}

- (void)ended:(NSNotification *)note {
	(void)note;
	if (self.repeats) {
		[self.player seekToTime:kCMTimeZero];
		[self applyPlayback];
		return;
	}
	[self reportProgress];
	emit(self.neonTag, MEDIA_END, @"");
}

- (void)seek:(double)seconds {
	__weak NeonVideo *weakSelf = self;
	[self.player seekToTime:CMTimeMakeWithSeconds(seconds, 600) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL finished) {
		if (finished) dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf reportProgress]; });
	}];
}

- (void)command:(NSString *)value {
	NSString *name, *argument;
	splitCommand(value, &name, &argument);
	if ([name isEqualToString:@"seek"]) [self seek:argument.doubleValue];
	else if ([name isEqualToString:@"pause"]) [self.player pause];
	else if ([name isEqualToString:@"resume"]) [self.player playImmediatelyAtRate:self.rate];
	else noCommand("Video", name);
}

- (void)setProp:(const char *)name value:(const char *)value {
	if (!strcmp(name, "source")) [self load:@(value)];
	else if (!strcmp(name, "paused")) {
		self.paused = !strcmp(value, "true");
		[self applyPlayback];
	} else if (!strcmp(name, "muted")) self.player.muted = !strcmp(value, "true");
	else if (!strcmp(name, "volume")) self.player.volume = (float)MAX(0, MIN(1, atof(value)));
	else if (!strcmp(name, "rate")) {
		self.rate = (float)atof(value);
		if (self.player.rate > 0) self.player.rate = self.rate;
	} else if (!strcmp(name, "repeat")) self.repeats = !strcmp(value, "true");
	else if (!strcmp(name, "controls")) [self showControls:!strcmp(value, "true")];
	else if (!strcmp(name, "progressUpdateInterval")) {
		self.progressEvery = atof(value);
		[self observeTime];
	} else if (!strcmp(name, "resizeMode")) {
		self.playerLayer.videoGravity = !strcmp(value, "cover") ? AVLayerVideoGravityResizeAspectFill :
			!strcmp(value, "stretch") ? AVLayerVideoGravityResize : AVLayerVideoGravityResizeAspect;
		self.playerView.videoGravity = self.playerLayer.videoGravity;
	} else if (!strcmp(name, "command")) [self command:@(value)];
	else noProp("Video", name);
}

- (void)neonRelease {
	[self stop];
	self.neonTag = 0;
}
@end

// --- CameraView: an AVCaptureSession behind an AVCaptureVideoPreviewLayer, photos through AVCapturePhotoOutput ---

@class NeonCamera;

@interface NeonPhotoCapture : NSObject <AVCapturePhotoCaptureDelegate>
@property(nonatomic, copy) NSString *pictureId;
@property(nonatomic) double quality;
@property(nonatomic) BOOL base64, answered;
@property(nonatomic, weak) NeonCamera *view;
@end

@interface NeonCamera : NeonView <NeonComponentView>
@property(nonatomic, strong) AVCaptureSession *session;
@property(nonatomic, strong) AVCapturePhotoOutput *photoOutput;
@property(nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;
@property(nonatomic, strong) NSView *preview;
@property(nonatomic, strong) AVCaptureDeviceInput *input;
@property(nonatomic, strong) dispatch_queue_t queue;
@property(nonatomic, strong) NSMutableSet<NeonPhotoCapture *> *captures;
@property(nonatomic, copy) NSString *facing;
@property(nonatomic) AVCaptureFlashMode flash;
@property(nonatomic) BOOL active, mirror, released, wanted, running;
@property(nonatomic) NSUInteger generation;
@end

static NSString *pictureError(NSString *pictureId, NSString *message) {
	return [@[pictureId, @"error", message] componentsJoinedByString:FIELD];
}

static void emitLater(NeonCamera *view, int phase, NSString *value) {
	dispatch_async(dispatch_get_main_queue(), ^{ emit(view.neonTag, phase, value); });
}

// A Mac's built-in camera faces the user; a facing no camera has falls back to the default camera.
static AVCaptureDevice *cameraFor(NSString *facing) {
	AVCaptureDevicePosition position = [facing isEqualToString:@"front"] ? AVCaptureDevicePositionFront : AVCaptureDevicePositionBack;
	AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera mediaType:AVMediaTypeVideo position:position];
	return device ?: [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
}

@implementation NeonPhotoCapture

- (void)finish:(NSString *)value {
	dispatch_async(dispatch_get_main_queue(), ^{
		if (self.answered) return;
		self.answered = YES;
		NeonCamera *view = self.view;
		[view.captures removeObject:self];
		emit(view.neonTag, CAMERA_PICTURE, value);
	});
}

- (NSString *)store:(NSData *)data {
	NSBitmapImageRep *image = data ? [NSBitmapImageRep imageRepWithData:data] : nil;
	if (!image) return pictureError(self.pictureId, @"the camera returned no image");
	NSData *bytes = self.quality < 1
		? [image representationUsingType:NSBitmapImageFileTypeJPEG properties:@{NSImageCompressionFactor: @(MAX(self.quality, 0))}]
		: data;
	NSString *caches = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
	NSString *folder = [caches stringByAppendingPathComponent:@"Camera"];
	[NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
	NSString *path = [folder stringByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingString:@".jpg"]];
	NSError *error = nil;
	if (!bytes || ![bytes writeToFile:path options:NSDataWritingAtomic error:&error]) {
		return pictureError(self.pictureId, error.localizedDescription ?: @"cannot store the picture");
	}
	return [@[self.pictureId, @"ok", [NSURL fileURLWithPath:path].absoluteString,
		[NSString stringWithFormat:@"%ld", (long)image.pixelsWide], [NSString stringWithFormat:@"%ld", (long)image.pixelsHigh],
		self.base64 ? [bytes base64EncodedStringWithOptions:0] : @""] componentsJoinedByString:FIELD];
}

- (void)captureOutput:(AVCapturePhotoOutput *)output didFinishProcessingPhoto:(AVCapturePhoto *)photo error:(NSError *)error {
	(void)output;
	if (error) [self finish:pictureError(self.pictureId, error.localizedDescription ?: @"the capture failed")];
	else [self finish:[self store:photo.fileDataRepresentation]];
}

- (void)captureOutput:(AVCapturePhotoOutput *)output didFinishCaptureForResolvedSettings:(AVCaptureResolvedPhotoSettings *)settings error:(NSError *)error {
	(void)output; (void)settings;
	[self finish:pictureError(self.pictureId, error.localizedDescription ?: @"the capture produced no photo")];
}

@end

@implementation NeonCamera

- (instancetype)initWithFrame:(NSRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		_session = [[AVCaptureSession alloc] init];
		_photoOutput = [[AVCapturePhotoOutput alloc] init];
		_queue = dispatch_queue_create("neon.camera", DISPATCH_QUEUE_SERIAL);
		_captures = [NSMutableSet set];
		_facing = @"back";
		_flash = AVCaptureFlashModeOff;
		_active = YES;
		_previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:_session];
		_previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
		_preview = [[NSView alloc] initWithFrame:NSZeroRect];
		_preview.layer = _previewLayer;
		_preview.wantsLayer = YES;
		[self addSubview:_preview];
	}
	return self;
}

- (void)setFrameSize:(NSSize)size {
	[super setFrameSize:size];
	self.preview.frame = NSMakeRect(0, 0, size.width, size.height);
}

- (void)setNeonTag:(int32_t)tag {
	[super setNeonTag:tag];
	[self update];
}

- (void)viewDidMoveToWindow {
	[super viewDidMoveToWindow];
	[self update];
}

- (void)update {
	BOOL want = !self.released && self.neonTag != 0 && self.window != nil && self.active;
	if (want == self.wanted) return;
	self.wanted = want;
	self.generation += 1;
	self.running = NO;
	if (want) {
		[self start];
		return;
	}
	AVCaptureSession *session = self.session;
	dispatch_async(self.queue, ^{ [session stopRunning]; });
}

- (NSString *)configure:(AVCaptureDevice *)device {
	NSError *error = nil;
	AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
	if (!input) return error.localizedDescription ?: @"cannot open the camera";
	NSString *problem = nil;
	[self.session beginConfiguration];
	if ([self.session canSetSessionPreset:AVCaptureSessionPresetPhoto]) self.session.sessionPreset = AVCaptureSessionPresetPhoto;
	AVCaptureDeviceInput *previous = self.input;
	if (previous) [self.session removeInput:previous];
	if ([self.session canAddInput:input]) {
		[self.session addInput:input];
		self.input = input;
	} else {
		problem = @"the camera cannot join the capture session";
		if (previous) [self.session addInput:previous];
	}
	if (!problem && ![self.session.outputs containsObject:self.photoOutput]) {
		if ([self.session canAddOutput:self.photoOutput]) [self.session addOutput:self.photoOutput];
		else problem = @"the photo output cannot join the capture session";
	}
	[self.session commitConfiguration];
	return problem;
}

// Reading the authorization never prompts; asking is the app's, through Camera.requestCameraPermissionsAsync.
- (void)start {
	if ([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo] != AVAuthorizationStatusAuthorized) {
		emitLater(self, CAMERA_MOUNT_ERROR, @"Camera permission not granted");
		return;
	}
	AVCaptureDevice *device = cameraFor(self.facing);
	if (!device) {
		emitLater(self, CAMERA_MOUNT_ERROR, @"No camera is available on this device");
		return;
	}
	NSUInteger generation = self.generation;
	dispatch_async(self.queue, ^{
		NSString *problem = [self configure:device];
		if (!problem) [self.session startRunning];
		dispatch_async(dispatch_get_main_queue(), ^{
			if (generation != self.generation || self.neonTag == 0) return;
			if (problem) {
				emit(self.neonTag, CAMERA_MOUNT_ERROR, problem);
				return;
			}
			self.running = YES;
			emit(self.neonTag, CAMERA_READY, @"");
		});
	});
}

- (void)face:(NSString *)facing {
	if ([facing isEqualToString:self.facing]) return;
	self.facing = facing;
	if (!self.wanted) return;
	self.generation += 1;
	self.running = NO;
	[self start];
}

- (void)takePicture:(NSString *)argument {
	NSArray<NSString *> *fields = [argument componentsSeparatedByString:FIELD];
	if (fields.count != 3) {
		fprintf(stderr, "neon macos bridge: CameraView takePicture wants 3 fields, got \"%s\"\n", argument.UTF8String);
		fflush(stderr);
		abort();
	}
	if (!self.running) {
		emitLater(self, CAMERA_PICTURE, pictureError(fields[0], @"the camera is not running"));
		return;
	}
	NeonPhotoCapture *capture = [NeonPhotoCapture new];
	capture.pictureId = fields[0];
	capture.quality = fields[1].doubleValue;
	capture.base64 = [fields[2] isEqualToString:@"1"];
	capture.view = self;
	[self.captures addObject:capture];
	AVCaptureFlashMode flash = self.flash;
	BOOL mirrored = self.mirror && [self.facing isEqualToString:@"front"];
	AVCapturePhotoOutput *output = self.photoOutput;
	dispatch_async(self.queue, ^{
		AVCaptureConnection *connection = [output connectionWithMediaType:AVMediaTypeVideo];
		if (!connection) {
			[capture finish:pictureError(capture.pictureId, @"the camera is not running")];
			return;
		}
		if (connection.isVideoMirroringSupported) {
			connection.automaticallyAdjustsVideoMirroring = NO;
			connection.videoMirrored = mirrored;
		}
		AVCapturePhotoSettings *settings = [output.availablePhotoCodecTypes containsObject:AVVideoCodecTypeJPEG]
			? [AVCapturePhotoSettings photoSettingsWithFormat:@{AVVideoCodecKey: AVVideoCodecTypeJPEG}]
			: [AVCapturePhotoSettings photoSettings];
		if ([output.supportedFlashModes containsObject:@(flash)]) settings.flashMode = flash;
		[output capturePhotoWithSettings:settings delegate:capture];
	});
}

- (void)command:(NSString *)value {
	NSString *name, *argument;
	splitCommand(value, &name, &argument);
	if ([name isEqualToString:@"takePicture"]) [self takePicture:argument];
	else if ([name isEqualToString:@"pausePreview"]) self.previewLayer.connection.enabled = NO;
	else if ([name isEqualToString:@"resumePreview"]) self.previewLayer.connection.enabled = YES;
	else noCommand("CameraView", name);
}

- (void)setProp:(const char *)name value:(const char *)value {
	NSString *text = @(value);
	if (!strcmp(name, "facing")) [self face:[text isEqualToString:@"front"] ? @"front" : @"back"];
	else if (!strcmp(name, "flash")) {
		self.flash = [text isEqualToString:@"on"] ? AVCaptureFlashModeOn : [text isEqualToString:@"auto"] ? AVCaptureFlashModeAuto : AVCaptureFlashModeOff;
	} else if (!strcmp(name, "active")) {
		self.active = ![text isEqualToString:@"false"];
		[self update];
	} else if (!strcmp(name, "mirror")) self.mirror = [text isEqualToString:@"true"];
	else if (!strcmp(name, "command")) [self command:text];
	else noProp("CameraView", name);
}

- (void)neonRelease {
	self.released = YES;
	self.neonTag = 0;
}
@end

NeonView *neonMediaCreate(const char *kind) {
	if (!strcmp(kind, "webview")) return [[NeonWebView alloc] initWithFrame:NSZeroRect];
	if (!strcmp(kind, "video")) return [[NeonVideo alloc] initWithFrame:NSZeroRect];
	if (!strcmp(kind, "camera")) return [[NeonCamera alloc] initWithFrame:NSZeroRect];
	return nil;
}

NSView *neonMediaNativeTarget(NeonView *view) {
	if ([view isKindOfClass:NeonWebView.class]) return ((NeonWebView *)view).web;
	if ([view isKindOfClass:NeonVideo.class]) return ((NeonVideo *)view).playerView;
	return nil;
}
