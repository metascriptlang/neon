import { nativeLayerEngine, nativeViewOf, runApp } from "../../src/platform/native/host";
import { createRoot, runWithOwner } from "../../src/core/owner";
import { getOwner } from "../../src/core/runtime";
import { Computation } from "../../src/core/types";
import { NeonNode } from "../../src/render/node";
import { HostNode } from "../../src/render/hostTypes";
import { View, ViewHandle } from "../../src/components/primitives";
import { setFrameDriver } from "../../src/animation/frame";
import { MotionSignals, neonClock, useAnimatedValue, useMotion } from "../../src/motion/neon";
import { LayerComponent, installLayerEngine } from "../../src/platform/native/layerEngine";
import { presentedComponent } from "../../src/platform/native/layerMotion";
import { Clock } from "pulse/src/clock";
import { flatten } from "pulse/src/compose";
import {
	ConformanceAdapter,
	ConformancePlayer,
	ConformanceProperty,
	ConformanceTiming,
	ConformanceValue,
	runConformance,
} from "pulse/src/conformance";
import { conformanceCases } from "pulse/src/conformanceCases";
import { CONFORMANCE_GOLDEN } from "pulse/src/conformanceGolden";
import { CONFORMANCE_FRAME_MS } from "pulse/src/headless";
import { MotionDocument } from "pulse/src/document";
import { MotionBinding, MotionPlayer, motionOptions } from "pulse/src/player";
import { MotionPolicy } from "pulse/src/policy";
import { Composition } from "pulse/src/target";
import { AnimatedValue, AnimationSpec } from "pulse/src/value";
import { CHANNEL, boundDocument, conformanceReport } from "../motion/conformanceBindings";
import {
	nmLayerSetNow,
	nmTeardown,
	nmViewLayerKeyCount,
	nmViewLayerKeyTime,
	nmViewLayerLive,
	nmViewLayerTiming,
	nmViewLayerValue,
} from "./nativeBridgeMock.h";
import { layerSupport } from "./layerSupport";

@include("./windowsLayerCurve.h");
@compile("./windowsLayerCurve.cpp");

extern function wlmHand(
	view: Ptr<void>,
	property: int32,
	keyTimes: Readonly<Span<float64>>,
	values: Readonly<Span<float64>>,
	durationMs: float64,
	repeatCount: float64,
	autoreverses: int32,
	startMs: float64,
	offsetMs: float64,
	speed: float64,
): void;
extern function wlmTranslateX(view: Ptr<void>, seconds: float64): float64;
extern function wlmReset(): void;

type LayerReader = (node: HostNode, time: float64) => float64;

const TRANSFORM: int32 = 1;
const TRANSFORM_WIDTH: int32 = 5;

function bridgeTranslateX(node: HostNode, time: float64): float64 {
	return presentedComponent(nativeViewOf(node), LayerComponent.TranslateX);
}

// The track the bridge was handed, rebuilt through the Windows bridge's handLayer and sampled from the
// DirectComposition begin time bridge.cpp sets (the composition time at hand-over minus its lag).
function directCompositionTranslateX(node: HostNode, time: float64): float64 {
	const view = nativeViewOf(node);
	if (nmViewLayerLive(view, TRANSFORM) === 0) { return presentedComponent(view, LayerComponent.TranslateX); }
	const keyCount = nmViewLayerKeyCount(view, TRANSFORM);
	const keyTimes: float64[] = [];
	const values: float64[] = [];
	for (let i: int32 = 0; i < keyCount; i += 1) { keyTimes.push(nmViewLayerKeyTime(view, TRANSFORM, i)); }
	for (let i: int32 = 0; i < keyCount * TRANSFORM_WIDTH; i += 1) { values.push(nmViewLayerValue(view, TRANSFORM, i)); }
	const timing = (field: int32): float64 => nmViewLayerTiming(view, TRANSFORM, field);
	wlmHand(view, TRANSFORM, keyTimes, values, timing(0), timing(1), timing(2) as int32, timing(3), timing(4), timing(5));
	const begin = timing(7) - timing(6);
	return wlmTranslateX(view, Math.max(0, time - begin) / 1000);
}

// Each conformance property is a View whose slot is ref'd through MotionSignals, so players and
// values reach the bridge's layer engine; reads go through niLayerPresented at the frame clock.
class Stage {
	time: float64 = 0;
	fire: ((target: number) => void) | null = null;
	policy: MotionPolicy;
	signals: MotionSignals = new MotionSignals();
	names: string[] = [];
	nodes: HostNode[] = [];
	owner: Computation | null = null;
	disposeOwner: () => void = (): void => {};
	reader: LayerReader;

	constructor(properties: ConformanceProperty[], policy: MotionPolicy, reader: LayerReader) {
		this.policy = policy;
		this.reader = reader;
		nmLayerSetNow(0);
		setFrameDriver({
			now: (): number => this.time,
			schedule: (fire: (target: number) => void): void => { this.fire = fire; },
		});
		installLayerEngine(nativeLayerEngine());
		for (const property of properties) {
			this.names.push(property.name);
			this.signals.number(property.name, CHANNEL, property.initial);
		}
		const signals = this.signals;
		const slots = this.names;
		runApp((): NeonNode => <View>{slots.map((slot: string): NeonNode => {
			const declare = signals.ref(slot);
			return <View
				ref={(handle: ViewHandle): void => {
					declare(handle);
					this.nodes.push(handle.node);
				}}
				style={signals.style(slot)} />;
		})}</View>);
		if (this.nodes.length !== slots.length) { throw new Error("conformance native: a View gave no ref"); }
		this.owner = createRoot((dispose: () => void): Computation | null => {
			this.disposeOwner = dispose;
			return getOwner();
		});
	}

	bindings(document: MotionDocument): MotionBinding[] {
		const slots: string[] = flatten(document).map((writer): string => writer.slot);
		return this.signals.bindings.filter((binding: MotionBinding): boolean => slots.includes(binding.slot));
	}

	player(document: MotionDocument, timing: ConformanceTiming, emit: (event: string) => void): ConformancePlayer {
		const bound = boundDocument(document);
		const player = runWithOwner(this.owner, (): MotionPlayer => useMotion(bound, this.bindings(bound), {
			...motionOptions(neonClock()),
			delay: timing.delay,
			repeat: timing.repeat,
			repeatDelay: timing.repeatDelay,
			yoyo: timing.yoyo,
			timeScale: timing.timeScale,
			paused: timing.paused,
			composition: timing.composition,
		}));
		player.onStart = (): void => { emit("start"); };
		player.onRepeat = (): void => { emit("repeat"); };
		player.onComplete = (): void => { emit("complete"); };
		player.onReverseComplete = (): void => { emit("reverseComplete"); };
		player.onInterrupt = (): void => { emit("interrupt"); };
		return {
			play: (): void => { player.play(); },
			pause: (): void => { player.pause(); },
			seek: (position: float64, suppressEvents: boolean): void => { player.seek(position, suppressEvents); },
			reverse: (): void => { player.reverse(); },
			setTimeScale: (rate: float64): void => { player.setTimeScale(rate); },
			cancel: (): void => { player.cancel(); },
			finish: (): void => { player.finish(); },
			revert: (): void => { player.revert(); },
			dispose: (): void => { player.dispose(); },
		};
	}

	value(property: string, composition: Composition): ConformanceValue {
		const target = this.signals.target(property, CHANNEL);
		const initial = this.read(property);
		const value = runWithOwner(this.owner, (): AnimatedValue => {
			const [_, made] = useAnimatedValue(initial, this.policy, target, composition);
			return made;
		});
		return {
			get: (): float64 => value.get(),
			set: (next: float64): void => { value.set(next); },
			animate: (spec: AnimationSpec, onEnd: ((finished: boolean) => void) | null): void => {
				value.animate(spec, onEnd);
			},
			cancel: (): void => { value.cancel(); },
			dispose: (): void => { value.dispose(); },
			subscribe: (callback: (next: float64) => void): (() => void) => value.subscribe(callback),
		};
	}

	advanceTo(time: float64): void {
		while (this.time < time) {
			this.time += Math.min(CONFORMANCE_FRAME_MS, time - this.time);
			nmLayerSetNow(this.time);
			const fire = this.fire;
			this.fire = null;
			if (fire !== null) { fire(this.time); }
		}
	}

	read(property: string): float64 {
		const index = this.names.indexOf(property) as int32;
		if (index < 0) { throw new Error("conformance native: unknown property " + property); }
		return this.reader(this.nodes[index], this.time);
	}

	close(): void {
		this.disposeOwner();
		nmTeardown();
		wlmReset();
		installLayerEngine(null);
		setFrameDriver(null);
	}
}

class LayerConformance {
	stage: Stage | null = null;
	adapter: ConformanceAdapter;

	constructor(name: string, reader: LayerReader) {
		this.adapter = {
			name,
			support: layerSupport,
			begin: (properties: ConformanceProperty[], policy: MotionPolicy): void => {
				this.stage = new Stage(properties, policy, reader);
			},
			player: (document: MotionDocument, timing: ConformanceTiming, emit: (event: string) => void): ConformancePlayer =>
				this.live().player(document, timing, emit),
			value: (property: string, composition: Composition): ConformanceValue => this.live().value(property, composition),
			clock: (): Clock => neonClock(),
			advanceTo: (time: float64): void => { this.live().advanceTo(time); },
			read: (property: string): float64 => this.live().read(property),
			end: (): void => {
				const stage = this.stage;
				this.stage = null;
				if (stage !== null) { stage.close(); }
			},
		};
	}

	live(): Stage {
		const stage = this.stage;
		if (stage === null) { throw new Error("conformance native: no case running"); }
		return stage;
	}
}

test "the native layer engine passes Pulse's conformance suite on the mock bridge" {
	const results = runConformance(new LayerConformance("neon native layer", bridgeTranslateX).adapter, conformanceCases(), CONFORMANCE_GOLDEN);
	const failures = conformanceReport("neon native layer", results);
	assert results.length > 0;
	assert failures.length === 0, failures.join("\n");
}

test "the curves the Windows bridge hands DirectComposition pass Pulse's conformance suite" {
	const name = "neon DirectComposition curves";
	const results = runConformance(new LayerConformance(name, directCompositionTranslateX).adapter, conformanceCases(), CONFORMANCE_GOLDEN);
	const failures = conformanceReport(name, results);
	assert results.length > 0;
	assert failures.length === 0, failures.join("\n");
}
