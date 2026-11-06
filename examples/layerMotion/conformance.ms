import { nativeViewOf } from "../../src/platform/native/host";
import { motionCommit, motionLayerClock } from "./harness.h";
import { createRoot, runWithOwner } from "../../src/core/owner";
import { getOwner } from "../../src/core/runtime";
import { Computation } from "../../src/core/types";
import { NeonNode } from "../../src/render/node";
import { HostNode } from "../../src/render/hostTypes";
import { View, ViewHandle } from "../../src/components/primitives";
import { setFrameDriver } from "../../src/animation/frame";
import { MotionSignals, neonClock, useAnimatedValue, useMotion } from "../../src/motion/neon";
import { LayerComponent, LayerEngine, LayerProperty, layerEngine } from "../../src/platform/native/layerEngine";
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
import { MotionDocument, linearKeyframe } from "pulse/src/document";
import { MotionBinding, MotionPlayer, motionOptions } from "pulse/src/player";
import { MotionPolicy } from "pulse/src/policy";
import { Composition } from "pulse/src/target";
import { AnimatedValue, AnimationSpec } from "pulse/src/value";
import { CHANNEL, boundDocument, conformanceReport } from "../../tests/motion/conformanceBindings";
import { layerSupport } from "../../tests/platform/layerSupport";
import { exit } from "std/process";

when (macos || ios) {
	@compile("./harness.m", "-fobjc-arc");
}

const POOL: int32 = 3;
const IDENTITY_TRANSFORM: float64[] = [1, 1, 0, 0, 0];

class Views {
	container: HostNode | null = null;
	pool: ViewHandle[] = [];
	time: float64 = 0;
	started: boolean = false;

	get engine(): LayerEngine {
		return layerEngine() as LayerEngine;
	}

	reset(handle: ViewHandle): void {
		this.engine.remove(handle.node, LayerProperty.Transform);
		this.engine.remove(handle.node, LayerProperty.Opacity);
		this.engine.write(handle.node, LayerProperty.Transform, IDENTITY_TRANSFORM);
	}

	step(ms: float64): void {
		this.time += ms;
		motionLayerClock(nativeViewOf(this.container as HostNode), this.time);
	}
}

const views = new Views();

// The pool views sit under one container whose layer clock is stopped and stepped, so real Core
// Animation evaluates each presentation layer at the conformance time.
class Stage {
	fire: (() => void) | null = null;
	origin: float64;
	at: float64 = 0;
	policy: MotionPolicy;
	signals: MotionSignals = new MotionSignals();
	names: string[] = [];
	owner: Computation | null = null;
	disposeOwner: () => void = (): void => {};

	constructor(properties: ConformanceProperty[], policy: MotionPolicy) {
		if (properties.length > POOL) { throw new Error("conformance ca: a case names more properties than the pool holds"); }
		this.policy = policy;
		this.origin = views.time;
		setFrameDriver({
			now: (): number => views.time,
			schedule: (fire: () => void): void => { this.fire = fire; },
		});
		this.owner = createRoot((dispose: () => void): Computation | null => {
			this.disposeOwner = dispose;
			for (let i: int32 = 0; i < properties.length; i += 1) {
				const name = properties[i].name;
				this.names.push(name);
				this.signals.number(name, CHANNEL, properties[i].initial);
				views.reset(views.pool[i]);
				this.signals.ref(name)(views.pool[i]);
			}
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
		while (this.at < time) {
			const ms = Math.min(CONFORMANCE_FRAME_MS, time - this.at);
			this.at += ms;
			views.step(ms);
			const fire = this.fire;
			this.fire = null;
			if (fire !== null) { fire(); }
		}
	}

	read(property: string): float64 {
		const index = this.names.indexOf(property) as int32;
		if (index < 0) { throw new Error("conformance ca: unknown property " + property); }
		motionCommit();
		return presentedComponent(nativeViewOf(views.pool[index].node), LayerComponent.TranslateX);
	}

	close(): void {
		this.disposeOwner();
		for (const handle of views.pool) { views.reset(handle); }
		setFrameDriver(null);
	}
}

class CoreAnimationConformance {
	stage: Stage | null = null;
	adapter: ConformanceAdapter;

	constructor() {
		this.adapter = {
			name: "neon core animation",
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
		if (stage === null) { throw new Error("conformance ca: no case running"); }
		return stage;
	}
}

// A clip handed over at its half while the app thread stops ticking: the layer must hold the end once the
// remaining half has played, where a timeOffset playhead would wrap back to the clip's start.
function midClipHandover(): string[] {
	const stage = new Stage([{ name: "box.x", initial: 0 }], new MotionPolicy());
	const track = [linearKeyframe("a", 0, 0), linearKeyframe("b", 1000, 100)];
	const document: MotionDocument = {
		version: 1,
		root: "main",
		clips: [{
			id: "main",
			duration: 1000,
			tracks: [{ slot: "box", property: "x", kind: track[0].value.kind, keyframes: track }],
			placements: [],
			labels: [],
		}],
	};
	const player = stage.player(document, {
		delay: 0,
		repeat: 0,
		repeatDelay: 0,
		yoyo: false,
		timeScale: 1,
		paused: true,
		composition: Composition.Replace,
		timeline: null,
	}, (event: string): void => {});
	stage.advanceTo(16);
	player.seek(500, true);
	player.play();
	const failures: string[] = [];
	const samples: float64[][] = [[300, 80], [700, 100]];
	let played: float64 = 0;
	for (const sample of samples) {
		views.step(sample[0] - played);
		played = sample[0];
		const shown = stage.read("box.x");
		console.log(`mid-clip handover +${sample[0]} ms: presented ${shown.toFixed(3)}, want ${sample[1]}`);
		if (Math.abs(shown - sample[1]) > 0.5) { failures.push(`mid-clip handover at +${sample[0]} ms shows ${shown}, want ${sample[1]}`); }
	}
	player.dispose();
	stage.close();
	return failures;
}

function run(): void {
	views.step(0);
	const results = runConformance(new CoreAnimationConformance().adapter, conformanceCases(), CONFORMANCE_GOLDEN);
	const failures = conformanceReport("neon core animation", results).concat(midClipHandover());
	for (const failure of failures) { console.log("FAIL " + failure); }
	exit(failures.length as int32);
}

export function MotionConformance(): NeonNode {
	const slots: int32[] = [0, 1, 2];
	return <View style={{ width: 360, height: 200, backgroundColor: "#101820" }}
		ref={(handle: ViewHandle): void => {
			views.container = handle.node;
			if (views.started) { return; }
			views.started = true;
			setTimeout(run, 300);
			setTimeout((): void => {
				console.log("FAIL timeout");
				exit(2);
			}, 60000);
		}}>
		{slots.map((i: int32): NeonNode => <View
			ref={(handle: ViewHandle): void => { views.pool.push(handle); }}
			style={{ position: "absolute", left: 20 + i * 110, top: 50, width: 90, height: 90, backgroundColor: "#2e86de" }} />)}
	</View>;
}
