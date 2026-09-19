// A NeonNode is a function that puts the host nodes it owns into `parent`, in
// front of `before`. JSX lowers to one through the element macro; the builders
// here are the same thing written by hand, for a tag, an attr list or an event
// list only known at runtime (src/components/primitives.ms).

import { createEffect } from "../core/effect";
import { Style } from "./style";
import { NeonEvent } from "./event";
import { Host, HostNode, NeonNode, RefFn } from "./hostTypes";
import { Row, place, needsStartMarker, reconcileArrays } from "./reconcile";
import { bindText, bindAttr, bindStyleAll } from "./bind";

export { NeonNode, RefFn } from "./hostTypes";

export interface VAttr {
	name: string;
	value: string | null;  // static value ("" when dynamic)
	isDyn: boolean;        // true → `dyn` is the live value source
	dyn: () => string | null;
}

export interface VEvent {
	name: string;          // raw JSX name, e.g. "onPress" (host maps to "click")
	handler: (e: NeonEvent) => void;
}

export type RegionFn = (host: Host) => () => Row[];

export type ComponentFn<P = unknown> = (props: P) => NeonNode;

export function attr(name: string, value: string | null): VAttr {
	return { name, value, isDyn: false, dyn: () => "" };
}

export function dynAttr(name: string, thunk: () => string | null): VAttr {
	return { name, value: "", isDyn: true, dyn: thunk };
}

export function evt(name: string, handler: (e: NeonEvent) => void): VEvent {
	return { name, handler };
}

export function hostElement(
	tag: string,
	attrs: VAttr[],
	events: VEvent[],
	children: NeonNode | null,
	style: (() => Style) | null,
	ref: RefFn | null,
): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		const node = host.createElement(tag);
		for (const a of attrs) {
			if (a.isDyn) {
				bindAttr(host, node, a.name, a.dyn);
			} else if (a.value !== null) {
				host.setAttr(node, a.name, a.value as string);
			}
		}
		if (style !== null) { bindStyleAll(host, node, style as () => Style); }
		for (const e of events) { host.addEvent(node, e.name, e.handler); }
		if (children !== null) { (children as NeonNode)(host, node, null); }
		if (ref !== null) { (ref as RefFn)(node); }
		place(host, parent, node, before);
	};
}

export function el(tag: string, attrs: VAttr[], events: VEvent[], children: NeonNode | null): NeonNode {
	return hostElement(tag, attrs, events, children, null, null);
}

export function text(s: string): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		place(host, parent, host.createText(s), before);
	};
}

export function dynText(thunk: () => string): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		const node = host.createText("");
		bindText(host, node, thunk);
		place(host, parent, node, before);
	};
}

export function mountChild(host: Host, parent: HostNode, before: HostNode | null, s: string): void {
	place(host, parent, host.createText(s), before);
}

export function mountChild(host: Host, parent: HostNode, before: HostNode | null, n: NeonNode): void {
	n(host, parent, before);
}

export function mountChild(host: Host, parent: HostNode, before: HostNode | null, ns: NeonNode[]): void {
	for (const n of ns) { n(host, parent, before); }
}

export function regionNode(fn: RegionFn): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		if (needsStartMarker(parent)) { place(host, parent, host.createText(""), before); }
		const anchor = host.createText("");
		place(host, parent, anchor, before);
		let current: Row[] = [];
		const rows = fn(host);
		createEffect(() => {
			const next = rows();
			reconcileArrays(host, parent, current, next, anchor);
			current = next.slice(0, next.length);
		});
	};
}

// Universal wire tags → html. One table shared by SSR (renderToString) and the
// browser host's createElement — the user-facing names (View/Text/…) are the
// the component vocabulary in src/components/primitives.ms; hosts receive the lowercase wire
// tag and translate (browser: this table; terminal: its boxes; void ignores).
export function htmlTagFor(tag: string): string {
	if (tag === "view") { return "div"; }
	if (tag === "text") { return "span"; }
	if (tag === "textinput") { return "input"; }
	if (tag === "pressable") { return "button"; }
	return tag;
}
