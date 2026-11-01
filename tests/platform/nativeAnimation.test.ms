import { runApp } from "../../src/platform/native/host";
import { flush } from "../../src/core/runtime";
import { Pressable } from "../../src/components/primitives";
import { NeonNode } from "../../src/render/node";
import { Easing } from "pulse/src/easing";
import { colorValue } from "pulse/src/document";
import { interpolate } from "pulse/src/evaluate";
import { timing } from "pulse/src/value";
import { cssColor } from "../../src/motion/neon";
import { createAnimatedValue, useValueSignal } from "../../src/motion/neonValues";
import { useManualFrames, setFrameDriver } from "../../src/animation/frame";
import {
	nmTeardown, nmLastPressableTag, nmRotation, nmOpacity, nmTranslateX, nmTransformWrites, nmProp,
	nmBackgroundAlpha,
} from "./nativeBridgeMock.h";
import { createSignal } from "../../src/core/signal";

test "an animated opacity, translateX and rotate are written to the native view each frame" {
	const clock = useManualFrames();
	const [progress, value] = createAnimatedValue(0);
	const app = (): NeonNode => {
		const spin = useValueSignal(value.interpolate({ inputRange: [0, 1], outputRange: [0, 360] }).source());
		return <Pressable onPress={() => {}} style={{
			width: 100, height: 40,
			opacity: progress(),
			transform: `translateX(${progress() * 50}px) rotate(${spin()}deg)`,
		}} />;
	};
	runApp(app);
	const tag = nmLastPressableTag();
	assert nmOpacity(tag) === 0 && nmRotation(tag) === 0, "starts at rest";
	value.animate(timing(1, { duration: 160, easing: Easing.linear }));
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
	const [progress, value] = createAnimatedValue(0);
	const black = colorValue(0, 0, 0, 1);
	const red = colorValue(1, 0, 0, 0.5);
	const bg = (): string => cssColor(interpolate(black, red, progress()).color);
	const app = (): NeonNode => <Pressable onPress={() => {}} style={{ width: 10, height: 10, backgroundColor: bg() }} />;
	runApp(app);
	const tag = nmLastPressableTag();
	value.animate(timing(1, { duration: 32 }));
	clock.runAll();
	assert bg() === "rgba(255, 0, 0, 0.5)", bg();
	assert Math.abs(nmBackgroundAlpha(tag) - 0.5) < 0.01, "alpha " + nmBackgroundAlpha(tag).toString();
	nmTeardown();
	setFrameDriver(null);
}

function prop(tag: int32, name: string): string {
	return nmProp(tag, name) as string;
}

test "overflow hidden clips a native view and visible releases it" {
	const [clip, setClip] = createSignal(true);
	const app = (): NeonNode => <Pressable onPress={() => {}} style={{ width: 10, height: 10, overflow: clip() ? "hidden" : "visible" }} />;
	runApp(app);
	const tag = nmLastPressableTag();
	assert prop(tag, "overflow") === "hidden", "hidden: " + prop(tag, "overflow");
	setClip(false);
	flush();
	assert prop(tag, "overflow") === "visible";
	nmTeardown();
}
