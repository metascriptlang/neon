import {
	CellMetrics, CellRange, OffsetHit, WindowScroll, newRangeCount, elementsThatOverlapOffsets, computeWindowedRenderLimits,
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
