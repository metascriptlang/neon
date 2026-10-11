import {
	CellMetrics, CellRange, OffsetHit, WindowScroll, newRangeCount, elementsThatOverlapOffsets, computeWindowedRenderLimits, shouldRenderWithPriority,
} from "../../../src/components/list/virtualizeUtils";

// Ported from React Native packages/virtualized-lists/Lists/__tests__/VirtualizeUtils-test.js;
// each test keeps the RN case's name, inputs and expected result.

function range(first: int32, last: int32): CellRange {
	return { first, last };
}

function frames(offsets: float64[], lengths: float64[]): (index: int32) => CellMetrics {
	return (index: int32): CellMetrics => ({ index, length: lengths[index], offset: offsets[index], isMounted: true });
}

function fixedFrames(length: float64): (index: int32) => CellMetrics {
	return (index: int32): CellMetrics => ({ index, length, offset: length * (index as float64), isMounted: true });
}

function hits(found: OffsetHit[]): string {
	let out = "";
	for (let i = 0; i < found.length; i += 1) {
		const h = found[i];
		out += (i > 0 ? "," : "") + (h.found ? `${h.index}` : "_");
	}
	return out;
}

function shown(r: CellRange): string {
	return `${r.first}..${r.last}`;
}

const still: WindowScroll = { offset: 0.0, velocity: 0.0, visibleLength: 500.0, zoomScale: 1.0 };

test "newRangeCount handles subset" { assert newRangeCount(range(1, 4), range(2, 3)) === 0; }
test "newRangeCount handles forward disjoint set" { assert newRangeCount(range(1, 4), range(6, 9)) === 4; }
test "newRangeCount handles reverse disjoint set" { assert newRangeCount(range(6, 8), range(1, 4)) === 4; }
test "newRangeCount handles superset" { assert newRangeCount(range(1, 4), range(0, 5)) === 2; }
test "newRangeCount handles end extension" { assert newRangeCount(range(1, 4), range(1, 8)) === 4; }
test "newRangeCount handles front extension" { assert newRangeCount(range(1, 4), range(0, 4)) === 1; }
test "newRangeCount handles forward intersect" { assert newRangeCount(range(1, 4), range(3, 6)) === 2; }
test "newRangeCount handles reverse intersect" { assert newRangeCount(range(3, 6), range(1, 4)) === 2; }

test "elementsThatOverlapOffsets handles fixed length" {
	const found = elementsThatOverlapOffsets([0.0, 250.0, 350.0, 450.0], 100, fixedFrames(100.0), 1.0);
	assert hits(found) === "0,2,3,4", hits(found);
}

test "elementsThatOverlapOffsets handles variable length" {
	const at = frames([0.0, 50.0, 250.0, 850.0, 950.0], [50.0, 200.0, 600.0, 100.0, 150.0]);
	const found = elementsThatOverlapOffsets([150.0, 250.0, 900.0], 5, at, 1.0);
	assert hits(found) === "1,1,3", "an offset on a cell's end belongs to that cell: " + hits(found);
}

test "elementsThatOverlapOffsets handles frame boundaries" {
	const found = elementsThatOverlapOffsets([0.0, 100.0, 200.0, 300.0], 100, fixedFrames(100.0), 1.0);
	assert hits(found) === "0,0,1,2", "a boundary belongs to the earlier cell: " + hits(found);
}

test "elementsThatOverlapOffsets handles out of bounds" {
	const at = frames([0.0, 50.0, 250.0], [50.0, 150.0, 100.0]);
	const found = elementsThatOverlapOffsets([-100.0, 150.0, 900.0], 3, at, 1.0);
	assert hits(found) === "_,1", "a miss leaves a hole and a trailing miss shortens the result: " + hits(found);
}

test "computeWindowedRenderLimits renders all items when list is small" {
	const r = computeWindowedRenderLimits(3, 5, 10, range(0, 2), fixedFrames(100.0), still);
	assert shown(r) === "0..2", shown(r);
}

test "computeWindowedRenderLimits handles overflow cases when window size suddenly collapses" {
	const at = frames([0.0, 275.0, 627.0, 953.0, 1305.0, 1598.0, 1891.0, 2184.0], [275.0, 352.0, 326.0, 352.0, 293.0, 293.0, 293.0, 293.0]);
	const scroll: WindowScroll = { offset: 2073.60009765625, velocity: 0.9264489707504611, visibleLength: 640.0, zoomScale: 1.0 };
	const r = computeWindowedRenderLimits(8, 1, 31, range(0, 5), at, scroll);
	assert shown(r) === "0..6", "cells already rendered cost no batch budget: " + shown(r);
}

test "computeWindowedRenderLimits handles reaching the end of the list" {
	const scroll: WindowScroll = { offset: 900.0, velocity: 1.0, visibleLength: 300.0, zoomScale: 1.0 };
	const r = computeWindowedRenderLimits(10, 2, 5, range(5, 9), fixedFrames(100.0), scroll);
	assert shown(r) === "3..9", shown(r);
}

test "computeWindowedRenderLimits respects maxToRenderPerBatch when adding new cells" {
	const r = computeWindowedRenderLimits(10, 2, 5, range(0, 2), fixedFrames(100.0), still);
	assert shown(r) === "0..4", shown(r);
}

test "computeWindowedRenderLimits handles case where overscanFirst and overscanLast encompass entire list" {
	const scroll: WindowScroll = { offset: 0.0, velocity: 0.0, visibleLength: 1000.0, zoomScale: 1.0 };
	const r = computeWindowedRenderLimits(5, 5, 10, range(0, 4), fixedFrames(100.0), scroll);
	assert shown(r) === "0..4", shown(r);
}

// RN VirtualizedList.js:1812-1848 and getScrollingThreshold at :95-97.
// The bottom distance uses the last cell's start, not its end.
test "shouldRenderWithPriority top overrun is urgent without velocity" {
	const at = fixedFrames(100.0);
	const scroll: WindowScroll = { offset: 199.75, velocity: 0.0, visibleLength: 100.0, zoomScale: 1.0 };
	assert shouldRenderWithPriority(10, range(2, 9), at, scroll, 2.0, 2.0);
	assert !shouldRenderWithPriority(10, range(2, 9), at, { ...scroll, offset: 200.0 }, 2.0, 2.0);
	assert !shouldRenderWithPriority(10, range(2, 9), at, { ...scroll, offset: 200.25 }, 2.0, 2.0);
	assert shouldRenderWithPriority(10, range(2, 9), at, { ...scroll, velocity: 3.0 }, 0.0, 0.0);
}

test "shouldRenderWithPriority bottom overrun uses the last cell offset" {
	const at = fixedFrames(100.0);
	const scroll: WindowScroll = { offset: 200.0, velocity: 0.0, visibleLength: 100.0, zoomScale: 1.0 };
	assert !shouldRenderWithPriority(10, range(0, 3), at, scroll, 2.0, 2.0);
	assert !shouldRenderWithPriority(10, range(0, 3), at, { ...scroll, offset: 199.75 }, 2.0, 2.0);
	assert shouldRenderWithPriority(10, range(0, 3), at, { ...scroll, offset: 200.25 }, 2.0, 2.0);
	assert shouldRenderWithPriority(10, range(0, 3), at, { ...scroll, offset: 200.25, velocity: -3.0 }, 0.0, 0.0);
}

test "shouldRenderWithPriority top velocity must be strictly below minus two" {
	const at = fixedFrames(100.0);
	const scroll: WindowScroll = { offset: 225.0, velocity: -2.001, visibleLength: 100.0, zoomScale: 1.0 };
	assert shouldRenderWithPriority(10, range(2, 9), at, scroll, 1.0, 0.0);
	assert !shouldRenderWithPriority(10, range(2, 9), at, { ...scroll, velocity: -2.0 }, 1.0, 0.0);
	assert !shouldRenderWithPriority(10, range(2, 9), at, { ...scroll, velocity: -1.999 }, 1.0, 0.0);
	assert !shouldRenderWithPriority(10, range(2, 9), at, { ...scroll, velocity: 3.0 }, 1.0, 0.0);
}

test "shouldRenderWithPriority bottom velocity must be strictly above two" {
	const at = fixedFrames(100.0);
	const scroll: WindowScroll = { offset: 175.0, velocity: 2.001, visibleLength: 100.0, zoomScale: 1.0 };
	assert shouldRenderWithPriority(10, range(0, 3), at, scroll, 0.0, 1.0);
	assert !shouldRenderWithPriority(10, range(0, 3), at, { ...scroll, velocity: 2.0 }, 0.0, 1.0);
	assert !shouldRenderWithPriority(10, range(0, 3), at, { ...scroll, velocity: 1.999 }, 0.0, 1.0);
	assert !shouldRenderWithPriority(10, range(0, 3), at, { ...scroll, velocity: -3.0 }, 0.0, 1.0);
}

test "shouldRenderWithPriority top threshold is half its viewport units" {
	const at = fixedFrames(100.0);
	const scroll: WindowScroll = { offset: 249.75, velocity: -3.0, visibleLength: 100.0, zoomScale: 1.0 };
	assert shouldRenderWithPriority(10, range(2, 9), at, scroll, 1.0, 0.0);
	assert !shouldRenderWithPriority(10, range(2, 9), at, { ...scroll, offset: 250.0 }, 1.0, 0.0);
	assert !shouldRenderWithPriority(10, range(2, 9), at, { ...scroll, offset: 250.25 }, 1.0, 0.0);
	assert shouldRenderWithPriority(10, range(2, 9), at, { ...scroll, offset: 299.75 }, 2.0, 0.0);
	assert !shouldRenderWithPriority(10, range(2, 9), at, { ...scroll, offset: 300.0 }, 2.0, 0.0);
}

test "shouldRenderWithPriority bottom threshold is independent and strictly bounded" {
	const at = fixedFrames(100.0);
	const scroll: WindowScroll = { offset: 100.25, velocity: 3.0, visibleLength: 100.0, zoomScale: 1.0 };
	assert shouldRenderWithPriority(10, range(0, 3), at, scroll, 0.1, 2.0);
	assert !shouldRenderWithPriority(10, range(0, 3), at, { ...scroll, offset: 100.0 }, 0.1, 2.0);
	assert !shouldRenderWithPriority(10, range(0, 3), at, { ...scroll, offset: 99.75 }, 0.1, 2.0);
	assert !shouldRenderWithPriority(10, range(0, 3), at, scroll, 2.0, 0.1);
}

test "shouldRenderWithPriority preserves fractional viewport thresholds" {
	const at = fixedFrames(100.0);
	const top: WindowScroll = { offset: 112.5625, velocity: -3.0, visibleLength: 100.5, zoomScale: 1.0 };
	assert !shouldRenderWithPriority(10, range(1, 9), at, top, 0.25, 0.0);
	assert shouldRenderWithPriority(10, range(1, 9), at, { ...top, offset: 112.562 }, 0.25, 0.0);
	const bottom: WindowScroll = { offset: 186.9375, velocity: 3.0, visibleLength: 100.5, zoomScale: 1.0 };
	assert !shouldRenderWithPriority(10, range(0, 3), at, bottom, 0.0, 0.25);
	assert shouldRenderWithPriority(10, range(0, 3), at, { ...bottom, offset: 186.938 }, 0.0, 0.25);
}

test "shouldRenderWithPriority skips metrics for empty and complete ranges" {
	let calls: int32 = 0;
	const at = (index: int32): CellMetrics => {
		calls += 1;
		return { index, length: 100.0, offset: (index as float64) * 100.0, isMounted: true };
	};
	assert !shouldRenderWithPriority(0, range(0, -1), at, still, 2.0, 2.0);
	assert !shouldRenderWithPriority(10, range(0, 9), at, { ...still, offset: -1000.0, velocity: -3.0 }, 2.0, 2.0);
	assert !shouldRenderWithPriority(10, range(0, 9), at, { ...still, offset: 1000.0, velocity: 3.0 }, 2.0, 2.0);
	assert calls === 0;
}

test "shouldRenderWithPriority only reads an eligible edge" {
	let seen = "";
	const at = (index: int32): CellMetrics => {
		seen += `${index},`;
		return { index, length: 100.0, offset: (index as float64) * 100.0, isMounted: true };
	};
	const scroll: WindowScroll = { offset: 200.0, velocity: 0.0, visibleLength: 100.0, zoomScale: 1.0 };
	assert !shouldRenderWithPriority(10, range(2, 9), at, scroll, 2.0, 2.0);
	assert seen === "2,", seen;
	seen = "";
	assert !shouldRenderWithPriority(10, range(0, 3), at, scroll, 2.0, 2.0);
	assert seen === "3,", seen;
	seen = "";
	assert !shouldRenderWithPriority(10, range(0, -1), at, scroll, 2.0, 2.0);
	assert seen === "", seen;
}

test "shouldRenderWithPriority short circuits top priority but checks bottom otherwise" {
	let seen = "";
	const at = (index: int32): CellMetrics => {
		seen += `${index},`;
		return { index, length: 100.0, offset: (index as float64) * 100.0, isMounted: true };
	};
	const scroll: WindowScroll = { offset: 199.75, velocity: 0.0, visibleLength: 100.0, zoomScale: 1.0 };
	assert shouldRenderWithPriority(10, range(2, 3), at, scroll, 2.0, 2.0);
	assert seen === "2,", seen;
	seen = "";
	assert shouldRenderWithPriority(10, range(2, 3), at, { ...scroll, offset: 200.25 }, 2.0, 2.0);
	assert seen === "2,3,", seen;
	seen = "";
	assert !shouldRenderWithPriority(10, range(2, 3), at, { ...scroll, offset: 200.0 }, 2.0, 2.0);
	assert seen === "2,3,", seen;
}
