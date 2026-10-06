import { onCleanup } from "../../src/core/cleanup";
import { sleepAsync } from "std/core/promise";
import { createSignal } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { NeonEvent, neonEvent } from "../../src/render/event";
import { NeonNode } from "../../src/render/hostTypes";
import { HostNode, MockNode, mockNode, mockHost, render, fireEventWith } from "../../src/render/host";
import { Text } from "../../src/components/primitives";
import { FlatList, FlatListHandle, ItemLayout, ListRenderItemInfo, EndReachedInfo, ScrollToIndexFailedInfo } from "../../src/components/flatList";

// Cases named after React Native's are ported from
// packages/virtualized-lists/Lists/__tests__/VirtualizedList-test.js; their expected content is
// RN's snapshot after every batch ran, written c<first>-<last> for rendered rows and sp<size> for
// a spacer.

interface Item {
	id: string;
	n: number;
}

function items(count: number): Item[] {
	const out: Item[] = [];
	for (let i = 0; i < count; i += 1) { out.push({ id: "k" + i.toString(), n: i }); }
	return out;
}

function tall10(data: Item[], index: number): ItemLayout {
	return { length: 10, offset: 10 * index, index };
}

function tall40(data: Item[], index: number): ItemLayout {
	return { length: 40, offset: 40 * index, index };
}

function tall50(data: Item[], index: number): ItemLayout {
	return { length: 50, offset: 50 * index, index };
}

function row(info: ListRenderItemInfo<Item>): NeonNode {
	return element(<Text>{"row " + info.item.n.toString()}</Text>);
}


function scrollView(root: MockNode): MockNode {
	return root.children[0];
}

function content(root: MockNode): MockNode {
	return root.children[0].children[0];
}

function rowLabel(k: MockNode): MockNode | null {
	if (k.tag === "text") { return k; }
	if (k.children.length > 0 && k.children[0].tag === "text") { return k.children[0]; }
	return null;
}

function measureRows(root: MockNode, length: number): void {
	for (const k of content(root).children) {
		if (k.tag === "" || k.tag === "text" || rowLabel(k) === null) { continue; }
		const n: number = parseInt((rowLabel(k) as MockNode).children[0].text.slice(4)) as number;
		const e = neonEvent("layout");
		e.y = n * length;
		e.width = 10;
		e.height = length;
		fireEventWith(k, "onLayout", e);
	}
}

function shape(root: MockNode): string {
	const parts: string[] = [];
	let runFirst: number = -1;
	let runLast: number = -1;
	const flush = (): void => {
		if (runFirst >= 0) { parts.push(runFirst === runLast ? `c${runFirst}` : `c${runFirst}-${runLast}`); }
		runFirst = -1;
	};
	for (const k of content(root).children) {
		if (k.tag === "") { continue; }
		const label = rowLabel(k);
		if (label !== null) {
			const n: number = parseInt((label as MockNode).children[0].text.slice(4)) as number;
			if (runFirst >= 0 && n === runLast + 1) {
				runLast = n;
			} else {
				flush();
				runFirst = n;
				runLast = n;
			}
		} else {
			flush();
			parts.push(`sp${k.style!.height as number}`);
		}
	}
	flush();
	return parts.join(" ");
}

function layoutEvent(height: number): NeonEvent {
	const e = neonEvent("layout");
	e.width = 10;
	e.height = height;
	return e;
}

function scrollEvent(y: number, height: number, contentHeight: number): NeonEvent {
	const e = neonEvent("scroll");
	e.y = y;
	e.width = 10;
	e.height = height;
	e.contentWidth = 10;
	e.contentHeight = contentHeight;
	return e;
}

function layOut(root: MockNode, viewport: number, contentHeight: number): void {
	fireEventWith(scrollView(root), "onLayout", layoutEvent(viewport));
	fireEventWith(content(root), "onLayout", layoutEvent(contentHeight));
}

async function performAllBatches(root: MockNode): Promise<void> {
	let seen = "";
	let rounds = 0;
	while (shape(root) !== seen && rounds < 100) {
		seen = shape(root);
		rounds += 1;
		await sleepAsync(20);
	}
}

function caught(fn: () => void): string {
	try {
		fn();
	} catch (e) {
		return e.toString();
	}
	return "";
}

test "renders simple list" {
	const root: MockNode = mockNode("root");
	render(element(<FlatList data={items(3)} getItemLayout={tall10} renderItem={row} />), mockHost(), root as unknown as HostNode);
	assert shape(root) === "c0-2", shape(root);
}

test "renders empty list" {
	const root: MockNode = mockNode("root");
	render(element(<FlatList data={items(0)} getItemLayout={tall10} renderItem={row} />), mockHost(), root as unknown as HostNode);
	assert shape(root) === "", shape(root);
}

test "initially renders nothing when initialNumToRender is 0" {
	const root: MockNode = mockNode("root");
	render(element(<FlatList data={items(10)} getItemLayout={tall10} initialNumToRender={0} renderItem={row} />), mockHost(), root as unknown as HostNode);
	assert shape(root) === "sp100", shape(root);
}

test "before its viewport is known FlatList mounts initialNumToRender rows" {
	const root: MockNode = mockNode("root");
	render(element(<FlatList data={items(10000)} getItemLayout={tall50} renderItem={row} />), mockHost(), root as unknown as HostNode);
	assert shape(root) === "c0-9 sp499500", shape(root);
}

test "renders windowSize derived region at top" {
	const root: MockNode = mockNode("root");
	render(element(<FlatList data={items(10)} getItemLayout={tall10} initialNumToRender={1} maxToRenderPerBatch={1} windowSize={3} updateCellsBatchingPeriod={0} renderItem={row} />), mockHost(), root as unknown as HostNode);
	layOut(root, 20, 100);
	await performAllBatches(root);
	assert shape(root) === "c0-3 sp60", shape(root);
}

test "renders windowSize derived region in middle" {
	const root: MockNode = mockNode("root");
	render(element(<FlatList data={items(10)} getItemLayout={tall10} initialNumToRender={1} maxToRenderPerBatch={1} windowSize={3} updateCellsBatchingPeriod={0} renderItem={row} />), mockHost(), root as unknown as HostNode);
	layOut(root, 20, 100);
	await performAllBatches(root);
	fireEventWith(scrollView(root), "onScroll", scrollEvent(50, 20, 100));
	await performAllBatches(root);
	assert shape(root) === "c0 sp10 c2-8 sp10", shape(root);
}

test "renders windowSize derived region at bottom" {
	const root: MockNode = mockNode("root");
	render(element(<FlatList data={items(10)} getItemLayout={tall10} initialNumToRender={1} maxToRenderPerBatch={1} windowSize={3} updateCellsBatchingPeriod={0} renderItem={row} />), mockHost(), root as unknown as HostNode);
	layOut(root, 20, 100);
	await performAllBatches(root);
	fireEventWith(scrollView(root), "onScroll", scrollEvent(80, 20, 100));
	await performAllBatches(root);
	assert shape(root) === "c0 sp40 c5-9", shape(root);
}

test "retains intitial render if initialScrollIndex == 0" {
	const root: MockNode = mockNode("root");
	render(element(<FlatList data={items(20)} getItemLayout={tall10} initialNumToRender={5} initialScrollIndex={0} windowSize={1} updateCellsBatchingPeriod={0} renderItem={row} />), mockHost(), root as unknown as HostNode);
	layOut(root, 50, 200);
	await performAllBatches(root);
	fireEventWith(scrollView(root), "onScroll", scrollEvent(150, 50, 200));
	await performAllBatches(root);
	assert shape(root) === "c0-4 sp90 c14-19", "the first initialNumToRender rows stay for scroll-to-top: " + shape(root);
}

test "scrolling mounts rows that enter the window, unmounts rows that leave, and keeps the rest" {
	const root: MockNode = mockNode("root");
	let mounts = 0;
	let unmounts = 0;
	render(element(<FlatList data={items(10000)} getItemLayout={tall50} updateCellsBatchingPeriod={0}
		renderItem={(info: ListRenderItemInfo<Item>): NeonNode => {
			mounts = mounts + 1;
			onCleanup((): void => { unmounts = unmounts + 1; });
			return row(info);
		}} />), mockHost(), root as unknown as HostNode);
	layOut(root, 500, 500000);
	await performAllBatches(root);
	assert shape(root) === "c0-109 sp494500", shape(root);
	assert mounts === 110 && unmounts === 0, `after layout ${mounts} ${unmounts}`;
	fireEventWith(scrollView(root), "onScroll", scrollEvent(1000, 500, 500000));
	await performAllBatches(root);
	assert mounts === 130 && unmounts === 0, "rows 110..129 mount, rows 0..109 stay: " + `${mounts} ${unmounts}`;
	fireEventWith(scrollView(root), "onScroll", scrollEvent(20000, 500, 500000));
	await performAllBatches(root);
	assert shape(root) === "c0-9 sp14450 c299-509 sp474500", shape(root);
	assert unmounts === 120, "rows 10..129 unmounted, the first ten stay: " + unmounts.toString();
}

test "a row that leaves the window and comes back is mounted again for the same item" {
	const root: MockNode = mockNode("root");
	let mounts = 0;
	render(element(<FlatList data={items(10000)} getItemLayout={tall50} updateCellsBatchingPeriod={0}
		renderItem={(info: ListRenderItemInfo<Item>): NeonNode => {
			if (info.item.id === "k200") { mounts = mounts + 1; }
			return row(info);
		}} />), mockHost(), root as unknown as HostNode);
	layOut(root, 500, 500000);
	await performAllBatches(root);
	fireEventWith(scrollView(root), "onScroll", scrollEvent(10000, 500, 500000));
	await performAllBatches(root);
	fireEventWith(scrollView(root), "onScroll", scrollEvent(0, 500, 500000));
	await performAllBatches(root);
	fireEventWith(scrollView(root), "onScroll", scrollEvent(10000, 500, 500000));
	await performAllBatches(root);
	assert mounts === 2, "row k200 mounted, left with its state and came back fresh: " + mounts.toString();
}

test "rows follow their items when the data is reordered or grows, and their index follows too" {
	const root: MockNode = mockNode("root");
	const a: Item = { id: "a", n: 0 };
	const b: Item = { id: "b", n: 1 };
	const z: Item = { id: "z", n: 9 };
	const [data, setData] = createSignal<Item[]>([a, b]);
	let mounts = 0;
	render(element(<FlatList data={data()} getItemLayout={tall10}
		renderItem={(info: ListRenderItemInfo<Item>): NeonNode => {
			mounts = mounts + 1;
			return <Text>{info.item.id + "@" + info.index.toString()}</Text>;
		}} />), mockHost(), root as unknown as HostNode);
	const texts = (): string => {
		let out = "";
		for (const k of content(root).children) { if (k.tag === "text") { out += k.children[0].text + ";"; } }
		return out;
	};
	assert texts() === "a@0;b@1;" && mounts === 2, texts();
	setData([z, a, b]);
	assert texts() === "z@0;a@1;b@2;", "kept rows read their new index: " + texts();
	assert mounts === 3, "only z mounts: " + mounts.toString();
	setData([b, a]);
	assert texts() === "b@0;a@1;", texts();
	assert mounts === 3, "a reorder moves rows, it does not rebuild them: " + mounts.toString();
}

test "the same item twice in the rendered rows fails loud" {
	const root: MockNode = mockNode("root");
	const a: Item = { id: "a", n: 0 };
	const msg = caught((): void => {
		render(element(<FlatList data={[a, a]} getItemLayout={tall10} renderItem={row} />), mockHost(), root as unknown as HostNode);
	});
	assert msg.includes("FlatList") && msg.includes("rows 0 and 1"), "names the list and both rows: " + msg;
}

test "calls onEndReached when near the end" {
	const root: MockNode = mockNode("root");
	let ends = 0;
	render(element(<FlatList data={items(40)} getItemLayout={tall40} initialNumToRender={10} onEndReachedThreshold={1} windowSize={10} updateCellsBatchingPeriod={0}
		onEndReached={(info: EndReachedInfo): void => { ends = ends + 1; }} renderItem={row} />), mockHost(), root as unknown as HostNode);
	layOut(root, 600, 1600);
	await performAllBatches(root);
	assert ends === 0, "not at the top";
	fireEventWith(scrollView(root), "onScroll", scrollEvent(40, 600, 1600));
	await performAllBatches(root);
	assert ends === 0, "not after a small scroll";
	fireEventWith(scrollView(root), "onScroll", scrollEvent(1600, 600, 1600));
	await performAllBatches(root);
	assert ends === 1, "at the end: " + ends.toString();
}

test "onEndReached without a threshold fires within 2 px of the end, React Native's default" {
	const root: MockNode = mockNode("root");
	let ends = "";
	render(element(<FlatList data={items(100)} getItemLayout={tall50} updateCellsBatchingPeriod={0}
		onEndReached={(info: EndReachedInfo): void => { ends = ends + info.distanceFromEnd.toString() + ";"; }}
		renderItem={row} />), mockHost(), root as unknown as HostNode);
	layOut(root, 500, 5000);
	await performAllBatches(root);
	fireEventWith(scrollView(root), "onScroll", scrollEvent(3600, 500, 5000));
	assert ends === "", "900 from the end is outside the 2 px default: " + ends;
	fireEventWith(scrollView(root), "onScroll", scrollEvent(4498, 500, 5000));
	assert ends === "2;", "exactly 2 px from the end is inside: " + ends;
	fireEventWith(scrollView(root), "onScroll", scrollEvent(3000, 500, 5000));
	fireEventWith(scrollView(root), "onScroll", scrollEvent(4499.9995, 500, 5000));
	assert ends === "2;0;", "leaving the threshold re-arms it, and a distance under 0.001 reads 0: " + ends;
}

test "the ref's handle scrolls to an index, an offset and the end" {
	const root: MockNode = mockNode("root");
	const handles: FlatListHandle[] = [];
	render(element(<FlatList data={items(100)} getItemLayout={tall50}
		ref={(h: FlatListHandle): void => { handles.push(h); }} renderItem={row} />), mockHost(), root as unknown as HostNode);
	const sv = scrollView(root);
	layOut(root, 500, 5000);
	handles[0].scrollToIndex({ index: 40 });
	assert `${sv.scrollY} ${sv.scrollAnimated}` === "2000 true", "index 40: " + `${sv.scrollY} ${sv.scrollAnimated}`;
	handles[0].scrollToIndex({ index: 40, viewPosition: 0.5, animated: false });
	assert `${sv.scrollY} ${sv.scrollAnimated}` === "1775 false", "centred: " + `${sv.scrollY} ${sv.scrollAnimated}`;
	handles[0].scrollToIndex({ index: 0, viewPosition: 0.5, viewOffset: -20, animated: false });
	assert sv.scrollY === 20, "clamped at 0 before viewOffset applies: " + sv.scrollY.toString();
	handles[0].scrollToOffset({ offset: 123 });
	assert sv.scrollY === 123, "offset " + sv.scrollY.toString();
	handles[0].scrollToEnd({});
	assert sv.scrollY === 4500, "end " + sv.scrollY.toString();
}

test "throws if using scrollToIndex with index less than 0" {
	const root: MockNode = mockNode("root");
	const handles: FlatListHandle[] = [];
	render(element(<FlatList data={items(3)} getItemLayout={tall10} ref={(h: FlatListHandle): void => { handles.push(h); }} renderItem={row} />), mockHost(), root as unknown as HostNode);
	const msg = caught((): void => { handles[0].scrollToIndex({ index: -1 }); });
	assert msg.includes("scrollToIndex out of range: requested index -1 but minimum is 0"), msg;
}

test "throws if using scrollToIndex when item length is less than 1" {
	const root: MockNode = mockNode("root");
	const handles: FlatListHandle[] = [];
	render(element(<FlatList data={items(0)} getItemLayout={tall10} ref={(h: FlatListHandle): void => { handles.push(h); }} renderItem={row} />), mockHost(), root as unknown as HostNode);
	const msg = caught((): void => { handles[0].scrollToIndex({ index: 0 }); });
	assert msg.includes("scrollToIndex out of range: item length 0 but minimum is 1"), msg;
}

test "throws if using scrollToIndex when requested index is bigger than or equal to item length" {
	const root: MockNode = mockNode("root");
	const handles: FlatListHandle[] = [];
	render(element(<FlatList data={items(3)} getItemLayout={tall10} ref={(h: FlatListHandle): void => { handles.push(h); }} renderItem={row} />), mockHost(), root as unknown as HostNode);
	const msg = caught((): void => { handles[0].scrollToIndex({ index: 3 }); });
	assert msg.includes("scrollToIndex out of range: requested index 3 is out of 0 to 2"), msg;
}

test "scrollToEnd works with null list" {
	const root: MockNode = mockNode("root");
	const handles: FlatListHandle[] = [];
	render(element(<FlatList data={items(0)} getItemLayout={tall10} ref={(h: FlatListHandle): void => { handles.push(h); }} renderItem={row} />), mockHost(), root as unknown as HostNode);
	assert caught((): void => { handles[0].scrollToEnd({}); }) === "", "no throw on an empty list";
}

test "renders a zero-height tail spacer on initial render if getItemLayout not defined" {
	const root: MockNode = mockNode("root");
	render(element(<FlatList data={items(10)} initialNumToRender={3} renderItem={row} />), mockHost(), root as unknown as HostNode);
	assert shape(root) === "c0-2 sp0", shape(root);
}

test "renders zero-height tail spacer on batch render if cells not yet measured and getItemLayout not defined" {
	const root: MockNode = mockNode("root");
	render(element(<FlatList data={items(10)} initialNumToRender={3} maxToRenderPerBatch={1} windowSize={1} updateCellsBatchingPeriod={200} renderItem={row} />), mockHost(), root as unknown as HostNode);
	layOut(root, 50, 200);
	await sleepAsync(300);
	assert shape(root) === "c0-2 sp0" || shape(root) === "c0-3 sp0", "a zero-height tail spacer after at most one batch: " + shape(root);
}

test "a tail spacer without getItemLayout reaches the highest measured row, measured rows that left the window included" {
	const root: MockNode = mockNode("root");
	render(element(<FlatList data={items(10)} initialNumToRender={3} windowSize={1} updateCellsBatchingPeriod={0} renderItem={row} />), mockHost(), root as unknown as HostNode);
	layOut(root, 30, 100);
	measureRows(root, 10);
	await performAllBatches(root);
	fireEventWith(scrollView(root), "onScroll", scrollEvent(50, 30, 100));
	await performAllBatches(root);
	measureRows(root, 10);
	await performAllBatches(root);
	fireEventWith(scrollView(root), "onScroll", scrollEvent(0, 30, 100));
	await performAllBatches(root);
	assert shape(root) === "c0-2 sp50", "rows 3..7, up to the measured row 7, not 8 and 9: " + shape(root);
}

test "does not call onEndReached when onContentSizeChange happens after onLayout" {
	const root: MockNode = mockNode("root");
	let ends = 0;
	render(element(<FlatList data={items(20)} initialNumToRender={10} onEndReachedThreshold={2} windowSize={21} updateCellsBatchingPeriod={0}
		onEndReached={(info: EndReachedInfo): void => { ends = ends + 1; }} renderItem={row} />), mockHost(), root as unknown as HostNode);
	fireEventWith(scrollView(root), "onLayout", layoutEvent(600));
	fireEventWith(content(root), "onLayout", layoutEvent(400));
	fireEventWith(content(root), "onLayout", layoutEvent(800));
	await performAllBatches(root);
	assert ends === 0, "React Native #16067: not before the rows are measured";
	measureRows(root, 40);
	fireEventWith(scrollView(root), "onScroll", scrollEvent(400, 600, 800));
	await performAllBatches(root);
	assert ends === 1, "at the end once measured: " + ends.toString();
}

test "scrollToIndex past the measured rows without getItemLayout calls onScrollToIndexFailed instead of scrolling" {
	const root: MockNode = mockNode("root");
	const handles: FlatListHandle[] = [];
	let failed = "";
	render(element(<FlatList data={items(100)} updateCellsBatchingPeriod={0}
		onScrollToIndexFailed={(info: ScrollToIndexFailedInfo): void => { failed = `${info.index} ${info.highestMeasuredFrameIndex} ${info.averageItemLength}`; }}
		ref={(h: FlatListHandle): void => { handles.push(h); }} renderItem={row} />), mockHost(), root as unknown as HostNode);
	layOut(root, 50, 100);
	measureRows(root, 10);
	handles[0].scrollToIndex({ index: 5, animated: false });
	assert scrollView(root).scrollY === 50 && failed === "", "a measured row scrolls: " + scrollView(root).scrollY.toString();
	handles[0].scrollToIndex({ index: 50, animated: false });
	assert failed === "50 9 10" && scrollView(root).scrollY === 50, "an unmeasured row reports and stays: " + failed;
}

test "scrollToIndex past the measured rows without getItemLayout or onScrollToIndexFailed fails loud" {
	const root: MockNode = mockNode("root");
	const handles: FlatListHandle[] = [];
	render(element(<FlatList data={items(100)} ref={(h: FlatListHandle): void => { handles.push(h); }} renderItem={row} />), mockHost(), root as unknown as HostNode);
	const msg = caught((): void => { handles[0].scrollToIndex({ index: 50 }); });
	assert msg.includes("scrollToIndex should be used in conjunction with getItemLayout or onScrollToIndexFailed"), msg;
}

test "onLayout reaches the author before the window moves, as React Native orders it" {
	const root: MockNode = mockNode("root");
	let seen = "";
	render(element(<FlatList data={items(10000)} getItemLayout={tall50} updateCellsBatchingPeriod={0}
		onLayout={(e: NeonEvent): void => { seen = `${e.height} ${shape(root)}`; }} renderItem={row} />), mockHost(), root as unknown as HostNode);
	fireEventWith(content(root), "onLayout", layoutEvent(500000));
	fireEventWith(scrollView(root), "onLayout", layoutEvent(500));
	assert seen === "500 c0-9 sp499500", "VirtualizedList._onLayout calls props.onLayout, then schedules the window: " + seen;
	assert shape(root) === "c0-19 sp499000", "then the window opens by one batch at once, the viewport reaching past the rendered rows: " + shape(root);
	await performAllBatches(root);
	assert shape(root) === "c0-109 sp494500", "and the later batches fill it: " + shape(root);
}

test "expands render area by maxToRenderPerBatch on tick" {
	const root: MockNode = mockNode("root");
	render(element(<FlatList data={items(20)} getItemLayout={tall10} initialNumToRender={5} maxToRenderPerBatch={2} updateCellsBatchingPeriod={200} renderItem={row} />), mockHost(), root as unknown as HostNode);
	layOut(root, 50, 200);
	assert shape(root) === "c0-4 sp150", "no batch before the period: " + shape(root);
	await sleepAsync(300);
	assert shape(root) === "c0-6 sp130", "one tick renders maxToRenderPerBatch more: " + shape(root);
}

test "a scroll past the rendered rows renders the visible rows at once and the rest of the window in batches" {
	const root: MockNode = mockNode("root");
	render(element(<FlatList data={items(10000)} getItemLayout={tall50} updateCellsBatchingPeriod={0} renderItem={row} />), mockHost(), root as unknown as HostNode);
	layOut(root, 500, 500000);
	await performAllBatches(root);
	fireEventWith(scrollView(root), "onScroll", scrollEvent(100000, 500, 500000));
	assert shape(root) === "c0-9 sp94450 c1899-2009 sp399500", "the viewport and the window behind it, synchronously: " + shape(root);
	await performAllBatches(root);
	assert shape(root) === "c0-9 sp94450 c1899-2109 sp394500", "then its window: " + shape(root);
}

test "a scroll inside the rendered rows waits for the batching period" {
	const root: MockNode = mockNode("root");
	render(element(<FlatList data={items(10000)} getItemLayout={tall50} updateCellsBatchingPeriod={100} renderItem={row} />), mockHost(), root as unknown as HostNode);
	layOut(root, 500, 500000);
	await sleepAsync(1500);
	assert shape(root) === "c0-109 sp494500", shape(root);
	fireEventWith(scrollView(root), "onScroll", scrollEvent(1000, 500, 500000));
	assert shape(root) === "c0-109 sp494500", "nothing at once: " + shape(root);
	await sleepAsync(150);
	assert shape(root) === "c0-119 sp494000", "one batch after the period: " + shape(root);
}

test "unmounting cancels the pending batch" {
	const root: MockNode = mockNode("root");
	let mounts = 0;
	const dispose = render(element(<FlatList data={items(10000)} getItemLayout={tall50} updateCellsBatchingPeriod={100}
		renderItem={(info: ListRenderItemInfo<Item>): NeonNode => {
			mounts = mounts + 1;
			return row(info);
		}} />), mockHost(), root as unknown as HostNode);
	layOut(root, 500, 500000);
	const before = mounts;
	dispose();
	await sleepAsync(250);
	assert mounts === before, `no row mounts after unmount: ${before} then ${mounts}`;
}

test "horizontal FlatList uses width and x for its window and every imperative offset" {
	const root = mockNode("root");
	const handles: FlatListHandle[] = [];
	render(element(<FlatList data={items(100)} getItemLayout={tall50} horizontal={true}
		ref={(h: FlatListHandle): void => { handles.push(h); }} renderItem={row} />), mockHost(), root as unknown as HostNode);
	const viewport = layoutEvent(80);
	viewport.width = 200;
	fireEventWith(scrollView(root), "onLayout", viewport);
	const dimensions = layoutEvent(80);
	dimensions.width = 5000;
	fireEventWith(content(root), "onLayout", dimensions);
	handles[0].scrollToIndex({ index: 40, viewPosition: 0.5, animated: false });
	assert scrollView(root).scrollX === 1925 && scrollView(root).scrollY === 0, "centres on the horizontal viewport";
	handles[0].scrollToOffset({ offset: 123, animated: false });
	assert scrollView(root).scrollX === 123 && scrollView(root).scrollY === 0, "offset moves only x";
	handles[0].scrollToEnd({ animated: false });
	assert scrollView(root).scrollX === 4800 && scrollView(root).scrollY === 0, "end subtracts viewport width";
}

function heights1to10(data: Item[], index: number): ItemLayout {
	return { length: index + 1, offset: index * (index + 1) / 2, index };
}

function scrolledTo(root: MockNode): string {
	return `${scrollView(root).scrollY} ${scrollView(root).scrollAnimated}`;
}

test "gracefully handles negative initialScrollIndex" {
	const root: MockNode = mockNode("root");
	render(element(<FlatList data={items(10)} getItemLayout={tall10} initialScrollIndex={-1} initialNumToRender={4} updateCellsBatchingPeriod={0} renderItem={row} />), mockHost(), root as unknown as HostNode);
	layOut(root, 50, 100);
	await performAllBatches(root);
	assert shape(root) === "c0-9", shape(root);
}

test "gracefully handles too large initialScrollIndex" {
	const root: MockNode = mockNode("root");
	render(element(<FlatList data={items(10)} getItemLayout={tall10} initialScrollIndex={15} initialNumToRender={4} updateCellsBatchingPeriod={0} renderItem={row} />), mockHost(), root as unknown as HostNode);
	layOut(root, 50, 100);
	await performAllBatches(root);
	assert scrolledTo(root) === "50 false", "scrollToEnd without animation: " + scrolledTo(root);
}

test "renders offset cells in initial render when initialScrollIndex set" {
	const root: MockNode = mockNode("root");
	render(element(<FlatList data={items(10)} getItemLayout={tall10} initialScrollIndex={4} initialNumToRender={4} renderItem={row} />), mockHost(), root as unknown as HostNode);
	assert shape(root) === "sp40 c4-7 sp20", shape(root);
}

test "scrolls after content sizing with integer initialScrollIndex" {
	const root: MockNode = mockNode("root");
	render(element(<FlatList data={items(10)} getItemLayout={tall10} initialScrollIndex={1} initialNumToRender={4} updateCellsBatchingPeriod={0} renderItem={row} />), mockHost(), root as unknown as HostNode);
	layOut(root, 50, 200);
	await performAllBatches(root);
	assert scrolledTo(root) === "10 false", scrolledTo(root);
}

test "scrolls after content sizing with near-zero initialScrollIndex" {
	const root: MockNode = mockNode("root");
	render(element(<FlatList data={items(10)} getItemLayout={tall10} initialScrollIndex={0.0001} initialNumToRender={4} updateCellsBatchingPeriod={0} renderItem={row} />), mockHost(), root as unknown as HostNode);
	layOut(root, 50, 200);
	await performAllBatches(root);
	assert scrolledTo(root) === "0.001 false", scrolledTo(root);
}

test "scrolls after content sizing with near-end initialScrollIndex" {
	const root: MockNode = mockNode("root");
	render(element(<FlatList data={items(10)} getItemLayout={tall10} initialScrollIndex={9.9999} initialNumToRender={4} updateCellsBatchingPeriod={0} renderItem={row} />), mockHost(), root as unknown as HostNode);
	layOut(root, 50, 200);
	await performAllBatches(root);
	assert scrolledTo(root) === "99.999 false", scrolledTo(root);
}

test "scrolls after content sizing with fractional initialScrollIndex (getItemLayout())" {
	const root: MockNode = mockNode("root");
	render(element(<FlatList data={items(10)} getItemLayout={heights1to10} initialScrollIndex={1.5} initialNumToRender={4} updateCellsBatchingPeriod={0} renderItem={row} />), mockHost(), root as unknown as HostNode);
	layOut(root, 50, 200);
	await performAllBatches(root);
	assert scrolledTo(root) === "2 false", scrolledTo(root);
}

test "scrolls after content sizing with fractional initialScrollIndex (cached layout)" {
	const root: MockNode = mockNode("root");
	render(element(<FlatList data={items(10)} initialScrollIndex={1.5} initialNumToRender={4} updateCellsBatchingPeriod={0} renderItem={row} />), mockHost(), root as unknown as HostNode);
	for (const k of content(root).children) {
		if (k.tag === "" || rowLabel(k) === null) { continue; }
		const n: number = parseInt((rowLabel(k) as MockNode).children[0].text.slice(4)) as number;
		const e = neonEvent("layout");
		e.y = n * (n + 1) / 2;
		e.width = 10;
		e.height = n + 1;
		fireEventWith(k, "onLayout", e);
	}
	layOut(root, 50, 200);
	await performAllBatches(root);
	assert scrolledTo(root) === "2 false", "row 1 measured at y 1, height 2: " + scrolledTo(root);
}

test "does not over-render when there is less than initialNumToRender cells" {
	const root: MockNode = mockNode("root");
	render(element(<FlatList data={items(10)} getItemLayout={tall10} initialScrollIndex={4} initialNumToRender={20} renderItem={row} />), mockHost(), root as unknown as HostNode);
	assert shape(root) === "sp40 c4-9", shape(root);
}

test "discards intitial render if initialScrollIndex != 0" {
	const root: MockNode = mockNode("root");
	render(element(<FlatList data={items(20)} getItemLayout={tall10} initialScrollIndex={5} initialNumToRender={5} windowSize={1} updateCellsBatchingPeriod={0} renderItem={row} />), mockHost(), root as unknown as HostNode);
	layOut(root, 50, 200);
	await performAllBatches(root);
	fireEventWith(scrollView(root), "onScroll", scrollEvent(150, 50, 200));
	await performAllBatches(root);
	assert shape(root) === "sp140 c14-19", shape(root);
}

test "does not move render area when initialScrollIndex is > 0 and offset not yet known" {
	const root: MockNode = mockNode("root");
	render(element(<FlatList data={items(20)} getItemLayout={tall10} initialScrollIndex={1} initialNumToRender={5} windowSize={10} updateCellsBatchingPeriod={0} renderItem={row} />), mockHost(), root as unknown as HostNode);
	layOut(root, 50, 100);
	await performAllBatches(root);
	assert shape(root) === "sp10 c1-5 sp140", shape(root);
}

test "clamps render area when items removed for initialScrollIndex > 0 and scroller position not yet known" {
	const root: MockNode = mockNode("root");
	const [data, setData] = createSignal<Item[]>(items(20));
	render(element(<FlatList data={data()} getItemLayout={tall10} initialScrollIndex={14} initialNumToRender={5} windowSize={10} updateCellsBatchingPeriod={0} renderItem={row} />), mockHost(), root as unknown as HostNode);
	setData(items(15));
	layOut(root, 50, 100);
	await performAllBatches(root);
	assert shape(root) === "sp40 c4-14", shape(root);
}

test "renders new items when data is updated with non-zero initialScrollIndex" {
	const root: MockNode = mockNode("root");
	const [data, setData] = createSignal<Item[]>(items(2));
	render(element(<FlatList data={data()} getItemLayout={tall10} initialScrollIndex={1} initialNumToRender={5} windowSize={10} maxToRenderPerBatch={10} updateCellsBatchingPeriod={0} renderItem={row} />), mockHost(), root as unknown as HostNode);
	layOut(root, 20, 20);
	await performAllBatches(root);
	setData(items(4));
	await performAllBatches(root);
	assert shape(root) === "c0-1 sp20", shape(root);
}

test "expands first in viewport to render up to maxToRenderPerBatch on initial render" {
	const root: MockNode = mockNode("root");
	render(element(<FlatList data={items(10)} getItemLayout={tall10} initialNumToRender={2} initialScrollIndex={4} maxToRenderPerBatch={10} renderItem={row} />), mockHost(), root as unknown as HostNode);
	assert shape(root) === "sp40 c4-5 sp40", shape(root);
}
