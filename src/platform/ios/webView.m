#import <WebKit/WebKit.h>
#import "component.h"
#include "../native/components.h"
#include <string.h>
#include <stdlib.h>

static NSString *mediaText(const char *text) { return [NSString stringWithUTF8String:text ? text : ""]; }

static NSString *field(NSArray<NSString *> *fields, NSUInteger at) { return at < fields.count ? fields[at] : @""; }

static NSString *jsonString(NSString *text) {
	NSData *data = [NSJSONSerialization dataWithJSONObject:text options:NSJSONWritingFragmentsAllowed error:nil];
	return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"\"\"";
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

@interface NeonWebView : WKWebView <NeonComponentView, WKNavigationDelegate, WKScriptMessageHandler, WKUIDelegate>
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
	neonEmitControl((int)self.tag, 11, data, 0, 0);
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
	neonEmitControl((int)self.tag, 12, request, 0, 0);
	BOOL allow = ![self.neonDecision isEqualToString:@"block"];
	decisionHandler(allow ? WKNavigationActionPolicyAllow : WKNavigationActionPolicyCancel, preferences);
}

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation {
	(void)webView; (void)navigation;
	neonEmitControl((int)self.tag, 10, [self neonNavigation], 0, 0);
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
	(void)webView; (void)navigation;
	neonEmitControl((int)self.tag, 5, [self neonNavigation], 0, 0);
}

- (void)neonFailed:(NSError *)error {
	// RN ignores a navigation cancelled by a newer one or by the policy decision (WebKit 102).
	if ([error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorCancelled) return;
	if ([error.domain isEqualToString:@"WebKitErrorDomain"] && error.code == 102) return;
	NSString *url = error.userInfo[NSURLErrorFailingURLStringErrorKey] ?: self.URL.absoluteString ?: @"";
	neonEmitControl((int)self.tag, 6, [NSString stringWithFormat:@"%ld\x1f%@\x1f%@", (long)error.code, error.localizedDescription ?: @"", url], 0, 0);
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

- (void)neonRelease {
	[self stopLoading];
	self.navigationDelegate = nil;
	[self.configuration.userContentController removeScriptMessageHandlerForName:@"ReactNativeWebView"];
	self.tag = 0;
}
@end

void *niWebViewCreate(void) { return CFBridgingRetain([NeonWebView neonWebView]); }
