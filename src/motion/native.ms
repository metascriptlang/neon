import { HostNode } from "../render/hostTypes";
import {
	LayerComponent,
	LayerEngine,
	LayerProperty,
	LayerTiming,
	componentCount,
	layerEngine,
} from "../platform/native/layerMotion";
import { MotionElement } from "./waapi";
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
import { Composition, MotionTarget } from "pulse/src/target";

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

class LayerTarget {
	node: HostNode;
	property: LayerProperty;
	target: MotionTarget = new MotionTarget();
	run: NativeRun | null = null;
	users: int32 = 0;

	constructor(node: HostNode, property: LayerProperty) {
		this.node = node;
		this.property = property;
		this.target.onClaim = (): void => {
			this.evict();
		};
	}

	evict(): void {
		const run = this.run;
		if (run === null) {
			return;
		}
		this.run = null;
		run.evicted = true;
		if (run.live) {
			run.halt(run.presented());
		}
	}

	read(engine: LayerEngine, component: LayerComponent): float64 {
		const run = this.run;
		if (run !== null && run.live) {
			return run.presented()[componentIndex(component)];
		}
		return engine.read(this.node, component);
	}
}

let layerTargets: LayerTarget[] = [];

function layerTarget(node: HostNode, property: LayerProperty): LayerTarget {
	layerTargets = layerTargets.filter(
		(entry: LayerTarget): boolean => entry.users > 0,
	);
	for (const entry of layerTargets) {
		if (entry.node === node && entry.property === property) {
			entry.users += 1;
			return entry;
		}
	}
	const entry = new LayerTarget(node, property);
	entry.users = 1;
	layerTargets.push(entry);
	return entry;
}

class NativeRun {
	plan: LayerRun;
	node: HostNode;
	owner: LayerTarget;
	engine: LayerEngine;
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
		node: HostNode,
		engine: LayerEngine,
		clock: Clock,
		iterationMs: float64,
	) {
		this.plan = plan;
		this.node = node;
		this.engine = engine;
		this.clock = clock;
		this.iterationMs = iterationMs;
		this.owner = layerTarget(node, plan.property);
		this.times =
			plan.route === LayerRoute.Compositor
				? sampleTimes(plan, iterationMs)
				: [];
	}

	get width(): int32 {
		return componentCount(this.plan.property);
	}

	modelNow(): float64[] {
		return componentsOf(this.plan.property).map(
			(component: LayerComponent): float64 =>
				this.engine.read(this.node, component),
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
		this.engine.write(this.node, this.plan.property, end);
		this.engine.animate(
			this.node,
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
		this.owner.run = this;
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
		return this.keyedAt(time / duration);
	}

	private keyedAt(progress: float64): float64[] {
		const keys = this.keyTimes;
		const width = this.width;
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
			const a = this.values[left * width + i];
			const b = this.values[right * width + i];
			out.push(a + (b - a) * t);
		}
		return out;
	}

	stop(): void {
		if (!this.live) {
			return;
		}
		this.engine.remove(this.node, this.plan.property);
		this.live = false;
	}

	halt(values: float64[]): void {
		this.stop();
		this.last = values.slice(0);
		this.engine.write(this.node, this.plan.property, this.last);
	}
}

function notify(listener: (() => void) | null): void {
	if (listener !== null) {
		listener();
	}
}

function nodeFor(elements: MotionElement[], run: LayerRun): HostNode {
	for (const entry of elements) {
		if (entry.slot === run.slot) {
			return entry.node;
		}
	}
	fail("no element for slot " + run.slot);
}

function requireEngine(): LayerEngine {
	const engine = layerEngine();
	if (engine === null) {
		fail(
			"this host has no layer engine for element tracks; " +
				"bind them through MotionSignals",
		);
	}
	return engine;
}

export class NativeMotionPlayer {
	onStart: (() => void) | null = null;
	onUpdate: (() => void) | null = null;
	onRepeat: (() => void) | null = null;
	onComplete: (() => void) | null = null;
	onReverseComplete: (() => void) | null = null;

	private master: MotionPlayer;
	private runs: NativeRun[] = [];
	private iterations: float64;
	private yoyo: boolean;

	constructor(
		doc: MotionDocument,
		elements: MotionElement[],
		bindings: MotionBinding[],
		options: MotionOptions,
	) {
		const custom = bindings.map(
			(binding: MotionBinding): string => binding.slot + "." + binding.property,
		);
		const plan = planLayers(doc, options, custom);
		this.iterations =
			options.repeat < 0 ? Infinity : (options.repeat + 1) as float64;
		this.yoyo = options.yoyo;
		const all: MotionBinding[] = bindings.slice(0);
		if (plan.runs.length > 0) {
			const engine = requireEngine();
			for (const planned of plan.runs) {
				const run = new NativeRun(
					planned,
					nodeFor(elements, planned),
					engine,
					options.clock,
					plan.iterationMs,
				);
				this.runs.push(run);
				for (let i: int32 = 0; i < planned.tracks.length; i += 1) {
					all.push(this.bind(run, i));
				}
			}
		}
		this.master = new MotionPlayer(doc, all, options);
		this.master.onStart = (): void => notify(this.onStart);
		this.master.onUpdate = (): void => notify(this.onUpdate);
		this.master.onRepeat = (): void => notify(this.onRepeat);
		this.master.onComplete = (): void => notify(this.onComplete);
		this.master.onReverseComplete = (): void => notify(this.onReverseComplete);
	}

	get disposed(): boolean {
		return this.master.disposed;
	}
	get paused(): boolean {
		return this.master.paused;
	}
	get cancelled(): boolean {
		return this.master.cancelled;
	}
	get reversed(): boolean {
		return this.master.reversed;
	}
	get timeScale(): float64 {
		return this.master.timeScale;
	}
	get time(): float64 {
		return this.master.time;
	}
	get totalTime(): float64 {
		return this.master.totalTime;
	}
	get rawTime(): float64 {
		return this.master.rawTime;
	}
	get duration(): float64 {
		return this.master.duration;
	}
	get totalDuration(): float64 {
		return this.master.totalDuration;
	}
	get iteration(): int32 {
		return this.master.iteration;
	}
	get progress(): float64 {
		return this.master.progress;
	}
	get totalProgress(): float64 {
		return this.master.totalProgress;
	}
	get isActive(): boolean {
		return this.master.isActive;
	}

	play(from: float64 | null = null, suppressEvents: boolean = true): void {
		this.master.play(from, suppressEvents);
		this.alignAll();
	}

	reverse(from: float64 | null = null, suppressEvents: boolean = true): void {
		this.master.reverse(from, suppressEvents);
		this.alignAll();
	}

	pause(atTime: float64 | null = null, suppressEvents: boolean = true): void {
		this.master.pause(atTime, suppressEvents);
		this.alignAll();
	}

	resume(): void {
		this.master.resume();
		this.alignAll();
	}

	restart(includeDelay: boolean = false, suppressEvents: boolean = true): void {
		this.master.restart(includeDelay, suppressEvents);
		this.alignAll();
	}

	seek(position: float64, suppressEvents: boolean = true): void {
		this.master.seek(position, suppressEvents);
		this.alignAll();
	}

	setTotalTime(value: float64, suppressEvents: boolean = false): void {
		this.master.setTotalTime(value, suppressEvents);
		this.alignAll();
	}

	setTime(value: float64, suppressEvents: boolean = false): void {
		this.master.setTime(value, suppressEvents);
		this.alignAll();
	}

	setTotalProgress(value: float64, suppressEvents: boolean = false): void {
		this.master.setTotalProgress(value, suppressEvents);
		this.alignAll();
	}

	setProgress(value: float64, suppressEvents: boolean = false): void {
		this.master.setProgress(value, suppressEvents);
		this.alignAll();
	}

	setTimeScale(value: float64): void {
		this.master.setTimeScale(value);
		this.alignAll();
	}

	finish(): void {
		this.master.finish();
		this.alignAll();
	}

	cancel(): void {
		this.master.cancel();
		this.holdPresented();
	}

	revert(): void {
		this.master.revert();
		this.alignAll();
	}

	dispose(): void {
		this.holdPresented();
		this.master.dispose();
		for (const run of this.runs) {
			if (run.owner.run === run) {
				run.owner.run = null;
			}
			run.owner.users -= 1;
		}
		this.onStart = null;
		this.onUpdate = null;
		this.onRepeat = null;
		this.onComplete = null;
		this.onReverseComplete = null;
	}

	private bind(run: NativeRun, index: int32): MotionBinding {
		const track = run.plan.tracks[index];
		const binding: MotionBinding = {
			slot: run.plan.slot,
			property: track.channel.name,
			write: (value: MotionValue): void => this.write(run, index, value),
			read: (): MotionValue =>
				numberValue(run.owner.read(run.engine, track.channel.components[0])),
		};
		return index === 0 ? { ...binding, target: run.owner.target } : binding;
	}

	private running(): boolean {
		const master = this.master;
		if (master.disposed || master.paused) {
			return false;
		}
		const at = master.rawTime;
		return master.timeScale > 0 ? at < master.totalDuration : at > 0;
	}

	private write(run: NativeRun, index: int32, value: MotionValue): void {
		run.record(index, value.number);
		if (index === 0) {
			run.evicted = false;
			run.owner.run = run;
		} else if (run.evicted) {
			return;
		}
		if (run.plan.route === LayerRoute.Compositor && this.running()) {
			if (!run.live) {
				this.handOver(run);
			}
			return;
		}
		run.stop();
		run.engine.write(run.node, run.plan.property, run.last);
	}

	private handOver(run: NativeRun): void {
		run.handOver(
			this.master.rawTime,
			this.master.timeScale,
			this.iterations,
			this.yoyo,
		);
	}

	private alignAll(): void {
		if (this.master.disposed) {
			return;
		}
		const running = this.running();
		for (const run of this.runs) {
			if (running) {
				const handed =
					run.plan.route === LayerRoute.Compositor &&
					!run.evicted &&
					run.last.length > 0;
				if (handed) {
					this.handOver(run);
				}
			} else if (run.live) {
				run.halt(run.last);
			}
		}
	}

	private holdPresented(): void {
		for (const run of this.runs) {
			if (run.live) {
				run.halt(run.presented());
			}
		}
	}
}
