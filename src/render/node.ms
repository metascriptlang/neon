// A NeonNode is a function that puts the host nodes it owns into `parent`, in
// front of `before`. JSX lowers to one through the element macro; the builders
// here are the same thing written by hand, for a tag, an attr list or an event
// list only known at runtime (src/components/primitives.ms).

import { createRenderEffect } from "../core/effect";
import { Cleanup } from "../core/types";
import { Style } from "./style";
import { NeonEvent } from "./event";
import { Host, HostNode, NeonNode, RefFn } from "./hostTypes";
import { Row, place, reconcileArrays, mountAt, removeRow } from "./reconcile";
import { regionAnchor, regionParent, sealRegion, serverRegionStart, serverRegionEnd } from "./claim";
import { isServer } from "./environment";
import { bindText, bindAttr, bindStyleAll, applyRef } from "./bind";

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
		if (ref !== null) { applyRef(node, ref as RefFn); }
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

// On the server a region writes its rows and then its anchor, in document order. The
// rows are read in the effect the client keeps them in, so they are owned and numbered
// as the client's; a row list that changes while its rows render (an ErrorBoundary that
// caught) takes back what it wrote and writes the new rows before the anchor follows.
function serverRegion(host: Host, parent: HostNode, before: HostNode | null, fn: RegionFn): void {
	serverRegionStart(host, parent, before);
	const rows = fn(host);
	let next: Row[] = [];
	let written = false;
	createRenderEffect<Row[]>(
		(prev: Row[] | null): Row[] => rows(),
		(value: Row[], prev: Row[] | null): Cleanup | null => {
			if (written) { throw new Error("SSR: a region's rows changed after the server wrote it; set the signal before the content that reads it"); }
			next = value;
			return null;
		},
	);
	let shown: Row[] = [];
	for (let pass = 0; !sameRows(next, shown); pass += 1) {
		if (pass === 100) { throw new Error("SSR: a region's rows kept changing while it rendered"); }
		const taken = shown;
		for (const r of taken) { removeRow(host, parent, r); }
		shown = next;
		for (const r of shown) {
			if (taken.includes(r)) { throw new Error("SSR: a region's rows changed while it rendered and kept a row it had written"); }
			mountAt(host, parent, before, r);
		}
	}
	written = true;
	serverRegionEnd(host, parent, before);
}

function sameRows(a: Row[], b: Row[]): boolean {
	if (a.length !== b.length) { return false; }
	for (let i = 0; i < a.length; i += 1) {
		if (a[i] !== b[i]) { return false; }
	}
	return true;
}

export function regionNode(fn: RegionFn): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		if (isServer()) { serverRegion(host, parent, before, fn); return; }
		const anchor = regionAnchor(host, parent, before);
		let current: Row[] = [];
		let mounted = false;
		const rows = fn(host);
		createRenderEffect<Row[]>(
			(prev: Row[] | null): Row[] => rows(),
			(next: Row[], prev: Row[] | null): Cleanup | null => {
				const at = mounted ? regionParent(host, anchor, "regionNode") : parent;
				reconcileArrays(host, at, current, next, anchor);
				mounted = true;
				current = next.slice(0, next.length);
				return null;
			},
		);
		sealRegion(host, parent, anchor);
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
