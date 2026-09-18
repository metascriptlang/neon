// Row list reconciler. A row is a span of host nodes plus the view that mounts it,
// so a row that is not in the host yet is mounted at its final position instead of
// being built somewhere else and moved in. Insertion targets come from the NEW
// order — the start of the row currently occupying the slot, or the region anchor
// (Svelte each.js `move(effect, current, anchor)`) — so a live row is never
// detached; only a row absent from the next list is removed.

import { Host, HostNode, NeonNode } from "./hostTypes";
import { Computation } from "../core/types";
import { getOwner } from "../core/runtime";
import { runWithOwner } from "../core/owner";
import { untrack } from "../core/signal";

export interface Row {
	view: NeonNode;
	owner: Computation | null;
	parent: HostNode | null;
	start: HostNode | null;
	end: HostNode | null;
}

function noView(host: Host, parent: HostNode, before: HostNode | null): void {}

export function makeRow(view: NeonNode): Row {
	return { view, owner: getOwner(), parent: null, start: null, end: null };
}

export function rowOf(n: HostNode): Row {
	return { view: noView, owner: null, parent: null, start: n, end: n };
}

let activeRow: Row | null = null;

export function place(host: Host, parent: HostNode, node: HostNode, before: HostNode | null): void {
	host.insertBefore(parent, node, before);
	const r = activeRow;
	if (r === null || r.parent !== parent) { return; }
	if (r.start === null) { r.start = node; }
	r.end = node;
}

export function needsStartMarker(parent: HostNode): boolean {
	const r = activeRow;
	return r !== null && r.parent === parent && r.start === null;
}

export function mountAt(host: Host, parent: HostNode, before: HostNode | null, r: Row): void {
	const prev = activeRow;
	r.parent = parent;
	activeRow = r;
	try {
		runWithOwner(r.owner, (): number => untrack((): number => { r.view(host, parent, before); return 0; }));
	} finally {
		activeRow = prev;
	}
	if (r.start === null) {
		const empty = host.createText("");
		place(host, parent, empty, before);
		r.start = empty;
		r.end = empty;
	}
}

export function moveRow(host: Host, parent: HostNode, r: Row, before: HostNode | null): void {
	const start = r.start;
	if (start === null || before === start) { return; }
	const end = r.end;
	let node: HostNode | null = start;
	while (node !== null) {
		const cur = node as HostNode;
		const next = host.nextSibling(cur);
		host.insertBefore(parent, cur, before);
		if (cur === end) { return; }
		node = next;
	}
}

export function removeRow(host: Host, parent: HostNode, r: Row): void {
	const start = r.start;
	if (start === null) { return; }
	const end = r.end;
	let node: HostNode | null = start;
	while (node !== null) {
		const cur = node as HostNode;
		const next = host.nextSibling(cur);
		host.removeChild(parent, cur);
		if (cur === end) { return; }
		node = next;
	}
}

export function reconcileArrays(host: Host, parent: HostNode, a: Row[], b: Row[], after: HostNode | null): void {
	const wanted = new Map<Row, number>();
	for (let i = 0; i < b.length; i += 1) { wanted.set(b[i], i); }

	const live: Row[] = [];
	for (const r of a) {
		if (wanted.has(r)) { live.push(r); } else { removeRow(host, parent, r); }
	}

	for (let i = 0; i < b.length; i += 1) {
		const want = b[i];
		if (i < live.length && live[i] === want) { continue; }
		const ref: HostNode | null = i < live.length ? live[i].start : after;
		let at = -1;
		for (let j = i + 1; j < live.length; j += 1) {
			if (live[j] === want) { at = j; break; }
		}
		if (at >= 0) { live.splice(at, 1); }
		if (want.start === null) {
			mountAt(host, parent, ref, want);
		} else {
			moveRow(host, parent, want, ref);
		}
		live.splice(i, 0, want);
	}
}
