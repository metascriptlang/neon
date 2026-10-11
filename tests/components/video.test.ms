import { createSignal } from "../../src/core/signal";
import { HostNode, MockNode, mockNode, mockHost, render, mockToString, fireEventWith } from "../../src/render/host";
import { neonEvent } from "../../src/render/event";
import {
	Video,
	VideoHandle,
	OnLoadStartData,
	OnLoadData,
	OnProgressData,
	OnVideoErrorData,
} from "../../src/components/video";

function attrOf(n: MockNode, name: string): string {
	for (const a of n.attrs) {
		if (a.name === name) { return a.value ?? ""; }
	}
	return "<unset>";
}

function fire(n: MockNode, name: string, value: string, width: number, height: number): void {
	const e = neonEvent(name);
	e.value = value;
	e.width = width;
	e.height = height;
	fireEventWith(n, name, e);
}

test "a Video writes react-native-video's playback props with their defaults" {
	const [paused, setPaused] = createSignal(true);
	const [rate, setRate] = createSignal(1.0);
	const root: MockNode = mockNode("root");
	render(<Video source={{ uri: "https://neon.dev/clip.mp4" }} paused={paused()} rate={rate()} resizeMode="cover" repeat={true} />, mockHost(), root as unknown as HostNode);
	const video = root.children[0];
	assert video.tag === "video", mockToString(root);
	const shape = ["source", "paused", "muted", "volume", "rate", "repeat", "controls", "progressUpdateInterval", "resizeMode"]
		.map((name: string): string => `${name}=${attrOf(video, name)}`).join(" ");
	assert shape === "source=https://neon.dev/clip.mp4 paused=true muted=false volume=1 rate=1 repeat=true controls=false progressUpdateInterval=250 resizeMode=cover", shape;
	setPaused(false);
	setRate(1.5);
	assert attrOf(video, "paused") === "false" && attrOf(video, "rate") === "1.5", mockToString(root);
}

test "playback events arrive as react-native-video's data objects" {
	let seen = "";
	const root: MockNode = mockNode("root");
	render(<Video
		source={{ uri: "file:///clip.mp4" }}
		onLoadStart={(d: OnLoadStartData): void => { seen += `start ${d.uri} ${d.isNetwork};`; }}
		onLoad={(d: OnLoadData): void => { seen += `load ${d.duration} ${d.naturalSize.width}x${d.naturalSize.height} ${d.naturalSize.orientation};`; }}
		onProgress={(d: OnProgressData): void => { seen += `progress ${d.currentTime}/${d.playableDuration};`; }}
		onEnd={(): void => { seen += "end;"; }}
		onError={(d: OnVideoErrorData): void => { seen += `error ${d.error.code} ${d.error.errorString};`; }}
	/>, mockHost(), root as unknown as HostNode);
	const video = root.children[0];
	fire(video, "onLoadStart", "", 0, 0);
	fire(video, "onLoad", "3\x1f0\x1f160\x1f90", 0, 0);
	fire(video, "onProgress", "1.5\x1f3\x1f3", 0, 0);
	fire(video, "onEnd", "", 0, 0);
	fire(video, "onError", "-11800\x1fThe operation could not be completed", 0, 0);
	assert seen === "start file:///clip.mp4 false;load 3 160x90 landscape;progress 1.5/3;end;error -11800 The operation could not be completed;", seen;
}

test "the ref seeks, pauses and resumes through commands and refuses a negative time" {
	let handle: VideoHandle | null = null;
	const root: MockNode = mockNode("root");
	render(<Video source={{ uri: "https://neon.dev/clip.mp4" }} ref={(h: VideoHandle): void => { handle = h; }} />, mockHost(), root as unknown as HostNode);
	const video = root.children[0];
	const h = handle as VideoHandle;
	h.seek(1.25);
	assert attrOf(video, "command") === "seek\x1f1.25", attrOf(video, "command");
	h.pause();
	assert attrOf(video, "command") === "pause\x1f", attrOf(video, "command");
	h.resume();
	assert attrOf(video, "command") === "resume\x1f", attrOf(video, "command");
	let refused = "";
	try {
		h.seek(-1);
	} catch (e) {
		refused = (e as Error).message;
	}
	assert refused === "Video.seek needs a time of 0 or more seconds, got -1", refused;
}
