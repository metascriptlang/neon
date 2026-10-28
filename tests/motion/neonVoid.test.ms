import { NeonNode } from "../../src/render/node";
import { Host, HostNode, render } from "../../src/render/host";
import { Style } from "../../src/render/style";
import { View } from "../../src/components/primitives";
import { createVoidHost, VoidHost, VoidNode } from "../../src/platform/void/host";
import { framePending, setFrameDriver, useManualFrames } from "../../src/animation/frame";
import {
	MotionDocument,
	MotionKeyframe,
	MotionTrack,
	ValueKind,
	colorValue,
	linearKeyframe,
} from "../../src/motion/document";
import { MotionPlayer } from "../../src/motion/player";
import { MotionPolicy } from "../../src/motion/policy";
import { AnimatedValue, spring, timing } from "../../src/motion/value";
import { MotionSignals, useAnimatedValue, useMotion } from "../../src/motion/neon";
import { Changed, local, paint } from "../../../void/src/void2d/node";

function documentOf(tracks: MotionTrack[]): MotionDocument {
	return {
		version: 1,
		root: "main",
		clips: [{ id: "main", duration: 160, tracks, placements: [], labels: [] }],
	};
}

function fadeTracks(): MotionTrack[] {
	const red: MotionKeyframe = { ...linearKeyframe("r0", 0, 0), value: colorValue(1, 0, 0, 1) };
	const blue: MotionKeyframe = { ...linearKeyframe("r1", 160, 0), value: colorValue(0, 0, 1, 1) };
	return [
		{
			slot: "box",
			property: "opacity",
			kind: ValueKind.Number,
			keyframes: [linearKeyframe("o0", 0, 0), linearKeyframe("o1", 160, 1)],
		},
		{ slot: "box", property: "backgroundColor", kind: ValueKind.Color, keyframes: [red, blue] },
	];
}

function mount(vh: VoidHost, app: () => NeonNode): () => void {
	const node: NeonNode = (h: Host, parent: HostNode, before: HostNode | null): void => {
		app()(h, parent, before);
	};
	return render(node, vh.host, vh.root);
}

function box(vh: VoidHost): VoidNode {
	return (vh.root as VoidNode).children[0];
}

function near(value: float32, expected: float64): boolean {
	return Math.abs((value as float64) - expected) < 0.01;
}

function repainted(vh: VoidHost, n: VoidNode, what: Changed): boolean {
	const marked = vh.scene.changed[n.ref.id.index].has(what);
	vh.scene.clearChanges();
	return marked;
}

test "useMotion fades and recolours a View's Void scene node frame by frame and settles" {
	const frames = useManualFrames();
	const vh = createVoidHost();
	const signals = new MotionSignals();
	const opacity = signals.number("box", "opacity", 0);
	const background = signals.color("box", "backgroundColor", colorValue(1, 0, 0, 1));
	let player: MotionPlayer | null = null;
	const dispose = mount(vh, (): NeonNode => {
		player = useMotion(documentOf(fadeTracks()), signals.bindings);
		return <View style={{ width: 40, height: 40, opacity: opacity(), backgroundColor: background() }} />;
	});
	const n = box(vh);
	assert near(n.ref.paint().alpha, 0) && near(n.ref.paint().color.r, 1), "starts clear and red";
	vh.scene.clearChanges();
	frames.step(5);
	const half = n.ref.paint();
	assert near(half.alpha, 0.5), "alpha " + half.alpha.toString();
	assert half.color.r < 0.99 && half.color.b > 0.01, "colour moves off red";
	assert repainted(vh, n, Changed.Paint), "each frame marks the node's paint for the next draw";
	frames.step(1);
	assert repainted(vh, n, Changed.Paint), "and the frame after";
	frames.runAll();
	const end = n.ref.paint();
	assert near(end.alpha, 1) && near(end.color.r, 0) && near(end.color.b, 1), "settles opaque blue";
	assert !framePending(), "a finished player asks for no frame";
	assert (player as MotionPlayer).progress === 1;
	dispose();
	setFrameDriver(null);
}

test "unmount on the Void host disposes the player and stops frames" {
	const frames = useManualFrames();
	const vh = createVoidHost();
	const signals = new MotionSignals();
	const opacity = signals.number("box", "opacity", 0);
	signals.color("box", "backgroundColor", colorValue(1, 0, 0, 1));
	let player: MotionPlayer | null = null;
	const dispose = mount(vh, (): NeonNode => {
		player = useMotion(documentOf(fadeTracks()), signals.bindings);
		return <View style={{ width: 40, height: 40, opacity: opacity() }} />;
	});
	frames.step(2);
	assert framePending();
	dispose();
	assert (player as MotionPlayer).disposed && !framePending(), "no frame after unmount";
	const before = opacity();
	frames.step(3);
	assert opacity() === before;
	setFrameDriver(null);
}

function mountValue(vh: VoidHost): [() => void, AnimatedValue] {
	let held: AnimatedValue | null = null;
	const dispose = mount(vh, (): NeonNode => {
		const [fade, value] = useAnimatedValue(0, new MotionPolicy());
		held = value;
		return <View style={{ width: 40, height: 40, backgroundColor: "#ffffff", opacity: fade() }} />;
	});
	return [dispose, held as AnimatedValue];
}

test "an AnimatedValue spring drives a Void node's alpha and settles on its target" {
	const frames = useManualFrames();
	const vh = createVoidHost();
	const [dispose, value] = mountValue(vh);
	const n = box(vh);
	value.animate(spring(1));
	frames.step(6);
	const moving = n.ref.paint().alpha;
	assert moving > 0.01 && moving < 0.99, "alpha mid-spring " + moving.toString();
	assert repainted(vh, n, Changed.Paint);
	frames.runAll();
	assert near(n.ref.paint().alpha, 1) && !value.isAnimating() && !framePending(), "settled";
	dispose();
	setFrameDriver(null);
}

test "unmount cancels an AnimatedValue mid-flight on the Void host" {
	const frames = useManualFrames();
	const vh = createVoidHost();
	const [dispose, value] = mountValue(vh);
	value.animate(timing(1, { duration: 1000 }));
	frames.step(2);
	assert framePending();
	dispose();
	assert value.disposed && !framePending(), "the value's frame is cancelled on unmount";
	setFrameDriver(null);
}

test "a translateX track moves the View's Void scene node" {
	const frames = useManualFrames();
	const vh = createVoidHost();
	const signals = new MotionSignals();
	const x = signals.number("box", "translateX", 0);
	const tracks: MotionTrack[] = [{
		slot: "box",
		property: "translateX",
		kind: ValueKind.Number,
		keyframes: [linearKeyframe("x0", 0, 0), linearKeyframe("x1", 160, 80)],
	}];
	const dispose = mount(vh, (): NeonNode => {
		useMotion(documentOf(tracks), signals.bindings);
		return <View style={{ width: 40, height: 40, transform: `translateX(${x()}px)` }} />;
	});
	const n = box(vh);
	frames.step(5);
	assert x() === 40, "the signal moved: " + x().toString();
	assert near(n.ref.local().x, 40), "scene x " + n.ref.local().x.toString() + ", style transform " +
		((n.style as Style).transform as string);
	dispose();
	setFrameDriver(null);
}
