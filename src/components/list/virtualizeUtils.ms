// React Native's VirtualizeUtils (packages/virtualized-lists/Lists/VirtualizeUtils.js): which
// rows a list keeps rendered around its viewport.

export struct CellRange {
	first: int32;
	last: int32;
}

export struct CellMetrics {
	index: int32;
	length: float64;
	offset: float64;
	isMounted: boolean;
}

export struct WindowScroll {
	offset: float64;
	velocity: float64;
	visibleLength: float64;
	zoomScale: float64;
}

// Parked: an (int32 | null)[] result cannot be built on C —
// ~/metascript/.inbox/compiler/2026-10-03-nullable-int32-array-push.md
export struct OffsetHit {
	found: boolean;
	index: int32;
}

enum FillPreference {
	After,
	Before,
	None,
}

export function newRangeCount(prev: CellRange, next: CellRange): int32 {
	return next.last - next.first + 1 - Math.max(0, 1 + Math.min(next.last, prev.last) - Math.max(next.first, prev.first));
}

export function elementsThatOverlapOffsets(offsets: float64[], itemCount: int32, metricsAt: (index: int32) => CellMetrics, zoomScale: float64): OffsetHit[] {
	const result: OffsetHit[] = [];
	for (let offsetIndex = 0; offsetIndex < offsets.length; offsetIndex += 1) {
		const current = offsets[offsetIndex];
		let left: int32 = 0;
		let right: int32 = itemCount - 1;
		while (left <= right) {
			const mid: int32 = left + (right - left) / 2;
			const frame = metricsAt(mid);
			const start = frame.offset * zoomScale;
			const end = (frame.offset + frame.length) * zoomScale;
			if ((mid === 0 && current < start) || (mid !== 0 && current <= start)) {
				right = mid - 1;
			} else if (current > end) {
				left = mid + 1;
			} else {
				while (result.length < offsetIndex) { result.push({ found: false, index: 0 }); }
				result.push({ found: true, index: mid });
				break;
			}
		}
	}
	return result;
}

function hitOr(hits: OffsetHit[], at: int32, fallback: int32): int32 {
	if (at >= hits.length) { return fallback; }
	const hit = hits[at];
	return hit.found ? hit.index : fallback;
}

// RN's fixVirtualizeListCollapseWindowSize branch (ReactNativeFeatureFlags.config.js:1002,
// expectedReleaseValue true): without it a fast scroll can collapse the window to one cell.
export function computeWindowedRenderLimits(itemCount: int32, maxToRenderPerBatch: int32, windowSize: int32, prev: CellRange, metricsAt: (index: int32) => CellMetrics, scroll: WindowScroll): CellRange {
	if (itemCount === 0) { return { first: 0, last: -1 }; }
	const visibleBegin = Math.max(0.0, scroll.offset);
	const visibleEnd = visibleBegin + scroll.visibleLength;
	const overscanLength = ((windowSize - 1) as float64) * scroll.visibleLength;
	const leadFactor = 0.5;
	const fill = scroll.velocity > 1.0 ? FillPreference.After : scroll.velocity < -1.0 ? FillPreference.Before : FillPreference.None;
	const overscanBegin = Math.max(0.0, visibleBegin - (1.0 - leadFactor) * overscanLength);
	const overscanEnd = Math.max(0.0, visibleEnd + leadFactor * overscanLength);

	const lastItemOffset = metricsAt(itemCount - 1).offset * scroll.zoomScale;
	if (lastItemOffset < overscanBegin) {
		return { first: Math.max(0, itemCount - 1 - maxToRenderPerBatch), last: itemCount - 1 };
	}

	const hits = elementsThatOverlapOffsets([overscanBegin, visibleBegin, visibleEnd, overscanEnd], itemCount, metricsAt, scroll.zoomScale);
	const overscanFirst = hitOr(hits, 0, 0);
	let first = hitOr(hits, 1, Math.max(0, overscanFirst));
	const overscanLast = hitOr(hits, 3, itemCount - 1);
	let last = hitOr(hits, 2, Math.min(overscanLast, first + maxToRenderPerBatch - 1));
	const visible: CellRange = { first, last };

	let newCellCount = newRangeCount(prev, visible);
	while (true) {
		if (first <= overscanFirst && last >= overscanLast) { break; }
		const maxNewCells = newCellCount >= maxToRenderPerBatch;
		const firstWillAddMore = first <= prev.first;
		const lastWillAddMore = last >= prev.last;
		const firstShouldIncrement = first > overscanFirst && (!maxNewCells || !firstWillAddMore);
		const lastShouldIncrement = last < overscanLast && (!maxNewCells || !lastWillAddMore);
		if (maxNewCells && !firstShouldIncrement && !lastShouldIncrement) { break; }
		if (firstShouldIncrement && !(fill === FillPreference.After && lastShouldIncrement && lastWillAddMore)) {
			if (firstWillAddMore) { newCellCount += 1; }
			first -= 1;
		}
		if (lastShouldIncrement && !(fill === FillPreference.Before && firstShouldIncrement && firstWillAddMore)) {
			if (lastWillAddMore) { newCellCount += 1; }
			last += 1;
		}
	}
	if (!(last >= first && first >= 0 && last < itemCount && first >= overscanFirst && last <= overscanLast && first <= visible.first && last >= visible.last)) {
		throw `computeWindowedRenderLimits: bad window ${first}..${last} for ${itemCount} items, overscan ${overscanFirst}..${overscanLast}, visible ${visible.first}..${visible.last}`;
	}
	return { first, last };
}
