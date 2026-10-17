// A ForList row that reads a pending value under a Loading is built in the compute that takes the list's ops, as mapArray builds a row in its
// computed (packages/signals/src/map.ts:362); the region effect only moves it in, so the pending read is the compute's pending status.
import { el, text, dynText, NeonNode } from "../../src/render/node";
import { Host, HostNode, MockNode, mockHost, render, mockToString } from "../../src/render/host";
import { Accessor, createSignal } from "../../src/core/signal";
import { createAsyncMemo } from "../../src/core/memo";
import { createList } from "../../src/core/list";
import { Loading, Show, ForList } from "../../src/macros/ui/flow";
import { Gate, gatedStr, release } from "../core/asyncClock";

const loadingB: NeonNode = el("b", [], [], text("loading"));

function pendingNote(gate: Gate, tag: Accessor<string>): Accessor<string> {
	return createAsyncMemo((p: string | null): Promise<string> => gatedStr(gate, "note" + tag()));
}

function rowOf(note: () => string, tail: () => string): (item: Accessor<string>) => NeonNode {
	return (item: Accessor<string>): NeonNode => (h: Host, parent: HostNode, before: HostNode | null): void => {
		const v = note();
		el("p", [], [], dynText((): string => v + item() + tail()))(h, parent, before);
	};
}

function mockRoot(): [Host, HostNode, () => string] {
	const host = mockHost();
	const root = host.createElement("root");
	return [host, root, (): string => mockToString(root as unknown as MockNode)];
}

test "a ForList row built while its value is pending waits for it, then shows, and every row stays reactive" {
	const gate = new Gate();
	const [tag, setTag] = createSignal("");
	const [tail, setTail] = createSignal("!");
	const items = createList<string>(["a", "b"]);
	const [host, root, shown] = mockRoot();
	const app: NeonNode = (h: Host, parent: HostNode, before: HostNode | null): void => {
		const note = pendingNote(gate, tag);
		Loading({ children: ForList({ each: items, children: rowOf(note, tail) }), fallback: loadingB })(h, parent, before);
	};
	const dispose = render(app, host, root);
	assert shown() === "<root><b>loading</b></root>", "the fallback shows while pending: " + shown();
	await release(gate);
	assert shown() === "<root><p>notea!</p><p>noteb!</p></root>", "both rows show once it landed: " + shown();
	gate.open = false;
	setTag("2");
	items.push("c");
	assert shown() === "<root><p>notea!</p><p>noteb!</p></root>", "a row built while the value is pending waits: " + shown();
	await release(gate);
	assert shown() === "<root><p>notea!</p><p>noteb!</p><p>note2c!</p></root>", "the row shows once it landed: " + shown();
	setTail("?");
	assert shown() === "<root><p>notea?</p><p>noteb?</p><p>note2c?</p></root>", "every row is alive: " + shown();
	dispose();
}

test "a ForList replaceAll that drops and reorders rows while a value is pending waits, then applies" {
	const gate = new Gate();
	const [tag, setTag] = createSignal("");
	const [tail, setTail] = createSignal("!");
	const items = createList<string>(["a", "b", "c"]);
	const [host, root, shown] = mockRoot();
	const app: NeonNode = (h: Host, parent: HostNode, before: HostNode | null): void => {
		const note = pendingNote(gate, tag);
		Loading({ children: ForList({ each: items, children: rowOf(note, tail) }), fallback: loadingB })(h, parent, before);
	};
	const dispose = render(app, host, root);
	await release(gate);
	assert shown() === "<root><p>notea!</p><p>noteb!</p><p>notec!</p></root>", "settled: " + shown();
	gate.open = false;
	setTag("2");
	items.replaceAll(["c", "d", "a"]);
	assert shown() === "<root><p>notea!</p><p>noteb!</p><p>notec!</p></root>", "the replace waits: " + shown();
	await release(gate);
	assert shown() === "<root><p>notec!</p><p>note2d!</p><p>notea!</p></root>", "the same rows moved, one was built, one left: " + shown();
	setTail("?");
	assert shown() === "<root><p>notec?</p><p>note2d?</p><p>notea?</p></root>", "every row is alive: " + shown();
	dispose();
}

test "a ForList nested in a Show builds a row while pending and leaves with the Show" {
	const gate = new Gate();
	const [on, setOn] = createSignal(true);
	const [tag, setTag] = createSignal("");
	const [tail, setTail] = createSignal("!");
	const items = createList<string>(["a"]);
	const [host, root, shown] = mockRoot();
	const app: NeonNode = (h: Host, parent: HostNode, before: HostNode | null): void => {
		const note = pendingNote(gate, tag);
		Loading({ children: Show({ when: on, children: el("div", [], [], ForList({ each: items, children: rowOf(note, tail) })) }), fallback: loadingB })(h, parent, before);
	};
	const dispose = render(app, host, root);
	await release(gate);
	assert shown() === "<root><div><p>notea!</p></div></root>", "settled: " + shown();
	gate.open = false;
	setTag("2");
	items.insert(0, "z");
	assert shown() === "<root><div><p>notea!</p></div></root>", "the insert waits: " + shown();
	await release(gate);
	assert shown() === "<root><div><p>note2z!</p><p>notea!</p></div></root>", "the row lands first: " + shown();
	setOn(false);
	assert shown() === "<root></root>", "the Show takes the list away: " + shown();
	dispose();
}
