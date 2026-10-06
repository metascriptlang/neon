import { domHost, documentBody } from "../../src/platform/browser/dom";
import { HostNode, NeonNode } from "../../src/render/hostTypes";
import { render } from "../../src/render/host";
import { Style } from "../../src/render/style";
import { element } from "../../src/macros/ui/element";
import { Text, View } from "../../src/components/primitives";
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
