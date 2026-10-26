import { HostNode, NeonNode } from "../../src/render/hostTypes";
import { NeonEvent } from "../../src/render/event";
import { View, Text, Pressable, ScrollView, TextInput } from "../../src/components/primitives";
import { Switch } from "../../src/components/switch";
import { ActivityIndicator } from "../../src/components/activityIndicator";
import { Image } from "../../src/components/image";
import { Modal } from "../../src/components/modal";
import { Video, OnLoadData, VideoResizeMode } from "../../src/components/video";
import { WebView, WebViewMessageEvent, WebViewNavigationEvent } from "../../src/components/webView";
import { CameraView, CameraType, CameraMountError } from "../../src/components/cameraView";
import { CLIP_MP4 } from "../../examples/media/clip";
import { Svg, Circle, G, Defs, LinearGradient, Stop, Rect } from "../../src/components/svg/elements";
import { Head } from "../../src/render/head";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import { createBreakpoints } from "../../src/render/breakpoints";
import { createSignal, Accessor } from "../../src/core/signal";
import { el, text } from "../../src/render/node";
import { createComponent } from "../../src/render/component";
import { lazyModule } from "../../src/render/lazy";
import { lazy } from "../../src/macros/lazy";
import { Loading } from "../../src/macros/ui/flow";

export const styles = createStyles({ box: { padding: 8 }, label: { color: "#334" } });

export const screen = createBreakpoints({ wide: 900 });
export const columns = createStyles({
	side: { width: "100%", height: 10, when: { [screen.wide]: { width: 280 } } },
});

export function breakpointsApp(): NeonNode {
	return <div id="side" style={columns.side}></div>;
}

when (js) {
	export extern function servedPart(name: cstring, part: cstring): string from
		"((n, p) => { const s = globalThis.neonServed?.[n]; if (s === undefined) { throw new Error('no server page named ' + n + ': tests/browser/run.sh renders them from tests/browser/serveApps.ms'); } return s[p]; })(#, #)";
}

export function docs(
	name: Accessor<string>,
	blank: Accessor<string>,
	open: Accessor<boolean>,
	rows: Accessor<string[]>,
	press: (e: NeonEvent) => void,
	mech: (n: HostNode) => void,
): NeonNode {
	return <View accessibilityLabel="Docs" style={styles.box}>
		<Text style={styles.label}>Hi {name()}</Text>
		<Text>{blank()}</Text>
		<Pressable accessibilityLabel="Copy" accessibilityState={{ selected: open() }} onPress={press}><Text>copy</Text></Pressable>
		<Show when={open()}><p id="shown">shown</p></Show>
		<For each={rows()}>{(row: string, i: Accessor<number>): NeonNode => <span class="row">{row}</span>}</For>
		<canvas id="mech" ref={mech}></canvas>
		<a href="/docs" title={name()}>docs &amp; more</a>
	</View>;
}

export function docsAtStart(): NeonNode {
	const [name, _name] = createSignal("Ann");
	const [blank, _blank] = createSignal("");
	const [open, _open] = createSignal(true);
	const [rows, _rows] = createSignal<string[]>(["a", "b", "c"]);
	return docs(name, blank, open, rows, (e: NeonEvent): void => {}, (node: HostNode): void => {});
}

export function scrollApp(onScroll: (e: NeonEvent) => void): NeonNode {
	return <View>
		<ScrollView horizontal={true} showsHorizontalScrollIndicator={false} onScroll={onScroll}>
			<Text>row</Text>
		</ScrollView>
	</View>;
}

export function clampedApp(): NeonNode {
	return <View><Text numberOfLines={3}>long</Text></View>;
}

export function switchApp(on: Accessor<boolean>, onValueChange: (v: boolean) => void): NeonNode {
	return <View>
		<Switch value={on()} onValueChange={onValueChange} />
		<ActivityIndicator animating={on()} color="#c00" />
	</View>;
}

export function switchAppOn(): NeonNode {
	const [on, _on] = createSignal(true);
	return switchApp(on, (v: boolean): void => {});
}

export function textareaApp(onChangeText: (t: string) => void): NeonNode {
	return <View>
		<TextInput multiline={true} defaultValue="note" onChangeText={onChangeText} />
	</View>;
}

export function plainTextareaApp(): NeonNode {
	return <View><TextInput multiline={true} defaultValue="note" /></View>;
}

export function HeadPage(props: { title: Accessor<string> }): NeonNode {
	return <View>
		<Head>
			<title>{props.title()}</title>
			<meta name="description" content="about this page" />
		</Head>
		<Text>body</Text>
	</View>;
}

export function headPageAtStart(): NeonNode {
	const [title, _title] = createSignal("Docs");
	return <HeadPage title={title} />;
}

export function primitivesApp(): NeonNode {
	return <View accessibilityLabel="Page" style={styles.box}>
		<Text style={styles.label}>café &amp; · …</Text>
		<Pressable accessibilityLabel="Open"><Text>go</Text></Pressable>
		<TextInput editable={false} secureTextEntry={true} keyboardType="number-pad" maxLength={4}
			autoCorrect={false} accessibilityRole="search" placeholder="PIN" />
		<TextInput editable={true} autoFocus={false} accessibilityLabel="Name" />
	</View>;
}

export function marksApp(): NeonNode {
	const [on, _on] = createSignal(false);
	const [open, _open] = createSignal(true);
	const [blank, _blank] = createSignal("");
	const [count, _count] = createSignal(3);
	const [rows, _rows] = createSignal<string[]>(["a", "b"]);
	return <View>
		<Text>count: {count().toString()} items</Text>
		<Text>{blank()}</Text>
		<Show when={on()}><Text>hidden</Text></Show>
		<Show when={open()}><Text>shown</Text></Show>
		<For each={rows()}>{(row: string, i: Accessor<number>): NeonNode => <Text>{row}</Text>}</For>
		<Text>tail</Text>
	</View>;
}

export function scrollViewApp(): NeonNode {
	return <View>
		<ScrollView horizontal={false}><Text>row</Text></ScrollView>
	</View>;
}

export function linesApp(): NeonNode {
	return <View>
		<Text numberOfLines={2}>long</Text>
		<Text numberOfLines={0}>free</Text>
	</View>;
}

export function switchesApp(): NeonNode {
	return <View>
		<Switch value={true} accessibilityLabel="Wi-Fi" />
		<Switch value={false} disabled={true} thumbColor="#fff" trackColorOn="#0a0" trackColorOff="#ccc" />
		<ActivityIndicator />
		<ActivityIndicator animating={false} hidesWhenStopped={false} color="#c00" size="large" />
	</View>;
}

export function textareasApp(): NeonNode {
	return <View>
		<TextInput multiline={true} defaultValue="note" placeholder="Write" />
		<TextInput multiline={true} value={"\nfirst <b> & \"second\""} editable={false} maxLength={40} />
		<TextInput multiline={true} />
	</View>;
}

export const TILE_PNG = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAIAAAADCAIAAAA2iEnWAAAAEElEQVR4nGP4z8AARAwoFABE0AX7pM/egAAAAABJRU5ErkJggg==";
export const DOT_GIF = "data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7";

export const NOT_AN_IMAGE = "/tests/browser/serve.mjs";

export function imagesApp(src: Accessor<string>, blur: Accessor<number>, onLoad: (e: NeonEvent) => void, onError: (e: NeonEvent) => void): NeonNode {
	return <View>
		<Image source={{ uri: src() }} resizeMode="repeat" blurRadius={blur()} onLoad={onLoad} style={{ width: 40, height: 40 }} />
		<Image source={{ uri: DOT_GIF }} resizeMode="contain" accessibilityLabel="Logo" style={{ width: 40, height: 40 }} />
		<Image source={{ uri: NOT_AN_IMAGE }} onError={onError} style={{ width: 10, height: 10 }} />
		<Image style={{ width: 10, height: 10 }} />
	</View>;
}

export function imagesAtStart(): NeonNode {
	const [src, _src] = createSignal(TILE_PNG);
	const [blur, _blur] = createSignal<number>(3);
	return imagesApp(src, blur, (e: NeonEvent): void => {}, (e: NeonEvent): void => {});
}

export function svgApp(radius: Accessor<number>): NeonNode {
	return <View>
		<Svg width={100} height={50} viewBox="0 0 20 10" accessibilityLabel="ring">
			<Defs><LinearGradient id="fade" x1="0" y1="0" x2="1" y2="0"><Stop offset={0} stopColor="#00ff00" /><Stop offset={1} stopColor="#0000ff" /></LinearGradient></Defs>
			<G><Circle cx={5} cy={5} r={radius()} fill="url(#fade)" /></G>
		</Svg>
		<Svg width={10} height={10}><Rect width={5} height={5} fill="#f00" /></Svg>
	</View>;
}

export function svgAtStart(): NeonNode {
	const [radius, _radius] = createSignal<number>(4);
	return svgApp(radius);
}

export function modalApp(open: Accessor<boolean>): NeonNode {
	return <View>
		<Text>before</Text>
		<Modal visible={open()} animationType="fade"><Text>inside</Text></Modal>
		<Text>after</Text>
	</View>;
}

export function modalAtStart(): NeonNode {
	const [open, _open] = createSignal(true);
	return modalApp(open);
}

export const FRAME_PAGE = "<p id=t>frame</p><script>window.ReactNativeWebView.postMessage('ready');</script>";
export const OTHER_PAGE = "<p id=t>other</p>";

export struct MediaHooks {
	onVideoLoad: (d: OnLoadData) => void;
	onVideoEnd: () => void;
	onMessage: (e: WebViewMessageEvent) => void;
	onFrameLoad: (e: WebViewNavigationEvent) => void;
	onCameraReady: () => void;
	onCameraError: (e: CameraMountError) => void;
}

export function mediaApp(fit: Accessor<VideoResizeMode>, facing: Accessor<CameraType>, page: Accessor<string>, hooks: MediaHooks): NeonNode {
	return <View>
		<Video source={{ uri: CLIP_MP4 }} muted={true} repeat={true} controls={true} resizeMode={fit()} onLoad={hooks.onVideoLoad} onEnd={hooks.onVideoEnd} style={{ width: 160, height: 90 }} />
		<WebView source={{ html: page() }} onMessage={hooks.onMessage} onLoad={hooks.onFrameLoad} style={{ width: 200, height: 80 }} />
		<WebView source={{ uri: "about:blank" }} javaScriptEnabled={false} style={{ width: 20, height: 20 }} />
		<WebView source={{ uri: "about:blank" }} onMessage={hooks.onMessage} style={{ width: 20, height: 20 }} />
		<CameraView facing={facing()} onCameraReady={hooks.onCameraReady} onMountError={hooks.onCameraError} style={{ width: 160, height: 120 }} />
	</View>;
}

export function mediaAtStart(): NeonNode {
	const [fit, _fit] = createSignal<VideoResizeMode>("cover");
	const [facing, _facing] = createSignal<CameraType>("front");
	const [page, _page] = createSignal(FRAME_PAGE);
	return mediaApp(fit, facing, page, {
		onVideoLoad: (d: OnLoadData): void => {},
		onVideoEnd: (): void => {},
		onMessage: (e: WebViewMessageEvent): void => {},
		onFrameLoad: (e: WebViewNavigationEvent): void => {},
		onCameraReady: (): void => {},
		onCameraError: (e: CameraMountError): void => {},
	});
}

async function loadCounter(): Promise<(props: { label: string }) => NeonNode> {
	const m = await import("./lazy/counter");
	return m.Counter;
}

const LazyCounter = lazy<{ label: string }>(loadCounter);

export function lazyCounterPage(): NeonNode {
	return el("div", [], [], Loading({ children: createComponent(LazyCounter, { label: "count" }), fallback: el("b", [], [], text("loading")) }));
}
