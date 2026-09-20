// Row list reconciler. A row is a span of host nodes plus the view that mounts it,
// so a row that is not in the host yet is mounted at its final position instead of
// being built somewhere else and moved in. Insertion targets come from the NEW
// order — the start of the next row already in the host, or the region anchor
// (Svelte each.js `move(effect, current, anchor)`) — so a live row is never
// detached; only a row absent from the next list is removed.
//
// The rows that keep their relative order are the longest increasing run of the
// surviving rows (Vue 3 / ivi); they are left alone and everything else moves, which
// is the minimum number of moves for a reorder — a swap of two rows is two moves.
// Moves run right to left, so each one already sees its final neighbour; the rows
// being mounted for the first time run afterwards, left to right, so a row body
// still runs in list order.

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
	slot: number;
	stamp: number;
	kept: boolean;
}

function noView(host: Host, parent: HostNode, before: HostNode | null): void {}

export function makeRow(view: NeonNode): Row {
	return { view, owner: getOwner(), parent: null, start: null, end: null, slot: -1, stamp: -1, kept: false };
}

export function rowOf(n: HostNode): Row {
	return { view: noView, owner: null, parent: null, start: n, end: n, slot: -1, stamp: -1, kept: false };
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

// Longest strictly increasing run of `xs`, marked per position (patience sorting with
// predecessors, O(n log n)).
function longestIncreasingRun(xs: number[]): boolean[] {
	const inRun: boolean[] = [];
	for (let i = 0; i < xs.length; i += 1) { inRun.push(false); }
	if (xs.length === 0) { return inRun; }

	const tailValue: number[] = [];
	const tailAt: number[] = [];
	const before: number[] = [];
	for (let i = 0; i < xs.length; i += 1) { before.push(-1); }

	for (let i = 0; i < xs.length; i += 1) {
		const v = xs[i];
		const last = tailValue.length - 1;
		if (last >= 0 && tailValue[last] < v) {
			before[i] = tailAt[last];
			tailValue.push(v);
			tailAt.push(i);
			continue;
		}
		let lo = 0;
		let hi = tailValue.length;
		while (lo < hi) {
			const span = lo + hi;
			const mid = (span - (span % 2)) / 2;
			if (tailValue[mid] < v) { lo = mid + 1; } else { hi = mid; }
		}
		if (lo > 0) { before[i] = tailAt[lo - 1]; }
		if (lo === tailValue.length) {
			tailValue.push(v);
			tailAt.push(i);
		} else {
			tailValue[lo] = v;
			tailAt[lo] = i;
		}
	}

	let at = tailAt[tailAt.length - 1];
	while (at >= 0) {
		inRun[at] = true;
		at = before[at];
	}
	return inRun;
}

let reconcileStamp = 0;

export function reconcileArrays(host: Host, parent: HostNode, a: Row[], b: Row[], after: HostNode | null): void {
	reconcileStamp = reconcileStamp + 1;
	const stamp = reconcileStamp;
	for (let i = 0; i < b.length; i += 1) {
		const row = b[i];
		if (row.stamp === stamp) { throw "reconcileArrays: the next list holds the same row twice"; }
		row.stamp = stamp;
		row.slot = i;
		row.kept = false;
	}

	const survivors: Row[] = [];
	const survivorSlots: number[] = [];
	let ordered = true;
	for (const r of a) {
		if (r.stamp !== stamp) {
			removeRow(host, parent, r);
			continue;
		}
		if (survivorSlots.length > 0 && r.slot < survivorSlots[survivorSlots.length - 1]) { ordered = false; }
		survivors.push(r);
		survivorSlots.push(r.slot);
	}
	if (ordered && survivors.length === b.length) { return; }

	if (ordered) {
		for (let p = 0; p < survivors.length; p += 1) { survivors[p].kept = true; }
	} else {
		const inRun = longestIncreasingRun(survivorSlots);
		for (let p = 0; p < survivors.length; p += 1) {
			if (inRun[p]) { survivors[p].kept = true; }
		}
	}

	const freshRows: Row[] = [];
	const freshAnchors: (HostNode | null)[] = [];
	let next: HostNode | null = after;
	for (let i = b.length - 1; i >= 0; i -= 1) {
		const row = b[i];
		const start = row.start;
		if (start === null) {
			freshRows.push(row);
			freshAnchors.push(next);
			continue;
		}
		if (!row.kept) { moveRow(host, parent, row, next); }
		next = start;
	}

	for (let k = freshRows.length - 1; k >= 0; k -= 1) {
		mountAt(host, parent, freshAnchors[k], freshRows[k]);
	}
}
