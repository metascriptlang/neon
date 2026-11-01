import { ScrollAxis, ScrollSource, scrollSource } from "pulse/src/scroll";
import { nativeViewOf, ownsNativeView, runApp } from "../../src/platform/native/host";
import { Pressable } from "../../src/components/primitives";
import { ElementHandle } from "../../src/render/measure";
import { NeonNode } from "../../src/render/node";
import { MotionElement, motionElements } from "../../src/motion/waapi";
import { nativeMotionPlayer } from "../../src/motion/native";
import { bridgeLayerEngine } from "../../src/platform/native/layerMotion";
import { installLayerEngine } from "../../src/platform/native/layerEngine";
import { ManualClock } from "pulse/src/clock";
import { MotionDocument, MotionTrack, linearKeyframe } from "pulse/src/document";
import { MotionOptions, MotionPlayer, motionOptions } from "pulse/src/player";
import {
	nmTeardown,
	nmLastPressableTag,
	nmOpacity,
	nmTranslateX,
	nmTranslateY,
	nmRotation,
	nmLayerAnimates,
	nmLayerRemoves,
	nmLayerLive,
	nmLayerKeyCount,
	nmLayerKeyTime,
	nmLayerValue,
	nmLayerTiming,
} from "./nativeBridgeMock.h";

const OPACITY: int32 = 0;
const TRANSFORM: int32 = 1;
const OFFSET: int32 = 4;
const SPEED: int32 = 5;

function ramp(property: string, from: float64, to: float64): MotionTrack {
	return {
		slot: "box",
		property,
		kind: linearKeyframe("a", 0, from).value.kind,
		keyframes: [linearKeyframe("a", 0, from), linearKeyframe("b", 1000, to)],
	};
}

function documentOf(tracks: MotionTrack[]): MotionDocument {
	return {
		version: 1,
		root: "main",
		clips: [{ id: "main", duration: 1000, tracks, placements: [], labels: [] }],
	};
}

function near(a: float64, b: float64): boolean { return Math.abs(a - b) < 1e-4; }

class Stage {
	tag: int32;
	handles: ElementHandle[] = [];
	clock: ManualClock = new ManualClock();

	constructor() {
		runApp((): NeonNode => <Pressable onPress={() => {}}
			ref={(h: ElementHandle): void => { this.handles.push(h); }}
			style={{ width: 100, height: 40 }} />);
		if (this.handles.length !== 1) { throw new Error("no ref"); }
		this.tag = nmLastPressableTag();
		installLayerEngine(bridgeLayerEngine(nativeViewOf, ownsNativeView));
	}

	options(): MotionOptions { return motionOptions(this.clock.clock); }

	play(tracks: MotionTrack[], options: MotionOptions): MotionPlayer {
		const element: MotionElement = { slot: "box", node: this.handles[0].node };
		return nativeMotionPlayer(
			documentOf(tracks),
			motionElements([element]),
			[],
			options,
		);
	}

	close(): void {
		installLayerEngine(null);
		nmTeardown();
	}
}

test "opacity and the merged transform go to the compositor once, with the final value in the model" {
	const stage = new Stage();
	const before = nmLayerAnimates();
	stage.play(
		[ramp("opacity", 0, 1), ramp("translateX", 0, 100), ramp("rotate", 0, 90)],
		stage.options(),
	);
	stage.clock.advance(16);
	const tag = stage.tag;
	assert nmLayerAnimates() === before + 2, "one animation per layer property";
	assert nmLayerKeyCount(tag, OPACITY) === 101, "keys " + nmLayerKeyCount(tag, OPACITY).toString();
	assert nmLayerKeyTime(tag, OPACITY, 0) === 0 && nmLayerKeyTime(tag, OPACITY, 100) === 1;
	assert near(nmLayerKeyTime(tag, OPACITY, 50), 0.5);
	assert near(nmLayerValue(tag, OPACITY, 50), 0.5), nmLayerValue(tag, OPACITY, 50).toString();
	assert nmLayerKeyCount(tag, TRANSFORM) === 101;
	assert near(nmLayerValue(tag, TRANSFORM, 50 * 5 + 0), 1), "scaleX keeps the model";
	assert near(nmLayerValue(tag, TRANSFORM, 50 * 5 + 2), 50), "translateX at the half";
	assert near(nmLayerValue(tag, TRANSFORM, 50 * 5 + 3), 0), "translateY keeps the model";
	assert near(nmLayerValue(tag, TRANSFORM, 50 * 5 + 4), 45), "rotation at the half";
	assert nmLayerTiming(tag, OPACITY, 0) === 1000 && nmLayerTiming(tag, OPACITY, 1) === 1;
	assert nmLayerTiming(tag, OPACITY, OFFSET) === 16, "starts at the playhead";
	assert nmOpacity(tag) === 1 && nmTranslateX(tag) === 100 && nmRotation(tag) === 90,
		"the model holds the end";
	stage.clock.advance(16);
	stage.clock.advance(16);
	assert nmLayerAnimates() === before + 2, "frames hand nothing more";
	stage.clock.advance(2000);
	assert nmLayerLive(tag, OPACITY) === 0 && nmOpacity(tag) === 1, "the end removes it";
	stage.close();
}

test "cancel writes what the compositor shows now into the model and removes the animation" {
	const stage = new Stage();
	const player = stage.play([ramp("opacity", 0, 1), ramp("translateX", 0, 100)], stage.options());
	stage.clock.advance(16);
	const removes = nmLayerRemoves();
	stage.clock.time = 600;
	player.cancel();
	assert nmLayerRemoves() === removes + 2;
	assert nmLayerLive(stage.tag, OPACITY) === 0 && nmLayerLive(stage.tag, TRANSFORM) === 0;
	assert near(nmOpacity(stage.tag), 0.6), "opacity " + nmOpacity(stage.tag).toString();
	assert Math.abs(nmTranslateX(stage.tag) - 60) < 0.001, "translateX " + nmTranslateX(stage.tag).toString();
	assert player.cancelled;
	stage.close();
}

test "pause holds the playhead, seek writes the model, play hands over again from the playhead" {
	const stage = new Stage();
	const player = stage.play([ramp("opacity", 0, 1)], stage.options());
	stage.clock.advance(16);
	stage.clock.advance(184);
	player.pause();
	assert nmLayerLive(stage.tag, OPACITY) === 0, "paused runs no animation";
	assert near(nmOpacity(stage.tag), 0.2), "pause " + nmOpacity(stage.tag).toString();
	player.seek(250);
	assert nmLayerLive(stage.tag, OPACITY) === 0 && near(nmOpacity(stage.tag), 0.25);
	const animates = nmLayerAnimates();
	player.play();
	assert nmLayerAnimates() === animates + 1 && nmLayerLive(stage.tag, OPACITY) === 1;
	assert nmLayerTiming(stage.tag, OPACITY, OFFSET) === 250, "resumes at the playhead";
	assert nmOpacity(stage.tag) === 1;
	player.reverse();
	assert nmLayerTiming(stage.tag, OPACITY, SPEED) === 1, "reverse plays forward in time";
	assert nmLayerTiming(stage.tag, OPACITY, OFFSET) === 750, "on mirrored keys";
	assert near(nmLayerValue(stage.tag, OPACITY, 0), 1) && near(nmLayerValue(stage.tag, OPACITY, 100), 0);
	assert nmOpacity(stage.tag) === 0, "the model holds where reverse ends";
	stage.close();
}

test "a newer player on the same layer property evicts the older one at its shown value" {
	const stage = new Stage();
	const older = stage.play([ramp("opacity", 0, 1)], stage.options());
	stage.clock.advance(16);
	stage.clock.advance(284);
	stage.clock.time = 400;
	const newer = stage.play([ramp("opacity", 1, 0)], stage.options());
	stage.clock.advance(16);
	assert older.cancelled, "the replaced player cancels";
	assert nmLayerLive(stage.tag, OPACITY) === 1;
	assert near(nmLayerValue(stage.tag, OPACITY, 0), 1), "the newer keys run";
	assert nmOpacity(stage.tag) === 0, "the newer end is the model";
	assert !newer.cancelled;
	older.dispose();
	assert nmLayerLive(stage.tag, OPACITY) === 1 && nmOpacity(stage.tag) === 0,
		"disposing the evicted player leaves the newer animation alone";
	stage.close();
}

test "a repeat with a repeat delay stays on the evaluator and writes the model each frame" {
	const stage = new Stage();
	const options = { ...stage.options(), repeat: 1, repeatDelay: 100 as float64 };
	const animates = nmLayerAnimates();
	stage.play([ramp("translateY", 0, 100)], options);
	stage.clock.advance(16);
	stage.clock.advance(484);
	assert nmLayerAnimates() === animates, "nothing handed over";
	assert Math.abs(nmTranslateY(stage.tag) - 50) < 0.001, "translateY " + nmTranslateY(stage.tag).toString();
	stage.close();
}

test "element tracks refuse to construct on a host with no layer engine" {
	const stage = new Stage();
	installLayerEngine(null);
	let message = "";
	try {
		stage.play([ramp("opacity", 0, 1)], stage.options());
	} catch (e) {
		message = (e as Error).message;
	}
	assert message.includes("no layer engine"), message;
	stage.close();
}

test "a property the layer cannot carry is refused at construction" {
	const stage = new Stage();
	let message = "";
	try {
		stage.play([ramp("width", 0, 1)], stage.options());
	} catch (e) {
		message = (e as Error).message;
	}
	assert message.includes("no native layer binding for track box.width"), message;
	stage.close();
}

test "a player on a scroll source writes the layer model from the scroll offset and hands the layer nothing" {
	const stage = new Stage();
	let offset: float64 = 0;
	const scroller: ScrollSource = {
		offset: (axis: ScrollAxis): float64 => offset,
		max: (axis: ScrollAxis): float64 => 100,
		viewport: (axis: ScrollAxis): float64 => 50,
	};
	const before = nmLayerAnimates();
	stage.play([ramp("opacity", 0, 1)], { ...stage.options(), source: scrollSource(scroller) });
	offset = 25;
	stage.clock.advance(16);
	assert near(nmOpacity(stage.tag), 0.25), "opacity " + nmOpacity(stage.tag).toString();
	offset = 80;
	stage.clock.advance(16);
	assert near(nmOpacity(stage.tag), 0.8), "opacity " + nmOpacity(stage.tag).toString();
	assert nmLayerAnimates() === before, "no layer animation";
	stage.close();
}
