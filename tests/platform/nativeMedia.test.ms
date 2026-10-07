import { runApp } from "../../src/platform/native/host";
import { createSignal } from "../../src/core/signal";
import { View } from "../../src/components/primitives";
import { NeonNode } from "../../src/render/node";
import { WebView, WebViewHandle, WebViewNavigation, WebViewMessageEvent, ShouldStartLoadRequest } from "../../src/components/webView";
import { Video, VideoHandle, OnLoadData, OnProgressData } from "../../src/components/video";
import {
	nmTeardown,
	nmControl,
	nmControlSized,
	nmProp,
	nmLastControlTag,
	nmLayoutWidth,
	nmLayoutHeight,
	nmReleaseCalls,
	nmViewsCreated,
} from "./nativeBridgeMock.h";

function prop(tag: int32, name: string): string {
	return nmProp(tag, name);
}

test "a native WebView is a media view created by name: source, page events, the synchronous load decision and commands" {
	const [page, setPage] = createSignal("https://example.com/");
	let log = "";
	let handle: WebViewHandle | null = null;
	const app = (): NeonNode => <View style={{ width: 300, height: 500 }}>
		<WebView
			source={{ uri: page() }}
			ref={(h: WebViewHandle): void => { handle = h; }}
			onNavigationStateChange={(n: WebViewNavigation): void => { log += `nav ${n.url} ${n.loading} ${n.canGoBack};`; }}
			onMessage={(e: WebViewMessageEvent): void => { log += `message ${e.nativeEvent.data};`; }}
			onShouldStartLoadWithRequest={(r: ShouldStartLoadRequest): boolean => r.url !== "https://example.com/no"}
		/>
	</View>;
	runApp(app);
	const web = nmLastControlTag(10);
	assert prop(web, "source") === "uri\x1fhttps://example.com/" && prop(web, "interceptLoads") === "true", "props";
	assert `${nmLayoutWidth(web)}x${nmLayoutHeight(web)}` === "300x500", "a WebView fills its parent: " + `${nmLayoutWidth(web)}x${nmLayoutHeight(web)}`;
	nmControl(web, 12, "https://example.com/next\x1fclick\x1ftrue");
	assert prop(web, "loadDecision") === "allow", "allowed before the handler returns";
	nmControl(web, 12, "https://example.com/no\x1fclick\x1ftrue");
	assert prop(web, "loadDecision") === "block", "refused before the handler returns";
	nmControl(web, 10, "https://example.com/next\x1f\x1ftrue\x1ftrue\x1ffalse");
	nmControl(web, 5, "https://example.com/next\x1fNext\x1ffalse\x1ftrue\x1ffalse");
	nmControl(web, 11, "from the page");
	assert log === "nav https://example.com/next true true;nav https://example.com/next false true;message from the page;", "events: " + log;
	(handle as WebViewHandle).postMessage("from the app");
	assert prop(web, "command") === "postMessage\x1ffrom the app", prop(web, "command");
	(handle as WebViewHandle).goBack();
	assert prop(web, "command") === "goBack\x1f", prop(web, "command");
	setPage("https://neon.dev/");
	assert prop(web, "source") === "uri\x1fhttps://neon.dev/", "a new source reaches the view";
	nmTeardown();
	assert nmReleaseCalls() === nmViewsCreated(), "media views are released";
}

test "a native Video takes its size from its style, reports load and progress, and seeks by command" {
	const [paused, setPaused] = createSignal(true);
	let log = "";
	let handle: VideoHandle | null = null;
	const app = (): NeonNode => <View style={{ width: 320 }}>
		<Video
			source={{ uri: "https://neon.dev/clip.mp4" }}
			paused={paused()}
			style={{ width: 320, height: 180 }}
			ref={(h: VideoHandle): void => { handle = h; }}
			onLoad={(d: OnLoadData): void => { log += `load ${d.duration} ${d.naturalSize.width}x${d.naturalSize.height};`; }}
			onProgress={(d: OnProgressData): void => { log += `at ${d.currentTime};`; }}
			onEnd={(): void => { log += "end;"; }}
		/>
	</View>;
	runApp(app);
	const video = nmLastControlTag(11);
	assert `${nmLayoutWidth(video)}x${nmLayoutHeight(video)}` === "320x180", "sized by style: " + `${nmLayoutWidth(video)}x${nmLayoutHeight(video)}`;
	assert prop(video, "paused") === "true" && prop(video, "source") === "https://neon.dev/clip.mp4", "props";
	setPaused(false);
	assert prop(video, "paused") === "false", "play";
	nmControlSized(video, 5, "3\x1f0", 160, 90);
	nmControl(video, 13, "1.25\x1f3\x1f3");
	nmControl(video, 14, "");
	assert log === "load 3 160x90;at 1.25;end;", "events: " + log;
	(handle as VideoHandle).seek(2);
	assert prop(video, "command") === "seek\x1f2", prop(video, "command");
	nmTeardown();
	assert nmReleaseCalls() === nmViewsCreated(), "media views are released";
}
