import { NeonEvent } from "../render/event";
import { Style } from "../render/style";
import { Accessor } from "../core/signal";
import { NeonNode, VAttr, VEvent, RefFn, hostElement, evt, dynAttr } from "../render/node";
import { AccessibilityProps, accessibilityAttrs } from "./primitives";

export interface ImageSource {
	uri: string;
}

export type ImageResizeMode = "cover" | "contain" | "stretch" | "center";

interface ImageProps extends AccessibilityProps {
	source?: Accessor<ImageSource> | null;
	resizeMode?: Accessor<ImageResizeMode> | null;
	style?: Accessor<Style> | null;
	ref?: RefFn | null;
	onLoadStart?: (() => void) | null;
	onLoad?: ((e: NeonEvent) => void) | null;
	onError?: ((e: NeonEvent) => void) | null;
	onLoadEnd?: (() => void) | null;
	onLayout?: ((e: NeonEvent) => void) | null;
}

export function Image(props: ImageProps): NeonNode {
	const attrs: VAttr[] = [];
	const source = props.source;
	const start = props.onLoadStart;
	if (source !== null) {
		const read = source as Accessor<ImageSource>;
		attrs.push(dynAttr("source", (): string | null => {
			const uri = read().uri;
			if (start !== null) { (start as () => void)(); }
			return uri;
		}));
	}
	const mode = props.resizeMode;
	if (mode !== null) {
		const read = mode as Accessor<ImageResizeMode>;
		attrs.push(dynAttr("resizeMode", (): string | null => { const m: ImageResizeMode = read(); return m; }));
	}
	if (props.accessibilityRole === null) { attrs.push(dynAttr("accessibilityRole", (): string | null => "image")); }
	accessibilityAttrs(props, attrs);
	const evts: VEvent[] = [];
	const load = props.onLoad;
	const fail = props.onError;
	const end = props.onLoadEnd;
	if (load !== null || end !== null) {
		evts.push(evt("onLoad", (e: NeonEvent): void => {
			if (load !== null) { (load as (x: NeonEvent) => void)(e); }
			if (end !== null) { (end as () => void)(); }
		}));
	}
	if (fail !== null || end !== null) {
		evts.push(evt("onError", (e: NeonEvent): void => {
			if (fail !== null) { (fail as (x: NeonEvent) => void)(e); }
			if (end !== null) { (end as () => void)(); }
		}));
	}
	if (props.onLayout !== null) { evts.push(evt("onLayout", props.onLayout as (e: NeonEvent) => void)); }
	let style: (() => Style) | null = null;
	if (props.style !== null) { style = props.style as () => Style; }
	return hostElement("image", attrs, evts, null, style, props.ref);
}
