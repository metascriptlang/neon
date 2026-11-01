// A track handed to Core Animation keeps moving while the main thread is blocked on purpose.
//   msc build examples/macosNative/ionMotion.ms --output=out/macosIonMotion
//   out/macosIonMotion    blocks the main thread for 300 ms mid-animation and exits 0 when the
//                         presentation layer, sampled on a background thread, advanced by the
//                         blocked time while the player did not
// Sample off the main thread: its presentationLayer read the same value before and after a 300 ms
// block (macOS 26, 2026-11-01).

import { runNativeWindow, nativeWindowOptions } from "../../src/platform/macos/ion";
import { nativeViewOf } from "../../src/platform/native/host";
import { motionSampleLater, motionSamplesReady, motionSampledOpacity, motionSampledAtMs } from "./motionHarness.h";
import { NeonNode } from "../../src/render/node";
import { ElementHandle } from "../../src/render/measure";
import { View } from "../../src/components/primitives";
import { NativeMotionPlayer } from "../../src/motion/native";
import { MotionElement, frameClock } from "../../src/motion/waapi";
import { LayerComponent, presentedComponent } from "../../src/platform/native/layerMotion";
import { MotionDocument, MotionTrack, linearKeyframe } from "pulse/src/document";
import { motionOptions } from "pulse/src/player";
import { exit } from "std/process";

when (macos) {
	@compile("./motionHarness.m", "-fobjc-arc");
}

const DURATION_MS: float64 = 2000;
const BLOCK_MS: float64 = 300;
const handles: ElementHandle[] = [];
let failures: int32 = 0;
let player: NativeMotionPlayer | null = null;

function ramp(property: string, to: float64): MotionTrack {
	return {
		slot: "box",
		property,
		kind: linearKeyframe("a", 0, 0).value.kind,
		keyframes: [linearKeyframe("a", 0, 0), linearKeyframe("b", DURATION_MS, to)],
	};
}

function expect(name: string, ok: boolean, detail: string): void {
	console.log(`${ok ? "ok  " : "FAIL"} ${name}: ${detail}`);
	if (!ok) { failures += 1; }
}

function App(): NeonNode {
	return <View style={{ width: 480, height: 200, backgroundColor: "#101820" }}>
		<View style={{ position: "absolute", left: 20, top: 50, width: 100, height: 100, backgroundColor: "#2e86de" }}
			ref={(h: ElementHandle): void => { handles.push(h); }} />
	</View>;
}

function start(): void {
	const doc: MotionDocument = {
		version: 1,
		root: "main",
		clips: [{
			id: "main",
			duration: DURATION_MS,
			tracks: [ramp("opacity", 1), ramp("translateX", 200)],
			placements: [],
			labels: [],
		}],
	};
	const element: MotionElement = { slot: "box", node: handles[0].node };
	player = new NativeMotionPlayer(doc, [element], [], motionOptions(frameClock()));
	setTimeout(block, 400);
}

function block(): void {
	const node = handles[0].node;
	const motion = player as NativeMotionPlayer;
	const opacityBefore = presentedComponent(node, LayerComponent.Opacity);
	const xBefore = presentedComponent(node, LayerComponent.TranslateX);
	const timeBefore = motion.time;
	motionSampleLater(nativeViewOf(node), 50, 250);
	const from = performance.now();
	while (performance.now() - from < BLOCK_MS) {}
	const blocked = performance.now() - from;
	const opacityAfter = presentedComponent(node, LayerComponent.Opacity);
	console.log(`blocked ${blocked.toFixed(1)} ms; player.time ${timeBefore.toFixed(1)} -> ${motion.time.toFixed(1)} ms`);
	console.log(`main thread presented opacity ${opacityBefore.toFixed(4)} -> ${opacityAfter.toFixed(4)}, translateX ${xBefore.toFixed(2)}`);
	expect("the app-thread player did not tick during the block", motion.time === timeBefore, `${motion.time}`);
	expect("the presented transform is the centred matrix of the same playhead", Math.abs(xBefore - 200 * opacityBefore) < 2,
		`translateX ${xBefore.toFixed(2)} at opacity ${opacityBefore.toFixed(4)}`);
	expect("the background samples finished inside the block", motionSamplesReady() === 1, `${motionSamplesReady()}`);
	const first = motionSampledOpacity(0);
	const second = motionSampledOpacity(1);
	const apart = motionSampledAtMs(1) - motionSampledAtMs(0);
	console.log(`background presented opacity ${first.toFixed(4)} -> ${second.toFixed(4)} over ${apart.toFixed(1)} ms of the block`);
	expect("the presentation layer advanced while the main thread was blocked",
		Math.abs(second - first - apart / DURATION_MS) < 0.02,
		`${(second - first).toFixed(4)}, want ${(apart / DURATION_MS).toFixed(4)}`);
	setTimeout(cancel, 200);
}

function cancel(): void {
	const node = handles[0].node;
	(player as NativeMotionPlayer).cancel();
	const opacity = presentedComponent(node, LayerComponent.Opacity);
	const x = presentedComponent(node, LayerComponent.TranslateX);
	console.log(`after cancel: presented opacity ${opacity.toFixed(4)}, translateX ${x.toFixed(2)}`);
	expect("cancel holds a value inside the run", opacity > 0.1 && opacity < 0.9 && x > 20 && x < 180,
		`${opacity.toFixed(4)}, ${x.toFixed(2)}`);
	console.log(`failures ${failures}`);
	exit(failures);
}

const options = nativeWindowOptions("Neon motion on Core Animation", 480, 200);
options.topmost = true;
exit(runNativeWindow(options, App, (): void => {
	setTimeout(start, 500);
	setTimeout((): void => {
		console.log("FAIL timeout");
		exit(2);
	}, 8000);
}));
