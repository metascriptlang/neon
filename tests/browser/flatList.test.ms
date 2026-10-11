import { domHost, documentBody } from "../../src/platform/browser/dom";
import { HostNode, NeonNode } from "../../src/render/hostTypes";
import { render } from "../../src/render/host";
import { Style } from "../../src/render/style";
import { element } from "../../src/macros/ui/element";
import { Text, TextInput, View } from "../../src/components/primitives";
import { createSignal } from "../../src/core/signal";
import { NeonEvent } from "../../src/render/event";
import { FlatList, FlatListHandle, ItemLayout, ListRenderItemInfo } from "../../src/components/flatList";
import { sleepAsync } from "std/core/promise";

extern class HTMLElement {
	textContent: string;
	scrollTop: number;
	scrollLeft: number;
	scrollWidth: number;
	scrollHeight: number;
	lastElementChild: HTMLElement;
	parentElement: HTMLElement;
	extern querySelectorAll(selector: cstring): ElementList;
	extern getBoundingClientRect(): Frame;
	extern remove(): void;
	extern focus(): void;
}

extern class document {
	static activeElement: HTMLElement;
}

extern class ElementList {
	length: number;
	extern item(index: int32): HTMLElement;
}

extern class Frame {
	top: number;
	left: number;
	width: number;
	height: number;
}

interface Item {
	id: string;
	n: number;
}

const ROW = 50;

const rowStyle: Style = { height: ROW };

function items(count: number): Item[] {
	const out: Item[] = [];
	for (let i = 0; i < count; i += 1) { out.push({ id: "k" + i.toString(), n: i }); }
	return out;
}

function fixed(data: Item[], index: number): ItemLayout {
	return { length: ROW, offset: ROW * index, index };
}

function rowsIn(text: string): number {
	let count = 0;
	for (let i = 0; i < text.length; i += 1) {
		if (text.charAt(i) === "<") { count += 1; }
	}
	return count;
}

test "a 10000-row FlatList mounts a window, keeps the full scroll height and follows scrollToIndex" {
	const handles: FlatListHandle[] = [];
	render(element(<FlatList data={items(10000)} style={{ height: 300 }} getItemLayout={fixed}
		ref={(h: FlatListHandle): void => { handles.push(h); }}
		renderItem={(info: ListRenderItemInfo<Item>): NeonNode => <View style={rowStyle}><Text>{"<" + info.item.n.toString() + ">"}</Text></View>} />), domHost(), documentBody());
	await sleepAsync(100);
	const scroller = (documentBody() as unknown as HTMLElement).lastElementChild;
	const mounted = rowsIn(scroller.textContent);
	assert mounted > 10 && mounted < 200, "a window of rows, not 10000: " + mounted.toString();
	assert scroller.scrollHeight === 10000 * ROW, "the spacers keep the full height: " + scroller.scrollHeight.toString();

	handles[0].scrollToIndex({ index: 3000, animated: false });
	await sleepAsync(200);
	assert scroller.scrollTop === 3000 * ROW, "offset " + scroller.scrollTop.toString();
	const text = scroller.textContent;
	assert text.includes("<3000>") && !text.includes("<1000>"), "the window moved to row 3000";
	assert text.includes("<0>") && text.includes("<9>"), "the first initialNumToRender rows stay for scroll-to-top";
	assert rowsIn(text) < 200, "still a window after the move: " + rowsIn(text).toString();
	scroller.remove();
}

const horizontalListStyle: Style = { width: 300, height: 100 };
const horizontalRowStyle: Style = { width: ROW, height: 100, flexShrink: 0 };

test "horizontal FlatList virtualizes on x and retains its complete scroll width" {
	const handles: FlatListHandle[] = [];
	const dispose = render(element(<FlatList data={items(10000)} horizontal={true} style={horizontalListStyle} getItemLayout={fixed}
		ref={(h: FlatListHandle): void => { handles.push(h); }}
		renderItem={(info: ListRenderItemInfo<Item>): NeonNode => <View style={horizontalRowStyle}><Text>{"<" + info.item.n.toString() + ">"}</Text></View>} />), domHost(), documentBody());
	await sleepAsync(100);
	const scroller = (documentBody() as unknown as HTMLElement).lastElementChild;
	assert scroller.scrollWidth === 10000 * ROW, "spacers preserve every row's width";
	handles[0].scrollToIndex({ index: 3000, animated: false });
	await sleepAsync(200);
	assert scroller.scrollLeft === 3000 * ROW && scroller.scrollTop === 0, "index scroll uses x only";
	assert scroller.textContent.includes("<3000>") && !scroller.textContent.includes("<1000>"), "the horizontal window follows the viewport";
	assert rowsIn(scroller.textContent) < 200, "only the render window remains mounted";
	dispose();
	scroller.remove();
}

function tallness(n: number): Style {
	return { height: 30 + (n % 4) * 10 };
}

test "a FlatList without getItemLayout measures rows of different heights and scrolls to its end through them" {
	let ends = 0;
	const dispose = render(element(<FlatList data={items(2000)} style={{ height: 300 }} windowSize={5}
		onEndReached={(): void => { ends += 1; }}
		renderItem={(info: ListRenderItemInfo<Item>): NeonNode => <View style={tallness(info.item.n)}><Text>{"<" + info.item.n.toString() + ">"}</Text></View>} />), domHost(), documentBody());
	await sleepAsync(500);
	const scroller = (documentBody() as unknown as HTMLElement).lastElementChild;
	const first = rowsIn(scroller.textContent);
	assert first > 10 && first < 200, "a measured window of rows: " + first.toString();
	assert scroller.scrollHeight < 2000 * 30, "the tail spacer stops at the measured rows: " + scroller.scrollHeight.toString();
	let steps = 0;
	while (!scroller.textContent.includes("<1999>") && steps < 400) {
		scroller.scrollTop = scroller.scrollHeight;
		await sleepAsync(60);
		steps += 1;
	}
	assert scroller.textContent.includes("<1999>"), "scrolling reaches the last row after " + steps.toString() + " steps";
	assert ends === 0, "not before the end is in view: " + ends.toString();
	scroller.scrollTop = scroller.scrollHeight;
	await sleepAsync(200);
	assert scroller.scrollHeight === 500 * (30 + 40 + 50 + 60), "every row measured at its own height: " + scroller.scrollHeight.toString();
	assert rowsIn(scroller.textContent) < 200 && !scroller.textContent.includes("<1000>"), "still a window at the end: " + rowsIn(scroller.textContent).toString();
	assert ends === 1, "onEndReached once at the end: " + ends.toString();
	dispose();
	scroller.remove();
}

test "initialScrollIndex opens a 10000-row FlatList at its row without the first rows" {
	const dispose = render(element(<FlatList data={items(10000)} style={{ height: 300 }} getItemLayout={fixed} initialScrollIndex={3000}
		renderItem={(info: ListRenderItemInfo<Item>): NeonNode => <View style={rowStyle}><Text>{"<" + info.item.n.toString() + ">"}</Text></View>} />), domHost(), documentBody());
	await sleepAsync(300);
	const scroller = (documentBody() as unknown as HTMLElement).lastElementChild;
	assert scroller.scrollTop === 3000 * ROW, "offset " + scroller.scrollTop.toString();
	const text = scroller.textContent;
	assert text.includes("<3000>") && !text.includes("<0>") && !text.includes("<1000>"), "the window starts at row 3000, the first rows are not kept";
	assert rowsIn(text) < 200, "a window: " + rowsIn(text).toString();
	dispose();
	scroller.remove();
}

test "an inverted measured list keeps logical indices and scroll offsets while painting rows bottom first" {
	const handles: FlatListHandle[] = [];
	let ends = 0;
	const dispose = render(element(<FlatList data={items(6)} inverted={true} style={{ height: 100 }}
		ref={(h: FlatListHandle): void => { handles.push(h); }} onEndReached={(): void => { ends += 1; }}
		ItemSeparatorComponent={<View class="separator-probe" style={{ height: 2 }} />}
		renderItem={(info: ListRenderItemInfo<Item>): NeonNode => <View style={tallness(info.item.n)}><Text>{"<" + info.item.n.toString() + ">"}</Text></View>} />), domHost(), documentBody());
	await sleepAsync(200);
	const scroller = (documentBody() as unknown as HTMLElement).lastElementChild;
	const labels = scroller.querySelectorAll("span");
	assert labels.item(0).textContent === "<0>" && labels.item(1).textContent === "<1>", "logical item order stays unchanged";
	assert labels.item(0).getBoundingClientRect().top > labels.item(1).getBoundingClientRect().top, "row 0 paints below row 1";
	const lower = labels.item(0).parentElement.getBoundingClientRect();
	const upper = labels.item(1).parentElement.getBoundingClientRect();
	const separator = scroller.querySelectorAll(".separator-probe").item(0).getBoundingClientRect();
	assert separator.top === upper.top + upper.height && separator.top + separator.height === lower.top, "the separator paints between neighbouring rows, not after the lower row";
	assert scroller.scrollHeight === 260, "untransformed measured lengths include the separators";
	handles[0].scrollToIndex({ index: 3, animated: false });
	await sleepAsync(100);
	assert scroller.scrollTop === 126, "row 3 retains its logical measured offset, including separators";
	handles[0].scrollToEnd({ animated: false });
	await sleepAsync(100);
	assert scroller.scrollTop === 160 && ends === 1, "end scrolling and callback retain logical direction";
	dispose();
	scroller.remove();
}

test "an initial index beyond the list scrolls to the measured footer end even when content layout arrives first" {
	const dispose = render(element(<FlatList data={items(3)} style={{ flexGrow: 0, flexShrink: 0, height: 100 }} getItemLayout={fixed} initialScrollIndex={999}
		ListFooterComponent={<View style={{ height: 40 }} />}
		renderItem={(info: ListRenderItemInfo<Item>): NeonNode => <View style={rowStyle}><Text>{"<" + info.item.n.toString() + ">"}</Text></View>} />), domHost(), documentBody());
	await sleepAsync(200);
	const scroller = (documentBody() as unknown as HTMLElement).lastElementChild;
	assert scroller.scrollHeight === 190 && scroller.scrollTop === 90, "the footer belongs to the initial end target: " + scroller.scrollTop.toString();
	dispose();
	scroller.remove();
}

function stickyRows(info: ListRenderItemInfo<Item>): NeonNode {
	return element(<View class={"sticky-row-" + info.item.n.toString()} style={rowStyle}><Text>{"<" + info.item.n.toString() + ">"}</Text></View>);
}

test "sticky rows collide with their successor and the nearest header survives outside the virtual window" {
	const dispose = render(element(<FlatList data={items(30)} getItemLayout={fixed} renderItem={stickyRows}
		style={{ height: 100 }} stickyHeaderIndices={[0, 3, 6, 9, 12, 15, 18, 21, 24, 27]}
		initialNumToRender={1} windowSize={1} updateCellsBatchingPeriod={0} />), domHost(), documentBody());
	await sleepAsync(200);
	const scroller = (documentBody() as unknown as HTMLElement).lastElementChild;
	const top = scroller.getBoundingClientRect().top;
	scroller.scrollTop = 120;
	await sleepAsync(100);
	const first = scroller.querySelectorAll(".sticky-row-0").item(0).getBoundingClientRect();
	const next = scroller.querySelectorAll(".sticky-row-3").item(0).getBoundingClientRect();
	assert first.top + first.height === next.top && first.top === top - 20, "the following header pushes the first one out";
	scroller.scrollTop = 200;
	await sleepAsync(100);
	assert scroller.querySelectorAll(".sticky-row-3").item(0).getBoundingClientRect().top === top, "the next header now sticks";
	scroller.scrollTop = 1000;
	await sleepAsync(200);
	assert scroller.querySelectorAll(".sticky-row-18").item(0).getBoundingClientRect().top === top, "the closest preceding header remains at the viewport edge";
	dispose();
	scroller.remove();
}

test "measured sticky headers count the list header slot and push it out before pinning an item" {
	const dispose = render(element(<FlatList data={items(6)} renderItem={stickyRows}
		style={{ height: 100 }} stickyHeaderIndices={[0, 2, 4]} initialNumToRender={6}
		ListHeaderComponent={<View class="list-sticky-header" style={{ height: 40 }}><Text>Header</Text></View>} />), domHost(), documentBody());
	await sleepAsync(200);
	const scroller = (documentBody() as unknown as HTMLElement).lastElementChild;
	const top = scroller.getBoundingClientRect().top;
	scroller.scrollTop = 80;
	await sleepAsync(100);
	const header = scroller.querySelectorAll(".list-sticky-header").item(0).getBoundingClientRect();
	const first = scroller.querySelectorAll(".sticky-row-1").item(0).getBoundingClientRect();
	assert header.top === top - 30 && header.top + header.height === first.top, "indices include the header slot and its collision uses measured row positions";
	scroller.scrollTop = 100;
	await sleepAsync(100);
	assert scroller.querySelectorAll(".sticky-row-1").item(0).getBoundingClientRect().top === top, "a measured item takes over at its actual offset";
	dispose();
	scroller.remove();
}

function gridCell(info: ListRenderItemInfo<Item>): NeonNode {
	return element(<View class={"grid-cell-" + info.item.n.toString()} style={{ height: ROW, width: 60 }}><Text>{"<" + info.item.n.toString() + ">"}</Text></View>);
}

test "a measured two-column grid lays rows side by side, applies columnWrapperStyle and scrolls by row" {
	const handles: FlatListHandle[] = [];
	const dispose = render(element(<FlatList data={items(41)} renderItem={gridCell} numColumns={2}
		columnWrapperStyle={{ gap: 10 }} style={{ height: 120 }} updateCellsBatchingPeriod={0}
		ref={(h: FlatListHandle): void => { handles.push(h); }} />), domHost(), documentBody());
	await sleepAsync(200);
	const scroller = (documentBody() as unknown as HTMLElement).lastElementChild;
	const a = scroller.querySelectorAll(".grid-cell-0").item(0).getBoundingClientRect();
	const b = scroller.querySelectorAll(".grid-cell-1").item(0).getBoundingClientRect();
	const c = scroller.querySelectorAll(".grid-cell-2").item(0).getBoundingClientRect();
	assert a.top === b.top && b.left === a.left + 70, "one row, 60 px cells 10 px apart: " + `${a.left} ${b.left}`;
	assert c.top === a.top + ROW && c.left === a.left, "the third item opens the second row";
	handles[0].scrollToIndex({ index: 10, animated: false });
	await sleepAsync(200);
	assert scroller.scrollTop === 10 * ROW, "row 10 holds items 20 and 21: " + scroller.scrollTop.toString();
	assert scroller.querySelectorAll(".grid-cell-20").length === 1, "item 20 mounted at row 10";
	handles[0].scrollToEnd({ animated: false });
	await sleepAsync(200);
	assert scroller.scrollTop === 21 * ROW - 120, "21 rows, the last holding item 40 alone: " + scroller.scrollTop.toString();
	dispose();
	scroller.remove();
}

function gridField(info: ListRenderItemInfo<Item>): NeonNode {
	const n = info.item.n.toString();
	const [taps, setTaps] = createSignal<number>(0);
	return element(<View class={"grid-field-" + n} style={{ height: ROW, width: 90 }}>
		<TextInput class={"grid-input-" + n} onFocus={(e: NeonEvent): void => { setTaps(taps() + 1); }} />
		<Text>{"<" + n + "@" + info.index().toString() + "#" + taps().toString() + ">"}</Text>
	</View>);
}

test "a prepend moves a focused grid field to the next row as the same element, still focused" {
	const all = items(6);
	const [data, setData] = createSignal<Item[]>(all.slice(1, 6));
	const dispose = render(element(<FlatList data={data()} renderItem={gridField} numColumns={2}
		getItemLayout={fixed} style={{ height: 300 }} />), domHost(), documentBody());
	await sleepAsync(100);
	const scroller = (documentBody() as unknown as HTMLElement).lastElementChild;
	const field = scroller.querySelectorAll(".grid-input-2").item(0);
	const cell = scroller.querySelectorAll(".grid-field-2").item(0);
	field.focus();
	const before = cell.getBoundingClientRect();
	assert document.activeElement === field && cell.textContent === "<2@1#1>", "item 2 sits in row 0 with focus: " + cell.textContent;
	setData(all);
	await sleepAsync(100);
	const after = cell.getBoundingClientRect();
	assert scroller.querySelectorAll(".grid-field-2").item(0) === cell, "the cell element survived the prepend";
	assert after.top === before.top + ROW && after.left === before.left - 90, "item 2 moved to the start of row 1: " + `${after.left - before.left} ${after.top - before.top}`;
	assert cell.textContent === "<2@2#1>", "its index followed and its state stayed: " + cell.textContent;
	assert document.activeElement === field, "the field kept the DOM focus across the move";
	dispose();
	scroller.remove();
}

function chatRow(info: ListRenderItemInfo<Item>): NeonNode {
	return element(<View class={"chat-row-" + info.item.n.toString()} style={rowStyle}><Text>{"<" + info.item.n.toString() + ">"}</Text></View>);
}

test "a FlatList with maintainVisibleContentPosition keeps the visible message still when older ones are prepended" {
	const [data, setData] = createSignal<Item[]>(items(100));
	const dispose = render(element(<FlatList data={data()} style={{ height: 300 }} getItemLayout={fixed} renderItem={chatRow}
		maintainVisibleContentPosition={{ minIndexForVisible: 0 }} />), domHost(), documentBody());
	await sleepAsync(100);
	const scroller = (documentBody() as unknown as HTMLElement).lastElementChild;
	scroller.scrollTop = 1000;
	await sleepAsync(200);
	const before = scroller.querySelectorAll(".chat-row-20").item(0).getBoundingClientRect().top;
	const next: Item[] = [];
	for (let i = 0; i < 20; i += 1) { next.push({ id: "old" + i.toString(), n: 1000 + i }); }
	for (const item of data()) { next.push(item); }
	setData(next);
	await sleepAsync(200);
	const after = scroller.querySelectorAll(".chat-row-20").item(0).getBoundingClientRect().top;
	assert after === before && scroller.scrollTop === 2000, `row 20 stays at ${before}: ${after}, offset ${scroller.scrollTop}`;
	assert scroller.scrollHeight === 120 * ROW, "the older rows extend the content above: " + scroller.scrollHeight.toString();
	scroller.scrollTop = 0;
	await sleepAsync(200);
	assert scroller.textContent.includes("<1000>"), "the oldest message is reachable at the top";
	dispose();
	scroller.remove();
}
