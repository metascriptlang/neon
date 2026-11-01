import { runApp } from "../../src/platform/native/host";
import { flush } from "../../src/core/runtime";
import { View, Pressable } from "../../src/components/primitives";
import { NeonNode } from "../../src/render/node";
import { createSignal } from "../../src/core/signal";
import { LayoutAnimation, LayoutAnimationPresets } from "../../src/motion/layoutAnimation";
import { useManualFrames, setFrameDriver } from "../../src/animation/frame";
import { Show } from "../../src/macros/ui/flow";
import { nmTeardown, nmLastPressableTag, nmLayoutHeight, nmLayoutWidth, nmLayoutY, nmOpacity, nmTap, nmVisualX, nmVisualY } from "./nativeBridgeMock.h";

function shownWidth(tag: int32): number {
	return (nmVisualX(tag, nmLayoutWidth(tag)) - nmVisualX(tag, 0)) as number;
}

function shownHeight(tag: int32): number {
	return (nmVisualY(tag, nmLayoutHeight(tag)) - nmVisualY(tag, 0)) as number;
}

test "configureNext tweens the next layout's frame changes, and only the next" {
	const clock = useManualFrames();
	const [open, setOpen] = createSignal(false);
	let ended = 0;
	const app = (): NeonNode => <View>
		<Pressable onPress={() => {
			LayoutAnimation.configureNext(LayoutAnimation.create(160, "linear", "opacity"), (): void => { ended += 1; });
			setOpen(!open());
		}} style={{ width: 100, height: open() ? 200 : 40 }} />
	</View>;
	runApp(app);
	const tag = nmLastPressableTag();
	assert nmLayoutHeight(tag) === 40;
	nmTap(tag);
	flush();
	assert nmLayoutHeight(tag) === 40, "the frame starts where it was " + nmLayoutHeight(tag).toString();
	clock.step(5);
	assert Math.abs(nmLayoutHeight(tag) - 120) < 0.5, "half way " + nmLayoutHeight(tag).toString();
	clock.runAll();
	assert nmLayoutHeight(tag) === 200 && ended === 1, "lands and reports the end";
	setOpen(false);
	flush();
	assert nmLayoutHeight(tag) === 40, "a layout without configureNext jumps";
	nmTeardown();
	setFrameDriver(null);
}

test "a created view fades in under the easeInEaseOut preset; siblings below slide" {
	const clock = useManualFrames();
	const [shown, setShown] = createSignal(false);
	const app = (): NeonNode => <View>
		<Show when={shown()}><View style={{ height: 50 }}><Pressable onPress={() => {}} style={{ height: 50 }} /></View></Show>
		<Pressable onPress={() => {}} style={{ height: 30 }} />
	</View>;
	runApp(app);
	const below = nmLastPressableTag();
	assert nmLayoutY(below) === 0;
	LayoutAnimation.configureNext(LayoutAnimationPresets.easeInEaseOut);
	setShown(true);
	flush();
	const created = nmLastPressableTag();
	assert nmLayoutY(below) === 0, "the sibling starts in place";
	clock.step(2);
	assert nmLayoutY(below) > 0 && nmLayoutY(below) < 50, "slides " + nmLayoutY(below).toString();
	assert nmOpacity(created) === 1, "only the inserted root fades, not its children " + nmOpacity(created).toString();
	clock.runAll();
	assert nmLayoutY(below) === 50 && nmOpacity(created) === 1;
	nmTeardown();
	setFrameDriver(null);
}

test "the spring preset overshoots a growing frame and lands on it" {
	const clock = useManualFrames();
	const [open, setOpen] = createSignal(false);
	const app = (): NeonNode => <View>
		<Pressable onPress={() => {}} style={{ width: 100, height: open() ? 200 : 40 }} />
	</View>;
	runApp(app);
	const tag = nmLastPressableTag();
	LayoutAnimation.spring();
	setOpen(true);
	flush();
	let highest = 0.0;
	for (let i = 0; i < 60; i += 1) {
		clock.step(1);
		highest = Math.max(highest, nmLayoutHeight(tag) as float64);
	}
	assert highest > 200.5, "damping 0.4 overshoots " + highest.toString();
	clock.runAll();
	assert nmLayoutHeight(tag) === 200, "lands " + nmLayoutHeight(tag).toString();
	nmTeardown();
	setFrameDriver(null);
}

test "a created view grows from nothing under a scaleXY create and keeps its opacity" {
	const clock = useManualFrames();
	const [shown, setShown] = createSignal(false);
	const app = (): NeonNode => <View>
		<Show when={shown()}><View style={{ width: 100, height: 50 }}><Pressable onPress={() => {}} style={{ width: 100, height: 50 }} /></View></Show>
	</View>;
	runApp(app);
	LayoutAnimation.configureNext(LayoutAnimation.create(160, "linear", "scaleXY"));
	setShown(true);
	flush();
	const created = nmLastPressableTag();
	clock.step(5);
	assert Math.abs(shownWidth(created) - 50) < 1 && Math.abs(shownHeight(created) - 25) < 1,
		"half grown " + shownWidth(created).toString() + "x" + shownHeight(created).toString();
	assert nmOpacity(created) === 1, "scale leaves opacity alone " + nmOpacity(created).toString();
	clock.runAll();
	assert shownWidth(created) === 100 && shownHeight(created) === 50;
	nmTeardown();
	setFrameDriver(null);
}

test "a scaleY create grows only the height" {
	const clock = useManualFrames();
	const [shown, setShown] = createSignal(false);
	const app = (): NeonNode => <View>
		<Show when={shown()}><View style={{ width: 100, height: 50 }}><Pressable onPress={() => {}} style={{ width: 100, height: 50 }} /></View></Show>
	</View>;
	runApp(app);
	LayoutAnimation.configureNext(LayoutAnimation.create(160, "linear", "scaleY"));
	setShown(true);
	flush();
	const created = nmLastPressableTag();
	clock.step(5);
	assert shownWidth(created) === 100 && Math.abs(shownHeight(created) - 25) < 1,
		"only the height grows " + shownWidth(created).toString() + "x" + shownHeight(created).toString();
	clock.runAll();
	assert shownHeight(created) === 50;
	nmTeardown();
	setFrameDriver(null);
}
