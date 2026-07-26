// Control flow — For / Index / Show. Each returns a region VNode that nests directly in
// el(tag, attrs, events, [ For({...}) ]). The reactive engines (mapArray/indexArray) and
// the host reconciler do the work; these are thin wrappers, mirroring the reference's
// <For>/<Index>/<Show> = thin wrappers over the array helpers + a condition memo.

import { mapArray, indexArray } from "../../core/array";
import { createMemo } from "../../core/memo";
import { createRoot } from "../../core/owner";
import { VNode, regionNode } from "../../render/node";
import { Host, HostNode, renderNode } from "../../render/host";

// Wrap a row list with an empty-state fallback. The fallback lives in its own root and is
// disposed the moment rows return (and rebuilt on the next empty), so it never leaks.
function withFallback(mapped: () => HostNode[], fb: VNode, host: Host): () => HostNode[] {
	let fbNode: HostNode | null = null;
	let fbDispose: (() => void) | null = null;
	return () => {
		const rows = mapped();
		if (rows.length > 0) {
			if (fbDispose !== null) { fbDispose(); fbDispose = null; fbNode = null; }
			return rows;
		}
		if (fbNode === null) {
			fbNode = createRoot((d) => { fbDispose = d; return renderNode(fb, host); });
		}
		return [fbNode];
	};
}

// Value-keyed list: rows reused by item identity; reorder moves DOM, never rebuilds.
export function For<T>(props: {
	each: () => T[];
	children: (item: T, index: () => number) => VNode;
	fallback?: VNode;
}): VNode {
	return regionNode((h) => {
		const host = h as Host;
		const mapped = mapArray<T, HostNode>(props.each, (item, idx) => renderNode(props.children(item, idx), host));
		const fb = props.fallback;
		if (!fb) { return mapped; }
		return withFallback(mapped, fb, host);
	});
}

// Index-keyed list: rows fixed per slot; value change updates the row's signal in place.
export function Index<T>(props: {
	each: () => T[];
	children: (item: () => T, index: number) => VNode;
	fallback?: VNode;
}): VNode {
	return regionNode((h) => {
		const host = h as Host;
		const mapped = indexArray<T, HostNode>(props.each, (item, idx) => renderNode(props.children(item, idx), host));
		const fb = props.fallback;
		if (!fb) { return mapped; }
		return withFallback(mapped, fb, host);
	});
}

// Conditional: children rebuild only when the condition's truthiness flips (equals memo).
export function Show(props: {
	when: () => boolean;
	children: VNode;
	fallback?: VNode;
}): VNode {
	return regionNode((h) => {
		const host = h as Host;
		const cond = createMemo(() => props.when(), (a, b) => a === b);
		return createMemo<HostNode[]>(() => {
			if (cond()) { return [renderNode(props.children, host)]; }
			const fb = props.fallback;
			if (fb) { return [renderNode(fb, host)]; }
			return [] as HostNode[];
		});
	});
}
