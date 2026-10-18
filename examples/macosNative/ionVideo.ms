// Video in a macOS Ion window: an AVPlayer in an AVPlayerView, playing examples/media's 3 s 160x90 clip.
//   msc build examples/macosNative/ionVideo.ms --output=out/macosIonVideo
//   out/macosIonVideo            opens the window and logs each load, progress, end and error
//   out/macosIonVideo --check    plays the clip muted, pauses and seeks it, plays it to its end, and exits 0 when every
//                                expectation holds

import { runNativeWindow, nativeWindowOptions } from "../../src/platform/macos/ion";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import { createSignal } from "../../src/core/signal";
import { NeonNode } from "../../src/render/node";
import { View } from "../../src/components/primitives";
import { Video, VideoHandle, OnLoadData, OnProgressData, OnVideoErrorData } from "../../src/components/video";
import { CLIP_MP4 } from "../media/clip";
import { harnessIsCheck } from "./harness.h";
import { exit } from "std/process";

when (macos) {
	@compile("./harness.m", "-fobjc-arc");
}

const styles = createStyles({
	base: { width: 480, height: 320, backgroundColor: "#101820" },
	video: { position: "absolute", left: 20, top: 20, width: 320, height: 180 },
	broken: { position: "absolute", left: 360, top: 20, width: 100, height: 60 },
});

const [paused, setPaused] = createSignal(false);
let loaded = "<none>";
let starts = 0;
let lastTime: number = -1;
let progresses = 0;
let ends = 0;
let brokenError = "<none>";
let handle: VideoHandle | null = null;

function App(): NeonNode {
	return <View style={styles.base}>
		<Video style={styles.video} source={{ uri: CLIP_MP4 }} muted={true} paused={paused()} progressUpdateInterval={100}
			ref={(h: VideoHandle): void => { handle = h; }}
			onLoadStart={(): void => { starts += 1; }}
			onLoad={(d: OnLoadData): void => {
				loaded = `${Math.round(d.duration * 10) / 10}s ${d.naturalSize.width}x${d.naturalSize.height}`;
				console.log(`load ${loaded}`);
			}}
			onProgress={(d: OnProgressData): void => {
				progresses += 1;
				lastTime = d.currentTime;
			}}
			onEnd={(): void => {
				ends += 1;
				console.log(`end at ${lastTime}`);
			}} />
		<Video style={styles.broken} source={{ uri: "file:///nonexistent/neon-macos-check.mp4" }}
			onError={(d: OnVideoErrorData): void => { brokenError = d.error.errorString; }} />
	</View>;
}

const TITLE = "Neon video on Ion";
const check = harnessIsCheck() !== 0;
let failures = 0;
let progressesAtPause = 0;

function expect(what: string, ok: boolean, detail: string): void {
	console.log(`${ok ? "ok  " : "FAIL"} ${what}: ${detail}`);
	if (!ok) { failures += 1; }
}

function video(): VideoHandle {
	if (handle === null) { throw new Error("the Video ref never arrived"); }
	return handle as VideoHandle;
}

// A step returns false while what it waits for has not arrived; run retries it every 100 ms, up to 3 s.
const steps: (() => boolean)[] = [];

function run(at: number, tries: number): void {
	if (at >= steps.length) {
		console.log(`failures ${failures}`);
		exit(failures);
		return;
	}
	if (!steps[at]() && tries < 30) {
		setTimeout((): void => { run(at, tries + 1); }, 100);
		return;
	}
	setTimeout((): void => { run(at + 1, 0); }, 700);
}

steps.push((): boolean => {
	expect("the load started", starts === 1, `${starts}`);
	expect("onLoad reports the duration and size", loaded === "3s 160x90", loaded);
	expect("playing reports progress", progresses > 0 && lastTime > 0, `${progresses} at ${lastTime}`);
	expect("a missing file reports an error", brokenError !== "<none>", brokenError);
	setPaused(true);
	return true;
});
steps.push((): boolean => {
	progressesAtPause = progresses;
	return true;
});
// The seek runs during playback: a paused exact seek in an on-screen layer can hold its completion until playback
// resumes (docs/MACOS.md). Playing on from about 1 s cannot reach 2.5 within the 1 s the seek is given.
let seekedAt: number = 0;
let seekTook: number = -1;
let seekLanded: number = -1;
steps.push((): boolean => {
	expect("paused stops progress", progresses === progressesAtPause, `${progressesAtPause} -> ${progresses}`);
	setPaused(false);
	video().seek(2.5);
	seekedAt = Date.now();
	return true;
});
steps.push((): boolean => {
	if (lastTime < 2.5) { return false; }
	seekTook = Date.now() - seekedAt;
	seekLanded = lastTime;
	return true;
});
steps.push((): boolean => {
	expect("seek jumps playback ahead", seekLanded >= 2.5 && seekTook < 1000, `${seekLanded} after ${seekTook} ms`);
	return true;
});
steps.push((): boolean => ends === 1);
steps.push((): boolean => {
	expect("the clip plays to its end once", ends === 1 && lastTime > 2.9, `${ends} ends at ${lastTime}`);
	return true;
});

const options = nativeWindowOptions(TITLE, 480, 320);
options.topmost = check;
exit(runNativeWindow(options, App, check ? (): void => {
	setTimeout((): void => { run(0, 0); }, 1200);
} : null));
