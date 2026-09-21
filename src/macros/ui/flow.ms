// Control flow — For / Index / Show. Each returns a region NeonNode. The reactive
// engines (mapArray/indexArray) and the host reconciler do the work; these are thin
// wrappers, mirroring the reference's
// <For>/<Index>/<Show> = thin wrappers over the array helpers + a condition memo.
// A row is described here and mounted by the reconciler at its final position, so
// nothing below touches the host.

import { mapArray, mapArrayKeyed, indexArray } from "../../core/array";
import { createMemo } from "../../core/memo";
import { Accessor, createSignal } from "../../core/signal";
import { createRoot } from "../../core/owner";
import { onCleanup } from "../../core/cleanup";
import { catchError } from "../../core/error";
import { NeonNode, regionNode } from "../../render/node";
import { Host, HostNode } from "../../render/hostTypes";
import { Row, makeRow } from "../../render/reconcile";

// Wrap a row list with an empty-state fallback. The fallback lives in its own root and is
// disposed the moment rows return (and rebuilt on the next empty), so it never leaks.
function withFallback(mapped: () => Row[], fb: NeonNode): () => Row[] {
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

// Value-keyed list: rows reused by item identity, or by key when one is given; reorder
// moves DOM, never rebuilds.
export function For<T>(props: {
	each: () => T[];
	children: (item: T, index: Accessor<number>) => NeonNode;
	key?: ((item: T) => number) | null;
	usesIndex?: boolean | null;
	fallback?: NeonNode | null;
}): NeonNode {
	return regionNode((h) => {
		const keyOf = props.key;
		const declared = props.usesIndex;
		const usesIndex = declared === null ? true : (declared as boolean);
		const row = (item: T, idx: Accessor<number>): Row => makeRow(props.children(item, idx));
		const mapped = keyOf === null
			? mapArray<T, Row>(props.each, row, usesIndex)
			: mapArrayKeyed<T, Row>(props.each, keyOf as (item: T) => number, row, usesIndex);
		const fb = props.fallback;
		if (fb === null) { return mapped; }
		return withFallback(mapped, fb as NeonNode);
	});
}

// Index-keyed list: rows fixed per slot; value change updates the row's signal in place.
export function Index<T>(props: {
	each: () => T[];
	children: (item: Accessor<T>, index: number) => NeonNode;
	fallback?: NeonNode | null;
}): NeonNode {
	return regionNode((h) => {
		const mapped = indexArray<T, Row>(props.each, (item, idx) => makeRow(props.children(item, idx)));
		const fb = props.fallback;
		if (fb === null) { return mapped; }
		return withFallback(mapped, fb as NeonNode);
	});
}

export function ErrorBoundary(props: {
	children: NeonNode;
	fallback: (err: string, reset: () => void) => NeonNode;
}): NeonNode {
	return regionNode((h) => {
		const [failed, setFailed] = createSignal<string | null>(null);
		const reset = (): void => { setFailed(null); };
		const guarded: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
			catchError(
				(): void => { props.children(host, parent, before); },
				(err: string): void => { setFailed(err); },
			);
		};
		return createMemo<Row[]>(() => {
			const err = failed();
			if (err !== null) { return [makeRow(props.fallback(err as string, reset))]; }
			return [makeRow(guarded)];
		});
	});
}

// Conditional: children rebuild only when the condition's truthiness flips (equals memo).
export function Show(props: {
	when: () => boolean;
	children: NeonNode;
	fallback?: NeonNode | null;
}): NeonNode {
	return regionNode((h) => {
		const cond = createMemo(() => props.when(), (a, b) => a === b);
		return createMemo<Row[]>(() => {
			if (cond()) { return [makeRow(props.children)]; }
			const fb = props.fallback;
			if (fb !== null) { return [makeRow(fb as NeonNode)]; }
			return [] as Row[];
		});
	});
}
