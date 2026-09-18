// Control flow — For / Index / Show. Each returns a region NeonNode that nests directly in
// el(tag, attrs, events, [ For({...}) ]). The reactive engines (mapArray/indexArray) and
// the host reconciler do the work; these are thin wrappers, mirroring the reference's
// <For>/<Index>/<Show> = thin wrappers over the array helpers + a condition memo.
// A row is described here and mounted by the reconciler at its final position, so
// nothing below touches the host.

import { mapArray, indexArray } from "../../core/array";
import { createMemo } from "../../core/memo";
import { Accessor } from "../../core/signal";
import { createRoot } from "../../core/owner";
import { onCleanup } from "../../core/cleanup";
import { NeonNode, regionNode } from "../../render/node";
import { NeonView } from "../../render/host";
import { Row, makeRow } from "../../render/reconcile";

// Wrap a row list with an empty-state fallback. The fallback lives in its own root and is
// disposed the moment rows return (and rebuilt on the next empty), so it never leaks.
function withFallback(mapped: () => Row[], fb: NeonView): () => Row[] {
	let fbRow: Row | null = null;
	let fbDispose: (() => void) | null = null;
	onCleanup(() => { if (fbDispose !== null) { fbDispose(); fbDispose = null; fbRow = null; } });
	return () => {
		const rows = mapped();
		if (rows.length > 0) {
			if (fbDispose !== null) { fbDispose(); fbDispose = null; fbRow = null; }
			return rows;
		}
		if (fbRow === null) {
			fbRow = createRoot((d) => { fbDispose = d; return makeRow(fb); });
		}
		return [fbRow as Row];
	};
}

// Value-keyed list: rows reused by item identity; reorder moves DOM, never rebuilds.
export function For<T>(props: {
	each: () => T[];
	children: (item: T, index: Accessor<number>) => NeonView;
	fallback?: NeonView | null;
}): NeonNode {
	return regionNode((h) => {
		const mapped = mapArray<T, Row>(props.each, (item, idx) => makeRow(props.children(item, idx)));
		const fb = props.fallback;
		if (fb === null) { return mapped; }
		return withFallback(mapped, fb as NeonView);
	});
}

// Index-keyed list: rows fixed per slot; value change updates the row's signal in place.
export function Index<T>(props: {
	each: () => T[];
	children: (item: Accessor<T>, index: number) => NeonView;
	fallback?: NeonView | null;
}): NeonNode {
	return regionNode((h) => {
		const mapped = indexArray<T, Row>(props.each, (item, idx) => makeRow(props.children(item, idx)));
		const fb = props.fallback;
		if (fb === null) { return mapped; }
		return withFallback(mapped, fb as NeonView);
	});
}

// Conditional: children rebuild only when the condition's truthiness flips (equals memo).
export function Show(props: {
	when: () => boolean;
	children: NeonView;
	fallback?: NeonView | null;
}): NeonNode {
	return regionNode((h) => {
		const cond = createMemo(() => props.when(), (a, b) => a === b);
		return createMemo<Row[]>(() => {
			if (cond()) { return [makeRow(props.children)]; }
			const fb = props.fallback;
			if (fb !== null) { return [makeRow(fb as NeonView)]; }
			return [] as Row[];
		});
	});
}
