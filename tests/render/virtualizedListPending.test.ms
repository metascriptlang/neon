// A VirtualizedList cell whose renderItem reads a pending value under a Loading is built in the compute of the cells' mapArray
// (packages/signals/src/map.ts:362), so the pending read is that compute's pending status and the Loading keeps its fallback.
import { createSignal, Accessor } from "../../src/core/signal";
import { createAsyncMemo } from "../../src/core/memo";
import { element } from "../../src/macros/ui/element";
import { Loading, Show } from "../../src/macros/ui/flow";
import { el, text, NeonNode } from "../../src/render/node";
import { Host, HostNode, MockNode, mockHost, render, mockToString } from "../../src/render/host";
import { Text } from "../../src/components/primitives";
import { VirtualizedList, ListRenderItemInfo } from "../../src/components/virtualizedList";
import { FlatList } from "../../src/components/flatList";
import { Gate, gated, release } from "../core/asyncClock";

interface Item {
	key: string;
}

const loadingB: NeonNode = el("b", [], [], text("loading"));

function pendingNote(gate: Gate, tag: Accessor<string>): Accessor<string> {
	return createAsyncMemo((p: string | null): Promise<string> => gated(gate, "note" + tag()));
}

function readsInMount(note: () => string, rest: () => string): NeonNode {
	return (h: Host, parent: HostNode, before: HostNode | null): void => {
		const v = note();
		element(<Text>{v + rest()}</Text>)(h, parent, before);
	};
}

function list(keys: Accessor<Item[]>, row: (info: ListRenderItemInfo<Item>) => NeonNode): NeonNode {
	return element(<VirtualizedList data={keys()}
		getItem={(d: Item[], index: number): Item => d[index]}
		getItemCount={(d: Item[]): number => d.length}
		renderItem={row} />);
}

function mockRoot(): [Host, HostNode, () => string] {
	const host = mockHost();
	const root = host.createElement("root");
	return [host, root, (): string => mockToString(root as unknown as MockNode)];
}

function has(whole: string, part: string): boolean {
	return whole.indexOf(part) >= 0;
}

test "a VirtualizedList cell that reads a pending value shows the fallback, then the cells, and stays reactive" {
	const gate = new Gate();
	const [tag, setTag] = createSignal("");
	const [tail, setTail] = createSignal("!");
	const [keys, setKeys] = createSignal<Item[]>([{ key: "a" }, { key: "b" }]);
	const [host, root, shown] = mockRoot();
	const app: NeonNode = (h: Host, parent: HostNode, before: HostNode | null): void => {
		const note = pendingNote(gate, tag);
		const row = (info: ListRenderItemInfo<Item>): NeonNode => readsInMount(note, (): string => info.item.key + tail());
		Loading({ children: list(keys, row), fallback: loadingB })(h, parent, before);
	};
	const dispose = render(app, host, root);
	assert shown() === "<root><b>loading</b></root>", "the fallback shows while pending: " + shown();
	await release(gate);
	assert has(shown(), "notea!") && has(shown(), "noteb!"), "both cells show once it landed: " + shown();
	setTail("?");
	assert has(shown(), "notea?") && has(shown(), "noteb?"), "a later write still updates the page: " + shown();
	gate.open = false;
	setTag("2");
	setKeys([{ key: "a" }, { key: "b" }, { key: "c" }]);
	assert has(shown(), "notea?") && !has(shown(), "notec"), "a cell built while the value is pending waits: " + shown();
	await release(gate);
	assert has(shown(), "note2c?"), "a later cell builds once it landed: " + shown();
	setTail("!");
	assert has(shown(), "note2c!") && has(shown(), "note2a!"), "and every cell is alive: " + shown();
	dispose();
}

test "a VirtualizedList nested in a Show leaves with it and comes back" {
	const gate = new Gate();
	const [on, setOn] = createSignal(true);
	const [tag, setTag] = createSignal("");
	const [tail, setTail] = createSignal("!");
	const [keys, setKeys] = createSignal<Item[]>([{ key: "a" }, { key: "b" }]);
	const [host, root, shown] = mockRoot();
	const app: NeonNode = (h: Host, parent: HostNode, before: HostNode | null): void => {
		const note = pendingNote(gate, tag);
		const row = (info: ListRenderItemInfo<Item>): NeonNode => readsInMount(note, (): string => info.item.key + tail());
		Loading({ children: Show({ when: on, children: list(keys, row) }), fallback: loadingB })(h, parent, before);
	};
	const dispose = render(app, host, root);
	assert shown() === "<root><b>loading</b></root>", "the fallback shows while pending: " + shown();
	await release(gate);
	assert has(shown(), "notea!"), "the cells show once it landed: " + shown();
	setOn(false);
	assert shown() === "<root></root>", "the list leaves: " + shown();
	setOn(true);
	setTail("?");
	assert has(shown(), "notea?") && has(shown(), "noteb?"), "and comes back alive: " + shown();
	dispose();
}

test "a two-column grid item that reads a pending value waits for it, then shows, and stays reactive" {
	const gate = new Gate();
	const [tag, setTag] = createSignal("");
	const [tail, setTail] = createSignal("!");
	const [keys, setKeys] = createSignal<Item[]>([{ key: "a" }, { key: "b" }, { key: "c" }]);
	const [host, root, shown] = mockRoot();
	const app: NeonNode = (h: Host, parent: HostNode, before: HostNode | null): void => {
		const note = pendingNote(gate, tag);
		const row = (info: ListRenderItemInfo<Item>): NeonNode => readsInMount(note, (): string => info.item.key + tail());
		Loading({ children: element(<FlatList data={keys()} numColumns={2} renderItem={row} />), fallback: loadingB })(h, parent, before);
	};
	const dispose = render(app, host, root);
	assert shown() === "<root><b>loading</b></root>", "the fallback shows while pending: " + shown();
	await release(gate);
	assert has(shown(), "notea!") && has(shown(), "noteb!") && has(shown(), "notec!"), "every item shows once it landed: " + shown();
	gate.open = false;
	setTag("2");
	setKeys([{ key: "a" }, { key: "b" }, { key: "c" }, { key: "d" }]);
	assert !has(shown(), "noted"), "an item built while the value is pending waits: " + shown();
	await release(gate);
	assert has(shown(), "note2d!"), "the item shows once it landed: " + shown();
	setTail("?");
	assert has(shown(), "note2d?") && has(shown(), "note2a?"), "every item is alive: " + shown();
	dispose();
}
