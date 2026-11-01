import { domHost, documentBody } from "../../src/platform/browser/dom";
import { createRoot, runWithOwner } from "../../src/core/owner";
import { getOwner } from "../../src/core/runtime";
import { Computation } from "../../src/core/types";
import { HostNode } from "../../src/render/hostTypes";
import { render } from "../../src/render/host";
import { element } from "../../src/macros/ui/element";
import { View, ViewHandle } from "../../src/components/primitives";
import { setFrameDriver } from "../../src/animation/frame";
import { MotionSignals, neonClock, useAnimatedValue, useMotion } from "../../src/motion/neon";
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

extern class HTMLElement {
	extern remove(): void;
}

extern function computed(el: HTMLElement, property: string): string from "getComputedStyle(#)[#]";

extern class VirtualClock {
	t: float64;
}

// runConformance is synchronous and Chrome's document timeline holds still within one task, so the
// page's clocks (document.timeline, performance.now, setTimeout) and every running Animation's
// currentTime advance together on a virtual time this harness steps.
extern function installVirtualClock(): VirtualClock from
	"(() => { const t0 = document.timeline.currentTime ?? performance.now(); const c = { t: t0, timers: [], next: 1, now: performance.now, setTimeout: globalThis.setTimeout, clearTimeout: globalThis.clearTimeout, startTime: Object.getOwnPropertyDescriptor(Animation.prototype, 'startTime') }; performance.now = () => c.t; Object.defineProperty(document.timeline, 'currentTime', { configurable: true, get: () => c.t }); globalThis.setTimeout = (fn, ms) => { const id = c.next++; c.timers.push({ id, due: c.t + Math.max(0, ms || 0), fn }); return id; }; globalThis.clearTimeout = (id) => { c.timers = c.timers.filter((x) => x.id !== id); }; Object.defineProperty(Animation.prototype, 'startTime', { configurable: true, get() { return c.startTime.get.call(this); }, set(v) { if (v === null) { c.startTime.set.call(this, v); } else { this.currentTime = (c.t - v) * this.playbackRate; } } }); return c; })()";

extern function stepVirtualClock(clock: VirtualClock, to: float64): void from
	"((c, to) => { for (let fired = 0; ; fired++) { if (fired > 100000) { throw new Error('virtual clock: timers keep firing at ' + c.t); } const due = c.timers.filter((x) => x.due <= to).sort((a, b) => a.due - b.due || a.id - b.id)[0]; const at = due ? due.due : to; if (at > c.t) { for (const a of document.getAnimations()) { if (a.playState === 'running') { a.currentTime += (at - c.t) * a.playbackRate; } } c.t = at; } if (!due) { return; } c.timers = c.timers.filter((x) => x !== due); due.fn(); } })(#, #)";

extern function removeVirtualClock(clock: VirtualClock): void from
	"(c => { performance.now = c.now; delete document.timeline.currentTime; globalThis.setTimeout = c.setTimeout; globalThis.clearTimeout = c.clearTimeout; Object.defineProperty(Animation.prototype, 'startTime', c.startTime); })(#)";

// waapi.ms planWaapi gives a player with a repeat delay no WAAPI timing.
const REPEAT_DELAY: string[] = ["time.repeat"];
// neon.ms useAnimatedValue: a value that is not Replace runs through signals.
const NOT_REPLACE: string[] = ["contention.blend", "contention.none"];
// waapi.ms ElementValue.animate hands over a spring only; timing, decay, sequence and a reduced
// spring stay on Pulse.
const UNHANDED_VALUES: string[] = [
	"retarget.timing",
	"contention.replace",
	"reducedMotion",
	"decay",
	"sequence",
	"composite.parallel",
	"composite.parallelStop",
	"composite.staggered",
	"composite.loop",
	"event",
];
// The reads are derived values Pulse computes; WAAPI would mix a colour in sRGB.
const DERIVED_READS: string[] = ["derived", "derived.color"];

function waapiSupport(testCase: ConformanceCase): ConformanceSupport {
	const name = testCase.name;
	const evaluated = REPEAT_DELAY.includes(name) || NOT_REPLACE.includes(name) ||
		UNHANDED_VALUES.includes(name) || DERIVED_READS.includes(name);
	return evaluated ? ConformanceSupport.Evaluator : ConformanceSupport.Engine;
}

class Stage {
	clock: VirtualClock;
	origin: float64;
	time: float64 = 0;
	fire: (() => void) | null = null;
	policy: MotionPolicy;
	signals: MotionSignals = new MotionSignals();
	names: string[] = [];
	nodes: HostNode[] = [];
	disposers: (() => void)[] = [];
	owner: Computation | null = null;

	constructor(clock: VirtualClock, properties: ConformanceProperty[], policy: MotionPolicy) {
		this.clock = clock;
		this.origin = clock.t;
		this.policy = policy;
		setFrameDriver({
			now: (): number => this.clock.t,
			schedule: (fire: () => void): void => { this.fire = fire; },
		});
		for (const property of properties) {
			this.names.push(property.name);
			this.signals.number(property.name, CHANNEL, property.initial);
		}
		for (const slot of this.names) {
			const signals = this.signals;
			const declare = signals.ref(slot);
			this.disposers.push(render(
				element(<View
					ref={(handle: ViewHandle): void => {
						declare(handle);
						this.nodes.push(handle.node);
					}}
					style={signals.style(slot)} />),
				domHost(),
				documentBody(),
			));
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
			stepVirtualClock(this.clock, this.origin + this.time);
			const fire = this.fire;
			this.fire = null;
			if (fire !== null) { fire(); }
		}
	}

	read(property: string): float64 {
		const index = this.names.indexOf(property) as int32;
		if (index < 0) { throw new Error("conformance waapi: unknown property " + property); }
		const shown = computed(this.nodes[index] as unknown as HTMLElement, "translate");
		return shown === "none" ? 0 : parseFloat(shown);
	}

	close(): void {
		for (const dispose of this.disposers) { dispose(); }
		for (const node of this.nodes) { (node as unknown as HTMLElement).remove(); }
		setFrameDriver(null);
	}
}

class WaapiConformance {
	clock: VirtualClock;
	stage: Stage | null = null;
	adapter: ConformanceAdapter;

	constructor(clock: VirtualClock) {
		this.clock = clock;
		this.adapter = {
			name: "neon waapi",
			support: waapiSupport,
			begin: (properties: ConformanceProperty[], policy: MotionPolicy): void => {
				this.stage = new Stage(this.clock, properties, policy);
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
		if (stage === null) { throw new Error("conformance waapi: no case running"); }
		return stage;
	}
}

test "Neon's WAAPI adapter passes Pulse's conformance suite in Chrome" {
	const clock = installVirtualClock();
	let failures: string[] = [];
	try {
		const results = runConformance(new WaapiConformance(clock).adapter, conformanceCases(), CONFORMANCE_GOLDEN);
		assert results.length > 0;
		failures = conformanceReport("neon waapi", results);
	} finally {
		removeVirtualClock(clock);
	}
	assert failures.length === 0, failures.join("\n");
}
