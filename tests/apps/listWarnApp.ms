import { createSignal } from "../../src/core/signal";
import { element } from "../../src/macros/ui/element";
import { NeonNode } from "../../src/render/hostTypes";
import { render, mockHost, mockNode, mockToString, HostNode } from "../../src/render/host";
import { Text } from "../../src/components/primitives";
import { FlatList, ItemLayout, ListRenderItemInfo } from "../../src/components/flatList";

interface Item {
	n: number;
}

function items(count: int32): Item[] {
	const out: Item[] = [];
	for (let i = 0; i < count; i += 1) { out.push({ n: i }); }
	return out;
}

function tall10(data: Item[], index: number): ItemLayout {
	return { length: 10, offset: 10 * index, index };
}

function row(info: ListRenderItemInfo<Item>): NeonNode {
	return element(<Text>{info.item.n.toString()}</Text>);
}

function main(): void {
	const [data, setData] = createSignal<Item[]>(items(10));
	const tooLarge = mockNode("app");
	render(element(<FlatList data={data()} initialScrollIndex={15} initialNumToRender={2}
		getItemLayout={tall10} renderItem={row} />), mockHost(), tooLarge as unknown as HostNode);
	setData(items(10));
	console.log(mockToString(tooLarge));
	const negative = mockNode("app");
	render(element(<FlatList data={items(3)} initialScrollIndex={-1} initialNumToRender={2}
		getItemLayout={tall10} renderItem={row} />), mockHost(), negative as unknown as HostNode);
	console.log(mockToString(negative));
	const valid = mockNode("app");
	render(element(<FlatList data={items(3)} initialScrollIndex={2} initialNumToRender={2}
		getItemLayout={tall10} renderItem={row} />), mockHost(), valid as unknown as HostNode);
	const empty = mockNode("app");
	render(element(<FlatList data={items(0)} initialScrollIndex={4}
		getItemLayout={tall10} renderItem={row} />), mockHost(), empty as unknown as HostNode);
}

main();
