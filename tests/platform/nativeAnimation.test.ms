import { runApp } from "../../src/platform/native/host";
import { Pressable } from "../../src/components/primitives";
import { NeonNode } from "../../src/render/node";
import { Animated } from "../../src/animation/animated";
import { AnimatedValue, AnimatedNode } from "../../src/animation/nodes";
import { Easing } from "../../src/animation/easing";
import { useManualFrames, setFrameDriver } from "../../src/animation/frame";
import { nmTeardown, nmLastPressableTag, nmRotation, nmOpacity, nmTranslateX, nmTransformWrites, nmProp } from "./nativeBridgeMock.h";
import { createSignal } from "../../src/core/signal";

test "an animated opacity, translateX and rotate are written to the native view each frame" {
	const clock = useManualFrames();
	const progress = Animated.Value(0);
	const spin = progress.interpolate({ inputRange: [0, 1], outputRange: [0, 360] });
	const app = (): NeonNode => <Pressable onPress={() => {}} style={{
		width: 100, height: 40,
		opacity: progress.get(),
		transform: `translateX(${progress.get() * 50}px) rotate(${spin.get()}deg)`,
	}} />;
	runApp(app);
	const tag = nmLastPressableTag();
	assert nmOpacity(tag) === 0 && nmRotation(tag) === 0, "starts at rest";
	Animated.timing(progress, { toValue: 1, duration: 160, easing: Easing.linear }).start();
	const writes = nmTransformWrites();
	clock.step(5);
	assert Math.abs(nmOpacity(tag) - 0.5) < 0.001, "opacity " + nmOpacity(tag).toString();
	assert Math.abs(nmTranslateX(tag) - 25) < 0.001, "translateX " + nmTranslateX(tag).toString();
	assert Math.abs(nmRotation(tag) - 180) < 0.01, "rotation " + nmRotation(tag).toString();
	assert nmTransformWrites() > writes, "frames wrote transforms";
	clock.runAll();
	assert nmOpacity(tag) === 1 && Math.abs(nmRotation(tag) - 360) < 0.01;
	nmTeardown();
	setFrameDriver(null);
}

test "an rgba background from a colour interpolation parses on native" {
	const clock = useManualFrames();
	const v = Animated.Value(0);
	const bg = v.interpolateString({ inputRange: [0, 1], outputRange: ["#000000", "rgba(255, 0, 0, 0.5)"] });
	const app = (): NeonNode => <Pressable onPress={() => {}} style={{ width: 10, height: 10, backgroundColor: bg.get() }} />;
	runApp(app);
	Animated.timing(v, { toValue: 1, duration: 32 }).start();
	clock.runAll();
	assert bg.peek() === "rgba(255, 0, 0, 0.5)", bg.peek();
	nmTeardown();
	setFrameDriver(null);
}

function prop(tag: int32, name: string): string {
	return nmProp(tag, name);
}

test "overflow hidden clips a native view and visible releases it" {
	const [clip, setClip] = createSignal(true);
	const app = (): NeonNode => <Pressable onPress={() => {}} style={{ width: 10, height: 10, overflow: clip() ? "hidden" : "visible" }} />;
	runApp(app);
	const tag = nmLastPressableTag();
	assert prop(tag, "overflow") === "hidden", "hidden: " + prop(tag, "overflow");
	setClip(false);
	assert prop(tag, "overflow") === "visible";
	nmTeardown();
}
