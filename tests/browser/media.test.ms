import { domHost, documentBody } from "../../src/platform/browser/dom";
import { render } from "../../src/render/host";
import { View } from "../../src/components/primitives";
import {
	WebView,
	WebViewHandle,
	WebViewNavigation,
	WebViewNavigationEvent,
	WebViewMessageEvent,
	ShouldStartLoadRequest,
} from "../../src/components/webView";
import { Video, VideoHandle, OnLoadData, OnProgressData } from "../../src/components/video";
import { CLIP_MP4 } from "../../examples/media/clip";
import { sleepAsync } from "std/core/promise";

extern function js(code: cstring): string from "String((0, eval)(#))";

async function waitFor(what: string, ready: () => boolean, ms: number): Promise<void> {
	const end = performance.now() + ms;
	while (!ready()) {
		if (performance.now() > end) { throw new Error("timed out waiting for " + what); }
		await sleepAsync(20);
	}
}

const PAGE = "<title>Local</title><p id=t>local page</p>" +
	"<a id=blocked href=\"https://blocked.invalid/\">blocked</a>" +
	"<a id=next href=\"__NEXT__\">next</a>" +
	"<script>window.addEventListener('message', function (e) { window.ReactNativeWebView.postMessage('echo:' + e.data); });" +
	"window.ReactNativeWebView.postMessage('ready:' + document.title);</script>";

test "an iframe WebView: local html talks to the app both ways, a link asks first, and back returns to the html" {
	const next = js("location.origin") + "/examples/media/assets/next.html";
	let messages: string[] = [];
	let asked: string[] = [];
	let loads: string[] = [];
	let nav: WebViewNavigation | null = null;
	let handle: WebViewHandle | null = null;
	render(<View style={{ width: 400, height: 300 }}>
		<WebView
			source={{ html: PAGE.replace("__NEXT__", next) }}
			ref={(h: WebViewHandle): void => { handle = h; }}
			onLoad={(e: WebViewNavigationEvent): void => { loads.push(e.nativeEvent.url); }}
			onMessage={(e: WebViewMessageEvent): void => { messages.push(e.nativeEvent.data); }}
			onNavigationStateChange={(n: WebViewNavigation): void => { nav = n; }}
			onShouldStartLoadWithRequest={(r: ShouldStartLoadRequest): boolean => {
				asked.push(r.url);
				return r.url.indexOf("blocked") < 0;
			}}
		/>
	</View>, domHost(), documentBody());
	await waitFor("the page's ready message", (): boolean => messages.length > 0, 5000);
	assert messages[0] === "ready:Local", messages.join(",");
	await waitFor("the first load", (): boolean => loads.length > 0, 5000);
	assert loads[0] === "about:blank" && !(nav as WebViewNavigation).canGoBack, loads.join(",");
	const h = handle as WebViewHandle;
	h.postMessage("ping");
	await waitFor("the echo", (): boolean => messages.length > 1, 5000);
	assert messages[1] === "echo:ping", messages.join(",");
	h.injectJavaScript("window.ReactNativeWebView.postMessage(document.getElementById('t').textContent)");
	await waitFor("the injected script's message", (): boolean => messages.length > 2, 5000);
	assert messages[2] === "local page", messages.join(",");
	h.injectJavaScript("document.getElementById('blocked').click()");
	await waitFor("the blocked request", (): boolean => asked.length > 0, 5000);
	await sleepAsync(300);
	assert asked[0] === "https://blocked.invalid/" && loads.length === 1, "refused: " + asked.join(",") + " loads " + loads.join(",");
	h.injectJavaScript("document.getElementById('next').click()");
	await waitFor("the next page", (): boolean => loads.length > 1, 5000);
	assert asked[1] === next && loads[1] === next, "allowed: " + loads.join(",");
	assert (nav as WebViewNavigation).canGoBack && !(nav as WebViewNavigation).canGoForward, "back is possible";
	h.goBack();
	await waitFor("the way back", (): boolean => loads.length > 2, 5000);
	assert loads[2] === "about:blank" && (nav as WebViewNavigation).canGoForward && !(nav as WebViewNavigation).canGoBack, "back: " + loads.join(",");
	h.goForward();
	await waitFor("the way forward", (): boolean => loads.length > 3, 5000);
	assert loads[3] === next, "forward: " + loads.join(",");
}

test "a <video> Video loads the bundled clip, reports progress, seeks, and ends" {
	let loaded: OnLoadData | null = null;
	let times: number[] = [];
	let ended = 0;
	let handle: VideoHandle | null = null;
	render(<View>
		<Video
			source={{ uri: CLIP_MP4 }}
			muted={true}
			progressUpdateInterval={100}
			style={{ width: 320, height: 180 }}
			ref={(h: VideoHandle): void => { handle = h; }}
			onLoad={(d: OnLoadData): void => { loaded = d; }}
			onProgress={(d: OnProgressData): void => { times.push(d.currentTime); }}
			onEnd={(): void => { ended += 1; }}
		/>
	</View>, domHost(), documentBody());
	await waitFor("the clip's metadata", (): boolean => loaded !== null, 5000);
	const d = loaded as OnLoadData;
	assert Math.abs(d.duration - 3) < 0.1 && d.naturalSize.width === 160 && d.naturalSize.height === 90, `load ${d.duration} ${d.naturalSize.width}x${d.naturalSize.height}`;
	await waitFor("progress", (): boolean => times.length > 2 && times[times.length - 1] > 0.2, 5000);
	(handle as VideoHandle).seek(2.5);
	await waitFor("the end", (): boolean => ended > 0, 5000);
	assert times[times.length - 1] >= 2.5, "progress after the seek: " + times.join(",");
	assert js("document.querySelector('video').getAttribute('playsinline')") === "", "inline on iOS Safari";
}
