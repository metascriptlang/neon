import { nativeViewOf, ownsNativeView, runApp } from "../../src/platform/native/host";
import { Pressable, View } from "../../src/components/primitives";
import { NeonNode } from "../../src/render/node";
import { HostNode } from "../../src/render/hostTypes";
import { MotionSignals, useAnimatedValue, useMotion } from "../../src/motion/neon";
import { bridgeLayerEngine } from "../../src/platform/native/layerMotion";
import {
	LayerComponent,
	installLayerEngine,
	layerEngine,
	LayerEngine,
} from "../../src/platform/native/layerEngine";
import { setFrameDriver, useManualFrames } from "../../src/animation/frame";
import { Accessor, createSignal } from "../../src/core/signal";
import { Show } from "../../src/macros/ui/flow";
import { Easing } from "pulse/src/easing";
import {
	MotionDocument,
	MotionTrack,
	colorValue,
	MotionValue,
	linearKeyframe,
} from "pulse/src/document";
import { MotionPlayer, motionOptions } from "pulse/src/player";
import { ManualClock } from "pulse/src/clock";
import { motionElements } from "../../src/motion/waapi";
import { nativeMotionPlayer, nativeOwns } from "../../src/motion/native";
import { MotionPolicy } from "pulse/src/policy";
import { decayConfig } from "pulse/src/decay";
import { AnimatedValue, decay, spring, timing } from "pulse/src/value";
import {
	nmTeardown,
	nmLastPressableTag,
	nmOpacity,
	nmLayerAnimates,
	nmLayerLive,
	nmLayerKeyCount,
	nmLayerValue,
	nmLayerTiming,
	nmLayerRemoves,
	nmLoop,
} from "./nativeBridgeMock.h";

const OPACITY: int32 = 0;
const TRANSFORM: int32 = 1;

function ramp(property: string, to: float64): MotionTrack {
	return {
		slot: "box",
		property,
		kind: linearKeyframe("a", 0, 0).value.kind,
		keyframes: [linearKeyframe("a", 0, 0), linearKeyframe("b", 1000, to)],
	};
}

function tint(): MotionTrack {
	return {
		slot: "box",
		property: "backgroundColor",
		kind: colorValue(0, 0, 0, 1).kind,
		keyframes: [
			{ ...linearKeyframe("a", 0, 0), value: colorValue(0, 0, 0, 1) },
			{ ...linearKeyframe("b", 1000, 0), value: colorValue(1, 0, 0, 1) },
		],
	};
}

function entrance(): MotionDocument {
	return {
		version: 1,
		root: "main",
		clips: [{
			id: "main",
			duration: 1000,
			tracks: [ramp("opacity", 1), ramp("translateX", 100), tint()],
			placements: [],
			labels: [],
		}],
	};
}

class Showcase {
	signals: MotionSignals = new MotionSignals();
	opacity: Accessor<float64>;
	color: Accessor<string>;
	player: MotionPlayer | null = null;
	tag: int32 = 0;

	constructor() {
		this.opacity = this.signals.number("box", "opacity", 0);
		this.signals.number("box", "translateX", 0);
		this.color = this.signals.color("box", "backgroundColor", colorValue(0, 0, 0, 1));
		runApp((): NeonNode => {
			const ref = this.signals.ref("box");
			this.player = useMotion(entrance(), this.signals.bindings);
			return <Pressable onPress={() => {}} ref={ref}
				style={[{ width: 100, height: 40 }, this.signals.style("box")]} />;
		});
		this.tag = nmLastPressableTag();
	}
}

function close(): void {
	nmTeardown();
	installLayerEngine(null);
	setFrameDriver(null);
}

test "useMotion on a slot named by signals.ref hands opacity and transform to the layer, keeping the rest on signals" {
	const frames = useManualFrames();
	installLayerEngine(bridgeLayerEngine(nativeViewOf, ownsNativeView));
	const before = nmLayerAnimates();
	const app = new Showcase();
	frames.step(1);
	assert nmLayerAnimates() === before + 2, "animations " + (nmLayerAnimates() - before).toString();
	assert nmLayerLive(app.tag, OPACITY) === 1 && nmLayerLive(app.tag, TRANSFORM) === 1;
	const colour = app.color();
	frames.step(20);
	assert app.opacity() === 0, "a handed track leaves its signal alone: " + app.opacity().toString();
	assert nmOpacity(app.tag) === 1, "the style no longer writes opacity over the model: " + nmOpacity(app.tag).toString();
	assert app.color() !== colour, "the colour the layer cannot carry still plays on its signal";
	frames.runAll();
	assert nmLayerLive(app.tag, OPACITY) === 0 && nmOpacity(app.tag) === 1;
	close();
}

test "with no layer engine the same program writes its signals and styles each frame" {
	const frames = useManualFrames();
	const before = nmLayerAnimates();
	const app = new Showcase();
	frames.step(1);
	frames.step(30);
	assert nmLayerAnimates() === before, "nothing handed over";
	assert app.opacity() > 0.3 && app.opacity() < 0.7, "signal " + app.opacity().toString();
	assert Math.abs(nmOpacity(app.tag) - app.opacity()) < 1e-6, "the style carries the signal";
	frames.runAll();
	assert app.opacity() === 1;
	close();
}

class Like {
	signals: MotionSignals = new MotionSignals();
	value: AnimatedValue | null = null;
	read: Accessor<float64> | null = null;
	tag: int32 = 0;

	constructor() {
		this.signals.number("like", "scale", 1);
		runApp((): NeonNode => {
			const ref = this.signals.ref("like");
			const [read, value] = useAnimatedValue(
				1,
				new MotionPolicy(),
				this.signals.target("like", "scale"),
			);
			this.read = read;
			this.value = value;
			return <Pressable onPress={() => {}} ref={ref}
				style={[{ width: 40, height: 40 }, this.signals.style("like")]} />;
		});
		this.tag = nmLastPressableTag();
	}

	get animated(): AnimatedValue { return this.value as AnimatedValue; }

	get node(): HostNode { return this.signals.elements.node("like") as HostNode; }

	model(): float64 {
		return (layerEngine() as LayerEngine).read(this.node, LayerComponent.ScaleX);
	}
}

test "useAnimatedValue on a named slot hands a spring and a timing to the layer and keeps decay on the evaluator" {
	const frames = useManualFrames();
	installLayerEngine(bridgeLayerEngine(nativeViewOf, ownsNativeView));
	const like = new Like();
	const before = nmLayerAnimates();
	like.animated.animate(spring(1.5));
	assert nmLayerAnimates() === before + 1 && nmLayerLive(like.tag, TRANSFORM) === 1;
	const keys = nmLayerKeyCount(like.tag, TRANSFORM);
	assert Math.abs(nmLayerValue(like.tag, TRANSFORM, 0) - 1) < 1e-9, "starts at the value";
	assert Math.abs(nmLayerValue(like.tag, TRANSFORM, (keys - 1) * 5) - 1.5) < 1e-3, "ends on the target";
	assert Math.abs(nmLayerValue(like.tag, TRANSFORM, (keys - 1) * 5 + 1) - 1.5) < 1e-3, "scale moves both axes";
	assert nmLayerTiming(like.tag, TRANSFORM, 0) > 0, "the sampled spring has a duration";
	assert like.model() === 1.5, "the model holds the target";
	frames.step(5);
	assert like.animated.get() > 1 && (like.read as Accessor<float64>)() === like.animated.get(),
		"the value and its signal still advance on the app thread";
	like.animated.animate(timing(1, { duration: 200 }));
	assert nmLayerAnimates() === before + 2, "the retarget hands over again";
	assert nmLayerKeyCount(like.tag, TRANSFORM) === 20, "keys " + nmLayerKeyCount(like.tag, TRANSFORM).toString();
	assert nmLayerTiming(like.tag, TRANSFORM, 0) === 200;
	frames.runAll();
	assert nmLayerLive(like.tag, TRANSFORM) === 0 && like.model() === 1, "the end leaves the model on the target";
	like.animated.animate(decay(decayConfig(), 2));
	frames.step(3);
	assert nmLayerAnimates() === before + 2, "decay is not handed over";
	assert like.model() > 1, "decay writes the model each frame: " + like.model().toString();
	close();
}

class ForeignNode {
	name: string = "a node another host made";
}

test "a node no native host made keeps its track on signals while a layer engine is installed" {
	const frames = useManualFrames();
	installLayerEngine(bridgeLayerEngine(nativeViewOf, ownsNativeView));
	const app = new Showcase();
	const foreign: HostNode = new ForeignNode();
	assert nativeOwns(app.signals.elements.node("box") as HostNode), "a native view is owned";
	assert !nativeOwns(foreign), "a foreign node is not owned";
	const signals = new MotionSignals();
	signals.number("box", "opacity", 0);
	const before = nmLayerAnimates();
	const clock = new ManualClock();
	nativeMotionPlayer(
		{
			version: 1,
			root: "main",
			clips: [{ id: "main", duration: 1000, tracks: [ramp("opacity", 1)], placements: [], labels: [] }],
		},
		motionElements([{ slot: "box", node: foreign }]),
		signals.bindings,
		motionOptions(clock.clock),
	);
	clock.advance(16);
	clock.advance(484);
	const written = (signals.bindings[0].read as () => MotionValue)().number;
	assert nmLayerAnimates() === before, "nothing handed to a layer";
	assert Math.abs(written - 0.5) < 1e-9, "the binding carries the track: " + written.toString();
	frames.runAll();
	close();
}

class Toggled {
	signals: MotionSignals = new MotionSignals();
	present: Accessor<boolean>;
	setPresent: (present: boolean) => void;
	value: AnimatedValue | null = null;

	constructor(player: boolean) {
		const [present, setPresent] = createSignal(true);
		this.present = present;
		this.setPresent = (next: boolean): void => { setPresent(next); };
		this.signals.number("box", "opacity", 0);
		this.signals.number("box", "translateX", 0);
		this.signals.number("box", "scale", 1);
		this.signals.color("box", "backgroundColor", colorValue(0, 0, 0, 1));
		runApp((): NeonNode => {
			const ref = this.signals.ref("box");
			if (player) {
				useMotion(entrance(), this.signals.bindings);
			} else {
				this.value = useAnimatedValue(1, new MotionPolicy(), this.signals.target("box", "scale"))[1];
			}
			return <View style={{ width: 200, height: 200 }}>
				<Show when={this.present()}>
					<Pressable onPress={() => {}} ref={ref}
						style={[{ width: 40, height: 40 }, this.signals.style("box")]} />
				</Show>
			</View>;
		});
	}

	toggle(present: boolean): void {
		this.setPresent(present);
		nmLoop();
	}

	scale(): float64 {
		const node = this.signals.elements.node("box") as HostNode;
		return (layerEngine() as LayerEngine).read(node, LayerComponent.ScaleX);
	}
}

test "an animated value on a slot inside a Show drives the remounted view and leaves the removed one alone" {
	const frames = useManualFrames();
	installLayerEngine(bridgeLayerEngine(nativeViewOf, ownsNativeView));
	const app = new Toggled(false);
	const first = nmLastPressableTag();
	const value = app.value as AnimatedValue;
	value.animate(timing(2, { duration: 1000, easing: Easing.linear }));
	assert nmLayerLive(first, TRANSFORM) === 1, "handed to the first view";
	frames.step(10);
	app.toggle(false);
	assert app.signals.elements.node("box") === null, "the slot names no view while unmounted";
	const removes = nmLayerRemoves();
	frames.step(10);
	app.toggle(true);
	const second = nmLastPressableTag();
	assert second !== first, "a new view mounted";
	frames.step(1);
	const mid = app.scale();
	assert mid > 1.2 && mid < 2, "the remounted view shows the running value: " + mid.toString();
	frames.runAll();
	assert app.scale() === 2, "the remounted view ends on the target: " + app.scale().toString();
	assert nmLayerRemoves() === removes, "the removed view gets no layer call: " +
		(nmLayerRemoves() - removes).toString();
	close();
}

test "a player on a slot inside a Show hands its remaining tracks to the remounted view" {
	const frames = useManualFrames();
	installLayerEngine(bridgeLayerEngine(nativeViewOf, ownsNativeView));
	const app = new Toggled(true);
	const first = nmLastPressableTag();
	frames.step(1);
	assert nmLayerLive(first, OPACITY) === 1, "handed to the first view";
	frames.step(10);
	app.toggle(false);
	frames.step(5);
	app.toggle(true);
	const second = nmLastPressableTag();
	assert second !== first, "a new view mounted";
	frames.step(1);
	assert nmLayerLive(second, OPACITY) === 1 && nmLayerLive(second, TRANSFORM) === 1,
		"the remounted view carries the tracks";
	frames.runAll();
	assert nmLayerLive(second, OPACITY) === 0 && nmOpacity(second) === 1,
		"the end leaves the remounted view on the last frame: " + nmOpacity(second).toString();
	close();
}
