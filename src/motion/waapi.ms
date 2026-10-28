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
