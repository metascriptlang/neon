// Control flow — For / Index / Show. Each returns a region NeonNode that nests directly in
// el(tag, attrs, events, [ For({...}) ]). The reactive engines (mapArray/indexArray) and
// the host reconciler do the work; these are thin wrappers, mirroring the reference's
// <For>/<Index>/<Show> = thin wrappers over the array helpers + a condition memo.

import { mapArray, indexArray } from "../../core/array";
import { createMemo } from "../../core/memo";
import { Accessor, untrack } from "../../core/signal";
import { createRoot } from "../../core/owner";
import { onCleanup } from "../../core/cleanup";
import { NeonNode, regionNode } from "../../render/node";
import { Host, NeonView, mountView } from "../../render/host";
import { Range, rangeOf } from "../../render/reconcile";

// Wrap a row list with an empty-state fallback. The fallback lives in its own root and is
// disposed the moment rows return (and rebuilt on the next empty), so it never leaks.
function withFallback(mapped: () => Range[], fb: NeonView, host: Host): () => Range[] {
	let fbNode: Range | null = null;
	let fbDispose: (() => void) | null = null;
	onCleanup(() => { if (fbDispose !== null) { fbDispose(); fbDispose = null; fbNode = null; } });
	return () => {
		const rows = mapped();
		if (rows.length > 0) {
			if (fbDispose !== null) { fbDispose(); fbDispose = null; fbNode = null; }
			return rows;
		}
		if (fbNode === null) {
			fbNode = createRoot((d) => { fbDispose = d; return rangeOf(mountView(fb, host)); });
		}
		return [fbNode];
	};
}

// Value-keyed list: rows reused by item identity; reorder moves DOM, never rebuilds.
export function For<T>(props: {
	each: () => T[];
	children: (item: T, index: Accessor<number>) => NeonView;
	fallback?: NeonView | null;
}): NeonNode {
	return regionNode((h) => {
		const host = h as Host;
		const mapped = mapArray<T, Range>(props.each, (item, idx) => rangeOf(mountView(props.children(item, idx), host)));
		const fb = props.fallback;
		if (fb === null) { return mapped; }
		return withFallback(mapped, fb as NeonView, host);
	});
}

// Index-keyed list: rows fixed per slot; value change updates the row's signal in place.
export function Index<T>(props: {
	each: () => T[];
	children: (item: Accessor<T>, index: number) => NeonView;
	fallback?: NeonView | null;
}): NeonNode {
	return regionNode((h) => {
		const host = h as Host;
		const mapped = indexArray<T, Range>(props.each, (item, idx) => rangeOf(mountView(props.children(item, idx), host)));
		const fb = props.fallback;
		if (fb === null) { return mapped; }
		return withFallback(mapped, fb as NeonView, host);
	});
}

// Conditional: children rebuild only when the condition's truthiness flips (equals memo).
export function Show(props: {
	when: () => boolean;
	children: NeonView;
	fallback?: NeonView | null;
}): NeonNode {
	return regionNode((h) => {
		const host = h as Host;
		const cond = createMemo(() => props.when(), (a, b) => a === b);
		return createMemo<Range[]>(() => {
			if (cond()) { return untrack(() => [rangeOf(mountView(props.children, host))]); }
			const fb = props.fallback;
			if (fb !== null) { return untrack(() => [rangeOf(mountView(fb as NeonView, host))]); }
			return [] as Range[];
		});
	});
}
