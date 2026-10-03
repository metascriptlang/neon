import { createRoot } from "../../src/core/owner";
import { Accessor, accessor } from "../../src/core/signal";
import { onCleanup } from "../../src/core/cleanup";
import { element } from "../../src/macros/ui/element";
import { NeonEvent, neonEvent } from "../../src/render/event";
import { NeonNode } from "../../src/render/hostTypes";
import { HostNode, MockNode, mockNode, mockHost, render, fireEventWith } from "../../src/render/host";
import { Text } from "../../src/components/primitives";
import { FlatList, FlatListHandle, ItemLayout, ListRenderItemInfo, EndReachedInfo } from "../../src/components/flatList";

interface Item {
	id: string;
	n: number;
}

const ROW = 50;

function items(count: number): Item[] {
	const out: Item[] = [];
	for (let i = 0; i < count; i += 1) { out.push({ id: "k" + i.toString(), n: i }); }
	return out;
}

function fixed(data: Item[], index: number): ItemLayout {
	return { length: ROW, offset: ROW * index, index };
}

function rowTexts(n: MockNode, out: string[]): string[] {
	if (n.tag === "text") {
		for (const k of n.children) { out.push(k.text); }
		return out;
	}
	for (const k of n.children) { rowTexts(k, out); }
	return out;
}

function scrollEvent(y: number, height: number, contentHeight: number): NeonEvent {
	const e = neonEvent("scroll");
	e.y = y;
	e.width = 320;
	e.height = height;
	e.contentWidth = 320;
	e.contentHeight = contentHeight;
	return e;
}

function layoutEvent(height: number): NeonEvent {
	const e = neonEvent("layout");
	e.width = 320;
	e.height = height;
	return e;
}

function spacers(root: MockNode): string {
	const content = root.children[0].children[0];
	const top = content.children[0];
	const bottom = content.children[content.children.length - 1];
	return `${top.style!.height as number} ${bottom.style!.height as number}`;
}

test "before its viewport is known FlatList mounts initialNumToRender rows" {
	const root: MockNode = mockNode("root");
	const data = items(10000);
	render(element(<FlatList data={data} keyExtractor={(it: Item, i: number): string => it.id} getItemLayout={fixed}
		renderItem={(info: ListRenderItemInfo<Item>): NeonNode => <Text>{"row " + info.item.n.toString()}</Text>} />), mockHost(), root as unknown as HostNode);
	const texts = rowTexts(root, []);
	assert texts.length === 10, "rows " + texts.length.toString();
	assert texts[0] === "row 0" && texts[9] === "row 9", "first rows: " + texts.join(",");
	assert spacers(root) === `0 ${10000 * ROW - 10 * ROW}`, "spacers " + spacers(root);
}

test "onLayout opens the window to the viewport plus windowSize" {
	const root: MockNode = mockNode("root");
	render(element(<FlatList data={items(10000)} keyExtractor={(it: Item, i: number): string => it.id} getItemLayout={fixed}
		renderItem={(info: ListRenderItemInfo<Item>): NeonNode => <Text>{"row " + info.item.n.toString()}</Text>} />), mockHost(), root as unknown as HostNode);
	fireEventWith(root.children[0], "onLayout", layoutEvent(500));
	const texts = rowTexts(root, []);
	assert texts.length === 111, "a 500-high viewport with windowSize 21 keeps rows 0..110: " + texts.length.toString();
	assert spacers(root) === `0 ${10000 * ROW - 111 * ROW}`, "spacers " + spacers(root);
}

test "scrolling mounts rows that enter the window, unmounts rows that leave, and keeps the rest" {
	const root: MockNode = mockNode("root");
	let mounts = 0;
	let unmounts = 0;
	render(element(<FlatList data={items(10000)} keyExtractor={(it: Item, i: number): string => it.id} getItemLayout={fixed}
		renderItem={(info: ListRenderItemInfo<Item>): NeonNode => {
			mounts = mounts + 1;
			onCleanup((): void => { unmounts = unmounts + 1; });
			return <Text>{"row " + info.item.n.toString()}</Text>;
		}} />), mockHost(), root as unknown as HostNode);
	const sv = root.children[0];
	fireEventWith(sv, "onLayout", layoutEvent(500));
	assert mounts === 111 && unmounts === 0, `after layout ${mounts} ${unmounts}`;
	fireEventWith(sv, "onScroll", scrollEvent(1000, 500, 10000 * ROW));
	assert mounts === 131 && unmounts === 0, "rows 111..130 mount, rows 0..110 stay: " + `${mounts} ${unmounts}`;
	fireEventWith(sv, "onScroll", scrollEvent(20000, 500, 10000 * ROW));
	const texts = rowTexts(root, []);
	assert texts.length === 211 && texts[0] === "row 300" && texts[210] === "row 510", "window 300..510: " + `${texts.length} ${texts[0]} ${texts[texts.length - 1]}`;
	assert unmounts === 131, "every row of the old window unmounted: " + unmounts.toString();
	assert spacers(root) === `${300 * ROW} ${10000 * ROW - 511 * ROW}`, "spacers " + spacers(root);
}

test "a row that leaves the window and comes back is mounted again for the same key" {
	const root: MockNode = mockNode("root");
	let k5 = 0;
	render(element(<FlatList data={items(10000)} keyExtractor={(it: Item, i: number): string => it.id} getItemLayout={fixed}
		renderItem={(info: ListRenderItemInfo<Item>): NeonNode => {
			if (info.item.id === "k5") { k5 = k5 + 1; }
			return <Text>{"row " + info.item.n.toString()}</Text>;
		}} />), mockHost(), root as unknown as HostNode);
	const sv = root.children[0];
	fireEventWith(sv, "onLayout", layoutEvent(500));
	fireEventWith(sv, "onScroll", scrollEvent(20000, 500, 10000 * ROW));
	fireEventWith(sv, "onScroll", scrollEvent(0, 500, 10000 * ROW));
	assert k5 === 2, "row k5 mounted, left with its state and came back fresh: " + k5.toString();
	assert rowTexts(root, [])[5] === "row 5", "the key renders its own item";
}

// Parked: a number literal on a generic component's Accessor prop loses its contextual type —
// ~/metascript/.inbox/compiler/2026-10-03-object-literal-prop-of-a-generic-component-loses-its-contextual-type.md
const twoViewports: Accessor<number> = accessor((): number => 2);

test "onEndReached fires once when the window reaches the end within the threshold" {
	const root: MockNode = mockNode("root");
	let ends = "";
	render(element(<FlatList data={items(100)} keyExtractor={(it: Item, i: number): string => it.id} getItemLayout={fixed}
		onEndReachedThreshold={twoViewports}
		onEndReached={(info: EndReachedInfo): void => { ends = ends + info.distanceFromEnd.toString() + ";"; }}
		renderItem={(info: ListRenderItemInfo<Item>): NeonNode => <Text>{"row " + info.item.n.toString()}</Text>} />), mockHost(), root as unknown as HostNode);
	const sv = root.children[0];
	fireEventWith(sv, "onLayout", layoutEvent(500));
	assert ends === "", "5000 high, at the top: not near the end";
	fireEventWith(sv, "onScroll", scrollEvent(3600, 500, 100 * ROW));
	assert ends === "900;", "900 from the end is inside 2 viewports: " + ends;
	fireEventWith(sv, "onScroll", scrollEvent(3700, 500, 100 * ROW));
	assert ends === "900;", "fires once per content length: " + ends;
}

test "onEndReached without a threshold fires within 2 px of the end, React Native's default" {
	const root: MockNode = mockNode("root");
	let ends = "";
	render(element(<FlatList data={items(100)} keyExtractor={(it: Item, i: number): string => it.id} getItemLayout={fixed}
		onEndReached={(info: EndReachedInfo): void => { ends = ends + info.distanceFromEnd.toString() + ";"; }}
		renderItem={(info: ListRenderItemInfo<Item>): NeonNode => <Text>{"row " + info.item.n.toString()}</Text>} />), mockHost(), root as unknown as HostNode);
	const sv = root.children[0];
	fireEventWith(sv, "onLayout", layoutEvent(500));
	fireEventWith(sv, "onScroll", scrollEvent(3600, 500, 100 * ROW));
	assert ends === "", "900 from the end is outside the 2 px default: " + ends;
	fireEventWith(sv, "onScroll", scrollEvent(4498, 500, 100 * ROW));
	assert ends === "2;", "exactly 2 px from the end is inside: " + ends;
	fireEventWith(sv, "onScroll", scrollEvent(3000, 500, 100 * ROW));
	fireEventWith(sv, "onScroll", scrollEvent(4499.9995, 500, 100 * ROW));
	assert ends === "2;0;", "leaving the threshold re-arms it, and a distance under 0.001 reads 0: " + ends;
}

test "the ref's handle scrolls to an index, an offset and the end" {
	const root: MockNode = mockNode("root");
	const handles: FlatListHandle[] = [];
	render(element(<FlatList data={items(100)} keyExtractor={(it: Item, i: number): string => it.id} getItemLayout={fixed}
		ref={(h: FlatListHandle): void => { handles.push(h); }}
		renderItem={(info: ListRenderItemInfo<Item>): NeonNode => <Text>{"row " + info.item.n.toString()}</Text>} />), mockHost(), root as unknown as HostNode);
	const sv = root.children[0];
	fireEventWith(sv, "onLayout", layoutEvent(500));
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
	let caught = "";
	try { handles[0].scrollToIndex({ index: 100 }); } catch (e) { caught = e.toString(); }
	assert caught.includes("100"), "an index past the data fails loud: " + caught;
}

test "FlatList without getItemLayout fails loud and names the prop" {
	const root: MockNode = mockNode("root");
	let caught = "";
	try {
		render(element(<FlatList data={items(3)} keyExtractor={(it: Item, i: number): string => it.id}
			renderItem={(info: ListRenderItemInfo<Item>): NeonNode => <Text>{"row " + info.item.n.toString()}</Text>} />), mockHost(), root as unknown as HostNode);
	} catch (e) { caught = e.toString(); }
	assert caught.includes("getItemLayout"), "names the prop: " + caught;
}

test "onLayout reaches the author after the window opened" {
	const root: MockNode = mockNode("root");
	let seen = "";
	render(element(<FlatList data={items(10000)} keyExtractor={(it: Item, i: number): string => it.id} getItemLayout={fixed}
		onLayout={(e: NeonEvent): void => { seen = `${e.height} ${rowTexts(root, []).length}`; }}
		renderItem={(info: ListRenderItemInfo<Item>): NeonNode => <Text>{"row " + info.item.n.toString()}</Text>} />), mockHost(), root as unknown as HostNode);
	fireEventWith(root.children[0], "onLayout", layoutEvent(500));
	assert seen === "500 111", "the author sees the layout with the window already mounted: " + seen;
}
