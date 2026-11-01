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

export class MotionElements {
	declared: string[] = [];
	private entries: MotionElement[] = [];

	declare(slot: string): void {
		if (!this.declared.includes(slot)) { this.declared.push(slot); }
	}

	set(slot: string, node: HostNode): void {
		this.declare(slot);
		this.entries = this.entries.filter(
			(entry: MotionElement): boolean => entry.slot !== slot,
		);
		this.entries.push({ slot, node });
	}

	node(slot: string): HostNode | null {
		for (const entry of this.entries) {
			if (entry.slot === slot) { return entry.node; }
		}
		return null;
	}
}

export function motionElements(entries: MotionElement[]): MotionElements {
	const elements = new MotionElements();
	for (const entry of entries) { elements.set(entry.slot, entry.node); }
	return elements;
}

when (js) {
	import { numberValue } from "pulse/src/document";
	import { MotionBinding, MotionPlayer } from "pulse/src/player";
	import { MotionPolicy } from "pulse/src/policy";
	import { cssLinear, sampleSpring } from "pulse/src/progress";
	import { SpringSimulation, createSpring } from "pulse/src/spring";
	import { Composition, MotionTarget } from "pulse/src/target";
	import { AnimatedValue, AnimationKind, AnimationSpec } from "pulse/src/value";

	extern class Animation {
		currentTime: number | null;
		startTime: number | null;
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
	extern function timelineTime(): float64 from
		"((typeof document === 'undefined' || document.timeline.currentTime === null) ? -1 : document.timeline.currentTime)";

	function timelineNow(): float64 {
		const time = timelineTime();
		return time < 0 ? frameNow() : time;
	}
	extern function liveNow(): float64 from "performance.now()";
	extern function startTimer(callback: () => void, ms: float64): float64 from
		"setTimeout(#, #)";
	extern function stopTimer(id: float64): void from "clearTimeout(#)";
	extern function readStyle(element: HTMLElement, property: string): string from
		"((el, p) => el.style[p])(#, #)";
	extern function domElement<T>(node: T): boolean from
		"(n => typeof HTMLElement !== 'undefined' && n instanceof HTMLElement)(#)";
	extern function writeStyle(element: HTMLElement, property: string, value: string): void from
		"((el, p, v) => { el.style[p] = v; })(#, #, #)";

	class TargetEntry {
		target: MotionTarget;
		run: StyleRun | null = null;
		holder: ElementValue | null = null;

		constructor(target: MotionTarget) {
			this.target = target;
			target.onClaim = (): void => {
				const run = this.run;
				if (run !== null) { run.evict(); }
				const holder = this.holder;
				if (holder !== null) { holder.settle(true); }
			};
		}
	}

	class ElementSlot {
		element: HTMLElement;
		property: string;
		target: MotionTarget = new MotionTarget();

		constructor(element: HTMLElement, property: string) {
			this.element = element;
			this.property = property;
		}
	}

	let targetEntries: TargetEntry[] = [];
	let elementSlots: ElementSlot[] = [];
	let liveRuns: StyleRun[] = [];

	function isDomNode(node: HostNode): boolean {
		return domElement(node);
	}

	function entryOf(target: MotionTarget): TargetEntry {
		for (const entry of targetEntries) {
			if (entry.target === target) { return entry; }
		}
		const entry = new TargetEntry(target);
		targetEntries.push(entry);
		return entry;
	}

	function elementTarget(element: HTMLElement, property: string): MotionTarget {
		for (const slot of elementSlots) {
			if (slot.element === element && slot.property === property) {
				return slot.target;
			}
		}
		const slot = new ElementSlot(element, property);
		elementSlots.push(slot);
		return slot.target;
	}

	export function browserOwns(node: HostNode): boolean {
		return isDomNode(node);
	}

	enum RunMode {
		Unresolved,
		Dom,
		Fallback,
	}

	class StyleRun {
		plan: CssRun;
		styles: StyleProperty[];
		fallbacks: (MotionBinding | null)[];
		entries: TargetEntry[] = [];
		values: MotionValue[] = [];
		element: HTMLElement | null = null;
		mode: RunMode = RunMode.Unresolved;
		animation: Animation | null = null;
		evicted: boolean = false;
		baseline: string = "";

		constructor(
			plan: CssRun,
			fallbacks: (MotionBinding | null)[],
			eager: HTMLElement | null,
		) {
			this.plan = plan;
			this.fallbacks = fallbacks;
			this.styles = plan.properties.map(
				(name: string): StyleProperty => styleProperty(name) as StyleProperty,
			);
			for (let i: int32 = 0; i < this.styles.length; i += 1) {
				const fallback = fallbacks[i];
				const own = fallback === null ? null : fallback.target;
				const target = own ?? elementTarget(
					eager as HTMLElement,
					this.styles[i].name,
				);
				this.entries.push(entryOf(target));
				this.values.push(numberValue(this.styles[i].identity));
			}
		}

		get dom(): HTMLElement {
			return this.element as HTMLElement;
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
				commitStyles(animation, this.dom, this.plan.css);
			} finally {
				animation.cancel();
			}
		}

		release(): void {
			for (const entry of this.entries) {
				if (entry.run === this) { entry.run = null; }
			}
			liveRuns = liveRuns.filter((run: StyleRun): boolean => run !== this);
		}
	}

	function claimCss(run: StyleRun): void {
		const rivals = liveRuns.filter(
			(other: StyleRun): boolean => other.element === run.element &&
				other.plan.css === run.plan.css,
		);
		for (const rival of rivals) { rival.evict(); }
		liveRuns.push(run);
	}

	function everyBound(fallbacks: (MotionBinding | null)[]): boolean {
		return fallbacks.every(
			(fallback: MotionBinding | null): boolean => fallback !== null,
		);
	}

	class WakeClock {
		clock: Clock;
		wake: (() => float64 | null) | null = null;
		private callback: ((time: float64) => void) | null = null;
		private ticket: int32 = 0;
		private frame: int32 = 0;
		private timer: float64 = -1;
		private deferredUntil: float64 = -1;
		private latest: float64 = 0;

		constructor() {
			this.clock = {
				now: (): float64 => this.now(),
				request: (callback: (time: float64) => void): int32 => this.request(callback),
				cancel: (id: int32): void => { if (id === this.ticket) { this.drop(); } },
			};
		}

		now(): float64 {
			this.latest = Math.max(this.latest, timelineNow());
			return this.latest;
		}

		flush(): void {
			if (this.callback !== null) { this.fire(); }
		}

		defer(ms: float64): void {
			this.deferredUntil = this.now() + ms;
			this.reschedule();
		}

		undefer(): void {
			this.deferredUntil = -1;
		}

		reschedule(): void {
			if (this.callback === null) { return; }
			this.unschedule();
			this.schedule();
		}

		private request(callback: (time: float64) => void): int32 {
			this.drop();
			this.callback = callback;
			this.ticket += 1;
			this.schedule();
			return this.ticket;
		}

		private waitMs(): float64 | null {
			const wake = this.wake;
			if (wake !== null) { return wake(); }
			if (this.deferredUntil < 0) { return null; }
			const left = this.deferredUntil - this.now();
			if (left <= 0) {
				this.deferredUntil = -1;
				return null;
			}
			return left + 1;
		}

		private schedule(): void {
			const wait = this.waitMs();
			if (wait === null) {
				this.frame = requestFrame((time: float64): void => {
					this.frame = 0;
					this.fire();
				});
				return;
			}
			this.timer = startTimer((): void => {
				this.timer = -1;
				this.latest = Math.max(this.latest, liveNow());
				this.fire();
			}, wait);
		}

		private unschedule(): void {
			if (this.frame !== 0) {
				cancelFrame(this.frame);
				this.frame = 0;
			}
			if (this.timer >= 0) {
				stopTimer(this.timer);
				this.timer = -1;
			}
		}

		private drop(): void {
			this.unschedule();
			this.callback = null;
		}

		private fire(): void {
			const callback = this.callback;
			this.drop();
			if (callback !== null) { callback(this.now()); }
		}
	}

	class BrowserRuns {
		doc: MotionDocument;
		options: MotionOptions;
		bindings: MotionBinding[] = [];
		runs: StyleRun[] = [];
		wake: WakeClock = new WakeClock();
		player: BrowserMotionPlayer | null = null;
		reverting: boolean = false;
		private elements: MotionElements;
		private timing: WaapiTiming | null;
		private evaluated: boolean;

		constructor(
			doc: MotionDocument,
			elements: MotionElements,
			bindings: MotionBinding[],
			options: MotionOptions,
		) {
			this.doc = doc;
			this.elements = elements;
			const owned: MotionBinding[] = [];
			for (const binding of bindings) {
				if (elements.declared.includes(binding.slot) &&
					styleProperty(binding.property) !== null) {
					owned.push(binding);
				} else {
					this.bindings.push(binding);
				}
			}
			this.evaluated = this.bindings.length > 0;
			const plan = planWaapi(
				doc,
				options,
				this.bindings.map(
					(binding: MotionBinding): string => binding.slot + "." + binding.property,
				),
			);
			this.timing = plan.timing;
			const blend = options.composition === Composition.Blend;
			for (const planned of plan.runs) {
				const css = blend && planned.route === TrackRoute.Waapi
					? { ...planned, route: TrackRoute.Style }
					: planned;
				const fallbacks = css.properties.map(
					(property: string): MotionBinding | null => {
						for (const binding of owned) {
							if (binding.slot === css.slot && binding.property === property) {
								return binding;
							}
						}
						return null;
					},
				);
				const run = new StyleRun(css, fallbacks, this.eager(css, fallbacks));
				this.runs.push(run);
				for (let i: int32 = 0; i < run.styles.length; i += 1) {
					this.bindings.push(this.bind(run, i));
				}
			}
			this.wake.wake = (): float64 | null => this.nextWake();
			this.options = {
				...options,
				clock: this.wake.clock,
			};
		}

		alignAll(): void {
			for (const run of this.runs) { this.align(run); }
		}

		halt(commit: boolean): void {
			let refused = "";
			for (const run of this.runs) {
				run.evicted = false;
				const animation = run.animation;
				if (animation === null) { continue; }
				run.animation = null;
				run.release();
				animation.pause();
				try {
					if (commit) { commitStyles(animation, run.dom, run.plan.css); }
				} catch (e) {
					if (refused === "") { refused = e.message; }
				}
				animation.cancel();
			}
			if (refused !== "") { throw new Error(refused); }
		}

		private eager(
			run: CssRun,
			fallbacks: (MotionBinding | null)[],
		): HTMLElement | null {
			if (everyBound(fallbacks)) { return null; }
			const node = this.elements.node(run.slot);
			if (node === null || !isDomNode(node)) {
				fail(
					"no element for slot " + run.slot + " of track " + run.slot + "." +
						run.properties[0],
				);
			}
			return node as unknown as HTMLElement;
		}

		private resolveAll(): void {
			for (const run of this.runs) {
				if (run.mode !== RunMode.Unresolved) { continue; }
				const node = this.elements.node(run.plan.slot);
				if (node !== null && isDomNode(node)) {
					run.element = node as unknown as HTMLElement;
					run.mode = RunMode.Dom;
					this.adopt(run);
				} else {
					run.mode = RunMode.Fallback;
				}
			}
		}

		private adopt(run: StyleRun): void {
			let known = false;
			for (let i: int32 = 0; i < run.styles.length; i += 1) {
				const fallback = run.fallbacks[i];
				const read = fallback === null ? null : fallback.read;
				if (read !== null) {
					run.values[i] = read();
					known = true;
				}
			}
			if (known) { writeStyle(run.dom, run.plan.css, run.cssText()); }
		}

		private bind(run: StyleRun, index: int32): MotionBinding {
			return {
				slot: run.plan.slot,
				property: run.plan.properties[index],
				write: (value: MotionValue): void => this.write(run, index, value),
				read: (): MotionValue => this.read(run, index),
				target: run.entries[index].target,
			};
		}

		private read(run: StyleRun, index: int32): MotionValue {
			this.resolveAll();
			const fallback = run.fallbacks[index];
			const own = fallback === null ? null : fallback.read;
			if (run.mode === RunMode.Dom) {
				run.baseline = readStyle(run.dom, run.plan.css);
			}
			return own === null ? numberValue(0) : own();
		}

		private write(run: StyleRun, index: int32, value: MotionValue): void {
			this.resolveAll();
			if (run.mode === RunMode.Fallback) {
				(run.fallbacks[index] as MotionBinding).write(value);
				return;
			}
			if (this.reverting) {
				writeStyle(run.dom, run.plan.css, run.baseline);
				return;
			}
			run.values[index] = value;
			run.entries[index].run = run;
			if (run.plan.route === TrackRoute.Style) {
				writeStyle(run.dom, run.plan.css, run.cssText());
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
				run.dom,
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

		private nextWake(): float64 | null {
			const player = this.player;
			if (player === null || this.evaluated || player.onUpdate !== null) {
				return null;
			}
			const at = player.rawTime;
			const forward = player.timeScale > 0;
			const marks: float64[] = [0, player.totalDuration];
			for (const run of this.runs) {
				if (run.mode !== RunMode.Dom || run.plan.route !== TrackRoute.Waapi) {
					return null;
				}
				if (run.animation !== null || run.evicted) { continue; }
				if (run.plan.delay <= at) { return 1; }
				marks.push(run.plan.delay);
			}
			const cycle = player.duration;
			const index = Math.floor(at / cycle);
			marks.push(index * cycle);
			marks.push((index + 1) * cycle);
			let next = forward ? Infinity : -Infinity;
			for (const mark of marks) {
				if (forward ? mark > at && mark < next : mark < at && mark > next) {
					next = mark;
				}
			}
			if (!Number.isFinite(next)) { return null; }
			return Math.abs(next - at) / Math.abs(player.timeScale) + 1;
		}

		private running(): boolean {
			const player = this.player as BrowserMotionPlayer;
			if (player.paused) { return false; }
			const at = player.rawTime;
			return player.timeScale > 0 ? at < player.totalDuration : at > 0;
		}

		private localTime(): float64 {
			const player = this.player as BrowserMotionPlayer;
			return player.rawTime + (this.timing as WaapiTiming).delay;
		}

		private align(run: StyleRun): void {
			const animation = run.animation;
			if (animation === null || this.player === null) { return; }
			animation.playbackRate = (this.player as BrowserMotionPlayer).timeScale;
			if (this.running()) { animation.play(); } else { animation.pause(); }
			animation.currentTime = this.localTime();
		}
	}

	export class BrowserMotionPlayer extends MotionPlayer {
		private setup: BrowserRuns;

		constructor(setup: BrowserRuns) {
			super(setup.doc, setup.bindings, setup.options);
			this.setup = setup;
			setup.player = this;
		}

		play(from: float64 | null = null, suppressEvents: boolean = true): void {
			this.setup.wake.flush();
			super.play(from, suppressEvents);
			this.setup.alignAll();
		}

		reverse(from: float64 | null = null, suppressEvents: boolean = true): void {
			this.setup.wake.flush();
			super.reverse(from, suppressEvents);
			this.setup.alignAll();
		}

		pause(atTime: float64 | null = null, suppressEvents: boolean = true): void {
			this.setup.wake.flush();
			super.pause(atTime, suppressEvents);
			this.setup.alignAll();
		}

		resume(): void {
			this.setup.wake.flush();
			super.resume();
			this.setup.alignAll();
		}

		restart(includeDelay: boolean = false, suppressEvents: boolean = true): void {
			this.setup.wake.flush();
			super.restart(includeDelay, suppressEvents);
			this.setup.alignAll();
		}

		seek(position: float64, suppressEvents: boolean = true): void {
			this.setup.wake.flush();
			super.seek(position, suppressEvents);
			this.setup.alignAll();
		}

		setTotalTime(value: float64, suppressEvents: boolean = false): void {
			this.setup.wake.flush();
			super.setTotalTime(value, suppressEvents);
			this.setup.alignAll();
		}

		setTime(value: float64, suppressEvents: boolean = false): void {
			this.setup.wake.flush();
			super.setTime(value, suppressEvents);
			this.setup.alignAll();
		}

		setTotalProgress(value: float64, suppressEvents: boolean = false): void {
			this.setup.wake.flush();
			super.setTotalProgress(value, suppressEvents);
			this.setup.alignAll();
		}

		setTimeScale(value: float64): void {
			this.setup.wake.flush();
			super.setTimeScale(value);
			this.setup.alignAll();
		}

		finish(): void {
			this.setup.wake.flush();
			super.finish();
			this.setup.alignAll();
		}

		cancel(): void {
			super.cancel();
			this.setup.halt(true);
		}

		revert(): void {
			this.setup.reverting = true;
			try {
				super.revert();
			} finally {
				this.setup.reverting = false;
			}
			this.setup.halt(false);
		}

		dispose(): void {
			this.setup.halt(true);
			super.dispose();
		}
	}

	export function browserMotionPlayer(
		doc: MotionDocument,
		elements: MotionElements,
		bindings: MotionBinding[],
		options: MotionOptions,
	): MotionPlayer {
		return new BrowserMotionPlayer(
			new BrowserRuns(doc, elements, bindings, options),
		);
	}

	class ValueParts {
		initial: float64;
		policy: MotionPolicy;
		elements: MotionElements;
		slot: string;
		style: StyleProperty;
		target: MotionTarget | null;
		wake: WakeClock = new WakeClock();
		element: HTMLElement | null = null;

		constructor(
			initial: float64,
			policy: MotionPolicy,
			elements: MotionElements,
			slot: string,
			style: StyleProperty,
			target: MotionTarget | null,
		) {
			this.initial = initial;
			this.policy = policy;
			this.elements = elements;
			this.slot = slot;
			this.style = style;
			const node = elements.node(slot);
			this.target = target ?? (node !== null && isDomNode(node)
				? elementTarget(node as unknown as HTMLElement, style.name)
				: null);
		}
	}

	export class ElementValue extends AnimatedValue {
		private parts: ValueParts;
		private animation: Animation | null = null;
		private entry: TargetEntry | null;

		constructor(parts: ValueParts) {
			super(parts.initial, parts.wake.clock, parts.policy, parts.target);
			this.parts = parts;
			const target = parts.target;
			this.entry = target === null ? null : entryOf(target);
			this.subscribe((next: float64): void => {
				const element = this.element();
				if (element !== null) { this.paint(element, next); }
			});
		}

		get handedOver(): boolean {
			return this.animation !== null;
		}

		get(): float64 {
			this.parts.wake.flush();
			return super.get();
		}

		velocity(): float64 {
			this.parts.wake.flush();
			return super.velocity();
		}

		isAnimating(): boolean {
			this.parts.wake.flush();
			return super.isAnimating();
		}

		animate(
			spec: AnimationSpec,
			onEnd: ((finished: boolean) => void) | null = null,
		): void {
			this.parts.wake.flush();
			const from = super.get();
			const carried = super.velocity();
			this.settle(false);
			super.animate(spec, (finished: boolean): void => {
				this.settle(false);
				if (onEnd !== null) { onEnd(finished); }
			});
			const element = this.element();
			if (spec.kind === AnimationKind.Spring && super.isAnimating() &&
				element !== null) {
				this.handOver(
					element,
					createSpring(
						spec.spring,
						from,
						spec.to,
						carried + spec.velocityPerSecond,
					),
				);
			}
		}

		set(value: float64): void {
			this.settle(false);
			super.set(value);
		}

		cancel(): void {
			this.parts.wake.flush();
			this.settle(false);
			super.cancel();
		}

		dispose(): void {
			if (!this.disposed) {
				this.parts.wake.flush();
				this.settle(false);
			}
			super.dispose();
		}

		settle(commit: boolean): void {
			const animation = this.animation;
			if (animation === null) { return; }
			this.animation = null;
			this.parts.wake.undefer();
			const entry = this.entry;
			if (entry !== null && entry.holder === this) { entry.holder = null; }
			animation.pause();
			try {
				if (commit) {
					commitStyles(
						animation,
						this.parts.element as HTMLElement,
						this.parts.style.css,
					);
				}
			} finally {
				animation.cancel();
			}
		}

		private element(): HTMLElement | null {
			const parts = this.parts;
			if (parts.element !== null || this.disposed) { return parts.element; }
			const node = parts.elements.node(parts.slot);
			if (node === null || !isDomNode(node)) { return null; }
			const element = node as unknown as HTMLElement;
			parts.element = element;
			this.paint(element, super.get());
			return element;
		}

		private paint(element: HTMLElement, value: float64): void {
			const style = this.parts.style;
			writeStyle(element, style.css, styleValue(style, numberValue(value)));
		}

		private handOver(element: HTMLElement, spring: SpringSimulation): void {
			const curve = sampleSpring(spring);
			const style = this.parts.style;
			const animation = animateStyle(
				element,
				style.css,
				[0, 1],
				[
					styleValue(style, numberValue(spring.from)),
					styleValue(style, numberValue(spring.to)),
				],
				[cssLinear(curve), "linear"],
				curve.durationMs,
				0,
				1,
				"normal",
				"both",
			);
			animation.startTime = this.parts.wake.now();
			this.animation = animation;
			const entry = this.entry;
			if (entry !== null) { entry.holder = this; }
			this.parts.wake.defer(curve.durationMs);
		}
	}

	export function elementValue(
		initial: float64,
		policy: MotionPolicy,
		elements: MotionElements,
		slot: string,
		property: string,
		target: MotionTarget | null = null,
	): AnimatedValue {
		const style = styleProperty(property);
		if (style === null || style.kind !== ValueKind.Number) {
			fail("an animated value has no numeric CSS property " + property);
		}
		return new ElementValue(
			new ValueParts(initial, policy, elements, slot, style, target),
		);
	}
}
