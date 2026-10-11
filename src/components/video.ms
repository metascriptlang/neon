import { NeonEvent } from "../render/event";
import { Style, layerStyles } from "../render/style";
import { Accessor } from "../core/signal";
import { onCleanup } from "../core/cleanup";
import { Host, HostNode } from "../render/hostTypes";
import { NeonNode, VAttr, VEvent, hostElement, evt, dynAttr } from "../render/node";
import { AccessibilityProps, accessibilityAttrs } from "./primitives";

export interface VideoSource {
	uri: string;
}

export type VideoResizeMode = "none" | "contain" | "cover" | "stretch";

export struct VideoNaturalSize {
	width: float64;
	height: float64;
	orientation: string;
}

export struct OnLoadStartData {
	isNetwork: boolean;
	type: string;
	uri: string;
}

export struct OnLoadData {
	currentTime: float64;
	duration: float64;
	naturalSize: VideoNaturalSize;
}

export struct OnProgressData {
	currentTime: float64;
	playableDuration: float64;
	seekableDuration: float64;
}

export struct VideoErrorDetail {
	errorString: string;
	localizedDescription: string;
	code: int32;
}

export struct OnVideoErrorData {
	error: VideoErrorDetail;
}

export interface VideoProps extends AccessibilityProps {
	source?: Accessor<VideoSource> | null;
	paused?: Accessor<boolean> | null;
	muted?: Accessor<boolean> | null;
	volume?: Accessor<float64> | null;
	rate?: Accessor<float64> | null;
	repeat?: Accessor<boolean> | null;
	resizeMode?: Accessor<VideoResizeMode> | null;
	controls?: Accessor<boolean> | null;
	progressUpdateInterval?: Accessor<float64> | null;
	style?: Accessor<Style> | null;
	ref?: ((handle: VideoHandle) => void) | null;
	onLoadStart?: ((data: OnLoadStartData) => void) | null;
	onLoad?: ((data: OnLoadData) => void) | null;
	onProgress?: ((data: OnProgressData) => void) | null;
	onEnd?: (() => void) | null;
	onError?: ((data: OnVideoErrorData) => void) | null;
	onLayout?: ((e: NeonEvent) => void) | null;
}

class VideoSlot {
	host: Host | null = null;
	node: HostNode | null = null;
	mounted: boolean = false;

	command(name: string, argument: string): void {
		if (!this.mounted || this.host === null || this.node === null) {
			throw new Error(`Video.${name} was called while the Video is not mounted`);
		}
		(this.host as Host).setAttr(this.node as HostNode, "command", name + "\x1f" + argument);
	}
}

export class VideoHandle {
	private slot: VideoSlot;

	constructor(slot: VideoSlot) {
		this.slot = slot;
	}

	seek(seconds: float64): void {
		if (!(seconds >= 0)) { throw new Error(`Video.seek needs a time of 0 or more seconds, got ${seconds}`); }
		this.slot.command("seek", seconds.toString());
	}

	pause(): void { this.slot.command("pause", ""); }
	resume(): void { this.slot.command("resume", ""); }
}

function fieldNumber(fields: string[], at: int32): float64 {
	if (at >= fields.length || fields[at] === "") { return 0; }
	return parseFloat(fields[at]);
}

export function isNetworkUri(uri: string): boolean {
	return uri.startsWith("http://") || uri.startsWith("https://");
}

function flag(attrs: VAttr[], name: string, value: Accessor<boolean> | null, fallback: boolean): void {
	if (value === null) {
		attrs.push(dynAttr(name, (): string | null => fallback ? "true" : "false"));
		return;
	}
	const read = value as Accessor<boolean>;
	attrs.push(dynAttr(name, (): string | null => read() ? "true" : "false"));
}

function decimal(attrs: VAttr[], name: string, value: Accessor<float64> | null, fallback: float64): void {
	if (value === null) {
		attrs.push(dynAttr(name, (): string | null => fallback.toString()));
		return;
	}
	const read = value as Accessor<float64>;
	attrs.push(dynAttr(name, (): string | null => read().toString()));
}

// react-native-video's default progressUpdateInterval.
const PROGRESS_EVERY_MS: float64 = 250;

const VIDEO_BASE: Style = { overflow: "hidden" };

export function Video(props: VideoProps): NeonNode {
	const slot = new VideoSlot();
	const attrs: VAttr[] = [];
	const source = props.source;
	let uri = "";
	if (source !== null) {
		const read = source as Accessor<VideoSource>;
		attrs.push(dynAttr("source", (): string | null => {
			uri = read().uri;
			return uri;
		}));
	}
	flag(attrs, "paused", props.paused, false);
	flag(attrs, "muted", props.muted, false);
	decimal(attrs, "volume", props.volume, 1);
	decimal(attrs, "rate", props.rate, 1);
	flag(attrs, "repeat", props.repeat, false);
	flag(attrs, "controls", props.controls, false);
	decimal(attrs, "progressUpdateInterval", props.progressUpdateInterval, PROGRESS_EVERY_MS);
	const mode = props.resizeMode;
	if (mode !== null) {
		const read = mode as Accessor<VideoResizeMode>;
		attrs.push(dynAttr("resizeMode", (): string | null => { const m: VideoResizeMode = read(); return m; }));
	}
	accessibilityAttrs(props, attrs);
	const evts: VEvent[] = [];
	const start = props.onLoadStart;
	if (start !== null) {
		evts.push(evt("onLoadStart", (e: NeonEvent): void => {
			const at = e.value !== "" ? e.value : uri;
			(start as (d: OnLoadStartData) => void)({ isNetwork: isNetworkUri(at), type: "", uri: at });
		}));
	}
	const load = props.onLoad;
	if (load !== null) {
		evts.push(evt("onLoad", (e: NeonEvent): void => {
			const fields = e.value.split("\x1f");
			(load as (d: OnLoadData) => void)({
				currentTime: fieldNumber(fields, 1),
				duration: fieldNumber(fields, 0),
				naturalSize: {
					width: fieldNumber(fields, 2),
					height: fieldNumber(fields, 3),
					orientation: fieldNumber(fields, 3) > fieldNumber(fields, 2) ? "portrait" : "landscape",
				},
			});
		}));
	}
	const progress = props.onProgress;
	if (progress !== null) {
		evts.push(evt("onProgress", (e: NeonEvent): void => {
			const fields = e.value.split("\x1f");
			(progress as (d: OnProgressData) => void)({
				currentTime: fieldNumber(fields, 0),
				playableDuration: fieldNumber(fields, 1),
				seekableDuration: fieldNumber(fields, 2),
			});
		}));
	}
	const end = props.onEnd;
	if (end !== null) { evts.push(evt("onEnd", (e: NeonEvent): void => { (end as () => void)(); })); }
	const fail = props.onError;
	if (fail !== null) {
		evts.push(evt("onError", (e: NeonEvent): void => {
			const cut = e.value.indexOf("\x1f");
			const code = cut < 0 ? 0 : parseInt(e.value.substring(0, cut)) as int32;
			const text = cut < 0 ? e.value : e.value.substring(cut + 1, e.value.length);
			(fail as (d: OnVideoErrorData) => void)({ error: { errorString: text, localizedDescription: text, code } });
		}));
	}
	if (props.onLayout !== null) { evts.push(evt("onLayout", props.onLayout as (e: NeonEvent) => void)); }
	const userStyle = props.style;
	const style = (): Style => userStyle === null ? VIDEO_BASE : layerStyles([VIDEO_BASE, (userStyle as () => Style)()]);
	const userRef = props.ref;
	const inner = hostElement("video", attrs, evts, null, style, (node: HostNode): void => {
		slot.node = node;
		slot.mounted = true;
		onCleanup((): void => { slot.mounted = false; });
		if (userRef !== null) { (userRef as (h: VideoHandle) => void)(new VideoHandle(slot)); }
	});
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		slot.host = host;
		inner(host, parent, before);
	};
}
