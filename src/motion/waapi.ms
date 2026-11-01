import { cancelFrame, frameNow, requestFrame } from "../animation/frame";
import { HostNode } from "../render/hostTypes";
import { Clock } from "pulse/src/clock";
import { ComposedTrack, flatten } from "pulse/src/compose";
import {
	MotionDocument,
	MotionKeyframe,
	MotionValue,
	ValueKind,
	findClip,
	validate,
} from "pulse/src/document";
import { MotionOptions } from "pulse/src/player";

export struct StyleProperty {
	name: string;
	css: string;
	prefix: string;
	suffix: string;
	kind: ValueKind;
	unit: string;
	axis: int32;
	identity: float64;
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
	delay: float64;
}

export struct CssRun {
	slot: string;
	css: string;
	properties: string[];
	route: TrackRoute;
	keyframes: WaapiKeyframe[];
	delay: float64;
}

export struct WaapiPlan {
	timing: WaapiTiming | null;
	tracks: RoutedTrack[];
	runs: CssRun[];
}

const NO_AXIS: int32 = -1;

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
		unit: suffix,
		axis: NO_AXIS,
		identity: 0,
	};
}

function axis(
	name: string,
	css: string,
	unit: string,
	index: int32,
	identity: float64,
): StyleProperty {
	const other = formatNumber(identity) + unit;
	return {
		name,
		css,
		prefix: index === 0 ? "" : other + " ",
		suffix: index === 0 && identity !== 0 ? unit + " " + other : unit,
		kind: ValueKind.Number,
		unit,
		axis: index,
		identity,
	};
}

function colour(name: string): StyleProperty {
	return {
		name,
		css: name,
		prefix: "",
		suffix: "",
		kind: ValueKind.Color,
		unit: "",
		axis: NO_AXIS,
		identity: 0,
	};
}

const STYLE_PROPERTIES: StyleProperty[] = [
	numeric("opacity", "opacity", "", ""),
	axis("translateX", "translate", "px", 0, 0),
	axis("translateY", "translate", "px", 1, 0),
	numeric("rotate", "rotate", "", "deg"),
	numeric("scale", "scale", "", ""),
	axis("scaleX", "scale", "", 0, 1),
	axis("scaleY", "scale", "", 1, 1),
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

struct OffsetKey {
	offset: float64;
	value: MotionValue;
	easing: string;
	linear: boolean;
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

function segmentLinear(left: MotionKeyframe, right: MotionKeyframe): boolean {
	return left.connectedRight && left.handles.rightX === left.handles.rightY &&
		right.handles.leftX === right.handles.leftY;
}

function offsetKeys(
	writer: ComposedTrack,
	duration: float64,
	delayable: boolean,
): OffsetKey[] | null {
	if (writer.start !== 0 && !delayable) { return null; }
	const keys = writer.track.keyframes;
	for (const key of keys) {
		if (key.time < 0 || key.time > writer.duration) { return null; }
	}
	const span = duration - writer.start;
	const offset = (time: float64): float64 => Math.min(
		1,
		Math.round(time / writer.rate / span * 1e8) / 1e8,
	);
	const out: OffsetKey[] = [];
	const first = keys[0];
	if (offset(first.time) > 0) {
		out.push(
			{
				offset: 0,
				value: first.value,
				easing: "linear",
				linear: true,
			},
		);
	}
	for (let i: int32 = 0; i < keys.length; i += 1) {
		const inner = i + 1 < keys.length;
		out.push(
			{
				offset: offset(keys[i].time),
				value: keys[i].value,
				easing: inner ? segmentEasing(keys[i], keys[i + 1]) : "linear",
				linear: inner ? segmentLinear(keys[i], keys[i + 1]) : true,
			},
		);
	}
	const last = keys[keys.length - 1];
	if (offset(last.time) < 1) {
		out.push(
			{
				offset: 1,
				value: last.value,
				easing: "linear",
				linear: true,
			},
		);
	}
	return out;
}

export function waapiKeyframes(
	writer: ComposedTrack,
	property: StyleProperty,
	duration: float64,
	delayable: boolean = false,
): WaapiKeyframe[] | null {
	const keys = offsetKeys(writer, duration, delayable);
	if (keys === null) { return null; }
	return keys.map(
		(key: OffsetKey): WaapiKeyframe => ({
			offset: key.offset,
			value: styleValue(property, key.value),
			easing: key.easing,
		}),
	);
}

export function axisValue(
	property: StyleProperty,
	values: float64[],
): string {
	const parts = values.map(
		(value: float64): string => formatNumber(value) + property.unit,
	);
	return parts.join(" ");
}

function segmentAt(keys: OffsetKey[], from: float64, to: float64): int32 {
	for (let i: int32 = 0; i + 1 < keys.length; i += 1) {
		if (keys[i].offset <= from && to <= keys[i + 1].offset) { return i; }
	}
	fail("an offset lies outside the keyframes it merges");
}

function exactAt(keys: OffsetKey[], offset: float64): float64 | null {
	const i = segmentAt(keys, offset, offset);
	const left = keys[i];
	const right = keys[i + 1];
	if (offset === right.offset) { return right.value.number; }
	if (offset === left.offset || left.value.number === right.value.number) {
		return left.value.number;
	}
	if (left.easing === "steps(1, end)") { return left.value.number; }
	if (!left.linear) { return null; }
	const t = (offset - left.offset) / (right.offset - left.offset);
	return left.value.number + (right.value.number - left.value.number) * t;
}

function pieceEasing(
	keys: OffsetKey[],
	from: float64,
	to: float64,
): string | null {
	const left = keys[segmentAt(keys, from, to)];
	if (left.linear) { return "linear"; }
	if (left.easing === "steps(1, end)") { return left.easing; }
	const right = keys[segmentAt(keys, from, to) + 1];
	return left.offset === from && right.offset === to ? left.easing : null;
}

function mergeAxes(
	property: StyleProperty,
	members: OffsetKey[][],
): WaapiKeyframe[] | null {
	const offsets: float64[] = [];
	for (const keys of members) {
		for (const key of keys) {
			if (!offsets.includes(key.offset)) { offsets.push(key.offset); }
		}
	}
	offsets.sort((a: float64, b: float64): float64 => a - b);
	const values: float64[][] = [];
	for (const offset of offsets) {
		const row: float64[] = [];
		for (const keys of members) {
			const value = exactAt(keys, offset);
			if (value === null) { return null; }
			row.push(value);
		}
		values.push(row);
	}
	const out: WaapiKeyframe[] = [];
	for (let i: int32 = 0; i < offsets.length; i += 1) {
		let easing = "linear";
		let chosen = false;
		for (let m: int32 = 0; i + 1 < offsets.length && m < members.length;
			m += 1) {
			if (values[i][m] === values[i + 1][m]) { continue; }
			const piece = pieceEasing(members[m], offsets[i], offsets[i + 1]);
			if (piece === null || (chosen && piece !== easing)) { return null; }
			easing = piece;
			chosen = true;
		}
		out.push(
			{
				offset: offsets[i],
				value: axisValue(property, values[i]),
				easing,
			},
		);
	}
	return out;
}

function delayable(timing: WaapiTiming | null): boolean {
	return timing !== null && timing.iterations === 1;
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
			delay: 0,
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
		? waapiKeyframes(writers[0], style, duration, delayable(timing))
		: null;
	if (keyframes === null) {
		return {
			slot,
			property: track.property,
			route: TrackRoute.Style,
			style,
			keyframes: [],
			delay: 0,
		};
	}
	return {
		slot,
		property: track.property,
		route: TrackRoute.Waapi,
		style,
		keyframes,
		delay: writers[0].start,
	};
}

function cssRuns(
	tracks: RoutedTrack[],
	groups: ComposedTrack[][],
	duration: float64,
	timing: WaapiTiming | null,
): CssRun[] {
	const runs: CssRun[] = [];
	const members: int32[][] = [];
	for (let i: int32 = 0; i < tracks.length; i += 1) {
		const style = tracks[i].style;
		if (style === null) { continue; }
		let index: int32 = -1;
		for (let r: int32 = 0; r < runs.length; r += 1) {
			if (runs[r].slot === tracks[i].slot && runs[r].css === style.css) {
				index = r;
			}
		}
		if (index < 0) {
			runs.push(
				{
					slot: tracks[i].slot,
					css: style.css,
					properties: [],
					route: tracks[i].route,
					keyframes: tracks[i].keyframes,
					delay: tracks[i].delay,
				},
			);
			members.push([]);
			index = runs.length - 1;
		}
		runs[index].properties.push(tracks[i].property);
		members[index].push(i);
	}
	const out: CssRun[] = [];
	for (let r: int32 = 0; r < runs.length; r += 1) {
		out.push(
			members[r].length > 1
				? mergeRun(runs[r], members[r], tracks, groups, duration, timing)
				: runs[r],
		);
	}
	return out;
}

function mergeRun(
	run: CssRun,
	unordered: int32[],
	tracks: RoutedTrack[],
	groups: ComposedTrack[][],
	duration: float64,
	timing: WaapiTiming | null,
): CssRun {
	const members = unordered.slice(0);
	const named = members.map(
		(i: int32): string => run.slot + "." + tracks[i].property,
	);
	for (const i of members) {
		if ((tracks[i].style as StyleProperty).axis === NO_AXIS) {
			fail(
				named.join(" and ") + " both write CSS " + run.css +
					": a uniform value and an axis have no exact merge",
			);
		}
	}
	members.sort(
		(a: int32, b: int32) => (tracks[a].style as StyleProperty).axis -
			(tracks[b].style as StyleProperty).axis,
	);
	const keys: OffsetKey[][] = [];
	const delay = tracks[members[0]].delay;
	for (const i of members) {
		const own = tracks[i].route === TrackRoute.Waapi &&
				tracks[i].delay === delay
			? offsetKeys(groups[i][0], duration, delayable(timing))
			: null;
		if (own !== null) { keys.push(own); }
	}
	const merged = keys.length === members.length
		? mergeAxes(tracks[members[0]].style as StyleProperty, keys)
		: null;
	return {
		slot: run.slot,
		css: run.css,
		properties: members.map((i: int32): string => tracks[i].property),
		route: merged === null ? TrackRoute.Style : TrackRoute.Waapi,
		keyframes: merged ?? [],
		delay: merged === null ? 0 : delay,
	};
}

function runOf(runs: CssRun[], track: RoutedTrack): CssRun | null {
	for (const run of runs) {
		if (run.slot === track.slot && run.properties.includes(track.property)) {
			return run;
		}
	}
	return null;
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
	const runs = cssRuns(tracks, groups, duration, timing);
	return {
		timing,
		tracks: tracks.map(
			(track: RoutedTrack): RoutedTrack => {
				const run = runOf(runs, track);
				return run === null ? track : { ...track, route: run.route };
			},
		),
		runs,
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
	import { numberValue } from "pulse/src/document";
	import { MotionBinding, MotionPlayer } from "pulse/src/player";
	import { Composition, MotionTarget } from "pulse/src/target";

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
	extern function commitStyles(
		animation: Animation,
		element: HTMLElement,
		property: string,
	): void from
		"((a, el, p) => { if (!el.isConnected) { return; } try { a.commitStyles(); } catch (e) { throw new Error(`motion: the browser refused to commit ${p} on a connected element: ${e.message}`); } })(#, #, #)";
	extern function readStyle(element: HTMLElement, property: string): string from
		"((el, p) => el.style[p])(#, #)";
	extern function writeStyle(element: HTMLElement, property: string, value: string): void from
		"((el, p, v) => { el.style[p] = v; })(#, #, #)";

	class StyleRun {
		element: HTMLElement;
		plan: CssRun;
		styles: StyleProperty[];
		owners: ElementTarget[] = [];
		values: MotionValue[] = [];
		animation: Animation | null = null;
		evicted: boolean = false;
		baseline: string = "";

		constructor(element: HTMLElement, plan: CssRun) {
			this.element = element;
			this.plan = plan;
			this.styles = plan.properties.map(
				(name: string): StyleProperty => styleProperty(name) as StyleProperty,
			);
			for (const style of this.styles) {
				this.owners.push(elementTarget(element, style.name));
				this.values.push(numberValue(style.identity));
			}
		}

		cssText(): string {
			if (this.styles.length === 1) {
				return styleValue(this.styles[0], this.values[0]);
			}
			return axisValue(
				this.styles[0],
				this.values.map((value: MotionValue): float64 => value.number),
			);
		}

		evict(): void {
			const animation = this.animation;
			if (animation === null) { return; }
			this.animation = null;
			this.evicted = true;
			this.release();
			animation.pause();
			try {
				commitStyles(animation, this.element, this.plan.css);
			} finally {
				animation.cancel();
			}
		}

		release(): void {
			for (const owner of this.owners) {
				if (owner.run === this) { owner.run = null; }
			}
			liveRuns = liveRuns.filter((run: StyleRun): boolean => run !== this);
		}
	}

	class ElementTarget {
		element: HTMLElement;
		property: string;
		target: MotionTarget = new MotionTarget();
		run: StyleRun | null = null;
		users: int32 = 0;

		constructor(element: HTMLElement, property: string) {
			this.element = element;
			this.property = property;
			this.target.onClaim = (): void => {
				const run = this.run;
				if (run !== null) { run.evict(); }
			};
		}
	}

	let elementTargets: ElementTarget[] = [];
	let liveRuns: StyleRun[] = [];

	function elementTarget(element: HTMLElement, property: string): ElementTarget {
		elementTargets = elementTargets.filter((entry: ElementTarget): boolean => entry.users > 0);
		for (const entry of elementTargets) {
			if (entry.element === element && entry.property === property) {
				entry.users += 1;
				return entry;
			}
		}
		const entry = new ElementTarget(element, property);
		entry.users = 1;
		elementTargets.push(entry);
		return entry;
	}

	function claimCss(run: StyleRun): void {
		const rivals = liveRuns.filter(
			(other: StyleRun): boolean => other.element === run.element &&
				other.plan.css === run.plan.css,
		);
		for (const rival of rivals) { rival.evict(); }
		liveRuns.push(run);
	}

	function notify(listener: (() => void) | null): void {
		if (listener !== null) { listener(); }
	}

	function elementFor(elements: MotionElement[], run: CssRun): HTMLElement {
		const name = run.slot + "." + run.properties[0];
		for (const entry of elements) {
			if (entry.slot === run.slot) { return entry.node as unknown as HTMLElement; }
		}
		fail("no element for slot " + run.slot + " of track " + name);
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
			for (const planned of plan.runs) {
				const css = blend && planned.route === TrackRoute.Waapi
					? { ...planned, route: TrackRoute.Style }
					: planned;
				const run = new StyleRun(elementFor(elements, css), css);
				this.runs.push(run);
				for (let i: int32 = 0; i < run.styles.length; i += 1) {
					all.push(this.bind(run, i));
				}
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
			for (const run of this.runs) {
				for (const owner of run.owners) { owner.users -= 1; }
			}
			this.onStart = null;
			this.onUpdate = null;
			this.onRepeat = null;
			this.onComplete = null;
			this.onReverseComplete = null;
		}

		private bind(run: StyleRun, index: int32): MotionBinding {
			return {
				slot: run.plan.slot,
				property: run.plan.properties[index],
				write: (value: MotionValue): void => this.write(run, index, value),
				read: (): MotionValue => {
					run.baseline = readStyle(run.element, run.plan.css);
					return numberValue(0);
				},
				target: run.owners[index].target,
			};
		}

		private write(run: StyleRun, index: int32, value: MotionValue): void {
			if (this.reverting) {
				writeStyle(run.element, run.plan.css, run.baseline);
				return;
			}
			run.values[index] = value;
			run.owners[index].run = run;
			if (run.plan.route === TrackRoute.Style) {
				writeStyle(run.element, run.plan.css, run.cssText());
				return;
			}
			if (run.animation !== null || run.evicted) { return; }
			run.animation = this.start(run);
			claimCss(run);
			this.align(run);
		}

		private start(run: StyleRun): Animation {
			const timing = this.timing as WaapiTiming;
			const keyframes = run.plan.keyframes;
			return animateStyle(
				run.element,
				run.plan.css,
				keyframes.map((keyframe: WaapiKeyframe): float64 => keyframe.offset),
				keyframes.map((keyframe: WaapiKeyframe): string => keyframe.value),
				keyframes.map((keyframe: WaapiKeyframe): string => keyframe.easing),
				timing.duration - run.plan.delay,
				timing.delay + run.plan.delay,
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
			let refused = "";
			for (const run of this.runs) {
				run.evicted = false;
				const animation = run.animation;
				if (animation === null) { continue; }
				run.animation = null;
				run.release();
				animation.pause();
				animation.currentTime = this.localTime();
				try {
					if (commit) { commitStyles(animation, run.element, run.plan.css); }
				} catch (e) {
					if (refused === "") { refused = e.message; }
				}
				animation.cancel();
			}
			if (refused !== "") { throw new Error(refused); }
		}
	}
}
