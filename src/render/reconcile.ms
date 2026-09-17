// DOM minimal-move list reconciler (udomdiff variant). Given the current row list
// `a` and the incoming list `b` (a row is a Range of host nodes; both lists share
// row identity for reused rows), it rearranges the host with the fewest
// inserts/removes. `after` is the marker the region ends before (insertion anchor);
// host ops do every mutation, so the same code drives the mock host and the browser
// DOM.

import { Host, HostNode } from "./hostTypes";

export interface Range {
	start: HostNode;
	end: HostNode;
}

export function rangeOf(n: HostNode): Range {
	return { start: n, end: n };
}

export function moveRange(host: Host, parent: HostNode, r: Range, before: HostNode | null): void {
	if (before === r.start) { return; }
	const end = r.end;
	let node: HostNode | null = r.start;
	while (node !== null) {
		const cur = node as HostNode;
		const next = host.nextSibling(cur);
		host.insertBefore(parent, cur, before);
		if (cur === end) { return; }
		node = next;
	}
}

function replaceRange(host: Host, parent: HostNode, fresh: Range, stale: Range): void {
	moveRange(host, parent, fresh, stale.start);
	removeRange(host, parent, stale);
}

export function removeRange(host: Host, parent: HostNode, r: Range): void {
	const end = r.end;
	let node: HostNode | null = r.start;
	while (node !== null) {
		const cur = node as HostNode;
		const next = host.nextSibling(cur);
		host.removeChild(parent, cur);
		if (cur === end) { return; }
		node = next;
	}
}

export function reconcileArrays(host: Host, parent: HostNode, a: Range[], b: Range[], after: HostNode | null): void {
	const bLength = b.length;
	let aEnd = a.length;
	let bEnd = bLength;
	let aStart = 0;
	let bStart = 0;
	let map: Map<Range, number> | null = null;

	if (aEnd === 0) {
		let i = 0;
		while (i < bLength) { moveRange(host, parent, b[i], after); i += 1; }
		return;
	}

	while (aStart < aEnd || bStart < bEnd) {
		// 1) common prefix
		if (aStart < aEnd && bStart < bEnd && a[aStart] === b[bStart]) {
			aStart += 1;
			bStart += 1;
			continue;
		}
		// 2) common suffix
		while (aEnd > aStart && bEnd > bStart && a[aEnd - 1] === b[bEnd - 1]) {
			aEnd -= 1;
			bEnd -= 1;
		}

		if (aEnd === aStart) {
			// 3) all remaining b are inserts
			let node: HostNode | null = after;
			if (bEnd < bLength) {
				node = bStart > 0 ? host.nextSibling(b[bStart - 1].end) : b[bEnd].start;
			}
			while (bStart < bEnd) { moveRange(host, parent, b[bStart], node); bStart += 1; }
		} else if (bEnd === bStart) {
			// 4) all remaining a are removes (skip ones the map already relocated)
			while (aStart < aEnd) {
				if (map === null || !map.has(a[aStart])) { removeRange(host, parent, a[aStart]); }
				aStart += 1;
			}
		} else if (a[aStart] === b[bEnd - 1] && b[bStart] === a[aEnd - 1]) {
			// 5) reversal at both ends — two moves instead of a remap
			aEnd -= 1;
			const swapNode = host.nextSibling(a[aEnd].end);
			const refA = host.nextSibling(a[aStart].end);
			moveRange(host, parent, b[bStart], refA);
			bStart += 1;
			aStart += 1;
			bEnd -= 1;
			moveRange(host, parent, b[bEnd], swapNode);
			a[aEnd] = b[bEnd];
		} else {
			// 6) map fallback with longest-consecutive-run heuristic
			if (map === null) {
				map = new Map<Range, number>();
				let i = bStart;
				while (i < bEnd) { map.set(b[i], i); i += 1; }
			}
			if (map.has(a[aStart])) {
				const index = map.get(a[aStart]) as number;
				if (bStart < index && index < bEnd) {
					let i = aStart;
					let sequence = 1;
					let cont = true;
					while (cont) {
						i += 1;
						if (i >= aEnd || i >= bEnd) {
							cont = false;
						} else if (!map.has(a[i])) {
							cont = false;
						} else {
							const t = map.get(a[i]) as number;
							if (t !== index + sequence) { cont = false; } else { sequence += 1; }
						}
					}
					if (sequence > index - bStart) {
						const node = a[aStart].start;
						while (bStart < index) { moveRange(host, parent, b[bStart], node); bStart += 1; }
					} else {
						replaceRange(host, parent, b[bStart], a[aStart]);
						bStart += 1;
						aStart += 1;
					}
				} else {
					aStart += 1;
				}
			} else {
				removeRange(host, parent, a[aStart]);
				aStart += 1;
			}
		}
	}
}
