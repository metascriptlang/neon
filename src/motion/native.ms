import { HostNode } from "../render/hostTypes";
import {
	LayerComponent,
	LayerEngine,
	LayerProperty,
	LayerTiming,
	componentCount,
	layerEngine,
} from "../platform/native/layerEngine";
import { MotionElements, frameClock } from "./waapi";
import { Clock } from "pulse/src/clock";
import { ComposedTrack, flatten, localTime } from "pulse/src/compose";
import {
	MotionDocument,
	MotionValue,
	ValueKind,
	findClip,
	numberValue,
	validate,
} from "pulse/src/document";
import { sampleTrack } from "pulse/src/evaluate";
import { MotionBinding, MotionOptions, MotionPlayer } from "pulse/src/player";
import { MotionPolicy } from "pulse/src/policy";
import { ProgressCurve, sampleEasing, sampleSpring } from "pulse/src/progress";
import { createSpring } from "pulse/src/spring";
import { Composition, MotionTarget } from "pulse/src/target";
import { AnimatedValue, AnimationKind, AnimationSpec } from "pulse/src/value";

const SAMPLE_STEP_MS: float64 = 10;

export struct LayerChannel {
	name: string;
	property: LayerProperty;
	components: LayerComponent[];
}

export enum LayerRoute {
	Compositor,
	Evaluator,
}

export struct LayerTrack {
	channel: LayerChannel;
	writer: ComposedTrack;
	writers: int32;
}

export struct LayerRun {
	slot: string;
	property: LayerProperty;
	route: LayerRoute;
	tracks: LayerTrack[];
}

export struct LayerPlan {
	iterationMs: float64;
	runs: LayerRun[];
}

const LAYER_CHANNELS: LayerChannel[] = [
	{
		name: "opacity",
		property: LayerProperty.Opacity,
		components: [LayerComponent.Opacity],
	},
	{
		name: "translateX",
		property: LayerProperty.Transform,
		components: [LayerComponent.TranslateX],
	},
	{
		name: "translateY",
		property: LayerProperty.Transform,
		components: [LayerComponent.TranslateY],
	},
	{
		name: "rotate",
		property: LayerProperty.Transform,
		components: [LayerComponent.Rotation],
	},
	{
		name: "scale",
		property: LayerProperty.Transform,
		components: [LayerComponent.ScaleX, LayerComponent.ScaleY],
	},
	{
		name: "scaleX",
		property: LayerProperty.Transform,
		components: [LayerComponent.ScaleX],
	},
	{
		name: "scaleY",
		property: LayerProperty.Transform,
		components: [LayerComponent.ScaleY],
	},
];

const OPACITY_COMPONENTS: LayerComponent[] = [LayerComponent.Opacity];
const TRANSFORM_COMPONENTS: LayerComponent[] = [
	LayerComponent.ScaleX,
	LayerComponent.ScaleY,
	LayerComponent.TranslateX,
	LayerComponent.TranslateY,
	LayerComponent.Rotation,
];

function fail(message: string): never {
	throw new Error("motion: " + message);
}

export function layerChannel(name: string): LayerChannel | null {
	for (const channel of LAYER_CHANNELS) {
		if (channel.name === name) {
			return channel;
		}
	}
	return null;
}

function componentsOf(property: LayerProperty): LayerComponent[] {
	return match (property) {
		LayerProperty.Opacity => OPACITY_COMPONENTS,
		LayerProperty.Transform => TRANSFORM_COMPONENTS,
	};
}

function componentIndex(component: LayerComponent): int32 {
	return match (component) {
		LayerComponent.Opacity => 0,
		LayerComponent.ScaleX => 0,
		LayerComponent.ScaleY => 1,
		LayerComponent.TranslateX => 2,
		LayerComponent.TranslateY => 3,
		LayerComponent.Rotation => 4,
	};
}

function componentName(component: LayerComponent): string {
	return match (component) {
		LayerComponent.Opacity => "opacity",
		LayerComponent.ScaleX => "scaleX",
		LayerComponent.ScaleY => "scaleY",
		LayerComponent.TranslateX => "translateX",
		LayerComponent.TranslateY => "translateY",
		LayerComponent.Rotation => "rotation",
	};
}

function refuseSharedComponent(run: LayerRun): void {
	const seen: LayerComponent[] = [];
	const owners: string[] = [];
	for (const track of run.tracks) {
		for (const component of track.channel.components) {
			const at = seen.indexOf(component);
			if (at >= 0) {
				fail(
					run.slot +
						"." +
						owners[at] +
						" and " +
						run.slot +
						"." +
						track.channel.name +
						" both write the native " +
						componentName(component),
				);
			}
			seen.push(component);
			owners.push(track.channel.name);
		}
	}
}

function handable(
	run: LayerRun,
	options: MotionOptions,
	iterationMs: float64,
): boolean {
	if (iterationMs <= 0 || options.composition === Composition.Blend) {
		return false;
	}
	if (options.repeat !== 0 && options.repeatDelay !== 0) {
		return false;
	}
	return run.tracks.every(
		(track: LayerTrack): boolean =>
			track.writers === 1 && track.writer.start === 0,
	);
}

export function planLayers(
	doc: MotionDocument,
	options: MotionOptions,
	custom: string[],
): LayerPlan {
	validate(doc);
	const iterationMs = findClip(doc, doc.root).duration;
	const names: string[] = [];
	const tracks: LayerTrack[] = [];
	const slots: string[] = [];
	for (const writer of flatten(doc)) {
		const name = writer.slot + "." + writer.track.property;
		if (custom.includes(name)) {
			continue;
		}
		const index = names.indexOf(name);
		if (index >= 0) {
			tracks[index] = { ...tracks[index], writers: tracks[index].writers + 1 };
			continue;
		}
		const channel = layerChannel(writer.track.property);
		if (channel === null) {
			fail("no native layer binding for track " + name);
		}
		if (writer.track.kind !== ValueKind.Number) {
			fail(
				"track " +
					name +
					" holds a colour but the native " +
					channel.name +
					" takes a number",
			);
		}
		names.push(name);
		slots.push(writer.slot);
		tracks.push({ channel, writer, writers: 1 });
	}
	const runs: LayerRun[] = [];
	for (let i: int32 = 0; i < tracks.length; i += 1) {
		const property = tracks[i].channel.property;
		const at = runs.findIndex(
			(run: LayerRun): boolean =>
				run.slot === slots[i] && run.property === property,
		);
		if (at >= 0) {
			runs[at].tracks.push(tracks[i]);
		} else {
			runs.push({
				slot: slots[i],
				property,
				route: LayerRoute.Evaluator,
				tracks: [tracks[i]],
			});
		}
	}
	for (let i: int32 = 0; i < runs.length; i += 1) {
		refuseSharedComponent(runs[i]);
		if (handable(runs[i], options, iterationMs)) {
			runs[i] = { ...runs[i], route: LayerRoute.Compositor };
		}
	}
	return { iterationMs, runs };
}

export function sampleTimes(run: LayerRun, iterationMs: float64): float64[] {
	const intervals = Math.max(Math.ceil(iterationMs / SAMPLE_STEP_MS), 1);
	const times: float64[] = [];
	for (let i: int32 = 0; i <= intervals; i += 1) {
		times.push((iterationMs * (i as float64)) / (intervals as float64));
	}
	for (const track of run.tracks) {
		const writer = track.writer;
		for (const key of writer.track.keyframes) {
			const time = writer.start + key.time / writer.rate;
			if (time > 0 && time < iterationMs && !times.includes(time)) {
				times.push(time);
			}
		}
	}
	return times.sort((a: float64, b: float64): float64 => a - b);
}

class LayerHold {
	yieldLayer: () => void;

	constructor(yieldLayer: () => void) {
		this.yieldLayer = yieldLayer;
	}
}

class LayerSlot {
	node: HostNode;
	property: LayerProperty;
	user: LayerHold | null = null;

	constructor(node: HostNode, property: LayerProperty) {
		this.node = node;
		this.property = property;
	}
}

let layerSlots: LayerSlot[] = [];

function occupy(
	node: HostNode,
	property: LayerProperty,
	user: LayerHold,
): void {
	let found: LayerSlot | null = null;
	for (const entry of layerSlots) {
		if (entry.node === node && entry.property === property) {
			found = entry;
		}
	}
	const slot = found ?? new LayerSlot(node, property);
	if (found === null) {
		layerSlots.push(slot);
	}
	const rival = slot.user;
	slot.user = user;
	if (rival !== null && rival !== user) {
		rival.yieldLayer();
	}
}

function vacate(user: LayerHold): void {
	for (const entry of layerSlots) {
		if (entry.user === user) {
			entry.user = null;
		}
	}
	layerSlots = layerSlots.filter(
		(entry: LayerSlot): boolean => entry.user !== null,
	);
}

class TargetEntry {
	target: MotionTarget;
	holder: LayerHold | null = null;

	constructor(target: MotionTarget) {
		this.target = target;
		target.onClaim = (): void => {
			const holder = this.holder;
			this.holder = null;
			if (holder !== null) {
				holder.yieldLayer();
			}
		};
	}
}

let targetEntries: TargetEntry[] = [];

function entryOf(target: MotionTarget): TargetEntry {
	for (const entry of targetEntries) {
		if (entry.target === target) {
			return entry;
		}
	}
	const entry = new TargetEntry(target);
	targetEntries.push(entry);
	return entry;
}

class ElementTarget {
	node: HostNode;
	name: string;
	target: MotionTarget = new MotionTarget();

	constructor(node: HostNode, name: string) {
		this.node = node;
		this.name = name;
	}
}

let elementTargets: ElementTarget[] = [];

function elementTarget(node: HostNode, name: string): MotionTarget {
	for (const entry of elementTargets) {
		if (entry.node === node && entry.name === name) {
			return entry.target;
		}
	}
	const entry = new ElementTarget(node, name);
	elementTargets.push(entry);
	return entry.target;
}

function resolvedNode(elements: MotionElements, slot: string): HostNode | null {
	if (layerEngine() === null) {
		return null;
	}
	return elements.node(slot);
}

function keyedAt(
	keys: float64[],
	values: float64[],
	width: int32,
	progress: float64,
): float64[] {
	let right: int32 = 1;
	while (right < keys.length - 1 && keys[right] < progress) {
		right += 1;
	}
	const left = right - 1;
	const span = keys[right] - keys[left];
	const t =
		span > 0 ? Math.min(1, Math.max(0, (progress - keys[left]) / span)) : 1;
	const out: float64[] = [];
	for (let i: int32 = 0; i < width; i += 1) {
		const a = values[left * width + i];
		const b = values[right * width + i];
		out.push(a + (b - a) * t);
	}
	return out;
}

class NativeRun {
	hold: LayerHold = new LayerHold((): void => {});
	plan: LayerRun;
	elements: MotionElements;
	fallbacks: (MotionBinding | null)[];
	entries: TargetEntry[] = [];
	node: HostNode | null = null;
	clock: Clock;
	times: float64[];
	iterationMs: float64;
	last: float64[] = [];
	live: boolean = false;
	evicted: boolean = false;
	begin: float64 = 0;
	keyTimes: float64[] = [];
	values: float64[] = [];
	model: float64[] = [];
	timing: LayerTiming = {
		durationMs: 0,
		repeatCount: 0,
		autoreverses: false,
		startMs: 0,
		offsetMs: 0,
		speed: 1,
	};

	constructor(
		plan: LayerRun,
		elements: MotionElements,
		fallbacks: (MotionBinding | null)[],
		clock: Clock,
		iterationMs: float64,
	) {
		this.plan = plan;
		this.elements = elements;
		this.fallbacks = fallbacks;
		this.clock = clock;
		this.iterationMs = iterationMs;
		this.times =
			plan.route === LayerRoute.Compositor
				? sampleTimes(plan, iterationMs)
				: [];
		this.hold = new LayerHold((): void => this.yieldLayer());
		const eager = elements.node(plan.slot);
		for (let i: int32 = 0; i < plan.tracks.length; i += 1) {
			const fallback = fallbacks[i];
			const own = fallback === null ? null : (fallback.target ?? null);
			const name = plan.tracks[i].channel.name;
			if (own !== null) {
				this.entries.push(entryOf(own as MotionTarget));
			} else if (eager !== null) {
				this.entries.push(entryOf(elementTarget(eager as HostNode, name)));
			} else {
				fail("no element and no binding for track " + plan.slot + "." + name);
			}
		}
	}

	get width(): int32 {
		return componentCount(this.plan.property);
	}

	get engine(): LayerEngine {
		return layerEngine() as LayerEngine;
	}

	get layerNode(): HostNode {
		return this.node as HostNode;
	}

	resolve(): boolean {
		if (this.node === null) {
			this.node = resolvedNode(this.elements, this.plan.slot);
		}
		return this.node !== null;
	}

	modelNow(): float64[] {
		return componentsOf(this.plan.property).map(
			(component: LayerComponent): float64 =>
				this.engine.read(this.layerNode, component),
		);
	}

	record(index: int32, value: float64): void {
		if (this.last.length === 0) {
			this.last = this.modelNow();
		}
		for (const component of this.plan.tracks[index].channel.components) {
			this.last[componentIndex(component)] = value;
		}
	}

	read(index: int32): MotionValue {
		const component = this.plan.tracks[index].channel.components[0];
		if (this.resolve()) {
			const value = this.live
				? this.presented()[componentIndex(component)]
				: this.engine.read(this.layerNode, component);
			return numberValue(value);
		}
		const fallback = this.fallbacks[index];
		const read = fallback === null ? null : fallback.read;
		return read === null ? numberValue(0) : read();
	}

	tupleAt(time: float64): float64[] {
		const out = this.last.slice(0);
		for (const track of this.plan.tracks) {
			const writer = track.writer;
			const value = sampleTrack(writer.track, writer.localTime(time)).number;
			for (const component of track.channel.components) {
				out[componentIndex(component)] = value;
			}
		}
		return out;
	}

	handOver(
		playhead: float64,
		rate: float64,
		iterations: float64,
		yoyo: boolean,
	): void {
		const duration = this.iterationMs;
		const tuples = this.times.map((time: float64): float64[] =>
			this.tupleAt(time),
		);
		let keyTimes = this.times.map((time: float64): float64 => time / duration);
		let ordered = tuples;
		let end: float64[] = [];
		let timing: LayerTiming;
		if (rate > 0) {
			const evenYoyo =
				yoyo && Number.isFinite(iterations) && iterations % 2 === 0;
			end = evenYoyo ? tuples[0] : tuples[tuples.length - 1];
			timing = {
				durationMs: duration,
				repeatCount: yoyo ? iterations / 2 : iterations,
				autoreverses: yoyo,
				startMs: playhead < 0 ? -playhead / rate : 0,
				offsetMs: playhead < 0 ? 0 : playhead,
				speed: rate,
			};
		} else {
			const period = yoyo ? duration * 2 : duration;
			const offset = (period - (playhead % period)) % period;
			if (!yoyo) {
				keyTimes = keyTimes.map((time: float64): float64 => 1 - time).reverse();
				ordered = tuples.slice(0).reverse();
			}
			end = tuples[0];
			timing = {
				durationMs: duration,
				repeatCount: (offset + playhead) / period,
				autoreverses: yoyo,
				startMs: 0,
				offsetMs: offset,
				speed: -rate,
			};
		}
		const values: float64[] = [];
		for (const tuple of ordered) {
			for (const value of tuple) {
				values.push(value);
			}
		}
		occupy(this.layerNode, this.plan.property, this.hold);
		this.engine.write(this.layerNode, this.plan.property, end);
		this.engine.animate(
			this.layerNode,
			this.plan.property,
			keyTimes,
			values,
			timing,
		);
		this.live = true;
		this.begin = this.clock.now();
		this.keyTimes = keyTimes;
		this.values = values;
		this.model = end;
		this.timing = timing;
	}

	presented(): float64[] {
		const timing = this.timing;
		const duration = timing.durationMs;
		const period = timing.autoreverses ? duration * 2 : duration;
		const elapsed = this.clock.now() - this.begin - timing.startMs;
		const active = Math.max(0, elapsed * timing.speed + timing.offsetMs);
		if (active >= timing.repeatCount * period) {
			return this.model.slice(0);
		}
		const within = active % period;
		const time = within > duration ? period - within : within;
		return keyedAt(this.keyTimes, this.values, this.width, time / duration);
	}

	stop(): void {
		if (!this.live) {
			return;
		}
		this.live = false;
		vacate(this.hold);
		for (const entry of this.entries) {
			if (entry.holder === this.hold) {
				entry.holder = null;
			}
		}
		this.engine.remove(this.layerNode, this.plan.property);
	}

	halt(values: float64[]): void {
		this.stop();
		this.last = values.slice(0);
		this.engine.write(this.layerNode, this.plan.property, this.last);
	}

	yieldLayer(): void {
		this.evicted = true;
		if (this.live) {
			this.halt(this.presented());
		}
	}
}

function fallbackOf(
	owned: MotionBinding[],
	slot: string,
	property: string,
): MotionBinding | null {
	for (const binding of owned) {
		if (binding.slot === slot && binding.property === property) {
			return binding;
		}
	}
	return null;
}

class NativeRuns {
	doc: MotionDocument;
	options: MotionOptions;
	bindings: MotionBinding[] = [];
	runs: NativeRun[] = [];
	player: NativeMotionPlayer | null = null;
	private iterations: float64;
	private yoyo: boolean;

	constructor(
		doc: MotionDocument,
		elements: MotionElements,
		bindings: MotionBinding[],
		options: MotionOptions,
	) {
		this.doc = doc;
		this.options = options;
		const owned: MotionBinding[] = [];
		for (const binding of bindings) {
			if (
				elements.declared.includes(binding.slot) &&
				layerChannel(binding.property) !== null
			) {
				owned.push(binding);
			} else {
				this.bindings.push(binding);
			}
		}
		const plan = planLayers(
			doc,
			options,
			this.bindings.map(
				(binding: MotionBinding): string =>
					binding.slot + "." + binding.property,
			),
		);
		this.iterations =
			options.repeat < 0 ? Infinity : (options.repeat + 1) as float64;
		this.yoyo = options.yoyo;
		for (const planned of plan.runs) {
			const fallbacks = planned.tracks.map(
				(track: LayerTrack): MotionBinding | null =>
					fallbackOf(owned, planned.slot, track.channel.name),
			);
			if (layerEngine() === null && fallbacks.includes(null)) {
				fail(
					"this host has no layer engine for element tracks; " +
						"bind them through MotionSignals",
				);
			}
			const run = new NativeRun(
				planned,
				elements,
				fallbacks,
				options.clock,
				plan.iterationMs,
			);
			this.runs.push(run);
			for (let i: int32 = 0; i < planned.tracks.length; i += 1) {
				this.bindings.push(this.bind(run, i));
			}
		}
	}

	get master(): NativeMotionPlayer {
		return this.player as NativeMotionPlayer;
	}

	running(): boolean {
		const master = this.master;
		if (master.disposed || master.paused) {
			return false;
		}
		const at = master.rawTime;
		return master.timeScale > 0 ? at < master.totalDuration : at > 0;
	}

	alignAll(): void {
		if (this.master.disposed) {
			return;
		}
		const running = this.running();
		for (const run of this.runs) {
			if (running) {
				run.evicted = false;
				const handed =
					run.plan.route === LayerRoute.Compositor &&
					run.last.length > 0 &&
					run.resolve();
				if (handed) {
					this.handOver(run);
				}
			} else if (run.live) {
				run.halt(run.last);
			}
		}
	}

	holdPresented(): void {
		for (const run of this.runs) {
			if (run.live) {
				run.halt(run.presented());
			}
		}
	}

	private bind(run: NativeRun, index: int32): MotionBinding {
		const track = run.plan.tracks[index];
		return {
			slot: run.plan.slot,
			property: track.channel.name,
			write: (value: MotionValue): void => this.write(run, index, value),
			read: (): MotionValue => run.read(index),
			target: run.entries[index].target,
		};
	}

	private write(run: NativeRun, index: int32, value: MotionValue): void {
		if (run.evicted) {
			return;
		}
		if (!run.resolve()) {
			const fallback = run.fallbacks[index];
			if (fallback === null) {
				fail("no element for slot " + run.plan.slot);
			}
			fallback.write(value);
			return;
		}
		run.record(index, value.number);
		if (run.plan.route === LayerRoute.Compositor && this.running()) {
			if (!run.live) {
				this.handOver(run);
			}
			run.entries[index].holder = run.hold;
			return;
		}
		run.stop();
		run.engine.write(run.layerNode, run.plan.property, run.last);
	}

	private handOver(run: NativeRun): void {
		const master = this.master;
		run.handOver(master.rawTime, master.timeScale, this.iterations, this.yoyo);
	}
}

export class NativeMotionPlayer extends MotionPlayer {
	private setup: NativeRuns;

	constructor(setup: NativeRuns) {
		super(setup.doc, setup.bindings, setup.options);
		this.setup = setup;
		setup.player = this;
	}

	play(from: float64 | null = null, suppressEvents: boolean = true): void {
		super.play(from, suppressEvents);
		this.setup.alignAll();
	}

	reverse(from: float64 | null = null, suppressEvents: boolean = true): void {
		super.reverse(from, suppressEvents);
		this.setup.alignAll();
	}

	pause(atTime: float64 | null = null, suppressEvents: boolean = true): void {
		super.pause(atTime, suppressEvents);
		this.setup.alignAll();
	}

	resume(): void {
		super.resume();
		this.setup.alignAll();
	}

	restart(includeDelay: boolean = false, suppressEvents: boolean = true): void {
		super.restart(includeDelay, suppressEvents);
		this.setup.alignAll();
	}

	seek(position: float64, suppressEvents: boolean = true): void {
		super.seek(position, suppressEvents);
		this.setup.alignAll();
	}

	setTotalTime(value: float64, suppressEvents: boolean = false): void {
		super.setTotalTime(value, suppressEvents);
		this.setup.alignAll();
	}

	setTime(value: float64, suppressEvents: boolean = false): void {
		super.setTime(value, suppressEvents);
		this.setup.alignAll();
	}

	setTotalProgress(value: float64, suppressEvents: boolean = false): void {
		super.setTotalProgress(value, suppressEvents);
		this.setup.alignAll();
	}

	setTimeScale(value: float64): void {
		super.setTimeScale(value);
		this.setup.alignAll();
	}

	finish(): void {
		super.finish();
		this.setup.alignAll();
	}

	cancel(): void {
		super.cancel();
		this.setup.holdPresented();
	}

	revert(): void {
		super.revert();
		this.setup.alignAll();
	}

	dispose(): void {
		this.setup.holdPresented();
		super.dispose();
	}
}

export function nativeMotionPlayer(
	doc: MotionDocument,
	elements: MotionElements,
	bindings: MotionBinding[],
	options: MotionOptions,
): MotionPlayer {
	return new NativeMotionPlayer(
		new NativeRuns(doc, elements, bindings, options),
	);
}

function layerTuple(node: HostNode, channel: LayerChannel, value: float64): float64[] {
	const engine = layerEngine() as LayerEngine;
	const out = componentsOf(channel.property).map(
		(component: LayerComponent): float64 => engine.read(node, component),
	);
	for (const component of channel.components) {
		out[componentIndex(component)] = value;
	}
	return out;
}

export function showLayer(node: HostNode, property: string, value: MotionValue): void {
	const channel = layerChannel(property);
	if (channel === null) {
		fail("no native layer property " + property);
	}
	(layerEngine() as LayerEngine).write(node, channel.property, layerTuple(node, channel, value.number));
}

export function nativeOwns(node: HostNode): boolean {
	return layerEngine() !== null;
}

class ValueParts {
	initial: float64;
	policy: MotionPolicy;
	elements: MotionElements;
	slot: string;
	channel: LayerChannel;
	target: MotionTarget | null;
	clock: Clock = frameClock();
	node: HostNode | null = null;

	constructor(
		initial: float64,
		policy: MotionPolicy,
		elements: MotionElements,
		slot: string,
		channel: LayerChannel,
		target: MotionTarget | null,
	) {
		this.initial = initial;
		this.policy = policy;
		this.elements = elements;
		this.slot = slot;
		this.channel = channel;
		const eager = resolvedNode(elements, slot);
		this.target =
			target ??
			(eager === null ? null : elementTarget(eager as HostNode, channel.name));
	}
}

export class NativeElementValue extends AnimatedValue {
	private hold: LayerHold = new LayerHold((): void => {});
	private parts: ValueParts;
	private entry: TargetEntry | null;
	private handed: boolean = false;
	private from: float64 = 0;
	private to: float64 = 0;
	private begin: float64 = 0;
	private curve: ProgressCurve = { durationMs: 0, progress: [] };

	constructor(parts: ValueParts) {
		super(parts.initial, parts.clock, parts.policy, parts.target);
		this.parts = parts;
		this.hold = new LayerHold((): void => this.yieldLayer());
		const target = parts.target;
		this.entry = target === null ? null : entryOf(target as MotionTarget);
		this.subscribe((next: float64): void => {
			if (!this.handed && this.element() !== null) {
				this.paint(next);
			}
		});
	}

	get handedOver(): boolean {
		return this.handed;
	}

	animate(
		spec: AnimationSpec,
		onEnd: ((finished: boolean) => void) | null = null,
	): void {
		const from = super.get();
		const carried = super.velocity();
		this.settle(false);
		super.animate(spec, (finished: boolean): void => {
			this.settle(false);
			if (onEnd !== null) {
				onEnd(finished);
			}
		});
		if (!super.isAnimating() || this.element() === null || from === spec.to) {
			return;
		}
		if (spec.kind === AnimationKind.Spring) {
			const spring = createSpring(
				spec.spring,
				from,
				spec.to,
				carried + spec.velocityPerSecond,
			);
			this.handOver(from, spec.to, sampleSpring(spring));
		} else if (spec.kind === AnimationKind.Timing && spec.durationMs > 0) {
			this.handOver(from, spec.to, sampleEasing(spec.easing, spec.durationMs));
		}
	}

	set(value: float64): void {
		this.settle(false);
		super.set(value);
	}

	cancel(): void {
		this.settle(false);
		super.cancel();
	}

	dispose(): void {
		if (!this.disposed) {
			this.settle(false);
		}
		super.dispose();
	}

	yieldLayer(): void {
		this.settle(true);
	}

	presented(): float64 {
		const duration = this.curve.durationMs;
		const progress =
			duration > 0
				? Math.min(
						1,
						Math.max(0, (this.parts.clock.now() - this.begin) / duration),
					)
				: 1;
		const points = this.curve.progress;
		const last = (points.length - 1) as float64;
		const keys = points.map(
			(_: float64, i: number): float64 => (i as float64) / last,
		);
		const eased = keyedAt(keys, points, 1, progress)[0];
		return this.from + (this.to - this.from) * eased;
	}

	private settle(commit: boolean): void {
		if (!this.handed) {
			return;
		}
		const shown = this.presented();
		this.handed = false;
		vacate(this.hold);
		const entry = this.entry;
		if (entry !== null && entry.holder === this.hold) {
			entry.holder = null;
		}
		const engine = layerEngine() as LayerEngine;
		engine.remove(this.parts.node as HostNode, this.parts.channel.property);
		this.paint(commit ? shown : super.get());
	}

	private element(): HostNode | null {
		const parts = this.parts;
		if (parts.node !== null || this.disposed) {
			return parts.node;
		}
		const node = resolvedNode(parts.elements, parts.slot);
		if (node === null) {
			return null;
		}
		parts.node = node;
		this.paint(super.get());
		return node;
	}

	private tuple(value: float64): float64[] {
		return layerTuple(this.parts.node as HostNode, this.parts.channel, value);
	}

	private paint(value: float64): void {
		const engine = layerEngine() as LayerEngine;
		engine.write(
			this.parts.node as HostNode,
			this.parts.channel.property,
			this.tuple(value),
		);
	}

	private handOver(from: float64, to: float64, curve: ProgressCurve): void {
		const node = this.parts.node as HostNode;
		const property = this.parts.channel.property;
		const count = curve.progress.length;
		const last = (count - 1) as float64;
		const keyTimes: float64[] = [];
		const values: float64[] = [];
		for (let i: int32 = 0; i < count; i += 1) {
			keyTimes.push((i as float64) / last);
			for (const part of this.tuple(from + (to - from) * curve.progress[i])) {
				values.push(part);
			}
		}
		occupy(node, property, this.hold);
		const engine = layerEngine() as LayerEngine;
		engine.write(node, property, this.tuple(to));
		engine.animate(node, property, keyTimes, values, {
			durationMs: curve.durationMs,
			repeatCount: 1,
			autoreverses: false,
			startMs: 0,
			offsetMs: 0,
			speed: 1,
		});
		this.handed = true;
		this.from = from;
		this.to = to;
		this.begin = this.parts.clock.now();
		this.curve = curve;
		const entry = this.entry;
		if (entry !== null) {
			entry.holder = this.hold;
		}
	}
}

export function nativeElementValue(
	initial: float64,
	policy: MotionPolicy,
	elements: MotionElements,
	slot: string,
	property: string,
	target: MotionTarget | null = null,
): AnimatedValue {
	const channel = layerChannel(property);
	if (channel === null) {
		fail("an animated value has no native layer property " + property);
	}
	return new NativeElementValue(
		new ValueParts(initial, policy, elements, slot, channel, target),
	);
}
