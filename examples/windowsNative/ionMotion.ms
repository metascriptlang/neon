// A track handed to DirectComposition keeps moving while the UI thread is blocked on purpose.
//   msc build examples/windowsNative/ionMotion.ms --output=out/windowsIonMotion.exe
//   out/windowsIonMotion.exe    blocks the UI thread for 300 ms mid-fade and exits 0 when the screen
//                               pixel at the box, read on a background thread, brightened by the
//                               blocked time while the player did not move; needs an interactive desktop
// Read the screen, not the visual: DirectComposition reports no animated value back.

import { runNativeWindow, nativeWindowOptions } from "../../src/platform/windows/ion";
import { NeonNode } from "../../src/render/node";
import { HostNode } from "../../src/render/hostTypes";
import { View, ViewHandle } from "../../src/components/primitives";
import { MotionSignals, useMotion } from "../../src/motion/neon";
import { LayerComponent, LayerEngine, layerEngine } from "../../src/platform/native/layerEngine";
import { MotionDocument, MotionTrack, linearKeyframe } from "pulse/src/document";
import { MotionPlayer } from "pulse/src/player";
import { motionSampleScreenLater, motionSamplesReady, motionSampledBlue, motionSampledAtMs } from "./motionHarness.h";
import { exit } from "std/process";

const TITLE = "Neon motion on DirectComposition";
const DURATION_MS: float64 = 2000;
const BLOCK_MS: float64 = 300;
const BACKGROUND_BLUE: float64 = 0x20;
const BOX_BLUE: float64 = 0xde;
const signals = new MotionSignals();
const opacitySignal = signals.number("box", "opacity", 0);
signals.number("box", "translateX", 0);
let failures: int32 = 0;
let player: MotionPlayer | null = null;
let started = false;

function ramp(property: string, to: float64): MotionTrack {
	return {
		slot: "box",
		property,
		kind: linearKeyframe("a", 0, 0).value.kind,
		keyframes: [linearKeyframe("a", 0, 0), linearKeyframe("b", DURATION_MS, to)],
	};
}

function entrance(): MotionDocument {
	return {
		version: 1,
		root: "main",
		clips: [{
			id: "main",
			duration: DURATION_MS,
			tracks: [ramp("opacity", 1), ramp("translateX", 40)],
			placements: [],
			labels: [],
		}],
	};
}

function expect(name: string, ok: boolean, detail: string): void {
	console.log(`${ok ? "ok  " : "FAIL"} ${name}: ${detail}`);
	if (!ok) { failures += 1; }
}

function App(): NeonNode {
	const ref = signals.ref("box");
	player = useMotion(entrance(), signals.bindings);
	return <View style={{ width: 480, height: 200, backgroundColor: "#101820" }}>
		<View style={[{ position: "absolute", left: 20, top: 50, width: 100, height: 100, backgroundColor: "#2e86de" }, signals.style("box")]}
			ref={(h: ViewHandle): void => {
				ref(h);
				if (started) { return; }
				started = true;
				setTimeout(block, 900);
				setTimeout((): void => {
					console.log("FAIL timeout");
					exit(2);
				}, 6000);
			}} />
	</View>;
}

function block(): void {
	const motion = player as MotionPlayer;
	const timeBefore = motion.time;
	motionSampleScreenLater(TITLE, 90, 100, 50, 250);
	const from = performance.now();
	while (performance.now() - from < BLOCK_MS) {}
	const blocked = performance.now() - from;
	console.log(`blocked ${blocked.toFixed(1)} ms; player.time ${timeBefore.toFixed(1)} -> ${motion.time.toFixed(1)} ms`);
	expect("the handed track leaves its signal alone", opacitySignal() === 0, `${opacitySignal()}`);
	expect("the app-thread player did not tick during the block", motion.time === timeBefore, `${motion.time}`);
	expect("the background samples finished inside the block", motionSamplesReady() === 1, `${motionSamplesReady()}`);
	const first = motionSampledBlue(0);
	const second = motionSampledBlue(1);
	const apart = motionSampledAtMs(1) - motionSampledAtMs(0);
	const want = apart / DURATION_MS * (BOX_BLUE - BACKGROUND_BLUE);
	console.log(`screen blue at the box ${first} -> ${second} over ${apart.toFixed(1)} ms of the block`);
	expect("the composed pixel brightened while the UI thread was blocked",
		Math.abs((second - first) as float64 - want) < 6,
		`${second - first}, want ${want.toFixed(1)}`);
	setTimeout(cancel, 200);
}

function cancel(): void {
	(player as MotionPlayer).cancel();
	const engine = layerEngine() as LayerEngine;
	const node = signals.elements.node("box") as HostNode;
	const opacity = engine.read(node, LayerComponent.Opacity);
	console.log(`after cancel: model opacity ${opacity.toFixed(4)}`);
	expect("cancel holds a value inside the run", opacity > 0.1 && opacity < 0.9, `${opacity.toFixed(4)}`);
	console.log(`failures ${failures}`);
	exit(failures);
}

const options = nativeWindowOptions(TITLE, 480, 200);
options.topmost = true;
exit(runNativeWindow(options, App, null));
