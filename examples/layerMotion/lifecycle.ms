import { nativeViewOf } from "../../src/platform/native/host";
import { niSetFrame } from "../../src/platform/native/bridge.h";
import { motionCommit, motionDetach, motionHasAnimation, motionReattach } from "./harness.h";
import { NeonNode } from "../../src/render/node";
import { HostNode } from "../../src/render/hostTypes";
import { View, ViewHandle } from "../../src/components/primitives";
import { MotionSignals, neonClock, useMotion } from "../../src/motion/neon";
import { LayerComponent } from "../../src/platform/native/layerEngine";
import { presentedComponent } from "../../src/platform/native/layerMotion";
import { MotionDocument, MotionTrack, linearKeyframe } from "pulse/src/document";
import { motionOptions } from "pulse/src/player";
import { exit } from "std/process";

when (macos || ios) {
	@compile("./harness.m", "-fobjc-arc");
}

const DURATION_MS: float64 = 2000;
const TRANSFORM: int32 = 1;
const signals = new MotionSignals();
signals.number("spin", "rotate", 0);
signals.number("drift", "translateX", 0);
let failures: int32 = 0;
let started = false;
let start: float64 = 0;

function ramp(slot: string, property: string, to: float64): MotionTrack {
	return {
		slot,
		property,
		kind: linearKeyframe("a", 0, 0).value.kind,
		keyframes: [linearKeyframe("a", 0, 0), linearKeyframe("b", DURATION_MS, to)],
	};
}

function documentOf(track: MotionTrack): MotionDocument {
	return {
		version: 1,
		root: "main",
		clips: [{ id: "main", duration: DURATION_MS, tracks: [track], placements: [], labels: [] }],
	};
}

function expect(name: string, ok: boolean, detail: string): void {
	console.log(`${ok ? "ok  " : "FAIL"} ${name}: ${detail}`);
	if (!ok) { failures += 1; }
}

function viewOf(slot: string): Ptr<void> {
	return nativeViewOf(signals.elements.node(slot) as HostNode);
}

function elapsed(): float64 {
	return performance.now() - start;
}

export function MotionLifecycle(): NeonNode {
	const spinRef = signals.ref("spin");
	const driftRef = signals.ref("drift");
	useMotion(documentOf(ramp("spin", "rotate", 90)), signals.bindings);
	useMotion(documentOf(ramp("drift", "translateX", 200)), signals.bindings, { ...motionOptions(neonClock()), repeat: -1 });
	return <View style={{ width: 480, height: 300, backgroundColor: "#101820" }}>
		<View style={[{ position: "absolute", left: 20, top: 20, width: 100, height: 100, backgroundColor: "#2e86de" }, signals.style("spin")]}
			ref={(h: ViewHandle): void => { spinRef(h); }} />
		<View style={[{ position: "absolute", left: 20, top: 160, width: 100, height: 100, backgroundColor: "#e67e22" }, signals.style("drift")]}
			ref={(h: ViewHandle): void => {
				driftRef(h);
				if (started) { return; }
				started = true;
				start = performance.now();
				setTimeout(resize, 500);
				setTimeout(detach, 900);
				setTimeout((): void => {
					console.log("FAIL timeout");
					exit(2);
				}, 6000);
			}} />
	</View>;
}

function resize(): void {
	niSetFrame(viewOf("spin"), 20, 20, 200, 100);
	motionCommit();
	setTimeout(checkResize, 50);
}

function checkResize(): void {
	const view = viewOf("spin");
	const x = presentedComponent(view, LayerComponent.TranslateX);
	const y = presentedComponent(view, LayerComponent.TranslateY);
	const turn = presentedComponent(view, LayerComponent.Rotation);
	const want = 90 * elapsed() / DURATION_MS;
	expect("a resize mid-turn keeps the turn about the new centre", Math.abs(x) < 1 && Math.abs(y) < 1,
		`translate ${x.toFixed(2)}, ${y.toFixed(2)} at rotation ${turn.toFixed(2)}`);
	expect("the turn keeps its playhead through the resize", Math.abs(turn - want) < 3,
		`${turn.toFixed(2)}, want ${want.toFixed(2)}`);
}

function detach(): void {
	const view = viewOf("drift");
	motionDetach(view);
	console.log(`detached: the layer holds its animation ${motionHasAnimation(view, TRANSFORM)}`);
	setTimeout(reattach, 200);
}

function reattach(): void {
	motionReattach(viewOf("drift"));
	setTimeout(checkReattach, 50);
}

function checkReattach(): void {
	const view = viewOf("drift");
	const x = presentedComponent(view, LayerComponent.TranslateX);
	const want = 200 * (elapsed() % DURATION_MS) / DURATION_MS;
	expect("a forever track is on the layer again after the view returns to its window",
		motionHasAnimation(view, TRANSFORM) === 1, `${motionHasAnimation(view, TRANSFORM)}`);
	expect("the returned track continues from the player's time", Math.abs(x - want) < 10,
		`translateX ${x.toFixed(2)}, want ${want.toFixed(2)}`);
	console.log(`failures ${failures}`);
	exit(failures);
}
