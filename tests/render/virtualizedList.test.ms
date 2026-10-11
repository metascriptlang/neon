import { createSignal } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { NeonNode } from "../../src/render/hostTypes";
import { HostNode, MockNode, mockNode, mockHost, render, fireEventWith } from "../../src/render/host";
import { NeonEvent, neonEvent } from "../../src/render/event";
import { Text } from "../../src/components/primitives";
import { VirtualizedList, FlatListHandle, ItemLayout, ListRenderItemInfo, ViewabilityInfo } from "../../src/components/virtualizedList";

// Cases named after React Native's are ported from
// packages/virtualized-lists/Lists/__tests__/VirtualizedList-test.js.

interface Item {
	key: string;
}

interface Page {
	rows: Item[];
	title: string;
}

function content(root: MockNode): MockNode {
	return root.children[0].children[0];
}

function textOf(node: MockNode): string {
	let out = node.text;
	for (const child of node.children) { out += textOf(child); }
	return out;
}

function texts(root: MockNode): string {
	let out = "";
	for (const k of content(root).children) {
		if (k.tag === "") { continue; }
		out += k.children.length === 0 ? `sp${k.style!.height as number};` : textOf(k) + ";";
	}
	return out;
}

function itemText(info: ListRenderItemInfo<Item>): NeonNode {
	return element(<Text>{info.item.key + "@" + info.index().toString()}</Text>);
}

function pageLayout(data: Page, index: number): ItemLayout {
	return { length: 10, offset: 10 * index, index };
}

function page(count: int32): Page {
	const rows: Item[] = [];
	for (let i = 0; i < count; i += 1) { rows.push({ key: "item_" + i.toString() }); }
	return { rows, title: "page" };
}

function caught(fn: () => void): string {
	try {
		fn();
	} catch (e) {
		return e.toString();
	}
	return "";
}

test "test getItem functionality where data is not an Array" {
	const root: MockNode = mockNode("root");
	const data = new Map<string, Item>();
	data.set("id_0", { key: "item_0" });
	const dispose = render(element(<VirtualizedList data={data}
		getItem={(d: Map<string, Item>, index: number): Item => d.get("id_" + index.toString()) as Item}
		getItemCount={(d: Map<string, Item>): number => d.size as number}
		renderItem={itemText} />), mockHost(), root as unknown as HostNode);
	assert texts(root) === "item_0@0;", texts(root);
	dispose();
}

test "VirtualizedList reads only the cells it renders through getItem" {
	const root: MockNode = mockNode("root");
	let reads = 0;
	const big = page(10000);
	const dispose = render(element(<VirtualizedList data={big} getItemLayout={pageLayout}
		getItem={(d: Page, index: number): Item => {
			reads += 1;
			return d.rows[index];
		}}
		getItemCount={(d: Page): number => d.rows.length}
		renderItem={itemText} />), mockHost(), root as unknown as HostNode);
	assert texts(root).startsWith("item_0@0;item_1@1;") && texts(root).endsWith("item_9@9;sp99900;"), texts(root);
	assert reads < 100, "10 rendered cells, not 10000 reads: " + reads.toString();
	dispose();
}

test "VirtualizedList keeps a cell for the same item when its data source changes" {
	const root: MockNode = mockNode("root");
	const first = page(2);
	const [data, setData] = createSignal<Page>(first);
	let mounts = 0;
	const dispose = render(element(<VirtualizedList data={data()} getItemLayout={pageLayout}
		getItem={(d: Page, index: number): Item => d.rows[index]}
		getItemCount={(d: Page): number => d.rows.length}
		renderItem={(info: ListRenderItemInfo<Item>): NeonNode => {
			mounts += 1;
			return itemText(info);
		}} />), mockHost(), root as unknown as HostNode);
	const added: Item = { key: "new" };
	setData({ rows: [added, first.rows[0], first.rows[1]], title: "next" });
	assert texts(root) === "new@0;item_0@1;item_1@2;", texts(root);
	assert mounts === 3, "only the new item mounts: " + mounts.toString();
	dispose();
}

test "VirtualizedList hands the list handle to ref" {
	const root: MockNode = mockNode("root");
	const handles: FlatListHandle[] = [];
	const dispose = render(element(<VirtualizedList data={page(100)} getItemLayout={pageLayout}
		getItem={(d: Page, index: number): Item => d.rows[index]}
		getItemCount={(d: Page): number => d.rows.length}
		ref={(h: FlatListHandle): void => { handles.push(h); }}
		renderItem={itemText} />), mockHost(), root as unknown as HostNode);
	handles[0].scrollToIndex({ index: 40, animated: false });
	assert root.children[0].scrollY === 400, root.children[0].scrollY.toString();
	dispose();
}

test "VirtualizedList names itself when getItem returns one item for two rows" {
	const root: MockNode = mockNode("root");
	const msg = caught((): void => {
		render(element(<VirtualizedList data={page(1)} getItemLayout={pageLayout}
			getItem={(d: Page, index: number): Item => d.rows[0]}
			getItemCount={(d: Page): number => 2}
			renderItem={itemText} />), mockHost(), root as unknown as HostNode);
	});
	assert msg.includes("VirtualizedList: the same item is at rows 0 and 1"), msg;
}

function scrollTo(y: number): NeonEvent {
	const e = neonEvent("scroll");
	e.y = y;
	e.width = 300;
	e.height = 600;
	e.contentWidth = 300;
	e.contentHeight = 2400;
	return e;
}

function tall800(data: Item[], index: number): ItemLayout {
	return { length: 800, offset: 800 * index, index };
}

test "returns the viewableItems correctly in the onViewableItemsChanged callback after changing the data" {
	const root: MockNode = mockNode("root");
	const first: Item[] = [{ key: "i1" }, { key: "i2" }, { key: "i3" }];
	const [data, setData] = createSignal<Item[]>(first);
	const calls: string[] = [];
	const dispose = render(element(<VirtualizedList data={data()} getItemLayout={tall800}
		getItem={(d: Item[], index: number): Item => d[index]}
		getItemCount={(d: Item[]): number => d.length}
		onViewableItemsChanged={(info: ViewabilityInfo<Item>): void => {
			let seen = "";
			for (const token of info.viewableItems) { seen += token.item.key + (token.isViewable ? "+" : "-"); }
			calls.push(seen);
		}}
		renderItem={itemText} />), mockHost(), root as unknown as HostNode);
	fireEventWith(root.children[0], "onScrollBeginDrag", scrollTo(0));
	fireEventWith(root.children[0], "onScroll", scrollTo(0));
	assert calls.length === 1 && calls[0] === "i1+", calls.join("|");
	setData([{ key: "i4" }, first[0], first[1], first[2]]);
	fireEventWith(root.children[0], "onScroll", scrollTo(100));
	assert calls.length === 2 && calls[1] === "i4+", "a data change resets the viewable indices: " + calls.join("|");
	dispose();
}

function ItemComponent(info: ListRenderItemInfo<Item>): NeonNode {
	return element(<Text>{info.item.key + "@" + info.index().toString()}</Text>);
}

test "renders simple list using ListItemComponent" {
	const root: MockNode = mockNode("root");
	const rows: Item[] = [{ key: "i1" }, { key: "i2" }, { key: "i3" }];
	const dispose = render(element(<VirtualizedList data={rows} getItemLayout={tall800}
		getItem={(d: Item[], index: number): Item => d[index]}
		getItemCount={(d: Item[]): number => d.length}
		ListItemComponent={ItemComponent} />), mockHost(), root as unknown as HostNode);
	assert texts(root) === "i1@0;i2@1;i3@2;", texts(root);
	dispose();
}

test "throws if no renderItem or ListItemComponent" {
	const rows: Item[] = [{ key: "i1" }];
	const msg = caught((): void => {
		render(element(<VirtualizedList data={rows} getItem={(d: Item[], index: number): Item => d[index]}
			getItemCount={(d: Item[]): number => d.length} />), mockHost(), mockNode("root") as unknown as HostNode);
	});
	assert msg.includes("VirtualizedList: Either ListItemComponent or renderItem props are required but none were found."), msg;
}
