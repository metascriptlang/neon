import { Animated } from "../../src/animation/animated";
import { AnimatedValue } from "../../src/animation/nodes";
import { Easing } from "../../src/animation/easing";
import { useManualFrames, setFrameDriver } from "../../src/animation/frame";
import { element } from "../../src/macros/ui/element";
import { HostNode, MockNode, mockNode, mockHost, render, mockToString } from "../../src/render/host";
import { Style } from "../../src/render/style";

function styleOf(n: MockNode): Style {
	return n.style as Style;
}

test "<Animated.View> resolves through the class's static field and mounts a view" {
	const root: MockNode = mockNode("root");
	render(element(<Animated.View><Animated.Text>hi</Animated.Text></Animated.View>), mockHost(), root as unknown as HostNode);
	assert mockToString(root) === "<root><view><text>hi</text></view></root>", mockToString(root);
}

test "an animated opacity and transform follow the value frame by frame" {
	const clock = useManualFrames();
	const fade = Animated.Value(0);
	const slide = new AnimatedValue(0);
	const root: MockNode = mockNode("root");
	render(element(<Animated.View style={{
		opacity: fade.get(),
		transform: `translateX(${slide.interpolate({ inputRange: [0, 1], outputRange: [0, 100] }).get()}px)`,
	}} />), mockHost(), root as unknown as HostNode);
	const box = root.children[0];
	assert styleOf(box).opacity === 0, "starts transparent";
	Animated.parallel([
		Animated.timing(fade, { toValue: 1, duration: 160, easing: Easing.linear }),
		Animated.timing(slide, { toValue: 1, duration: 160, easing: Easing.linear }),
	]).start();
	clock.step(5);
	assert Math.abs((styleOf(box).opacity as number) - 0.5) < 0.0001, "half way " + (styleOf(box).opacity as number).toString();
	assert styleOf(box).transform === "translateX(50px)", styleOf(box).transform as string;
	clock.runAll();
	assert styleOf(box).opacity === 1 && styleOf(box).transform === "translateX(100px)";
	setFrameDriver(null);
}

test "a color interpolation drives backgroundColor" {
	const clock = useManualFrames();
	const v = new AnimatedValue(0);
	const bg = v.interpolateString({ inputRange: [0, 1], outputRange: ["#000000", "#ff0000"] });
	const root: MockNode = mockNode("root");
	render(element(<Animated.View style={{ backgroundColor: bg.get() }} />), mockHost(), root as unknown as HostNode);
	Animated.timing(v, { toValue: 1, duration: 100, easing: Easing.linear }).start();
	clock.runAll();
	assert styleOf(root.children[0]).backgroundColor === "rgba(255, 0, 0, 1)", styleOf(root.children[0]).backgroundColor as string;
	setFrameDriver(null);
}

test "a component style layer array merges RN-style, the reactive layer stays live" {
	const clock = useManualFrames();
	const v = new AnimatedValue(0);
	const base: Style = { width: 10, opacity: 1, backgroundColor: "#111" };
	const root: MockNode = mockNode("root");
	render(element(<Animated.View style={[base, { opacity: v.get() }]} />), mockHost(), root as unknown as HostNode);
	const box = root.children[0];
	assert styleOf(box).width === 10 && styleOf(box).opacity === 0 && styleOf(box).backgroundColor === "#111";
	v.setValue(0.5);
	assert styleOf(box).opacity === 0.5 && styleOf(box).width === 10;
	setFrameDriver(null);
}
