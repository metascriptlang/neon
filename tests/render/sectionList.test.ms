import { createSignal } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { NeonNode } from "../../src/render/hostTypes";
import { neonEvent } from "../../src/render/event";
import { HostNode, MockNode, mockNode, mockHost, render, fireEventWith } from "../../src/render/host";
import { Text } from "../../src/components/primitives";
import { ItemLayout } from "../../src/components/virtualizedList";
import {
	SectionBase,
	SectionInfo,
	SectionList,
	SectionListHandle,
	SectionListRenderItemInfo,
	SectionViewabilityInfo,
	VirtualizedSectionList,
} from "../../src/components/sectionList";

// Cases named after React Native's are ported from
// packages/virtualized-lists/Lists/__tests__/VirtualizedSectionList-test.js.

interface Item {
	key: string;
}

interface Group {
	title: string;
	items: Item[];
}

function content(root: MockNode): MockNode {
	return root.children[0].children[0];
}

function textOf(node: MockNode): string {
	let out = node.text;
	for (const child of node.children) { out += textOf(child); }
	return out;
}

function cell100(sections: Group[], index: number): ItemLayout {
	return { length: 100, offset: 100 * index, index };
}

function cell10(sections: Group[], index: number): ItemLayout {
	return { length: 10, offset: 10 * index, index };
}

function group(title: string, keys: string[]): Group {
	const items: Item[] = [];
	for (const key of keys) { items.push({ key }); }
	return { title, items };
}

function groupItem(section: Group, index: number): Item {
	return section.items[index];
}

function groupCount(section: Group): number {
	return section.items.length;
}

function itemAt(info: SectionListRenderItemInfo<Item, Group>): NeonNode {
	return element(<Text>{info.item.key + "@" + info.index().toString() + ":" + info.section().title}</Text>);
}

function header(info: SectionInfo<Group>): NeonNode {
	return element(<Text>{"H:" + info.section.title}</Text>);
}

function footer(info: SectionInfo<Group>): NeonNode {
	return element(<Text>{"F:" + info.section.title}</Text>);
}

function Bar(): NeonNode { return element(<Text>|</Text>); }
function Hash(): NeonNode { return element(<Text>#</Text>); }

test "renders simple list" {
	const root: MockNode = mockNode("root");
	const dispose = render(element(<VirtualizedSectionList sections={[group("s1", ["i1", "i2", "i3"])]}
		getItem={groupItem} getItemCount={groupCount} getItemLayout={cell10} renderItem={itemAt} />), mockHost(), root as unknown as HostNode);
	assert textOf(content(root)) === "i1@0:s1i2@1:s1i3@2:s1", textOf(content(root));
	dispose();
}

test "section headers, footers, item separators and section separators follow React Native's order" {
	const root: MockNode = mockNode("root");
	const dispose = render(element(<VirtualizedSectionList sections={[group("s1", ["a", "b"]), group("s2", ["c"])]}
		getItem={groupItem} getItemCount={groupCount} getItemLayout={cell10} renderItem={itemAt}
		renderSectionHeader={header} renderSectionFooter={footer}
		ItemSeparatorComponent={Bar} SectionSeparatorComponent={Hash} />), mockHost(), root as unknown as HostNode);
	assert textOf(content(root)) === "H:s1#a@0:s1|b@1:s1#F:s1H:s2#c@0:s2#F:s2", textOf(content(root));
	dispose();
}

test "an item keeps its cell when it moves to another section and reads its new section and index" {
	const root: MockNode = mockNode("root");
	const s1 = group("s1", ["a", "b"]);
	const s2 = group("s2", ["c"]);
	const [sections, setSections] = createSignal<Group[]>([s1, s2]);
	let mounts = "";
	const dispose = render(element(<VirtualizedSectionList sections={sections()}
		getItem={groupItem} getItemCount={groupCount} getItemLayout={cell10}
		renderItem={(info: SectionListRenderItemInfo<Item, Group>): NeonNode => {
			mounts += info.item.key;
			return itemAt(info);
		}}
		ItemSeparatorComponent={Bar} SectionSeparatorComponent={Hash} />), mockHost(), root as unknown as HostNode);
	assert textOf(content(root)) === "#a@0:s1|b@1:s1##c@0:s2#", textOf(content(root));
	setSections([{ title: "s1", items: [s1.items[0]] }, { title: "s2", items: [s1.items[1], s2.items[0]] }]);
	assert textOf(content(root)) === "#a@0:s1##b@0:s2|c@1:s2#", textOf(content(root));
	assert mounts === "abc", "items move between sections without remounting: " + mounts;
	dispose();
}

test "SectionList reads section.data and renders through the shared list" {
	const root: MockNode = mockNode("root");
	const sections: SectionBase<Item>[] = [{ key: "fruit", data: [{ key: "apple" }, { key: "pear" }] }];
	const dispose = render(element(<SectionList sections={sections}
		renderSectionHeader={(info: SectionInfo<SectionBase<Item>>): NeonNode => element(<Text>{(info.section.key as string) + ":"}</Text>)}
		renderItem={(info: SectionListRenderItemInfo<Item, SectionBase<Item>>): NeonNode => element(<Text>{info.item.key + " "}</Text>)} />),
		mockHost(), root as unknown as HostNode);
	assert textOf(content(root)) === "fruit:apple pear ", textOf(content(root));
	dispose();
}

function scrolledTo(sticky: boolean, sectionIndex: number, itemIndex: number, viewOffset: number): number {
	const root: MockNode = mockNode("root");
	const handles: SectionListHandle[] = [];
	const dispose = render(element(<VirtualizedSectionList
		sections={[group("s1", ["i1.1", "i1.2", "i1.3"]), group("s2", ["i2.1", "i2.2", "i2.3"]), group("s3", ["i3.1", "i3.2", "i3.3"])]}
		getItem={groupItem} getItemCount={groupCount} getItemLayout={cell100} renderItem={itemAt}
		stickySectionHeadersEnabled={sticky} ref={(h: SectionListHandle): void => { handles.push(h); }} />),
		mockHost(), root as unknown as HostNode);
	handles[0].scrollToLocation({ sectionIndex, itemIndex, viewOffset, animated: false });
	const y = root.children[0].scrollY;
	dispose();
	return y;
}

test "scrollToLocation: when sticky stickySectionHeadersEnabled={true}, header height is added to the developer-provided viewOffset" {
	assert scrolledTo(true, 0, 1, 25) === 100 - (25 + 100), "index 1, viewOffset 25 + the 100 px header: " + scrolledTo(true, 0, 1, 25).toString();
	assert scrolledTo(true, 0, 0, 0) === 0, "prevents React Native #18098: the first item adds no header";
	assert scrolledTo(true, 2, 1, 0) === 1100 - 100, "index 11 counts every earlier header and footer";
	assert scrolledTo(false, 2, 1, 0) === 1100, "without sticky headers the viewOffset is the developer's";
}

test "stickySectionHeadersEnabled pins the section header cells, not the items" {
	const root: MockNode = mockNode("root");
	const dispose = render(element(<VirtualizedSectionList sections={[group("s1", ["a"]), group("s2", ["b"])]}
		getItem={groupItem} getItemCount={groupCount} getItemLayout={cell10} renderItem={itemAt}
		renderSectionHeader={header} stickySectionHeadersEnabled={true} />), mockHost(), root as unknown as HostNode);
	const cells = content(root).children;
	assert cells[0].style!.zIndex === 10 && textOf(cells[0]) === "H:s1", "first header: " + textOf(cells[0]);
	assert cells[1].style!.zIndex === null, "item a is not sticky";
	assert cells[3].style!.zIndex === 10 && textOf(cells[3]) === "H:s2", "second header: " + textOf(cells[3]);
	dispose();
}

function sectionTokens(info: SectionViewabilityInfo<Item, Group>): string {
	let out = "";
	for (const token of info.viewableItems) {
		out += token.section.title + ":" + (token.item === null ? "cell" : (token.item as Item).key + "@" + (token.index as number).toString()) + " ";
	}
	return out.trim();
}

test "onViewableItemsChanged reports section-local tokens with their section" {
	const root: MockNode = mockNode("root");
	const calls: string[] = [];
	const dispose = render(element(<VirtualizedSectionList sections={[group("s1", ["a", "b"]), group("s2", ["c"])]}
		getItem={groupItem} getItemCount={groupCount} getItemLayout={cell10} renderItem={itemAt}
		onViewableItemsChanged={(info: SectionViewabilityInfo<Item, Group>): void => { calls.push(sectionTokens(info)); }} />),
		mockHost(), root as unknown as HostNode);
	const e = neonEvent("scroll");
	e.y = 10;
	e.width = 10;
	e.height = 45;
	e.contentWidth = 10;
	e.contentHeight = 70;
	fireEventWith(root.children[0], "onScroll", e);
	assert calls.length === 1 && calls[0] === "s1:a@0 s1:b@1 s1:cell s2:cell s2:c@0", calls.join("|");
	dispose();
}
