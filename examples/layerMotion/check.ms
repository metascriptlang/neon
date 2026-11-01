// Sample off the main thread: its presentationLayer read the same value before and after a 300 ms
// block (macOS 26, 2026-11-01).

import { nativeViewOf } from "../../src/platform/native/host";
import {
	motionSampleLater,
	motionSamplesReady,
	motionSampledOpacity,
	motionSampledAtMs,
} from "./harness.h";
import { NeonNode } from "../../src/render/node";
import { HostNode } from "../../src/render/hostTypes";
import { View, ViewHandle } from "../../src/components/primitives";
import { MotionSignals, useMotion } from "../../src/motion/neon";
import { LayerComponent } from "../../src/platform/native/layerEngine";
import { presentedComponent } from "../../src/platform/native/layerMotion";
import { MotionDocument, MotionTrack, linearKeyframe } from "pulse/src/document";
import { MotionPlayer } from "pulse/src/player";
import { exit } from "std/process";

when (macos || ios) {
	@compile("./harness.m", "-fobjc-arc");
}

const DURATION_MS: float64 = 2000;
const BLOCK_MS: float64 = 300;
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
			tracks: [ramp("opacity", 1), ramp("translateX", 200)],
			placements: [],
			labels: [],
		}],
	};
}

function expect(name: string, ok: boolean, detail: string): void {
	console.log(`${ok ? "ok  " : "FAIL"} ${name}: ${detail}`);
	if (!ok) { failures += 1; }
}

function boxView(): Ptr<void> {
	return nativeViewOf(signals.elements.node("box") as HostNode);
}

export function MotionCheck(): NeonNode {
	const ref = signals.ref("box");
	player = useMotion(entrance(), signals.bindings);
	return <View style={{ width: 320, height: 200, backgroundColor: "#101820" }}>
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
	const view = boxView();
	const motion = player as MotionPlayer;
	const opacityBefore = presentedComponent(view, LayerComponent.Opacity);
	const xBefore = presentedComponent(view, LayerComponent.TranslateX);
	const timeBefore = motion.time;
	motionSampleLater(view, 50, 250);
	const from = performance.now();
	while (performance.now() - from < BLOCK_MS) {}
	const blocked = performance.now() - from;
	const opacityAfter = presentedComponent(view, LayerComponent.Opacity);
	console.log(`blocked ${blocked.toFixed(1)} ms; player.time ${timeBefore.toFixed(1)} -> ${motion.time.toFixed(1)} ms`);
	console.log(`main thread presented opacity ${opacityBefore.toFixed(4)} -> ${opacityAfter.toFixed(4)}, translateX ${xBefore.toFixed(2)}`);
	expect("the handed track leaves its signal alone", opacitySignal() === 0, `${opacitySignal()}`);
	expect("the app-thread player did not tick during the block", motion.time === timeBefore, `${motion.time}`);
	expect("the presented transform is the platform matrix of the same playhead", Math.abs(xBefore - 200 * opacityBefore) < 2,
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
	const view = boxView();
	(player as MotionPlayer).cancel();
	const opacity = presentedComponent(view, LayerComponent.Opacity);
	const x = presentedComponent(view, LayerComponent.TranslateX);
	console.log(`after cancel: presented opacity ${opacity.toFixed(4)}, translateX ${x.toFixed(2)}`);
	expect("cancel holds a value inside the run", opacity > 0.1 && opacity < 0.9 && x > 20 && x < 180,
		`${opacity.toFixed(4)}, ${x.toFixed(2)}`);
	console.log(`failures ${failures}`);
	exit(failures);
}
