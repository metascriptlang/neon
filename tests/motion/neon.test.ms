import { createRoot } from "../../src/core/owner";
import { flush } from "../../src/core/runtime";
import { NeonNode } from "../../src/render/node";
import { Host, HostNode, MockNode, mockHost, render } from "../../src/render/host";
import { Style } from "../../src/render/style";
import { styleToCss } from "../../src/render/css";
import { View } from "../../src/components/primitives";
import { Easing } from "../../src/animation/easing";
import { framePending, setFrameDriver, useManualFrames } from "../../src/animation/frame";
import {
	MotionDocument,
	MotionKeyframe,
	ValueKind,
	colorValue,
	linearKeyframe,
} from "../../src/motion/document";
import { MotionOptions, MotionPlayer, motionOptions } from "../../src/motion/player";
import { MotionPolicy } from "../../src/motion/policy";
import { AnimatedValue, spring, timing } from "../../src/motion/value";
import { MotionSignals, neonClock, useAnimatedValue, useMotion } from "../../src/motion/neon";

function fadeDocument(): MotionDocument {
	const red: MotionKeyframe = { ...linearKeyframe("r0", 0, 0), value: colorValue(1, 0, 0, 1) };
	const blue: MotionKeyframe = {
		...linearKeyframe("r1", 160, 0),
		value: colorValue(0, 0, 1, 0.5),
	};
	return {
		version: 1,
		root: "main",
		clips: [
			{
				id: "main",
				duration: 160,
				tracks: [
					{
						slot: "box",
						property: "opacity",
						kind: ValueKind.Number,
						keyframes: [linearKeyframe("o0", 0, 0), linearKeyframe("o1", 160, 1)],
					},
					{
						slot: "box",
						property: "translateX",
						kind: ValueKind.Number,
						keyframes: [linearKeyframe("x0", 0, 0), linearKeyframe("x1", 160, 80)],
					},
					{
						slot: "box",
						property: "backgroundColor",
						kind: ValueKind.Color,
						keyframes: [red, blue],
					},
				],
				placements: [],
				labels: [],
			},
		],
	};
}

function mount(app: () => NeonNode): [MockNode, () => void] {
	const host = mockHost();
	const root = host.createElement("root");
	const node: NeonNode = (h: Host, parent: HostNode, before: HostNode | null): void => {
		app()(h, parent, before);
	};
	const dispose = render(node, host, root);
	return [root as unknown as MockNode, dispose];
}

function css(root: MockNode): string {
	const style = root.children[0].style;
	return style === null ? "(none)" : styleToCss(style as Style);
}

test "a document drives an ordinary View's opacity, translate and colour across frames" {
	const frames = useManualFrames();
	const signals = new MotionSignals();
	const opacity = signals.number("box", "opacity", 0);
	const x = signals.number("box", "translateX", 0);
	const background = signals.color("box", "backgroundColor", colorValue(1, 0, 0, 1));
	const [root, dispose] = mount((): NeonNode => {
		useMotion(fadeDocument(), signals.bindings);
		return <View style={{
			opacity: opacity(),
			transform: `translateX(${x()}px)`,
			backgroundColor: background(),
		}} />;
	});
	const start = css(root);
	assert start.includes("opacity:0;") && start.includes("rgba(255, 0, 0, 1)"), start;
	frames.step(5);
	const middle = css(root);
	assert middle.includes("opacity:0.5;"), middle;
	assert middle.includes("translateX(40px)"), middle;
	assert middle.includes(", 0.75)") && !middle.includes("rgba(255, 0, 0,"), middle;
	frames.runAll();
	const end = css(root);
	assert end.includes("opacity:1;") && end.includes("translateX(80px)"), end;
	assert end.includes("rgba(0, 0, 255, 0.5)"), end;
	dispose();
	setFrameDriver(null);
}

test "unmount disposes the player and the shared frame loop goes idle" {
	const frames = useManualFrames();
	const signals = new MotionSignals();
	const opacity = signals.number("box", "opacity", 0);
	signals.number("box", "translateX", 0);
	signals.color("box", "backgroundColor", colorValue(1, 0, 0, 1));
	let player: MotionPlayer | null = null;
	const [root, dispose] = mount((): NeonNode => {
		player = useMotion(fadeDocument(), signals.bindings);
		return <View style={{ opacity: opacity() }} />;
	});
	frames.step(2);
	assert framePending(), "the player asks for frames while it runs";
	dispose();
	assert (player as MotionPlayer).disposed, "the owner's cleanup disposed the player";
	assert !framePending(), "no frame is pending after unmount";
	const before = opacity();
	frames.step(3);
	assert opacity() === before, "a disposed player writes nothing";
	setFrameDriver(null);
}

test "two players share one frame without sharing playheads" {
	const frames = useManualFrames();
	const first = new MotionSignals();
	const firstOpacity = first.number("box", "opacity", 0);
	first.number("box", "translateX", 0);
	first.color("box", "backgroundColor", colorValue(1, 0, 0, 1));
	const second = new MotionSignals();
	const secondOpacity = second.number("box", "opacity", 0);
	second.number("box", "translateX", 0);
	second.color("box", "backgroundColor", colorValue(1, 0, 0, 1));
	const [slow, dispose] = createRoot((dispose: () => void): [MotionPlayer, () => void] => {
		useMotion(fadeDocument(), first.bindings);
		const options: MotionOptions = { ...motionOptions(neonClock()), timeScale: 0.5 };
		return [useMotion(fadeDocument(), second.bindings, options), dispose];
	});
	frames.step(4);
	assert frames.frames === 4, "four shared frames: " + frames.frames.toString();
	assert Math.abs(firstOpacity() - 0.4) < 1e-9, "first " + firstOpacity().toString();
	assert Math.abs(secondOpacity() - 0.2) < 1e-9, "second " + secondOpacity().toString();
	slow.pause();
	frames.step(2);
	assert Math.abs(firstOpacity() - 0.6) < 1e-9, "first keeps playing";
	assert Math.abs(secondOpacity() - 0.2) < 1e-9, "pausing one leaves the other alone";
	dispose();
	assert !framePending();
	setFrameDriver(null);
}

test "a player disposed inside the shared frame does not tick in that frame" {
	const frames = useManualFrames();
	const first = new MotionSignals();
	first.number("box", "opacity", 0);
	first.number("box", "translateX", 0);
	first.color("box", "backgroundColor", colorValue(1, 0, 0, 1));
	const second = new MotionSignals();
	const secondOpacity = second.number("box", "opacity", 0);
	second.number("box", "translateX", 0);
	second.color("box", "backgroundColor", colorValue(1, 0, 0, 1));
	const [leader, follower, dispose] = createRoot(
		(dispose: () => void): [MotionPlayer, MotionPlayer, () => void] => [
			useMotion(fadeDocument(), first.bindings),
			useMotion(fadeDocument(), second.bindings),
			dispose,
		],
	);
	frames.step(1);
	leader.onUpdate = (): void => { follower.dispose(); };
	const before = secondOpacity();
	frames.step(1);
	assert follower.disposed && secondOpacity() === before, "follower wrote after dispose";
	dispose();
	assert !framePending();
	setFrameDriver(null);
}

function mountValue(policy: MotionPolicy): [MockNode, () => void, AnimatedValue] {
	let held: AnimatedValue | null = null;
	const [root, dispose] = mount((): NeonNode => {
		const [scale, value] = useAnimatedValue(0, policy);
		held = value;
		return <View style={{ opacity: scale() }} />;
	});
	return [root, dispose, held as AnimatedValue];
}

test "an AnimatedValue spring drives a View style through its accessor" {
	const frames = useManualFrames();
	const [root, dispose, value] = mountValue(new MotionPolicy());
	assert css(root).includes("opacity:0;"), css(root);
	value.animate(spring(1));
	frames.step(10);
	const middle = css(root);
	assert !middle.includes("opacity:0;") && !middle.includes("opacity:1;"), middle;
	frames.runAll();
	assert css(root).includes("opacity:1;"), css(root);
	dispose();
	assert !framePending();
	setFrameDriver(null);
}

test "unmount disposes an AnimatedValue mid-flight" {
	const frames = useManualFrames();
	const [root, dispose, value] = mountValue(new MotionPolicy());
	value.animate(timing(1, { duration: 1000 }));
	frames.step(2);
	assert framePending();
	dispose();
	assert !framePending(), "the value's frame is cancelled on unmount";
	setFrameDriver(null);
}

test "an AnimatedValue disposed by hand unmounts without a second dispose" {
	useManualFrames();
	const [root, dispose, value] = mountValue(new MotionPolicy());
	value.dispose();
	assert value.disposed;
	dispose();
	assert !framePending();
	setFrameDriver(null);
}

test "a reduced motion policy jumps the value to its end" {
	const frames = useManualFrames();
	const [root, dispose, value] = mountValue(new MotionPolicy(true));
	value.animate(timing(1, { duration: 1000 }));
	flush();
	assert css(root).includes("opacity:1;"), css(root);
	assert !framePending() && frames.frames === 0, "reduced motion runs no animation frame";
	dispose();
	setFrameDriver(null);
}

test "ownerless use refuses" {
	const frames = useManualFrames();
	const signals = new MotionSignals();
	signals.number("box", "opacity", 0);
	signals.number("box", "translateX", 0);
	signals.color("box", "backgroundColor", colorValue(1, 0, 0, 1));
	let motionError = "";
	try { useMotion(fadeDocument(), signals.bindings); } catch (e) { motionError = e.toString(); }
	assert motionError.includes("useMotion") && motionError.includes("owner"), motionError;
	let valueError = "";
	try { useAnimatedValue(0); } catch (e) { valueError = e.toString(); }
	assert valueError.includes("useAnimatedValue") && valueError.includes("owner"), valueError;
	assert !framePending(), "a refused use requests no frame";
	setFrameDriver(null);
}

function fade(from: float64, to: float64): MotionDocument {
	return {
		version: 1,
		root: "main",
		clips: [
			{
				id: "main",
				duration: 160,
				tracks: [
					{
						slot: "box",
						property: "opacity",
						kind: ValueKind.Number,
						keyframes: [linearKeyframe("a", 0, from), linearKeyframe("b", 160, to)],
					},
				],
				placements: [],
				labels: [],
			},
		],
	};
}

function near(a: float64, b: float64): boolean {
	return Math.abs(a - b) < 1e-9;
}

test "a second player on one MotionSignals property replaces the first mid-flight" {
	const frames = useManualFrames();
	const signals = new MotionSignals();
	const opacity = signals.number("box", "opacity", 0);
	const [older, dispose] = createRoot((dispose: () => void): [MotionPlayer, () => void] => [
		useMotion(fade(0, 1), signals.bindings),
		dispose,
	]);
	frames.step(5);
	assert near(opacity(), 0.5), opacity().toString();
	const disposeNewer = createRoot((dispose: () => void): () => void => {
		useMotion(fade(0.5, 0), signals.bindings);
		return dispose;
	});
	frames.step(1);
	assert older.cancelled, "the older player lost its only target";
	assert near(opacity(), 0.45), opacity().toString();
	frames.step(4);
	assert near(opacity(), 0.25), "the older player never writes again: " + opacity().toString();
	frames.runAll();
	assert opacity() === 0 && !framePending();
	disposeNewer();
	dispose();
	setFrameDriver(null);
}

test "useAnimatedValue joining a running player starts from the shown value" {
	const frames = useManualFrames();
	const signals = new MotionSignals();
	const opacity = signals.number("box", "opacity", 0);
	const [player, value, dispose] = createRoot(
		(dispose: () => void): [MotionPlayer, AnimatedValue, () => void] => {
			const player = useMotion(fade(0, 1), signals.bindings);
			const pair = useAnimatedValue(0, new MotionPolicy(), signals.bindings[0].target);
			return [player, pair[1], dispose];
		},
	);
	frames.step(5);
	assert near(opacity(), 0.5) && value.get() === 0;
	value.animate(timing(0, { duration: 160, easing: Easing.linear }));
	assert player.cancelled, "the value replaced the player";
	assert near(value.get(), 0.5) && near(opacity(), 0.5), "no jump: " + opacity().toString();
	frames.step(5);
	assert near(opacity(), 0.25) && near(value.get(), 0.25), opacity().toString();
	frames.runAll();
	assert opacity() === 0 && !framePending();
	dispose();
	setFrameDriver(null);
}

test "a binding refuses a value of the other kind" {
	const signals = new MotionSignals();
	signals.number("box", "opacity", 0);
	let error = "";
	try { signals.bindings[0].write(colorValue(0, 0, 0, 1)); } catch (e) { error = e.toString(); }
	assert error.includes("box.opacity") && error.includes("number"), error;
}
