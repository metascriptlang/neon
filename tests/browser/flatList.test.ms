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
	scrollHeight: number;
	lastElementChild: HTMLElement;
	extern remove(): void;
}

interface Item {
	id: string;
	n: number;
}

const ROW = 50;

// Parked: style={{ height: 300 }} on the generic FlatList loses its Style type —
// ~/metascript/.inbox/compiler/2026-10-03-object-literal-prop-of-a-generic-component-loses-its-contextual-type.md
const listStyle: Style = { height: 300 };
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
	render(element(<FlatList data={items(10000)} style={listStyle} keyExtractor={(it: Item, i: number): string => it.id} getItemLayout={fixed}
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
	assert text.includes("<3000>") && !text.includes("<0>"), "the window moved to row 3000";
	assert rowsIn(text) < 200, "still a window after the move: " + rowsIn(text).toString();
	scroller.remove();
}
