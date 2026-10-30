import { cancelFrame, frameNow, requestFrame } from "../animation/frame";
import { HostNode } from "../render/hostTypes";
import { Clock } from "./clock";
import { ComposedTrack, flatten } from "./compose";
import {
	MotionDocument,
	MotionKeyframe,
	MotionValue,
	ValueKind,
	findClip,
	validate,
} from "./document";
import { MotionOptions } from "./player";

export struct StyleProperty {
	name: string;
	css: string;
	prefix: string;
	suffix: string;
	kind: ValueKind;
}

export enum TrackRoute {
	Waapi,
	Style,
	Custom,
}

export struct WaapiKeyframe {
	offset: float64;
	value: string;
	easing: string;
}

export struct WaapiTiming {
	duration: float64;
	delay: float64;
	iterations: float64;
	direction: string;
	playbackRate: float64;
	fill: string;
}

export struct RoutedTrack {
	slot: string;
	property: string;
	route: TrackRoute;
	style: StyleProperty | null;
	keyframes: WaapiKeyframe[];
}

export struct WaapiPlan {
	timing: WaapiTiming | null;
	tracks: RoutedTrack[];
}

function numeric(
	name: string,
	css: string,
	prefix: string,
	suffix: string,
): StyleProperty {
	return {
		name,
		css,
		prefix,
		suffix,
		kind: ValueKind.Number,
	};
}

function colour(name: string): StyleProperty {
	return {
		name,
		css: name,
		prefix: "",
		suffix: "",
		kind: ValueKind.Color,
	};
}

const STYLE_PROPERTIES: StyleProperty[] = [
	numeric("opacity", "opacity", "", ""),
	numeric("translateX", "translate", "", "px"),
	numeric("translateY", "translate", "0px ", "px"),
	numeric("rotate", "rotate", "", "deg"),
	numeric("scale", "scale", "", ""),
	numeric("scaleX", "scale", "", " 1"),
	numeric("scaleY", "scale", "1 ", ""),
	numeric("width", "width", "", "px"),
	numeric("height", "height", "", "px"),
	numeric("left", "left", "", "px"),
	numeric("top", "top", "", "px"),
	numeric("right", "right", "", "px"),
	numeric("bottom", "bottom", "", "px"),
	numeric("borderRadius", "borderRadius", "", "px"),
	colour("backgroundColor"),
	colour("color"),
	colour("borderColor"),
];

function fail(message: string): never { throw new Error("motion: " + message); }

function formatNumber(value: float64): string {
	const rounded = Math.round(value * 1e6) / 1e6;
	return (rounded === 0 ? 0 : rounded).toString();
}

export function styleProperty(name: string): StyleProperty | null {
	for (const property of STYLE_PROPERTIES) {
		if (property.name === name) { return property; }
	}
	return null;
}

export function styleValue(
	property: StyleProperty,
	value: MotionValue,
): string {
	if (value.kind !== property.kind) {
		fail("value kind does not match CSS " + property.css);
	}
	if (value.kind === ValueKind.Number) {
		return property.prefix + formatNumber(value.number) + property.suffix;
	}
	const c = value.color;
	const channels = [c.r * 255, c.g * 255, c.b * 255].map(
		(channel: float64): string => formatNumber(channel),
	);
	return `rgba(${channels.join(", ")}, ${formatNumber(c.a)})`;
}

export function waapiTiming(
	options: MotionOptions,
	duration: float64,
): WaapiTiming | null {
	if (options.repeat !== 0 && options.repeatDelay !== 0) { return null; }
	return {
		duration,
		delay: options.delay,
		iterations: options.repeat < 0 ? Infinity : (options.repeat + 1) as float64,
		direction: options.yoyo ? "alternate" : "normal",
		playbackRate: options.timeScale,
		fill: "both",
	};
}

function segmentEasing(left: MotionKeyframe, right: MotionKeyframe): string {
	if (!left.connectedRight) { return "steps(1, end)"; }
	const points = [
		left.handles.rightX,
		left.handles.rightY,
		right.handles.leftX,
		right.handles.leftY,
	];
	const text = points.map((point: float64): string => formatNumber(point));
	return `cubic-bezier(${text.join(", ")})`;
}

export function waapiKeyframes(
	writer: ComposedTrack,
	property: StyleProperty,
	duration: float64,
): WaapiKeyframe[] | null {
	if (writer.start !== 0) { return null; }
	const keys = writer.track.keyframes;
	for (const key of keys) {
		if (key.time < 0 || key.time > writer.duration) { return null; }
	}
	const offset = (time: float64): float64 => Math.min(
		1,
		Math.round(time / writer.rate / duration * 1e8) / 1e8,
	);
	const out: WaapiKeyframe[] = [];
	const first = keys[0];
	if (offset(first.time) > 0) {
		out.push(
			{
				offset: 0,
				value: styleValue(property, first.value),
				easing: "linear",
			},
		);
	}
	for (let i: int32 = 0; i < keys.length; i += 1) {
		const easing = i + 1 < keys.length
			? segmentEasing(keys[i], keys[i + 1])
			: "linear";
		out.push(
			{
				offset: offset(keys[i].time),
				value: styleValue(property, keys[i].value),
				easing,
			},
		);
	}
	const last = keys[keys.length - 1];
	if (offset(last.time) < 1) {
		out.push(
			{
				offset: 1,
				value: styleValue(property, last.value),
				easing: "linear",
			},
		);
	}
	return out;
}

function kindName(kind: ValueKind): string {
	return match (kind) {
		ValueKind.Number => "number",ValueKind.Color => "colour",
	};
}

function routeTrack(
	writers: ComposedTrack[],
	custom: string[],
	timing: WaapiTiming | null,
	duration: float64,
): RoutedTrack {
	const track = writers[0].track;
	const slot = writers[0].slot;
	const name = slot + "." + track.property;
	if (custom.includes(name)) {
		return {
			slot,
			property: track.property,
			route: TrackRoute.Custom,
			style: null,
			keyframes: [],
		};
	}
	const style = styleProperty(track.property);
	if (style === null) { fail("no browser binding for track " + name); }
	if (style.kind !== track.kind) {
		fail(
			"track " + name + " holds a " + kindName(track.kind) + " but CSS " +
				style.css +
				" takes a " +
				kindName(style.kind),
		);
	}
	const keyframes = timing !== null && writers.length === 1
		? waapiKeyframes(writers[0], style, duration)
		: null;
	if (keyframes === null) {
		return {
			slot,
			property: track.property,
			route: TrackRoute.Style,
			style,
			keyframes: [],
		};
	}
	return {
		slot,
		property: track.property,
		route: TrackRoute.Waapi,
		style,
		keyframes,
	};
}

function refuseSharedCss(tracks: RoutedTrack[]): void {
	for (let i: int32 = 0; i < tracks.length; i += 1) {
		const a = tracks[i];
		const aStyle = a.style;
		if (aStyle === null) { continue; }
		for (let j: int32 = i + 1; j < tracks.length; j += 1) {
			const bStyle = tracks[j].style;
			if (bStyle !== null && tracks[j].slot === a.slot &&
				bStyle.css === aStyle.css) {
				fail(
					a.slot + "." + a.property + " and " + a.slot + "." +
						tracks[j].property +
						" both write CSS " +
						aStyle.css,
				);
			}
		}
	}
}

export function planWaapi(
	doc: MotionDocument,
	options: MotionOptions,
	custom: string[],
): WaapiPlan {
	validate(doc);
	const duration = findClip(doc, doc.root).duration;
	const timing = waapiTiming(options, duration);
	const keys: string[] = [];
	const groups: ComposedTrack[][] = [];
	for (const writer of flatten(doc)) {
		const key = writer.slot + "\n" + writer.track.property;
		const index = keys.indexOf(key);
		if (index >= 0) { groups[index].push(writer); } else {
			keys.push(key);
			groups.push([writer]);
		}
	}
	const tracks = groups.map(
		(writers: ComposedTrack[]): RoutedTrack => routeTrack(
			writers,
			custom,
			timing,
			duration,
		),
	);
	refuseSharedCss(tracks);
	return {
		timing,
		tracks,
	};
}

export function frameClock(): Clock {
	return {
		now: (): float64 => frameNow(),
		request: (callback: (time: float64) => void): int32 => requestFrame(
			callback,
		),
		cancel: (id: int32): void => cancelFrame(id),
	};
}

export struct MotionElement {
	slot: string;
	node: HostNode;
}

when (js) {
	import { numberValue } from "./document";
	import { MotionBinding, MotionPlayer } from "./player";
	import { Composition, MotionTarget } from "./target";

	extern class Animation {
		currentTime: number | null;
		playbackRate: number;
		extern play(): void;
		extern pause(): void;
		extern cancel(): void;
	}

	extern class HTMLElement {}

	extern function animateStyle(
		element: HTMLElement,
		property: string,
		offsets: float64[],
		values: string[],
		easings: string[],
		duration: float64,
		delay: float64,
		iterations: float64,
		direction: string,
		fill: string,
	): Animation from
		"((el, p, o, v, e, duration, delay, iterations, direction, fill) => el.animate(o.map((offset, i) => ({ offset, easing: e[i], [p]: v[i] })), { duration, delay, iterations, direction, fill }))(#, #, #, #, #, #, #, #, #, #)";
	extern function commitStyles(animation: Animation): void from
		"(a => { try { a.commitStyles(); } catch {} })(#)";
	extern function readStyle(element: HTMLElement, property: string): string from
		"((el, p) => el.style[p])(#, #)";
	extern function writeStyle(element: HTMLElement, property: string, value: string): void from
		"((el, p, v) => { el.style[p] = v; })(#, #, #)";

	class StyleRun {
		element: HTMLElement;
		track: RoutedTrack;
		style: StyleProperty;
		owner: ElementTarget;
		animation: Animation | null = null;
		baseline: string = "";

		constructor(element: HTMLElement, track: RoutedTrack, style: StyleProperty) {
			this.element = element;
			this.track = track;
			this.style = style;
			this.owner = elementTarget(element, style.css);
		}
	}

	class ElementTarget {
		element: HTMLElement;
		css: string;
		target: MotionTarget = new MotionTarget();
		run: StyleRun | null = null;
		users: int32 = 0;

		constructor(element: HTMLElement, css: string) {
			this.element = element;
			this.css = css;
			this.target.onClaim = (): void => { this.evict(); };
		}

		evict(): void {
			const run = this.run;
			if (run === null) { return; }
			this.run = null;
			const animation = run.animation;
			if (animation === null) { return; }
			animation.pause();
			commitStyles(animation);
			animation.cancel();
			run.animation = null;
		}
	}

	let elementTargets: ElementTarget[] = [];

	function elementTarget(element: HTMLElement, css: string): ElementTarget {
		elementTargets = elementTargets.filter((entry: ElementTarget): boolean => entry.users > 0);
		for (const entry of elementTargets) {
			if (entry.element === element && entry.css === css) {
				entry.users += 1;
				return entry;
			}
		}
		const entry = new ElementTarget(element, css);
		entry.users = 1;
		elementTargets.push(entry);
		return entry;
	}

	function notify(listener: (() => void) | null): void {
		if (listener !== null) { listener(); }
	}

	function elementFor(elements: MotionElement[], track: RoutedTrack): HTMLElement {
		const name = track.slot + "." + track.property;
		for (const entry of elements) {
			if (entry.slot === track.slot) { return entry.node as unknown as HTMLElement; }
		}
		fail("no element for slot " + track.slot + " of track " + name);
	}

	export class BrowserMotionPlayer {
		onStart: (() => void) | null = null;
		onUpdate: (() => void) | null = null;
		onRepeat: (() => void) | null = null;
		onComplete: (() => void) | null = null;
		onReverseComplete: (() => void) | null = null;

		private master: MotionPlayer;
		private timing: WaapiTiming | null;
		private runs: StyleRun[] = [];
		private reverting: boolean = false;

		constructor(
			doc: MotionDocument,
			elements: MotionElement[],
			bindings: MotionBinding[],
			options: MotionOptions,
		) {
			const custom = bindings.map(
				(binding: MotionBinding): string => binding.slot + "." + binding.property,
			);
			const plan = planWaapi(doc, options, custom);
			this.timing = plan.timing;
			const all: MotionBinding[] = bindings.slice(0);
			const blend = options.composition === Composition.Blend;
			for (const planned of plan.tracks) {
				const style = planned.style;
				if (style === null) { continue; }
				const track = blend && planned.route === TrackRoute.Waapi
					? { ...planned, route: TrackRoute.Style }
					: planned;
				const run = new StyleRun(elementFor(elements, track), track, style);
				this.runs.push(run);
				all.push(this.bind(run));
			}
			this.master = new MotionPlayer(doc, all, options);
			this.master.onStart = (): void => notify(this.onStart);
			this.master.onUpdate = (): void => notify(this.onUpdate);
			this.master.onRepeat = (): void => notify(this.onRepeat);
			this.master.onComplete = (): void => notify(this.onComplete);
			this.master.onReverseComplete = (): void => notify(this.onReverseComplete);
		}

		get disposed(): boolean { return this.master.disposed; }
		get paused(): boolean { return this.master.paused; }
		get cancelled(): boolean { return this.master.cancelled; }
		get reversed(): boolean { return this.master.reversed; }
		get timeScale(): float64 { return this.master.timeScale; }
		get time(): float64 { return this.master.time; }
		get totalTime(): float64 { return this.master.totalTime; }
		get rawTime(): float64 { return this.master.rawTime; }
		get duration(): float64 { return this.master.duration; }
		get totalDuration(): float64 { return this.master.totalDuration; }
		get iteration(): int32 { return this.master.iteration; }
		get progress(): float64 { return this.master.progress; }
		get totalProgress(): float64 { return this.master.totalProgress; }
		get isActive(): boolean { return this.master.isActive; }

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
			this.halt(true);
		}

		revert(): void {
			this.reverting = true;
			try {
				this.master.revert();
			} finally {
				this.reverting = false;
			}
			this.halt(false);
		}

		dispose(): void {
			this.halt(true);
			this.master.dispose();
			for (const run of this.runs) { run.owner.users -= 1; }
			this.onStart = null;
			this.onUpdate = null;
			this.onRepeat = null;
			this.onComplete = null;
			this.onReverseComplete = null;
		}

		private bind(run: StyleRun): MotionBinding {
			return {
				slot: run.track.slot,
				property: run.track.property,
				write: (value: MotionValue): void => this.write(run, value),
				read: (): MotionValue => {
					run.baseline = readStyle(run.element, run.style.css);
					return numberValue(0);
				},
				target: run.owner.target,
			};
		}

		private write(run: StyleRun, value: MotionValue): void {
			if (this.reverting) {
				writeStyle(run.element, run.style.css, run.baseline);
				return;
			}
			if (run.track.route === TrackRoute.Style) {
				writeStyle(run.element, run.style.css, styleValue(run.style, value));
				return;
			}
			if (run.animation !== null) { return; }
			run.animation = this.start(run);
			run.owner.run = run;
			this.align(run);
		}

		private start(run: StyleRun): Animation {
			const timing = this.timing as WaapiTiming;
			const keyframes = run.track.keyframes;
			return animateStyle(
				run.element,
				run.style.css,
				keyframes.map((keyframe: WaapiKeyframe): float64 => keyframe.offset),
				keyframes.map((keyframe: WaapiKeyframe): string => keyframe.value),
				keyframes.map((keyframe: WaapiKeyframe): string => keyframe.easing),
				timing.duration,
				timing.delay,
				timing.iterations,
				timing.direction,
				timing.fill,
			);
		}

		private running(): boolean {
			const master = this.master;
			if (master.paused) { return false; }
			const at = master.rawTime;
			return master.timeScale > 0 ? at < master.totalDuration : at > 0;
		}

		private localTime(): float64 {
			return this.master.rawTime + (this.timing as WaapiTiming).delay;
		}

		private align(run: StyleRun): void {
			const animation = run.animation;
			if (animation === null) { return; }
			animation.playbackRate = this.master.timeScale;
			if (this.running()) { animation.play(); } else { animation.pause(); }
			animation.currentTime = this.localTime();
		}

		private alignAll(): void {
			for (const run of this.runs) { this.align(run); }
		}

		private halt(commit: boolean): void {
			for (const run of this.runs) {
				const animation = run.animation;
				if (animation === null) { continue; }
				animation.pause();
				animation.currentTime = this.localTime();
				if (commit) { commitStyles(animation); }
				animation.cancel();
				run.animation = null;
				if (run.owner.run === run) { run.owner.run = null; }
			}
		}
	}
}
