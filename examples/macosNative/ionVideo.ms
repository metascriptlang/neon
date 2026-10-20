// Video in a macOS Ion window: an AVPlayer in an AVPlayerView, playing examples/media's 3 s 160x90 clip.
//   msc build examples/macosNative/ionVideo.ms --output=out/macosIonVideo
//   out/macosIonVideo            opens the window and logs each load, progress, end and error
//   out/macosIonVideo --check    checks muted playback, rate, repeat, replacement and lifetime

import { runNativeWindow, nativeWindowOptions } from "../../src/platform/macos/ion";
import { createStyles, styleOf } from "../../src/macros/ui/style";
import { createSignal } from "../../src/core/signal";
import { onCleanup } from "../../src/core/cleanup";
import { Show } from "../../src/macros/ui/flow";
import { NeonNode } from "../../src/render/node";
import { View } from "../../src/components/primitives";
import {
	Video,
	VideoHandle,
	OnLoadStartData,
	OnLoadData,
	OnProgressData,
	OnVideoErrorData,
} from "../../src/components/video";
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

const RATE_MP4 = CLIP_MP4.replace("video/mp4;", "video/mp4;neon=rate;");
const REPLACEMENT_MP4 = CLIP_MP4.replace("video/mp4;", "video/mp4;neon=replacement;");
const [paused, setPaused] = createSignal(false);
const [rate, setRate] = createSignal<float64>(1);
const [repeats, setRepeats] = createSignal(false);
const [sourceUri, setSourceUri] = createSignal(CLIP_MP4);
const [mounted, setMounted] = createSignal(true);

interface Playback {
	handle: VideoHandle | null;
	starts: int32;
	loads: int32;
	progresses: int32;
	ends: int32;
	errors: int32;
	callbacks: int32;
	callbacksAtDispose: int32;
	disposedAt: float64;
	disposed: boolean;
	lastStartUri: string;
	loaded: string;
	loadTime: float64;
	lastTime: float64;
	sampledAt: float64;
	wraps: int32;
	staleProgress: int32;
}

let active: Playback | null = null;
let retired: Playback | null = null;
let brokenError = "<none>";
let watchRepeat = false;
let replacementAt: float64 = 0;
let endsAtReplacementStart = 0;
let watchReplacement = false;

function ObservedVideo(): NeonNode {
	const playback: Playback = {
		handle: null,
		starts: 0,
		loads: 0,
		progresses: 0,
		ends: 0,
		errors: 0,
		callbacks: 0,
		callbacksAtDispose: 0,
		disposedAt: 0,
		disposed: false,
		lastStartUri: "",
		loaded: "<none>",
		loadTime: -1,
		lastTime: -1,
		sampledAt: 0,
		wraps: 0,
		staleProgress: 0,
	};
	active = playback;
	onCleanup((): void => {
		playback.disposed = true;
		playback.disposedAt = Date.now();
		playback.callbacksAtDispose = playback.callbacks;
	});
	return <Video style={styles.video} source={{ uri: sourceUri() }} muted={true}
		paused={paused()} rate={rate()} repeat={repeats()} progressUpdateInterval={100}
		ref={(h: VideoHandle): void => { playback.handle = h; }}
		onLoadStart={(d: OnLoadStartData): void => {
			playback.callbacks += 1;
			playback.starts += 1;
			playback.lastStartUri = d.uri;
			if (d.uri === REPLACEMENT_MP4) {
				replacementAt = Date.now();
				endsAtReplacementStart = playback.ends;
				watchReplacement = true;
			}
		}}
		onLoad={(d: OnLoadData): void => {
			playback.callbacks += 1;
			playback.loads += 1;
			playback.loadTime = d.currentTime;
			playback.loaded = `${Math.round(d.duration * 10) / 10}s ` +
				`${d.naturalSize.width}x${d.naturalSize.height}`;
			console.log(`load ${playback.loads}: ${playback.loaded} at ${d.currentTime}`);
		}}
		onProgress={(d: OnProgressData): void => {
			const now: float64 = Date.now();
			playback.callbacks += 1;
			playback.progresses += 1;
			if (watchRepeat && playback.lastTime > 2.7 && d.currentTime < 0.35) {
				playback.wraps += 1;
			}
			if (watchReplacement && d.currentTime > (now - replacementAt) / 1000 + 0.3) {
				playback.staleProgress += 1;
			}
			playback.lastTime = d.currentTime;
			playback.sampledAt = now;
		}}
		onEnd={(): void => {
			playback.callbacks += 1;
			playback.ends += 1;
			console.log(`end ${playback.ends} at ${playback.lastTime}`);
		}}
		onError={(d: OnVideoErrorData): void => {
			playback.callbacks += 1;
			playback.errors += 1;
			console.log(`unexpected video error: ${d.error.errorString}`);
		}} />;
}

function App(): NeonNode {
	return <View style={styles.base}>
		<Show when={mounted()}><ObservedVideo /></Show>
		<Video style={styles.broken} source={{ uri: "file:///nonexistent/neon-macos-check.mp4" }}
			onError={(d: OnVideoErrorData): void => { brokenError = d.error.errorString; }} />
	</View>;
}

const TITLE = "Neon video on Ion";
const check = harnessIsCheck() !== 0;
let failures = 0;
let checks = 0;
let stepStartedAt: float64 = 0;
let progressesAtPause = 0;
let seekedAt: float64 = 0;
let seekTook: float64 = -1;
let seekLanded: float64 = -1;
let sampleTime: float64 = 0;
let sampleWall: float64 = 0;
let normalSlope: float64 = 0;
let rateChangedAt: float64 = 0;

function expect(what: string, ok: boolean, detail: string): void {
	checks += 1;
	console.log(`${ok ? "ok  " : "FAIL"} ${what}: ${detail}`);
	if (!ok) { failures += 1; }
}

function playback(): Playback {
	if (active === null) { throw new Error("the Video never mounted"); }
	return active as Playback;
}

function video(): VideoHandle {
	const handle = playback().handle;
	if (handle === null) { throw new Error("the Video ref never arrived"); }
	return handle as VideoHandle;
}

interface VideoCheck {
	name: string;
	run: () => boolean;
}

const steps: VideoCheck[] = [];

function step(name: string, run: () => boolean): void { steps.push({ name, run }); }
function elapsed(): float64 { return Date.now() - stepStartedAt; }

function run(at: int32): void {
	if (at >= steps.length) {
		console.log(`checks ${checks} failures ${failures}`);
		exit(failures);
		return;
	}
	const current = steps[at];
	if (!current.run()) {
		if (elapsed() >= 5000) {
			const p = playback();
			expect(`timeout: ${current.name}`, false,
				`loads ${p.loads}, progress ${p.progresses} at ${p.lastTime}, ` +
				`ends ${p.ends}, wraps ${p.wraps}, errors ${p.errors}`);
			exit(failures);
			return;
		}
		setTimeout((): void => { run(at); }, 50);
		return;
	}
	if (failures > 0) { exit(failures); return; }
	setTimeout((): void => {
		stepStartedAt = Date.now();
		run(at + 1);
	}, 50);
}

step("initial load and progress", (): boolean => {
	const p = playback();
	if (p.loads < 1 || p.lastTime <= 0 || brokenError === "<none>") { return false; }
	expect("the load started", p.starts === 1, `${p.starts}`);
	expect("onLoad reports the duration and size", p.loaded === "3s 160x90", p.loaded);
	expect("playing reports progress", p.progresses > 0 && p.lastTime > 0,
		`${p.progresses} at ${p.lastTime}`);
	expect("a missing file reports an error", brokenError !== "<none>", brokenError);
	setPaused(true);
	return true;
});
step("pause settles", (): boolean => {
	if (elapsed() < 200) { return false; }
	progressesAtPause = playback().progresses;
	return true;
});
// Keep exact seeks playing: AVPlayerLayer can defer paused completion until resume (docs/MACOS.md).
step("pause and seek", (): boolean => {
	if (elapsed() < 600) { return false; }
	const p = playback();
	expect("paused stops progress", p.progresses === progressesAtPause,
		`${progressesAtPause} -> ${p.progresses}`);
	setPaused(false);
	video().seek(2.5);
	seekedAt = Date.now();
	return true;
});
step("seek progress arrives", (): boolean => {
	if (playback().lastTime < 2.5) { return false; }
	seekTook = Date.now() - seekedAt;
	seekLanded = playback().lastTime;
	return true;
});
step("seek is not ordinary playback", (): boolean => {
	expect("seek jumps playback ahead", seekLanded >= 2.5 && seekTook < 1000,
		`${seekLanded} after ${seekTook} ms`);
	return true;
});
step("nonrepeating end", (): boolean => playback().ends >= 1);
step("end once and restart for rate", (): boolean => {
	const p = playback();
	expect("the clip plays to its end once", p.ends === 1 && p.lastTime > 2.9,
		`${p.ends} ends at ${p.lastTime}`);
	setSourceUri(RATE_MP4);
	return true;
});
step("fresh rate sample", (): boolean => {
	const p = playback();
	if (p.loads < 2 || p.lastTime <= 0.15 || p.lastTime >= 0.5) { return false; }
	expect("source replacement loads from zero", p.starts === 2 && p.loads === 2 &&
		p.lastStartUri === RATE_MP4 && p.loadTime < 0.15,
		`${p.starts}/${p.loads} at ${p.loadTime}`);
	sampleTime = p.lastTime;
	sampleWall = p.sampledAt;
	return true;
});
step("1x callback clock", (): boolean => {
	const p = playback();
	const wall = p.sampledAt - sampleWall;
	if (wall < 600) { return false; }
	normalSlope = (p.lastTime - sampleTime) * 1000 / wall;
	expect("1x advances at wall clock rate", normalSlope >= 0.82 && normalSlope <= 1.18,
		`${normalSlope} s/s over ${wall} ms`);
	setRate(2);
	rateChangedAt = Date.now();
	return true;
});
step("2x settles", (): boolean => {
	const p = playback();
	if (p.sampledAt < rateChangedAt + 150) { return false; }
	sampleTime = p.lastTime;
	sampleWall = p.sampledAt;
	return true;
});
step("2x callback clock", (): boolean => {
	const p = playback();
	const wall = p.sampledAt - sampleWall;
	if (wall < 600) { return false; }
	const slope = (p.lastTime - sampleTime) * 1000 / wall;
	expect("2x doubles playback rate", slope >= 1.72 && slope <= 2.28,
		`${slope} s/s over ${wall} ms`);
	expect("rate change differs from 1x", slope / normalSlope >= 1.7 &&
		slope / normalSlope <= 2.3, `${normalSlope} -> ${slope}`);
	setRate(1);
	setRepeats(true);
	watchRepeat = true;
	video().seek(2.65);
	return true;
});
step("repeat wraps and keeps playing", (): boolean => {
	const p = playback();
	if (p.ends > 1) {
		expect("repeat rewinds without onEnd", false,
			`${p.wraps} wraps, ${p.ends} ends at ${p.lastTime}`);
		return true;
	}
	if (p.wraps < 1 || p.lastTime < 0.4 || p.lastTime > 1.2) { return false; }
	expect("repeat rewinds without onEnd", p.wraps === 1 && p.ends === 1,
		`${p.wraps} wraps, ${p.ends} ends at ${p.lastTime}`);
	watchRepeat = false;
	setRepeats(false);
	video().seek(2.75);
	return true;
});
step("replace a playing near-end item with seek pending", (): boolean => {
	if (playback().lastTime < 2.75) { return false; }
	video().seek(2.9);
	setSourceUri(REPLACEMENT_MP4);
	return true;
});
step("replacement rejects old progress and end", (): boolean => {
	const p = playback();
	if (p.loads < 3 || elapsed() < 800 || p.lastTime < 0.2) { return false; }
	expect("pending seek cannot report old source progress", p.starts === 3 && p.loads === 3 &&
		p.lastStartUri === REPLACEMENT_MP4 && p.loadTime < 0.15 &&
		p.lastTime < 1.4 && p.staleProgress === 0,
		`${p.starts}/${p.loads}, time ${p.lastTime}, stale ${p.staleProgress}`);
	expect("replaced item cannot end its successor", p.ends === endsAtReplacementStart,
		`${endsAtReplacementStart} -> ${p.ends}`);
	watchReplacement = false;
	setRepeats(true);
	video().seek(2.85);
	return true;
});
step("unmount near end with seek pending", (): boolean => {
	const p = playback();
	if (p.lastTime < 2.85) { return false; }
	video().seek(2.95);
	retired = p;
	setMounted(false);
	return true;
});
step("cleanup and remount", (): boolean => {
	const old = retired as Playback;
	if (!old.disposed) { return false; }
	expect("the playing mount was disposed", old.disposed, `${old.callbacksAtDispose} callbacks`);
	let message = "<no error>";
	try { (old.handle as VideoHandle).pause(); }
	catch (e) { message = (e as Error).message; }
	expect("retired handle refuses commands",
		message === "Video.pause was called while the Video is not mounted", message);
	setRate(1);
	setRepeats(false);
	setSourceUri(CLIP_MP4);
	setMounted(true);
	return true;
});
step("new mount loads and progresses independently", (): boolean => {
	const p = playback();
	if (p === retired || p.loads < 1 || p.lastTime < 0.2) { return false; }
	expect("remount has fresh callbacks and position", p.starts === 1 && p.loads === 1 &&
		p.ends === 0 && p.loadTime < 0.15 && p.lastTime < 0.8,
		`${p.starts}/${p.loads}, time ${p.lastTime}`);
	return true;
});
step("new mount reaches its own end", (): boolean => playback().ends >= 1);
step("late callbacks stay retired", (): boolean => {
	if (elapsed() < 600) { return false; }
	const p = playback();
	const old = retired as Playback;
	expect("remount ends exactly once", p.ends === 1 && p.lastTime > 2.9,
		`${p.ends} ends at ${p.lastTime}`);
	const silentFor = Date.now() - old.disposedAt;
	expect("unmounted callbacks stay silent through successor playback",
		old.callbacks === old.callbacksAtDispose && silentFor >= 3500,
		`${old.callbacksAtDispose} -> ${old.callbacks} over ${silentFor} ms`);
	expect("synthetic playback has no errors", old.errors === 0 && p.errors === 0,
		`${old.errors}/${p.errors}`);
	return true;
});

const options = nativeWindowOptions(TITLE, 480, 320);
options.topmost = check;
exit(runNativeWindow(options, App, check ? (): void => {
	setTimeout((): void => {
		stepStartedAt = Date.now();
		run(0);
	}, 100);
	setTimeout((): void => {
		console.log("FAIL video check exceeded 45 seconds");
		exit(1);
	}, 45000);
} : null));
