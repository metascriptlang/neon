import { CellRenderMask } from "../../../src/components/list/cellRenderMask";

// Ported from React Native packages/virtualized-lists/Lists/__tests__/CellRenderMask-test.js;
// each test keeps the RN case's name and its expected regions, written s(first,last) for a
// spacer and c(first,last) for rendered cells.

function regions(mask: CellRenderMask): string {
	let out = "";
	for (const r of mask.enumerateRegions()) {
		out += `${r.isSpacer ? "s" : "c"}(${r.first},${r.last})`;
	}
	return out;
}

function caught(fn: () => void): string {
	try {
		fn();
	} catch (e) {
		return e.toString();
	}
	return "";
}

test "throws when constructed with invalid size" {
	assert caught((): void => { new CellRenderMask(-1); }).includes("non-negative"), "a negative size fails loud";
}

test "allows creation of empty mask" {
	assert regions(new CellRenderMask(0)) === "", regions(new CellRenderMask(0));
}

test "allows creation of single-cell mask" {
	assert regions(new CellRenderMask(1)) === "s(0,0)", regions(new CellRenderMask(1));
}

test "throws when adding invalid cell ranges" {
	const mask = new CellRenderMask(5);
	assert caught((): void => { mask.addCells({ first: -2, last: -1 }); }).includes("invalid cell range"), "-2..-1";
	assert caught((): void => { mask.addCells({ first: -2, last: 0 }); }).includes("invalid cell range"), "-2..0";
	assert caught((): void => { mask.addCells({ first: 0, last: 5 }); }).includes("invalid cell range"), "0..5";
	assert caught((): void => { mask.addCells({ first: 6, last: 7 }); }).includes("invalid cell range"), "6..7";
}

test "allows adding single cell at beginning" {
	const mask = new CellRenderMask(5);
	mask.addCells({ first: 0, last: 0 });
	assert regions(mask) === "c(0,0)s(1,4)", regions(mask);
}

test "allows adding single cell at end" {
	const mask = new CellRenderMask(5);
	mask.addCells({ first: 4, last: 4 });
	assert regions(mask) === "s(0,3)c(4,4)", regions(mask);
}

test "allows adding single cell in middle" {
	const mask = new CellRenderMask(5);
	mask.addCells({ first: 2, last: 2 });
	assert regions(mask) === "s(0,1)c(2,2)s(3,4)", regions(mask);
}

test "allows marking entire cell range" {
	const mask = new CellRenderMask(5);
	mask.addCells({ first: 0, last: 4 });
	assert regions(mask) === "c(0,4)", regions(mask);
}

test "allows adding empty cell range" {
	const mask = new CellRenderMask(5);
	mask.addCells({ first: 0, last: -1 });
	assert regions(mask) === "s(0,4)", regions(mask);
}

test "correctly replaces fragmented cell ranges" {
	const mask = new CellRenderMask(10);
	mask.addCells({ first: 3, last: 3 });
	mask.addCells({ first: 5, last: 7 });
	assert regions(mask) === "s(0,2)c(3,3)s(4,4)c(5,7)s(8,9)", regions(mask);
	mask.addCells({ first: 3, last: 7 });
	assert regions(mask) === "s(0,2)c(3,7)s(8,9)", regions(mask);
}

test "left-expands region" {
	const mask = new CellRenderMask(5);
	mask.addCells({ first: 3, last: 3 });
	assert regions(mask) === "s(0,2)c(3,3)s(4,4)", regions(mask);
	mask.addCells({ first: 2, last: 3 });
	assert regions(mask) === "s(0,1)c(2,3)s(4,4)", regions(mask);
}

test "right-expands region" {
	const mask = new CellRenderMask(5);
	mask.addCells({ first: 3, last: 3 });
	mask.addCells({ first: 3, last: 4 });
	assert regions(mask) === "s(0,2)c(3,4)", regions(mask);
}

test "left+right expands region" {
	const mask = new CellRenderMask(5);
	mask.addCells({ first: 3, last: 3 });
	mask.addCells({ first: 2, last: 4 });
	assert regions(mask) === "s(0,1)c(2,4)", regions(mask);
}

test "does nothing when adding existing cells" {
	const mask = new CellRenderMask(5);
	mask.addCells({ first: 2, last: 3 });
	assert regions(mask) === "s(0,1)c(2,3)s(4,4)", regions(mask);
	mask.addCells({ first: 3, last: 3 });
	assert regions(mask) === "s(0,1)c(2,3)s(4,4)", regions(mask);
}

test "equals compares the cell count and every region" {
	const a = new CellRenderMask(5);
	const b = new CellRenderMask(5);
	a.addCells({ first: 1, last: 2 });
	assert !a.equals(b), "different regions";
	b.addCells({ first: 1, last: 2 });
	assert a.equals(b), "same regions";
	assert !a.equals(new CellRenderMask(6)), "different cell counts";
}
