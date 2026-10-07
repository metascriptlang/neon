import { createSignal } from "../../src/core/signal";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import { Show } from "../../src/macros/ui/flow";
import { NeonNode } from "../../src/render/node";
import { View, Text, Pressable } from "../../src/components/primitives";
import {
	WebView,
	WebViewHandle,
	WebViewNavigation,
	WebViewMessageEvent,
	WebViewErrorEvent,
	ShouldStartLoadRequest,
} from "../../src/components/webView";
import { Video, VideoHandle, OnLoadData, OnProgressData } from "../../src/components/video";
import { CLIP_MP4 } from "./clip";

const styles = createStyles({
	screen: { flex: 1, backgroundColor: "#11111b" },
	top: { paddingTop: 48, paddingLeft: 12, paddingRight: 12, paddingBottom: 8, gap: 6, backgroundColor: "#1e1e2e" },
	title: { color: "#cdd6f4", fontSize: 20, fontWeight: "bold" },
	status: { color: "#89b4fa", fontSize: 15 },
	row: { flexDirection: "row", flexWrap: "wrap", gap: 6 },
	tab: { paddingTop: 8, paddingBottom: 8, paddingLeft: 10, paddingRight: 10, backgroundColor: "#45475a", color: "#cdd6f4", borderRadius: 6 },
	button: { paddingTop: 8, paddingBottom: 8, paddingLeft: 12, paddingRight: 12, backgroundColor: "#89b4fa", color: "#11111b", borderRadius: 6 },
	body: { flex: 1, padding: 8, gap: 8 },
	web: { flex: 1 },
	video: { width: 320, height: 180, alignSelf: "center" },
});

const PAGE = "<!doctype html><html><head><meta name=viewport content='width=device-width'>" +
	"<title>Neon bridge</title><style>body{font:18px system-ui;padding:16px}button{font-size:18px;padding:8px}</style></head>" +
	"<body><h1>Local page</h1><p id=inbox>no message yet</p>" +
	"<button id=send onclick=\"window.ReactNativeWebView.postMessage('hello from the page')\">Send to app</button>" +
	"<script>" +
	"window.addEventListener('message', function (e) {" +
	" document.getElementById('inbox').textContent = 'got ' + e.data;" +
	" window.ReactNativeWebView.postMessage('page got ' + e.data); });" +
	"window.ReactNativeWebView.postMessage('page ready');" +
	"</script></body></html>";

interface ScreenProps {
	say: (s: string) => void;
}

function BridgeScreen(props: ScreenProps): NeonNode {
	let web: WebViewHandle | null = null;
	const say = props.say;
	return <View style={styles.body}>
		<View style={styles.row}>
			<Pressable style={styles.button} onPress={() => { (web as WebViewHandle).postMessage("hello from the app"); }}>send to page</Pressable>
			<Pressable style={styles.button} onPress={() => {
				(web as WebViewHandle).injectJavaScript("window.ReactNativeWebView.postMessage('title ' + document.title)");
			}}>inject</Pressable>
		</View>
		<WebView
			style={styles.web}
			source={{ html: PAGE }}
			ref={(h: WebViewHandle): void => { web = h; }}
			onMessage={(e: WebViewMessageEvent): void => { say(e.nativeEvent.data); }}
		/>
	</View>;
}

function BrowserScreen(props: ScreenProps): NeonNode {
	let web: WebViewHandle | null = null;
	const say = props.say;
	const [back, setBack] = createSignal(false);
	return <View style={styles.body}>
		<View style={styles.row}>
			<Pressable style={styles.button} onPress={() => { (web as WebViewHandle).goBack(); }}>back</Pressable>
			<Pressable style={styles.button} onPress={() => { (web as WebViewHandle).goForward(); }}>forward</Pressable>
			<Pressable style={styles.button} onPress={() => { (web as WebViewHandle).reload(); }}>reload</Pressable>
			<Pressable style={styles.button} onPress={() => {
				(web as WebViewHandle).injectJavaScript("location.href = 'https://example.org/'");
			}}>next site</Pressable>
			<Text style={styles.status}>{back() ? "can go back" : "first page"}</Text>
		</View>
		<WebView
			style={styles.web}
			source={{ uri: "https://example.com/" }}
			ref={(h: WebViewHandle): void => { web = h; }}
			onNavigationStateChange={(n: WebViewNavigation): void => {
				setBack(n.canGoBack);
				if (!n.loading) { say("loaded " + n.url); }
			}}
			onShouldStartLoadWithRequest={(r: ShouldStartLoadRequest): boolean => r.url.indexOf("blocked") < 0}
			onError={(e: WebViewErrorEvent): void => { say("error " + e.nativeEvent.description); }}
		/>
	</View>;
}

function tenths(seconds: float64): string {
	return (Math.round(seconds * 10) / 10).toString();
}

function VideoScreen(props: ScreenProps): NeonNode {
	let video: VideoHandle | null = null;
	const say = props.say;
	const [paused, setPaused] = createSignal(true);
	const [time, setTime] = createSignal("0");
	return <View style={styles.body}>
		<Video
			style={styles.video}
			source={{ uri: CLIP_MP4 }}
			paused={paused()}
			resizeMode="contain"
			progressUpdateInterval={200}
			ref={(h: VideoHandle): void => { video = h; }}
			onLoad={(d: OnLoadData): void => { say(`video ${tenths(d.duration)}s ${d.naturalSize.width}x${d.naturalSize.height}`); }}
			onProgress={(d: OnProgressData): void => { setTime(tenths(d.currentTime)); }}
			onEnd={(): void => {
				setPaused(true);
				say("video ended");
			}}
		/>
		<Text style={styles.status}>{"time " + time()}</Text>
		<View style={styles.row}>
			<Pressable style={styles.button} onPress={() => { setPaused(!paused()); say(paused() ? "paused" : "playing"); }}>{paused() ? "play" : "pause"}</Pressable>
			<Pressable style={styles.button} onPress={() => { (video as VideoHandle).seek(2); }}>seek 2</Pressable>
			<Pressable style={styles.button} onPress={() => { (video as VideoHandle).seek(0); }}>restart</Pressable>
		</View>
	</View>;
}

export function MediaApp(): NeonNode {
	const [screen, setScreen] = createSignal<int32>(0);
	const [status, setStatus] = createSignal("ready");
	const say = (s: string): void => { setStatus(s); };
	return <View style={styles.screen}>
		<View style={styles.top}>
			<Text style={styles.title}>Neon media</Text>
			<Text style={styles.status}>{"status " + status()}</Text>
			<View style={styles.row}>
				<Pressable style={styles.tab} onPress={() => { setScreen(0); say("bridge"); }}>bridge</Pressable>
				<Pressable style={styles.tab} onPress={() => { setScreen(1); say("browser"); }}>browser</Pressable>
				<Pressable style={styles.tab} onPress={() => { setScreen(2); say("video"); }}>video</Pressable>
			</View>
		</View>
		<Show when={screen() === 0}><BridgeScreen say={say} /></Show>
		<Show when={screen() === 1}><BrowserScreen say={say} /></Show>
		<Show when={screen() === 2}><VideoScreen say={say} /></Show>
	</View>;
}
