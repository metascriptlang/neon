import { runApp } from "../../src/platform/native/host";
import { View, Pressable } from "../../src/components/primitives";
import { NeonNode } from "../../src/render/node";
import { createSignal } from "../../src/core/signal";
import { LayoutAnimation, LayoutAnimationPresets } from "../../src/animation/layoutAnimation";
import { useManualFrames, setFrameDriver } from "../../src/animation/frame";
import { Show } from "../../src/macros/ui/flow";
import { nmLoop, nmTeardown, nmLastPressableTag, nmLayoutHeight, nmLayoutY, nmOpacity, nmTouch } from "./nativeBridgeMock.h";

const PRESS: int32 = 2;

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
	nmLoop();
	const tag = nmLastPressableTag();
	assert nmLayoutHeight(tag) === 40;
	nmTouch(tag, PRESS);
	nmLoop();
	assert nmLayoutHeight(tag) === 40, "the frame starts where it was " + nmLayoutHeight(tag).toString();
	clock.step(5);
	nmLoop();
	assert Math.abs(nmLayoutHeight(tag) - 120) < 0.5, "half way " + nmLayoutHeight(tag).toString();
	clock.runAll();
	nmLoop();
	assert nmLayoutHeight(tag) === 200 && ended === 1, "lands and reports the end";
	setOpen(false);
	nmLoop();
	assert nmLayoutHeight(tag) === 40, "a layout without configureNext jumps";
	nmTeardown();
	nmLoop();
	setFrameDriver(null);
	nmLoop();
}

test "a created view fades in under the easeInEaseOut preset; siblings below slide" {
	const clock = useManualFrames();
	const [shown, setShown] = createSignal(false);
	const app = (): NeonNode => <View>
		<Show when={shown()}><View style={{ height: 50 }}><Pressable onPress={() => {}} style={{ height: 50 }} /></View></Show>
		<Pressable onPress={() => {}} style={{ height: 30 }} />
	</View>;
	runApp(app);
	nmLoop();
	const below = nmLastPressableTag();
	assert nmLayoutY(below) === 0;
	LayoutAnimation.configureNext(LayoutAnimationPresets.easeInEaseOut);
	setShown(true);
	nmLoop();
	const created = nmLastPressableTag();
	assert nmLayoutY(below) === 0, "the sibling starts in place";
	clock.step(2);
	nmLoop();
	assert nmLayoutY(below) > 0 && nmLayoutY(below) < 50, "slides " + nmLayoutY(below).toString();
	assert nmOpacity(created) === 1, "only the inserted root fades, not its children " + nmOpacity(created).toString();
	clock.runAll();
	nmLoop();
	assert nmLayoutY(below) === 50 && nmOpacity(created) === 1;
	nmTeardown();
	nmLoop();
	setFrameDriver(null);
	nmLoop();
}
