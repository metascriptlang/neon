#import <WebKit/WebKit.h>
#include "../native/components.h"
#import "media.h"

static NSString *jsonString(NSString *text) {
	NSData *data = [NSJSONSerialization dataWithJSONObject:text options:NSJSONWritingFragmentsAllowed error:nil];
	return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"\"\"";
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
- (NSView *)neonNativeTarget { return self.web; }
@end

void *niWebViewCreate(void) {
	neonRequireRoot("niWebViewCreate");
	return (void *)CFBridgingRetain([[NeonWebView alloc] initWithFrame:NSZeroRect]);
}
