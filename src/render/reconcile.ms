// DOM minimal-move list reconciler (udomdiff variant). Given the current host-node
// list `a` and the incoming list `b` (both sharing node identity for reused rows),
// it rearranges the host with the fewest inserts/removes. `after` is the marker the
// region ends before (insertion anchor); host ops do every mutation, so the same code
// drives the mock host and the browser DOM.

import { Host, HostNode } from "./hostTypes";

function replaceChild(host: Host, parent: HostNode, newNode: HostNode, oldNode: HostNode): void {
	host.insertBefore(parent, newNode, oldNode);
	host.removeChild(parent, oldNode);
}

export function reconcileArrays(host: Host, parent: HostNode, a: HostNode[], b: HostNode[], after: HostNode | null): void {
	const bLength = b.length;
	let aEnd = a.length;
	let bEnd = bLength;
	let aStart = 0;
	let bStart = 0;
	let map: Map<HostNode, number> | null = null;

	if (aEnd === 0) {
		let i = 0;
		while (i < bLength) { host.insertBefore(parent, b[i], after); i += 1; }
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
				node = bStart > 0 ? host.nextSibling(b[bStart - 1]) : b[bEnd];
			}
			while (bStart < bEnd) { host.insertBefore(parent, b[bStart], node); bStart += 1; }
		} else if (bEnd === bStart) {
			// 4) all remaining a are removes (skip ones the map already relocated)
			while (aStart < aEnd) {
				if (map === null || !map.has(a[aStart])) { host.removeChild(parent, a[aStart]); }
				aStart += 1;
			}
		} else if (a[aStart] === b[bEnd - 1] && b[bStart] === a[aEnd - 1]) {
			// 5) reversal at both ends — two moves instead of a remap
			aEnd -= 1;
			const swapNode = host.nextSibling(a[aEnd]);
			const refA = host.nextSibling(a[aStart]);
			host.insertBefore(parent, b[bStart], refA);
			bStart += 1;
			aStart += 1;
			bEnd -= 1;
			host.insertBefore(parent, b[bEnd], swapNode);
			a[aEnd] = b[bEnd];
		} else {
			// 6) map fallback with longest-consecutive-run heuristic
			if (map === null) {
				map = new Map<HostNode, number>();
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
						const node = a[aStart];
						while (bStart < index) { host.insertBefore(parent, b[bStart], node); bStart += 1; }
					} else {
						replaceChild(host, parent, b[bStart], a[aStart]);
						bStart += 1;
						aStart += 1;
					}
				} else {
					aStart += 1;
				}
			} else {
				host.removeChild(parent, a[aStart]);
				aStart += 1;
			}
		}
	}
}
