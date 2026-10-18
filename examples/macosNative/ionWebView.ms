// WebView in a macOS Ion window: a WKWebView with react-native-webview's ReactNativeWebView script bridge.
//   msc build examples/macosNative/ionWebView.ms --output=out/macosIonWebView
//   out/macosIonWebView            opens the window and logs each load, message and navigation request
//   out/macosIonWebView --check    loads an HTML source, round-trips messages, blocks a navigation, clicks the page
//                                  through AppKit, samples it through WebKit's snapshot, and exits 0 when every
//                                  expectation holds

import { runNativeWindow, nativeWindowOptions } from "../../src/platform/macos/ion";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import { NeonNode } from "../../src/render/node";
import { View } from "../../src/components/primitives";
import {
	WebView, WebViewHandle, WebViewNavigationEvent, WebViewMessageEvent, ShouldStartLoadRequest,
} from "../../src/components/webView";
import { harnessIsCheck, harnessClick, harnessSnapshotWeb, harnessWebPixel } from "./harness.h";
import { exit } from "std/process";

when (macos) {
	@compile("./harness.m", "-fobjc-arc");
}

const PAGE = `<!doctype html><html><head><title>Neon page</title><style>
html, body { margin: 0; height: 100%; background: #27ae60; }
#button { position: absolute; left: 200px; top: 120px; width: 80px; height: 60px; background: #2e86de; }
</style></head><body><div id="button"></div><script>
window.addEventListener("message", function (e) { window.ReactNativeWebView.postMessage("echo:" + e.data); });
document.getElementById("button").addEventListener("click", function () { window.ReactNativeWebView.postMessage("clicked"); });
window.ReactNativeWebView.postMessage("ready");
</script></body></html>`;

const styles = createStyles({
	base: { width: 480, height: 320, backgroundColor: "#101820" },
	web: { position: "absolute", left: 20, top: 20, width: 300, height: 200, flexGrow: 0 },
});

const starts: string[] = [];
const loads: string[] = [];
const messages: string[] = [];
const requests: string[] = [];
let handle: WebViewHandle | null = null;

function App(): NeonNode {
	return <View style={styles.base}>
		<WebView style={styles.web} source={{ html: PAGE, baseUrl: "https://neon.example/" }}
			ref={(h: WebViewHandle): void => { handle = h; }}
			onLoadStart={(e: WebViewNavigationEvent): void => { starts.push(e.nativeEvent.url); }}
			onLoad={(e: WebViewNavigationEvent): void => {
				loads.push(`${e.nativeEvent.url} ${e.nativeEvent.title}`);
				console.log(`load ${e.nativeEvent.url} "${e.nativeEvent.title}"`);
			}}
			onMessage={(e: WebViewMessageEvent): void => {
				messages.push(e.nativeEvent.data);
				console.log(`message "${e.nativeEvent.data}"`);
			}}
			onShouldStartLoadWithRequest={(r: ShouldStartLoadRequest): boolean => {
				requests.push(r.url);
				console.log(`request ${r.url} ${r.navigationType}`);
				return r.url.indexOf("blocked") < 0;
			}} />
	</View>;
}

const TITLE = "Neon web view on Ion";
const check = harnessIsCheck() !== 0;
let failures = 0;

function expect(what: string, ok: boolean, detail: string): void {
	console.log(`${ok ? "ok  " : "FAIL"} ${what}: ${detail}`);
	if (!ok) { failures += 1; }
}

function web(): WebViewHandle {
	if (handle === null) { throw new Error("the WebView ref never arrived"); }
	return handle as WebViewHandle;
}

function hex(rgb: number): string {
	return rgb < 0 ? "none" : `#${rgb.toString(16)}`;
}

// WebKit's snapshot is colour-managed, so a page colour comes back a few levels off its CSS value.
function near(rgb: number, want: number): boolean {
	if (rgb < 0) { return false; }
	const close = (shift: number): boolean => Math.abs(((rgb >> shift) & 255) - ((want >> shift) & 255)) <= 24;
	return close(16) && close(8) && close(0);
}

const steps: (() => void)[] = [];

function run(at: number): void {
	if (at >= steps.length) {
		console.log(`failures ${failures}`);
		exit(failures);
		return;
	}
	steps[at]();
	setTimeout((): void => { run(at + 1); }, 700);
}

steps.push((): void => {
	expect("the page started and loaded", starts.length === 1 && loads.length === 1, `${starts.join(",")} / ${loads.join(",")}`);
	expect("the load reports the base url", loads.length > 0 && loads[0].startsWith("https://neon.example/ "), loads.join(","));
	expect("the page's own message arrived", messages.indexOf("ready") >= 0, messages.join(","));
	expect("the first navigation was asked", requests.length > 0 && requests[0] === "https://neon.example/", requests.join(","));
	web().postMessage("hi");
	web().injectJavaScript("window.ReactNativeWebView.postMessage('title:' + document.title)");
	harnessSnapshotWeb(TITLE);
});
steps.push((): void => {
	expect("postMessage reaches the page and comes back", messages.indexOf("echo:hi") >= 0, messages.join(","));
	expect("injectJavaScript runs in the page", messages.indexOf("title:Neon page") >= 0, messages.join(","));
	expect("the page draws its background", near(harnessWebPixel(50, 50), 0x27ae60), hex(harnessWebPixel(50, 50)));
	expect("the page draws its element", near(harnessWebPixel(240, 150), 0x2e86de), hex(harnessWebPixel(240, 150)));
	web().injectJavaScript("location.href = 'https://blocked.example/away'");
});
steps.push((): void => {
	expect("the navigation was asked", requests.indexOf("https://blocked.example/away") >= 0, requests.join(","));
	expect("a refused navigation never loads", loads.length === 1 && starts.length === 1, `${starts.length} starts, ${loads.length} loads`);
	harnessClick(TITLE, 20 + 240, 20 + 150);
});
steps.push((): void => {
	expect("a click reaches the page", messages.indexOf("clicked") >= 0, messages.join(","));
});

const options = nativeWindowOptions(TITLE, 480, 320);
options.topmost = check;
exit(runNativeWindow(options, App, check ? (): void => {
	setTimeout((): void => { run(0); }, 1500);
} : null));
