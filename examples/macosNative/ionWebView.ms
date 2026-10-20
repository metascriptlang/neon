// WebView in a macOS Ion window: a WKWebView with react-native-webview's ReactNativeWebView script bridge.
//   msc build examples/macosNative/ionWebView.ms --output=out/macosIonWebView
//   out/macosIonWebView            opens the window and logs each load, message and navigation request
//   out/macosIonWebView --check    loads an HTML source, round-trips messages, blocks a navigation, clicks the page
//                                  through AppKit, samples it through WebKit's snapshot, and exits 0 when every
//                                  expectation holds (local history/reload and pending-load disposal too)

import { runNativeWindow, nativeWindowOptions } from "../../src/platform/macos/ion";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import { NeonNode } from "../../src/render/node";
import { createSignal } from "../../src/core/signal";
import { onCleanup } from "../../src/core/cleanup";
import { Show } from "../../src/macros/ui/flow";
import { View } from "../../src/components/primitives";
import {
	WebView, WebViewHandle, WebViewSource, WebViewNavigation, WebViewNavigationEvent,
	WebViewMessageEvent, WebViewErrorEvent, ShouldStartLoadRequest,
} from "../../src/components/webView";
import { harnessIsCheck, harnessClick, harnessSnapshotWeb, harnessWebPixel } from "./harness.h";
import { exit, cwd } from "std/process";
import { exists, mkdir, writeFile } from "std/fs";

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
const [mounted, setMounted] = createSignal(true);
const [source, setSource] = createSignal<WebViewSource>({
	html: PAGE, baseUrl: "https://neon.example/",
});

interface MountEvents {
	callbacks: string[];
	disposed: boolean;
	callbacksAtDisposal: int32;
	navigation: WebViewNavigation;
}

const mounts: MountEvents[] = [];
const requestTypes: string[] = [];
const errors: string[] = [];
let disposeWhenArmed = false;

function Browser(): NeonNode {
	const events: MountEvents = {
		callbacks: [], disposed: false, callbacksAtDisposal: -1,
		navigation: {
			url: "", title: "", loading: false, canGoBack: false, canGoForward: false,
		},
	};
	mounts.push(events);
	onCleanup((): void => {
		events.disposed = true;
		events.callbacksAtDisposal = events.callbacks.length as int32;
		console.log(`disposed after ${events.callbacksAtDisposal} callbacks`);
	});
	return <WebView style={styles.web} source={source()}
			originWhitelist={["https://*", "file://*"]}
			ref={(h: WebViewHandle): void => { handle = h; }}
			onLoadStart={(e: WebViewNavigationEvent): void => {
				events.callbacks.push("start:" + e.nativeEvent.url);
				starts.push(e.nativeEvent.url);
			}}
			onLoad={(e: WebViewNavigationEvent): void => {
				events.callbacks.push("load:" + e.nativeEvent.url);
				loads.push(`${e.nativeEvent.url} ${e.nativeEvent.title}`);
				console.log(`load ${e.nativeEvent.url} "${e.nativeEvent.title}"`);
			}}
			onLoadEnd={(e: WebViewNavigationEvent): void => {
				events.callbacks.push("end:" + e.nativeEvent.url);
			}}
			onError={(e: WebViewErrorEvent): void => {
				events.callbacks.push("error:" + e.nativeEvent.description);
				errors.push(e.nativeEvent.description);
			}}
			onNavigationStateChange={(navigation: WebViewNavigation): void => {
				events.callbacks.push("navigation:" + navigation.url);
				events.navigation = navigation;
			}}
			onMessage={(e: WebViewMessageEvent): void => {
				events.callbacks.push("message:" + e.nativeEvent.data);
				messages.push(e.nativeEvent.data);
				console.log(`message "${e.nativeEvent.data}"`);
				if (disposeWhenArmed && e.nativeEvent.data === "pending:armed") {
					setMounted(false);
				}
			}}
			onShouldStartLoadWithRequest={(r: ShouldStartLoadRequest): boolean => {
				events.callbacks.push("request:" + r.url);
				requests.push(r.url);
				requestTypes.push(r.navigationType);
				console.log(`request ${r.url} ${r.navigationType}`);
				return r.url.indexOf("blocked") < 0;
			}} />;
}

function App(): NeonNode {
	return <View style={styles.base}>
		<Show when={mounted()}><Browser /></Show>
	</View>;
}

function localPages(): string {
	const out = cwd() + "/out";
	if (!exists(out)) {
		const created = mkdir(out);
		if (!created.ok) { throw new Error("cannot create WebView fixture output directory"); }
	}
	const directory = out + "/macosWebView-" + Date.now().toString();
	const created = mkdir(directory);
	if (!created.ok) { throw new Error("cannot create WebView fixture page directory"); }
	for (const name of ["a", "b", "pending"]) {
		const script = name === "pending" ? `
window.ReactNativeWebView.postMessage("pending:armed");
setTimeout(function () { window.ReactNativeWebView.postMessage("pending:late"); }, 1800);
var until = Date.now() + 1200;
while (Date.now() < until) {}` :
			`window.ReactNativeWebView.postMessage("local:${name}");`;
		const page = `<!doctype html><html><head><title>Local ${name}</title></head>
<body><script>${script}</script></body></html>`;
		const written = writeFile(directory + "/" + name + ".html", page);
		if (!written.ok) { throw new Error("cannot write WebView fixture page " + name); }
	}
	return "file://" + directory + "/";
}

const TITLE = "Neon web view on Ion";
const check = harnessIsCheck() !== 0;
let failures = 0;
let checks = 0;
const local = check ? localPages() : "";
let loadsBeforeCommand: int32 = 0;
let messagesBeforeCommand: int32 = 0;
let staleHandle: WebViewHandle | null = null;
let pendingLoadsBeforeDisposal: int32 = 0;

function expect(what: string, ok: boolean, detail: string): void {
	checks += 1;
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

const steps: ((expired: boolean) => boolean)[] = [];

function run(at: int32, tries: int32 = 0): void {
	if (at >= steps.length || failures > 0) {
		console.log(`checks ${checks}, failures ${failures}`);
		exit(failures);
		return;
	}
	if (!steps[at](tries >= 40)) {
		if (tries >= 40) { throw new Error(`WebView check step ${at} ignored its deadline`); }
		setTimeout((): void => { run(at, tries + 1); }, 100);
		return;
	}
	setTimeout((): void => { run(at + 1); }, 700);
}

steps.push((expired: boolean): boolean => {
	if (!expired && (loads.length < 1 || messages.indexOf("ready") < 0)) { return false; }
	expect("the page started and loaded", starts.length === 1 && loads.length === 1, `${starts.join(",")} / ${loads.join(",")}`);
	expect("the load reports the base url", loads.length > 0 && loads[0].startsWith("https://neon.example/ "), loads.join(","));
	expect("the page's own message arrived", messages.indexOf("ready") >= 0, messages.join(","));
	expect("the first navigation was asked", requests.length > 0 && requests[0] === "https://neon.example/", requests.join(","));
	web().postMessage("hi");
	web().injectJavaScript("window.ReactNativeWebView.postMessage('title:' + document.title)");
	harnessSnapshotWeb(TITLE);
	return true;
});
steps.push((expired: boolean): boolean => {
	if (!expired && (messages.indexOf("echo:hi") < 0 ||
		messages.indexOf("title:Neon page") < 0 || harnessWebPixel(50, 50) < 0)) {
		return false;
	}
	expect("postMessage reaches the page and comes back", messages.indexOf("echo:hi") >= 0, messages.join(","));
	expect("injectJavaScript runs in the page", messages.indexOf("title:Neon page") >= 0, messages.join(","));
	expect("the page draws its background", near(harnessWebPixel(50, 50), 0x27ae60), hex(harnessWebPixel(50, 50)));
	expect("the page draws its element", near(harnessWebPixel(240, 150), 0x2e86de), hex(harnessWebPixel(240, 150)));
	web().injectJavaScript("location.href = 'https://blocked.example/away'");
	return true;
});
steps.push((expired: boolean): boolean => {
	if (!expired && requests.indexOf("https://blocked.example/away") < 0) { return false; }
	expect("the navigation was asked", requests.indexOf("https://blocked.example/away") >= 0, requests.join(","));
	expect("a refused navigation never loads", loads.length === 1 && starts.length === 1, `${starts.length} starts, ${loads.length} loads`);
	harnessClick(TITLE, 20 + 240, 20 + 150);
	return true;
});
steps.push((expired: boolean): boolean => {
	if (!expired && messages.indexOf("clicked") < 0) { return false; }
	expect("a click reaches the page", messages.indexOf("clicked") >= 0, messages.join(","));
	loadsBeforeCommand = loads.length as int32;
	setSource({ uri: local + "a.html" });
	return true;
});
steps.push((expired: boolean): boolean => {
	const state = mounts[0].navigation;
	if (!expired && (state.url !== local + "a.html" || state.loading)) { return false; }
	expect("source replacement loads a local URI", loads.length === loadsBeforeCommand + 1 &&
		state.url === local + "a.html" && messages.indexOf("local:a") >= 0, loads.join(","));
	web().injectJavaScript("location.href = 'b.html'");
	return true;
});
steps.push((expired: boolean): boolean => {
	const state = mounts[0].navigation;
	if (!expired && (state.url !== local + "b.html" || state.loading)) { return false; }
	expect("local navigation creates back history", state.url === local + "b.html" &&
		state.canGoBack && messages.indexOf("local:b") >= 0, state.url);
	web().goBack();
	return true;
});
steps.push((expired: boolean): boolean => {
	const state = mounts[0].navigation;
	if (!expired && (state.url !== local + "a.html" || state.loading)) { return false; }
	expect("goBack restores local A and forward history", state.url === local + "a.html" &&
		state.canGoForward, state.url);
	web().goForward();
	return true;
});
steps.push((expired: boolean): boolean => {
	const state = mounts[0].navigation;
	if (!expired && (state.url !== local + "b.html" || state.loading)) { return false; }
	expect("goForward restores local B", state.url === local + "b.html" &&
		!state.canGoForward, state.url);
	loadsBeforeCommand = loads.length as int32;
	messagesBeforeCommand = messages.length as int32;
	web().reload();
	return true;
});
steps.push((expired: boolean): boolean => {
	if (!expired && (loads.length <= loadsBeforeCommand ||
		messages.length <= messagesBeforeCommand)) { return false; }
	expect("reload completes one new local load", loads.length === loadsBeforeCommand + 1 &&
		mounts[0].navigation.url === local + "b.html", loads.join(","));
	expect("reload reruns page script", messages.length === messagesBeforeCommand + 1 &&
		messages[messages.length - 1] === "local:b", messages.join(","));
	expect("reload uses the synchronous policy wire", requestTypes[requestTypes.length - 1] ===
		"reload", requestTypes.join(","));
	setSource({ uri: local + "pending.html" });
	return true;
});
steps.push((expired: boolean): boolean => {
	if (!expired && (messages.indexOf("pending:late") < 0 ||
		mounts[0].navigation.loading)) { return false; }
	expect("armed local page finishes while mounted", mounts[0].navigation.url ===
		local + "pending.html" && !mounts[0].navigation.loading, loads.join(","));
	expect("armed page delivers its delayed message while mounted",
		messages.indexOf("pending:armed") >= 0 && messages.indexOf("pending:late") >= 0,
		messages.join(","));
	setSource({ uri: local + "b.html" });
	return true;
});
steps.push((expired: boolean): boolean => {
	if (!expired && (mounts[0].navigation.url !== local + "b.html" ||
		mounts[0].navigation.loading)) { return false; }
	expect("replacement leaves pending page", mounts[0].navigation.url === local + "b.html",
		mounts[0].navigation.url);
	staleHandle = web();
	disposeWhenArmed = true;
	pendingLoadsBeforeDisposal = loads.length as int32;
	setSource({ uri: local + "pending.html" });
	return true;
});
steps.push((expired: boolean): boolean => {
	if (!expired && !mounts[0].disposed) { return false; }
	expect("armed message disposes old owner before load completes", mounts[0].disposed &&
		loads.length === pendingLoadsBeforeDisposal,
		`${mounts[0].disposed}, ${loads.length} loads`);
	let refused = false;
	try { (staleHandle as WebViewHandle).reload(); }
	catch (error) {
		refused = error.message === "WebView.reload was called while the WebView is not mounted";
	}
	expect("disposed handle refuses commands", refused, `${refused}`);
	setSource({ html: PAGE, baseUrl: "https://neon.example/" });
	setMounted(true);
	return true;
});
steps.push((expired: boolean): boolean => true);
steps.push((expired: boolean): boolean => true);
steps.push((expired: boolean): boolean => {
	if (!expired && (mounts.length < 2 ||
		mounts[1].callbacks.indexOf("message:ready") < 0)) { return false; }
	const old = mounts[0];
	expect("pending callbacks cannot reach disposed handlers", old.callbacks.length ===
		old.callbacksAtDisposal, `${old.callbacksAtDisposal} -> ${old.callbacks.length}`);
	expect("remount owns independent callbacks and history", mounts.length === 2 &&
		!mounts[1].disposed && !mounts[1].navigation.canGoBack &&
		!mounts[1].navigation.canGoForward &&
		mounts[1].navigation.url === "https://neon.example/" &&
		mounts[1].callbacks.indexOf("message:ready") >= 0 &&
		mounts[1].callbacks.indexOf("message:pending:armed") < 0 &&
		mounts[1].callbacks.indexOf("message:pending:late") < 0,
		`${mounts.length} mounts`);
	web().postMessage("remount");
	return true;
});
steps.push((expired: boolean): boolean => {
	if (!expired && mounts.length === 2 &&
		mounts[1].callbacks.indexOf("message:echo:remount") < 0) { return false; }
	expect("remounted bridge receives its own message", mounts.length === 2 &&
		mounts[1].callbacks.indexOf("message:echo:remount") >= 0 &&
		mounts[0].callbacks.indexOf("message:echo:remount") < 0, messages.join(","));
	expect("local fixture has no unexpected load errors", errors.length === 0, errors.join(","));
	return true;
});

const options = nativeWindowOptions(TITLE, 480, 320);
options.topmost = check;
exit(runNativeWindow(options, App, check ? (): void => {
	setTimeout((): void => { run(0); }, 1500);
} : null));
