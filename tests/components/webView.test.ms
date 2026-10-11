import { createSignal } from "../../src/core/signal";
import { HostNode, MockNode, mockNode, mockHost, render, mockToString, fireEventWith } from "../../src/render/host";
import { neonEvent } from "../../src/render/event";
import { Style } from "../../src/render/style";
import {
	WebView,
	WebViewHandle,
	WebViewNavigation,
	WebViewNavigationEvent,
	WebViewMessageEvent,
	WebViewErrorEvent,
	ShouldStartLoadRequest,
	originOf,
	passesWhitelist,
} from "../../src/components/webView";

function attrOf(n: MockNode, name: string): string {
	for (const a of n.attrs) {
		if (a.name === name) { return a.value ?? ""; }
	}
	return "<unset>";
}

function fire(n: MockNode, name: string, value: string): void {
	const e = neonEvent(name);
	e.value = value;
	fireEventWith(n, name, e);
}

test "originOf keeps scheme and authority the way RN's extractOrigin regex does" {
	assert originOf("https://example.com/a/b?c") === "https://example.com", originOf("https://example.com/a/b?c");
	assert originOf("about:blank") === "about:blank", originOf("about:blank");
	assert originOf("mailto:a@b.c") === "mailto:a@b.c", originOf("mailto:a@b.c");
	assert originOf("/relative") === "", "a relative url has no origin";
	assert originOf("x:") === "", "a one-letter scheme does not match the regex";
}

test "passesWhitelist matches each entry as a prefix glob of the origin, with about:blank always allowed" {
	const web: string[] = ["http://*", "https://*"];
	assert passesWhitelist(web, "https://example.com/x");
	assert passesWhitelist(web, "about:blank");
	assert !passesWhitelist(web, "tel:123");
	assert passesWhitelist(["*"], "tel:123");
	assert passesWhitelist(["https://*.neon.dev"], "https://docs.neon.dev/a");
	assert !passesWhitelist(["https://*.neon.dev"], "https://neon.dev/a");
}

test "a WebView writes its source to the wire and fills its parent by default" {
	const [page, setPage] = createSignal("https://example.com");
	const root: MockNode = mockNode("root");
	render(<WebView source={{ uri: page() }} javaScriptEnabled={false} />, mockHost(), root as unknown as HostNode);
	const view = root.children[0];
	assert view.tag === "webview", mockToString(root);
	assert attrOf(view, "source") === "uri\x1fhttps://example.com", attrOf(view, "source");
	assert attrOf(view, "javaScriptEnabled") === "false" && attrOf(view, "interceptLoads") === "true", mockToString(root);
	assert (view.style as Style).flexGrow === 1, "fills its parent";
	setPage("https://neon.dev");
	assert attrOf(view, "source") === "uri\x1fhttps://neon.dev", attrOf(view, "source");
}

test "an html source carries its baseUrl" {
	const root: MockNode = mockNode("root");
	render(<WebView source={{ html: "<p>hi</p>", baseUrl: "https://neon.dev/" }} />, mockHost(), root as unknown as HostNode);
	assert attrOf(root.children[0], "source") === "html\x1f<p>hi</p>\x1fhttps://neon.dev/", attrOf(root.children[0], "source");
}

test "page events reach RN's callbacks with nativeEvent and the navigation state" {
	let seen = "";
	const root: MockNode = mockNode("root");
	render(<WebView
		source={{ uri: "https://example.com" }}
		injectedJavaScript="document.title"
		onLoadStart={(e: WebViewNavigationEvent): void => { seen += `start ${e.nativeEvent.url} ${e.nativeEvent.loading};`; }}
		onLoad={(e: WebViewNavigationEvent): void => { seen += `load ${e.nativeEvent.title};`; }}
		onLoadEnd={(e: WebViewNavigationEvent): void => { seen += `end ${e.nativeEvent.canGoBack};`; }}
		onError={(e: WebViewErrorEvent): void => { seen += `error ${e.nativeEvent.code} ${e.nativeEvent.description} ${e.nativeEvent.url};`; }}
		onMessage={(e: WebViewMessageEvent): void => { seen += `message ${e.nativeEvent.data} at ${e.nativeEvent.url};`; }}
		onNavigationStateChange={(n: WebViewNavigation): void => { seen += `nav ${n.url} ${n.canGoBack};`; }}
	/>, mockHost(), root as unknown as HostNode);
	const view = root.children[0];
	fire(view, "onLoadStart", "https://example.com/\x1f\x1ftrue\x1ffalse\x1ffalse");
	fire(view, "onLoad", "https://example.com/\x1fExample\x1ffalse\x1ftrue\x1ffalse");
	assert attrOf(view, "command") === "injectJavaScript\x1fdocument.title", "injectedJavaScript runs after the load: " + attrOf(view, "command");
	fire(view, "onMessage", "hello");
	fire(view, "onError", "-1003\x1fhost not found\x1fhttps://nowhere.invalid/");
	const expected = "start https://example.com/ true;nav https://example.com/ false;" +
		"load Example;end true;nav https://example.com/ true;" +
		"message hello at https://example.com/;" +
		"end true;error -1003 host not found https://nowhere.invalid/;";
	assert seen === expected, seen;
}

test "onShouldStartLoadWithRequest answers synchronously through loadDecision, after the origin whitelist" {
	let asked = "";
	const root: MockNode = mockNode("root");
	render(<WebView
		source={{ uri: "https://example.com" }}
		originWhitelist={["https://*"]}
		onShouldStartLoadWithRequest={(r: ShouldStartLoadRequest): boolean => {
			asked += `${r.url} ${r.navigationType} ${r.isTopFrame};`;
			return r.url.indexOf("blocked") < 0;
		}}
	/>, mockHost(), root as unknown as HostNode);
	const view = root.children[0];
	fire(view, "onShouldStartLoad", "https://example.com/ok\x1fclick\x1ftrue");
	assert attrOf(view, "loadDecision") === "allow", attrOf(view, "loadDecision");
	fire(view, "onShouldStartLoad", "https://example.com/blocked\x1fclick\x1ftrue");
	assert attrOf(view, "loadDecision") === "block", attrOf(view, "loadDecision");
	fire(view, "onShouldStartLoad", "http://example.com/plain\x1fother\x1ftrue");
	assert attrOf(view, "loadDecision") === "block", "outside the whitelist: " + attrOf(view, "loadDecision");
	assert asked === "https://example.com/ok click true;https://example.com/blocked click true;", "the handler sees only whitelisted urls: " + asked;
}

test "the ref's methods are commands on the node, and refuse once the WebView unmounted" {
	let handle: WebViewHandle | null = null;
	const [shown, setShown] = createSignal(true);
	const root: MockNode = mockNode("root");
	render(<view>{shown() ? <WebView source={{ uri: "https://example.com" }} ref={(h: WebViewHandle): void => { handle = h; }} /> : null}</view>, mockHost(), root as unknown as HostNode);
	const view = root.children[0].children[0];
	const h = handle as WebViewHandle;
	h.goBack();
	assert attrOf(view, "command") === "goBack\x1f", attrOf(view, "command");
	h.goForward();
	assert attrOf(view, "command") === "goForward\x1f", attrOf(view, "command");
	h.reload();
	assert attrOf(view, "command") === "reload\x1f", attrOf(view, "command");
	h.stopLoading();
	assert attrOf(view, "command") === "stopLoading\x1f", attrOf(view, "command");
	h.postMessage("ping");
	assert attrOf(view, "command") === "postMessage\x1fping", attrOf(view, "command");
	h.injectJavaScript("1 + 1");
	assert attrOf(view, "command") === "injectJavaScript\x1f1 + 1", attrOf(view, "command");
	setShown(false);
	let refused = "";
	try {
		h.reload();
	} catch (e) {
		refused = (e as Error).message;
	}
	assert refused === "WebView.reload was called while the WebView is not mounted", refused;
}
