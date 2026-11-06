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
import { elementScrollSource, elementViewSubject } from "../../src/motion/waapi";
import { Clock } from "pulse/src/clock";
import { flatten } from "pulse/src/compose";
import {
	ConformanceAdapter,
	ConformanceCase,
	ConformanceCheckpoint,
	ConformancePlayer,
	ConformanceProperty,
	ConformanceResult,
	ConformanceScene,
	ConformanceScrollGeometry,
	ConformanceSupport,
	ConformanceTimeline,
	ConformanceTiming,
	ConformanceTrace,
	ConformanceValue,
	compare,
	runConformance,
} from "pulse/src/conformance";
import { conformanceCases } from "pulse/src/conformanceCases";
import { CONFORMANCE_GOLDEN } from "pulse/src/conformanceGolden";
import { CONFORMANCE_FRAME_MS } from "pulse/src/headless";
import { MotionDocument } from "pulse/src/document";
import { MotionBinding, MotionPlayer, motionOptions } from "pulse/src/player";
import { MotionPolicy } from "pulse/src/policy";
import { TimeSource, TimeSourceKind, scrollSource, timeSource, viewSource } from "pulse/src/scroll";
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
	"((c, to) => { for (let fired = 0; ; fired++) { if (fired > 100000) { throw new Error('virtual clock: timers keep firing at ' + c.t); } const due = c.timers.filter((x) => x.due <= to).sort((a, b) => a.due - b.due || a.id - b.id)[0]; const at = due ? due.due : to; if (at > c.t) { for (const a of document.getAnimations()) { if (a.playState === 'running' && a.timeline === document.timeline) { a.currentTime += (at - c.t) * a.playbackRate; } } c.t = at; } if (!due) { return; } c.timers = c.timers.filter((x) => x !== due); due.fn(); } })(#, #)";

extern function removeVirtualClock(clock: VirtualClock): void from
	"(c => { performance.now = c.now; delete document.timeline.currentTime; globalThis.setTimeout = c.setTimeout; globalThis.clearTimeout = c.clearTimeout; Object.defineProperty(Animation.prototype, 'startTime', c.startTime); })(#)";

// waapi.ms planWaapi gives a player with a repeat delay no WAAPI timing.
const REPEAT_DELAY: string[] = ["time.repeat"];
// neon.ms useAnimatedValue: a value that is not Replace runs through signals.
const NOT_REPLACE: string[] = ["contention.blend", "contention.none"];
// waapi.ms ElementValue.animate hands over a spring or a timing; decay and a sequence stay on Pulse.
const UNHANDED_VALUES: string[] = ["decay", "sequence"];
// The reads are derived values Pulse computes; WAAPI would mix a colour in sRGB.
const DERIVED_READS: string[] = ["derived", "derived.color"];

extern function makeScroller(): HTMLElement from
	"(() => { const s = document.createElement('div'); const c = document.createElement('div'); const subject = document.createElement('div'); s.style.cssText = 'position: relative; width: 50px; overflow-x: hidden; overflow-y: scroll'; c.style.cssText = 'position: relative; overflow: clip'; subject.style.cssText = 'position: absolute; left: 0; width: 10px'; c.append(subject); s.append(c); document.body.append(s); return s; })()";
extern function placeScroller(scroller: HTMLElement, geometry: ConformanceScrollGeometry): void from
	"((s, g) => { s.style.height = g.viewport + 'px'; s.firstChild.style.height = (g.viewport + g.max) + 'px'; s.firstChild.firstChild.style.top = g.subjectStart + 'px'; s.firstChild.firstChild.style.height = g.subjectSize + 'px'; })(#, #)";
extern function scrollerSubject(scroller: HTMLElement): HTMLElement from "(s => s.firstChild.firstChild)(#)";
extern function setScrollTop(scroller: HTMLElement, offset: float64): void from "((s, o) => { s.scrollTop = o; })(#, #)";
// A scroll timeline's progress is snapshotted once per rendering frame (scroll-animations-1 §5),
// and a new animation on it is pending until the frame after.
extern function renderedFrames(): Promise<void> from
	"new Promise((done) => requestAnimationFrame(() => requestAnimationFrame(() => done())))";
extern function hideTimelines(): () => void from
	"(() => { const saved = [globalThis.ScrollTimeline, globalThis.ViewTimeline]; delete globalThis.ScrollTimeline; delete globalThis.ViewTimeline; return () => { globalThis.ScrollTimeline = saved[0]; globalThis.ViewTimeline = saved[1]; }; })()";

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
	scroller: HTMLElement | null = null;

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
			source: this.source(timing.timeline),
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

	place(geometry: ConformanceScrollGeometry): void {
		const scroller = this.scroller ?? makeScroller();
		this.scroller = scroller;
		placeScroller(scroller, geometry);
	}

	scrollTo(offset: float64): void {
		setScrollTop(this.scroller as HTMLElement, offset);
	}

	source(timeline: ConformanceTimeline | null): TimeSource {
		if (timeline === null) { return timeSource(); }
		const scroller = this.scroller as HTMLElement;
		const node = scroller as unknown as HostNode;
		const source = elementScrollSource(node);
		return match (timeline.kind) {
			TimeSourceKind.Time => timeSource(),
			TimeSourceKind.Scroll => scrollSource(source, timeline.axis),
			TimeSourceKind.View => viewSource(
				source,
				elementViewSubject(scrollerSubject(scroller) as unknown as HostNode, node),
				timeline.range,
				timeline.inset,
				timeline.axis,
			),
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
		const scroller = this.scroller;
		if (scroller !== null) { scroller.remove(); }
		setFrameDriver(null);
	}
}

class WaapiConformance {
	clock: VirtualClock;
	stage: Stage | null = null;
	adapter: ConformanceAdapter;

	constructor(clock: VirtualClock, timelines: boolean) {
		this.clock = clock;
		this.adapter = {
			name: timelines ? "neon waapi" : "neon waapi without scroll timelines",
			support: (testCase: ConformanceCase): ConformanceSupport =>
				testCase.scroll !== null && !timelines ? ConformanceSupport.Evaluator : waapiSupport(testCase),
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
			scroll: {
				place: (geometry: ConformanceScrollGeometry): void => { this.live().place(geometry); },
				scrollTo: (offset: float64): void => { this.live().scrollTo(offset); },
			},
		};
	}

	live(): Stage {
		const stage = this.stage;
		if (stage === null) { throw new Error("conformance waapi: no case running"); }
		return stage;
	}
}

async function observeScrolled(adapter: ConformanceAdapter, testCase: ConformanceCase): Promise<ConformanceTrace> {
	const checkpoints: ConformanceCheckpoint[] = [];
	let error = "";
	try {
		const scene = new ConformanceScene(adapter, testCase);
		let step: int32 = 0;
		let checkpoint: int32 = 0;
		while (checkpoint < testCase.checkpoints.length) {
			const at = testCase.checkpoints[checkpoint];
			if (step < testCase.steps.length && testCase.steps[step].at <= at) {
				adapter.advanceTo(testCase.steps[step].at);
				testCase.steps[step].run(scene);
				step += 1;
				continue;
			}
			adapter.advanceTo(at);
			await renderedFrames();
			checkpoints.push({
				at,
				values: testCase.reads.map((name: string): float64 => scene.read(name)),
				events: scene.drain(),
			});
			checkpoint += 1;
		}
	} catch (e) {
		error = e.message;
	}
	adapter.end();
	return { name: testCase.name, error, checkpoints };
}

async function runScrolled(adapter: ConformanceAdapter): Promise<ConformanceResult[]> {
	const results: ConformanceResult[] = [];
	for (const testCase of conformanceCases()) {
		if (testCase.scroll === null) { continue; }
		const support = adapter.support(testCase);
		const golden = CONFORMANCE_GOLDEN.filter((trace: ConformanceTrace): boolean => trace.name === testCase.name);
		if (golden.length !== 1) {
			results.push({ name: testCase.name, support, failures: [testCase.name + ": no golden trace"] });
			continue;
		}
		const observed = await observeScrolled(adapter, testCase);
		results.push({
			name: testCase.name,
			support,
			failures: compare(testCase, support, golden[0], observed, testCase.tolerance),
		});
	}
	return results;
}

test "Neon's WAAPI adapter passes Pulse's conformance suite in Chrome" {
	const clock = installVirtualClock();
	let failures: string[] = [];
	try {
		const adapter = new WaapiConformance(clock, true).adapter;
		const timed = conformanceCases().filter((testCase: ConformanceCase): boolean => testCase.scroll === null);
		const results = runConformance(adapter, timed, CONFORMANCE_GOLDEN);
		for (const result of await runScrolled(adapter)) { results.push(result); }
		assert results.length === conformanceCases().length;
		failures = conformanceReport("neon waapi", results);
	} finally {
		removeVirtualClock(clock);
	}
	assert failures.length === 0, failures.join("\n");
}

test "without ScrollTimeline a scroll or view player runs on the evaluator with the same trace" {
	const clock = installVirtualClock();
	const restore = hideTimelines();
	let failures: string[] = [];
	try {
		const adapter = new WaapiConformance(clock, false).adapter;
		failures = conformanceReport("neon waapi without scroll timelines", await runScrolled(adapter));
	} finally {
		restore();
		removeVirtualClock(clock);
	}
	assert failures.length === 0, failures.join("\n");
}
