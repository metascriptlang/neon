import { createRoot, runWithOwner } from "../../src/core/owner";
import { flush, getOwner } from "../../src/core/runtime";
import { Computation } from "../../src/core/types";
import { NeonNode } from "../../src/render/node";
import { Host, HostNode, MockNode, mockHost, render } from "../../src/render/host";
import { Style } from "../../src/render/style";
import { View } from "../../src/components/primitives";
import { ManualFrames, setFrameDriver, useManualFrames } from "../../src/animation/frame";
import { MotionSignals, neonClock, useAnimatedValue, useMotion } from "../../src/motion/neon";
import { Clock } from "pulse/src/clock";
import { flatten } from "pulse/src/compose";
import {
	ConformanceAdapter,
	ConformanceCase,
	ConformancePlayer,
	ConformanceProperty,
	ConformanceScrollGeometry,
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
import { CHANNEL, ConformanceScroller, boundDocument, conformanceReport, translateOf } from "./conformanceBindings";

// The path of every host without a layer engine: MotionSignals bindings, Neon's frame loop as the
// clock, and each property shown through signals.style on a View of the mock host.
class Stage {
	frames: ManualFrames = useManualFrames();
	policy: MotionPolicy;
	signals: MotionSignals = new MotionSignals();
	names: string[] = [];
	root: MockNode;
	disposers: (() => void)[] = [];
	owner: Computation | null = null;
	scroller: ConformanceScroller;

	constructor(scroller: ConformanceScroller, properties: ConformanceProperty[], policy: MotionPolicy) {
		this.policy = policy;
		this.scroller = scroller;
		const host = mockHost();
		const root = host.createElement("root");
		this.root = root as unknown as MockNode;
		for (const property of properties) {
			const slot = property.name;
			this.names.push(slot);
			this.signals.number(slot, CHANNEL, property.initial);
			const signals = this.signals;
			const view = (): NeonNode => <View style={signals.style(slot)} />;
			const node: NeonNode = (h: Host, parent: HostNode, before: HostNode | null): void => {
				view()(h, parent, before);
			};
			this.disposers.push(render(node, host, root));
		}
		this.owner = createRoot((dispose: () => void): Computation | null => {
			this.disposers.push(dispose);
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
			source: this.scroller.source(timing.timeline),
		}));
		player.onStart = (): void => { emit("start"); };
		player.onRepeat = (): void => { emit("repeat"); };
		player.onComplete = (): void => { emit("complete"); };
		player.onInterrupt = (): void => { emit("interrupt"); };
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
		const value = runWithOwner(this.owner, (): AnimatedValue => {
			const [_, made] = useAnimatedValue(target.read!().number, this.policy, target, composition);
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
		while (this.frames.time < time) {
			this.frames.advance(Math.min(CONFORMANCE_FRAME_MS, time - this.frames.time));
		}
	}

	read(property: string): float64 {
		flush();
		const index = this.names.indexOf(property) as int32;
		if (index < 0) { throw new Error("conformance signals: unknown property " + property); }
		const style = this.root.children[index].style;
		if (style === null) { throw new Error("conformance signals: " + property + " has no style"); }
		return translateOf((style as Style).transform as string);
	}

	close(): void {
		for (const dispose of this.disposers) { dispose(); }
		setFrameDriver(null);
	}
}

class SignalsConformance {
	stage: Stage | null = null;
	scroller: ConformanceScroller = new ConformanceScroller();
	adapter: ConformanceAdapter;

	constructor() {
		this.adapter = {
			name: "neon signals",
			support: (testCase: ConformanceCase): ConformanceSupport => ConformanceSupport.Evaluator,
			begin: (properties: ConformanceProperty[], policy: MotionPolicy): void => {
				this.scroller = new ConformanceScroller();
				this.stage = new Stage(this.scroller, properties, policy);
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
			scroll: {
				place: (geometry: ConformanceScrollGeometry): void => { this.scroller.place(geometry); },
				scrollTo: (offset: float64): void => { this.scroller.scrollTo(offset); },
			},
		};
	}

	live(): Stage {
		const stage = this.stage;
		if (stage === null) { throw new Error("conformance signals: no case running"); }
		return stage;
	}
}

test "Neon's signals adapter passes Pulse's conformance suite on the mock host" {
	const results = runConformance(new SignalsConformance().adapter, conformanceCases(), CONFORMANCE_GOLDEN);
	const failures = conformanceReport("neon signals", results);
	assert results.length > 0;
	assert failures.length === 0, failures.join("\n");
}
