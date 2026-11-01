import { nativeViewOf, runApp } from "../../src/platform/native/host";
import { createRoot, runWithOwner } from "../../src/core/owner";
import { getOwner } from "../../src/core/runtime";
import { Computation } from "../../src/core/types";
import { NeonNode } from "../../src/render/node";
import { HostNode } from "../../src/render/hostTypes";
import { View, ViewHandle } from "../../src/components/primitives";
import { setFrameDriver } from "../../src/animation/frame";
import { MotionSignals, neonClock, useAnimatedValue, useMotion } from "../../src/motion/neon";
import { LayerComponent, installLayerEngine } from "../../src/platform/native/layerEngine";
import { bridgeLayerEngine, presentedComponent } from "../../src/platform/native/layerMotion";
import { Clock } from "pulse/src/clock";
import { flatten } from "pulse/src/compose";
import {
	ConformanceAdapter,
	ConformanceCase,
	ConformancePlayer,
	ConformanceProperty,
	ConformanceSupport,
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
import { nmLayerSetNow, nmTeardown } from "./nativeBridgeMock.h";

// native.ms planLayers: a player that repeats with a repeat delay is not handable.
const REPEAT_DELAY: string[] = ["time.repeat"];
// NativeRuns.alignAll hands a run over only while the player runs; these stay paused.
const PAUSED_PLAYERS: string[] = ["seek.silent", "seek.events"];
// neon.ms animatedValue: a value that is not Replace runs through signals, not the layer.
const NOT_REPLACE: string[] = ["contention.blend", "contention.none"];
// NativeElementValue.animate hands over spring and timing only.
const UNHANDED_SPECS: string[] = ["decay", "sequence"];
// The reads are derived values Pulse computes on the app thread.
const DERIVED_READS: string[] = ["derived", "derived.color"];

export function layerSupport(testCase: ConformanceCase): ConformanceSupport {
	const name = testCase.name;
	const evaluated = REPEAT_DELAY.includes(name) || PAUSED_PLAYERS.includes(name) ||
		NOT_REPLACE.includes(name) || UNHANDED_SPECS.includes(name) || DERIVED_READS.includes(name);
	return evaluated ? ConformanceSupport.Evaluator : ConformanceSupport.Engine;
}

// Each conformance property is a View whose slot is ref'd through MotionSignals, so players and
// values reach the bridge's layer engine; reads go through niLayerPresented at the frame clock.
class Stage {
	time: float64 = 0;
	fire: (() => void) | null = null;
	policy: MotionPolicy;
	signals: MotionSignals = new MotionSignals();
	names: string[] = [];
	nodes: HostNode[] = [];
	owner: Computation | null = null;
	disposeOwner: () => void = (): void => {};

	constructor(properties: ConformanceProperty[], policy: MotionPolicy) {
		this.policy = policy;
		nmLayerSetNow(0);
		setFrameDriver({
			now: (): number => this.time,
			schedule: (fire: () => void): void => { this.fire = fire; },
		});
		installLayerEngine(bridgeLayerEngine(nativeViewOf));
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
			if (fire !== null) { fire(); }
		}
	}

	read(property: string): float64 {
		const index = this.names.indexOf(property) as int32;
		if (index < 0) { throw new Error("conformance native: unknown property " + property); }
		return presentedComponent(nativeViewOf(this.nodes[index]), LayerComponent.TranslateX);
	}

	close(): void {
		this.disposeOwner();
		nmTeardown();
		installLayerEngine(null);
		setFrameDriver(null);
	}
}

class LayerConformance {
	stage: Stage | null = null;
	adapter: ConformanceAdapter;

	constructor() {
		this.adapter = {
			name: "neon native layer",
			support: layerSupport,
			begin: (properties: ConformanceProperty[], policy: MotionPolicy): void => {
				this.stage = new Stage(properties, policy);
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
	const results = runConformance(new LayerConformance().adapter, conformanceCases(), CONFORMANCE_GOLDEN);
	const failures = conformanceReport("neon native layer", results);
	assert results.length > 0;
	assert failures.length === 0, failures.join("\n");
}
