import { NeonEvent, neonEvent } from "../render/event";
import { Style } from "../render/style";
import { Accessor, accessor, createSignal, untrack } from "../core/signal";
import { NeonNode, VAttr, VEvent, RefFn, hostElement, evt, dynAttr } from "../render/node";
import { AccessibilityProps, accessibilityAttrs } from "./primitives";
import { appServices } from "../api/services";
import { sleepAsync } from "std/core/promise";

export interface ImageSource {
	uri: string;
}

export type ImageResizeMode = "cover" | "contain" | "stretch" | "center" | "repeat";

export interface ImageProps extends AccessibilityProps {
	source?: Accessor<ImageSource> | null;
	defaultSource?: Accessor<ImageSource> | null;
	resizeMode?: Accessor<ImageResizeMode> | null;
	blurRadius?: Accessor<number> | null;
	style?: Accessor<Style> | null;
	ref?: RefFn | null;
	onLoadStart?: (() => void) | null;
	onLoad?: ((e: NeonEvent) => void) | null;
	onError?: ((e: NeonEvent) => void) | null;
	onLoadEnd?: (() => void) | null;
	onLayout?: ((e: NeonEvent) => void) | null;
}

// Polls like Share.share (WORKAROUND.md P2): `new Promise(executor)` does not lower.
class PrefetchSlot {
	settled: boolean = false;
	ok: boolean = false;

	settle(ok: boolean): void {
		if (this.settled) { return; }
		this.ok = ok;
		this.settled = true;
	}

	async wait(): Promise<boolean> {
		while (!this.settled) { await sleepAsync(16); }
		return this.ok;
	}
}

// RN's Image statics. A function component cannot carry members in msc (compiler card
// 2026-10-08-function-component-cannot-carry-static-members.md, WORKAROUND.md G1), so RN's
// `Image.getSize` / `Image.prefetch` are `ImageLoader.getSize` / `ImageLoader.prefetch`.
export class ImageLoader {
	static getSize(uri: string, success: (width: number, height: number) => void, failure: ((error: Error) => void) | null = null): void {
		appServices("Image.getSize").imageSize(uri, (width: number, height: number, error: string): void => {
			if (error === "") {
				success(width, height);
			} else if (failure !== null) {
				(failure as (e: Error) => void)(new Error(error));
			}
		});
	}

	static async prefetch(uri: string): Promise<boolean> {
		const slot = new PrefetchSlot();
		appServices("Image.prefetch").imageSize(uri, (width: number, height: number, error: string): void => {
			slot.settle(error === "");
		});
		return await slot.wait();
	}
}

// RN defaultSource: the placeholder shows until the source is in the image cache, then the
// view switches to the source, which loads from that cache.
function sourceWithDefault(read: Accessor<ImageSource>, fallback: Accessor<ImageSource>, failed: (error: string) => void): Accessor<string> {
	const [ready, setReady] = createSignal<string>("");
	let asked = "";
	return accessor((): string => {
		const uri = read().uri;
		if (ready() === uri) { return uri; }
		if (asked !== uri) {
			asked = uri;
			untrack((): void => {
				appServices("Image.defaultSource").imageSize(uri, (width: number, height: number, error: string): void => {
					if (asked !== uri) { return; }
					if (error === "") { setReady(uri); } else { failed(error); }
				});
			});
		}
		return fallback().uri;
	});
}

export function Image(props: ImageProps): NeonNode {
	const attrs: VAttr[] = [];
	const source = props.source;
	const start = props.onLoadStart;
	const load = props.onLoad;
	const fail = props.onError;
	const end = props.onLoadEnd;
	const fallback = props.defaultSource;
	let shown = "";
	let wanted = "";
	if (source !== null) {
		const read = source as Accessor<ImageSource>;
		const pick: Accessor<string> = fallback === null
			? accessor((): string => read().uri)
			: sourceWithDefault(read, fallback as Accessor<ImageSource>, (error: string): void => {
				const e = neonEvent("error");
				e.value = error;
				if (fail !== null) { (fail as (x: NeonEvent) => void)(e); }
				if (end !== null) { (end as () => void)(); }
			});
		attrs.push(dynAttr("source", (): string | null => {
			wanted = read().uri;
			shown = pick();
			if (start !== null && shown === wanted) { (start as () => void)(); }
			return shown;
		}));
	}
	const mode = props.resizeMode;
	if (mode !== null) {
		const read = mode as Accessor<ImageResizeMode>;
		attrs.push(dynAttr("resizeMode", (): string | null => { const m: ImageResizeMode = read(); return m; }));
	}
	const blur = props.blurRadius;
	if (blur !== null) {
		const read = blur as Accessor<number>;
		attrs.push(dynAttr("blurRadius", (): string | null => Math.max(0, read()).toString()));
	}
	if (props.accessibilityRole === null) { attrs.push(dynAttr("accessibilityRole", (): string | null => "image")); }
	accessibilityAttrs(props, attrs);
	const evts: VEvent[] = [];
	if (load !== null || end !== null) {
		evts.push(evt("onLoad", (e: NeonEvent): void => {
			if (shown !== wanted) { return; }
			if (load !== null) { (load as (x: NeonEvent) => void)(e); }
			if (end !== null) { (end as () => void)(); }
		}));
	}
	if (fail !== null || end !== null) {
		evts.push(evt("onError", (e: NeonEvent): void => {
			if (shown !== wanted) { return; }
			if (fail !== null) { (fail as (x: NeonEvent) => void)(e); }
			if (end !== null) { (end as () => void)(); }
		}));
	}
	if (props.onLayout !== null) { evts.push(evt("onLayout", props.onLayout as (e: NeonEvent) => void)); }
	let style: (() => Style) | null = null;
	if (props.style !== null) { style = props.style as () => Style; }
	return hostElement("image", attrs, evts, null, style, props.ref);
}
