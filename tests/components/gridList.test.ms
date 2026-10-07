import { createRoot } from "../../src/core/owner";
import { createSignal, Accessor } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { neonEvent } from "../../src/render/event";
import { NeonNode } from "../../src/render/node";
import { HostNode, MockNode, mockNode, mockHost, render, fireEventWith } from "../../src/render/host";
import { Text, View } from "../../src/components/primitives";
import { GridList, GridRenderItemInfo, MasonryList, MasonryRenderItemInfo, maxExtentColumns, shortestColumn } from "../../src/components/gridList";

interface Photo {
	id: string;
	height: number;
}

function photos(heights: number[]): Photo[] {
	const out: Photo[] = [];
	for (let i = 0; i < heights.length; i += 1) { out.push({ id: "p" + i.toString(), height: heights[i] }); }
	return out;
}

function labels(n: MockNode, out: string[]): string[] {
	if (n.tag === "" && n.text.startsWith("p")) { out.push(n.text); }
	for (const k of n.children) { labels(k, out); }
	return out;
}

function widthOf(n: MockNode): string {
	const s = n.style;
	if (s === null || s.width === null) { return "none"; }
	return `${s.width}`;
}

function cellOf(root: MockNode, label: string): MockNode | null {
	if (root.tag === "" && root.text === label) { return root; }
	for (const k of root.children) {
		const hit = cellOf(k, label);
		if (hit !== null) { return hit; }
	}
	return null;
}

function layout(n: MockNode, width: number): void {
	const e = neonEvent("layout");
	e.width = width;
	e.height = 600;
	fireEventWith(n, "onLayout", e);
}

test "maxItemWidth derives the column count and the item width like Flutter's max-extent delegate" {
	const a = maxExtentColumns(400, 150, 0);
	assert a.columns === 3, "3 columns: " + a.columns.toString();
	assert Math.abs(a.itemWidth - 133.333) < 0.01, "item width " + a.itemWidth.toString();
	const b = maxExtentColumns(400, 150, 10);
	assert b.columns === 3 && Math.abs(b.itemWidth - 126.667) < 0.01, "with spacing " + b.itemWidth.toString();
	const c = maxExtentColumns(100, 150, 0);
	assert c.columns === 1 && c.itemWidth === 100, "never fewer than one column";
}

test "a GridList waits for its width, then lays out max-extent columns and re-derives them when the width changes" {
	const root = mockNode("root");
	createRoot((): void => {
		render(element(<GridList data={photos([1, 1, 1, 1, 1, 1, 1])} maxItemWidth={150}
			renderItem={(info: GridRenderItemInfo<Photo>): NeonNode => <Text>{info.item.id}</Text>} />), mockHost(), root as unknown as HostNode);
	});
	const outer = root.children[0];
	assert labels(root, []).length === 0, "nothing before the width is known";
	layout(outer, 400);
	assert labels(root, []).join(",") === "p0,p1,p2,p3,p4,p5,p6", "every item: " + labels(root, []).join(",");
	const cell = (cellOf(root, "p0") as MockNode).parent as MockNode;
	assert widthOf((cell.parent as MockNode)) === "133.33333333333334" || widthOf(cell.parent as MockNode).startsWith("133.33"), "cell width: " + widthOf(cell.parent as MockNode);
	const row = ((cell.parent as MockNode).parent as MockNode);
	let cells = 0;
	for (const k of row.children) { if (k.tag !== "") { cells += 1; } }
	assert cells === 3, "three cells in the first row: " + cells.toString();
	layout(outer, 700);
	const wide = ((((cellOf(root, "p0") as MockNode).parent as MockNode).parent as MockNode).parent as MockNode);
	let wideCells = 0;
	for (const k of wide.children) { if (k.tag !== "") { wideCells += 1; } }
	assert wideCells === 5, "five columns at 700: " + wideCells.toString();
}

test "the masonry layout puts each item in the shortest column" {
	assert shortestColumn([100, 50, 80]) === 1, "the shortest";
	assert shortestColumn([10, 10]) === 0, "ties go left";
	const root = mockNode("root");
	createRoot((): void => {
		render(element(<MasonryList data={photos([100, 50, 50, 50, 100])} numColumns={2}
			getItemHeight={(item: Photo, index: number, columnWidth: number): number => item.height}
			renderItem={(info: MasonryRenderItemInfo<Photo>): NeonNode => <Text>{info.item.id}</Text>} />), mockHost(), root as unknown as HostNode);
	});
	layout(root.children[0], 400);
	const columnOf = (label: string): MockNode => {
		let at = cellOf(root, label) as MockNode;
		while (at.parent !== null && !(at.style !== null && at.style.width === 200)) { at = at.parent as MockNode; }
		return at;
	};
	assert columnOf("p0") === columnOf("p3"), "p0 and p3 share the left column";
	assert columnOf("p1") === columnOf("p2") && columnOf("p2") === columnOf("p4"), "p1, p2, p4 fill the right";
	assert columnOf("p0") !== columnOf("p1"), "two columns";
	assert labels(columnOf("p1"), []).join(",") === "p1,p2,p4", "right column order: " + labels(columnOf("p1"), []).join(",");
}
