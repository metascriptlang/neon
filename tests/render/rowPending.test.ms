// A Show / For / Match row that reads a pending value under a Loading is built where Solid builds it, in the compute that
// makes the row (packages/solid/src/client/flow.ts:226 Show, packages/signals/src/map.ts:362 mapArray), so the pending read
// is that compute's pending status and the Loading holds its fallback until the value settles.
import { el, text, dynText, NeonNode } from "../../src/render/node";
import { Host, HostNode, MockNode, mockHost, render, mockToString } from "../../src/render/host";
import { Accessor, accessor, createSignal } from "../../src/core/signal";
import { createAsyncMemo } from "../../src/core/memo";
import { Loading, Show, For, ForKeyedBy, Match, Case } from "../../src/macros/ui/flow";
import { Gate, gated, release } from "../core/asyncClock";
import { flush } from "../../src/core/runtime";

const loadingB: NeonNode = el("b", [], [], text("loading"));

function readsInBody(note: () => string, tail: () => string): NeonNode {
	return (h: Host, parent: HostNode, before: HostNode | null): void => {
		const v = note();
		el("p", [], [], dynText((): string => v + tail()))(h, parent, before);
	};
}

function pendingNote(gate: Gate): Accessor<string> {
	return createAsyncMemo((p: string | null): Promise<string> => gated(gate, "note"));
}

function mockRoot(): [Host, HostNode, () => string] {
	const host = mockHost();
	const root = host.createElement("root");
	return [host, root, (): string => mockToString(root as unknown as MockNode)];
}

test "a Show row whose build reads a pending value shows the fallback, then the content, and stays reactive" {
	const gate = new Gate();
	const [on, setOn] = createSignal(true);
	const [tail, setTail] = createSignal("!");
	const [host, root, shown] = mockRoot();
	const app: NeonNode = (h: Host, parent: HostNode, before: HostNode | null): void => {
		const note = pendingNote(gate);
		Loading({ children: Show({ when: on, children: readsInBody(note, tail) }), fallback: loadingB })(h, parent, before);
	};
	const dispose = render(app, host, root);
	assert shown() === "<root><b>loading</b></root>", "the fallback shows while pending: " + shown();
	await release(gate);
	assert shown() === "<root><p>note!</p></root>", "the content shows once it landed: " + shown();
	setTail("?");
	flush();
	assert shown() === "<root><p>note?</p></root>", "a later write still updates the page: " + shown();
	setOn(false);
	flush();
	assert shown() === "<root></root>", "the row leaves: " + shown();
	setOn(true);
	flush();
	assert shown() === "<root><p>note?</p></root>", "and comes back: " + shown();
	dispose();
}

test "a Show row whose fallback reads a pending value holds the Loading fallback too" {
	const gate = new Gate();
	const [on, setOn] = createSignal(false);
	const [tail, setTail] = createSignal("!");
	const [host, root, shown] = mockRoot();
	const app: NeonNode = (h: Host, parent: HostNode, before: HostNode | null): void => {
		const note = pendingNote(gate);
		Loading({ children: Show({ when: on, children: el("i", [], [], text("on")), fallback: readsInBody(note, tail) }), fallback: loadingB })(h, parent, before);
	};
	const dispose = render(app, host, root);
	assert shown() === "<root><b>loading</b></root>", "the fallback shows while pending: " + shown();
	await release(gate);
	assert shown() === "<root><p>note!</p></root>", "the Show fallback shows once it landed: " + shown();
	setOn(true);
	flush();
	assert shown() === "<root><i>on</i></root>", "the content replaces it: " + shown();
	setTail("?");
	flush();
	setOn(false);
	flush();
	assert shown() === "<root><p>note?</p></root>", "and it builds again: " + shown();
	dispose();
}

test "a For row whose build reads a pending value shows the fallback, then every row, and stays reactive" {
	const gate = new Gate();
	const [items, setItems] = createSignal<string[]>(["a", "b"]);
	const [tail, setTail] = createSignal("!");
	const [host, root, shown] = mockRoot();
	const app: NeonNode = (h: Host, parent: HostNode, before: HostNode | null): void => {
		const note = pendingNote(gate);
		const row = (item: string, index: Accessor<number>): NeonNode => readsInBody((): string => note() + item, tail);
		Loading({ children: For({ each: items, children: row }), fallback: loadingB })(h, parent, before);
	};
	const dispose = render(app, host, root);
	assert shown() === "<root><b>loading</b></root>", "the fallback shows while pending: " + shown();
	await release(gate);
	assert shown() === "<root><p>notea!</p><p>noteb!</p></root>", "both rows show once it landed: " + shown();
	setTail("?");
	flush();
	assert shown() === "<root><p>notea?</p><p>noteb?</p></root>", "a later write still updates the page: " + shown();
	setItems(["a", "b", "c"]);
	flush();
	assert shown() === "<root><p>notea?</p><p>noteb?</p><p>notec?</p></root>", "a later row builds: " + shown();
	dispose();
}

test "a For fallback row reads a pending value" {
	const gate = new Gate();
	const [items, setItems] = createSignal<string[]>([]);
	const [tail, setTail] = createSignal("!");
	const [host, root, shown] = mockRoot();
	const app: NeonNode = (h: Host, parent: HostNode, before: HostNode | null): void => {
		const note = pendingNote(gate);
		const row = (item: string, index: Accessor<number>): NeonNode => el("i", [], [], text(item));
		Loading({ children: For({ each: items, children: row, fallback: readsInBody(note, tail) }), fallback: loadingB })(h, parent, before);
	};
	const dispose = render(app, host, root);
	assert shown() === "<root><b>loading</b></root>", "the fallback shows while pending: " + shown();
	await release(gate);
	assert shown() === "<root><p>note!</p></root>", "the empty fallback shows once it landed: " + shown();
	setItems(["a"]);
	flush();
	assert shown() === "<root><i>a</i></root>", "a row replaces it: " + shown();
	dispose();
}

test "a Match arm whose build reads a pending value shows the fallback, then the arm, and stays reactive" {
	const gate = new Gate();
	const [pick, setPick] = createSignal(1);
	const [tail, setTail] = createSignal("!");
	const [host, root, shown] = mockRoot();
	const app: NeonNode = (h: Host, parent: HostNode, before: HostNode | null): void => {
		const note = pendingNote(gate);
		const arms = Match({ cases: [
			Case({ when: accessor((): boolean => pick() === 1), children: readsInBody(note, tail) }),
			Case({ when: accessor((): boolean => pick() === 2), children: el("i", [], [], text("two")) }),
		] });
		Loading({ children: arms, fallback: loadingB })(h, parent, before);
	};
	const dispose = render(app, host, root);
	assert shown() === "<root><b>loading</b></root>", "the fallback shows while pending: " + shown();
	await release(gate);
	assert shown() === "<root><p>note!</p></root>", "the arm shows once it landed: " + shown();
	setTail("?");
	flush();
	assert shown() === "<root><p>note?</p></root>", "a later write still updates the page: " + shown();
	setPick(2);
	flush();
	assert shown() === "<root><i>two</i></root>", "the other arm: " + shown();
	setPick(1);
	flush();
	assert shown() === "<root><p>note?</p></root>", "and back: " + shown();
	dispose();
}

test "a Show inside a Show reads a pending value in its build" {
	const gate = new Gate();
	const [outer, setOuter] = createSignal(true);
	const [inner, setInner] = createSignal(true);
	const [tail, setTail] = createSignal("!");
	const [host, root, shown] = mockRoot();
	const app: NeonNode = (h: Host, parent: HostNode, before: HostNode | null): void => {
		const note = pendingNote(gate);
		const nested = Show({ when: inner, children: readsInBody(note, tail) });
		Loading({ children: Show({ when: outer, children: el("div", [], [], nested) }), fallback: loadingB })(h, parent, before);
	};
	const dispose = render(app, host, root);
	assert shown() === "<root><b>loading</b></root>", "the fallback shows while pending: " + shown();
	await release(gate);
	assert shown() === "<root><div><p>note!</p></div></root>", "both rows show once it landed: " + shown();
	setTail("?");
	flush();
	assert shown() === "<root><div><p>note?</p></div></root>", "a later write still updates the page: " + shown();
	setInner(false);
	flush();
	assert shown() === "<root><div></div></root>", "the inner row leaves: " + shown();
	setInner(true);
	flush();
	setOuter(false);
	flush();
	assert shown() === "<root></root>", "the outer row leaves: " + shown();
	setOuter(true);
	flush();
	assert shown() === "<root><div><p>note?</p></div></root>", "and both come back: " + shown();
	dispose();
}

test "a keyed For reorder after the rows settled moves the same nodes and builds nothing" {
	const gate = new Gate();
	const [items, setItems] = createSignal<string[]>(["a", "b", "c"]);
	const builds = [0];
	const [host, root, shown] = mockRoot();
	const app: NeonNode = (h: Host, parent: HostNode, before: HostNode | null): void => {
		const note = pendingNote(gate);
		const row = (item: Accessor<string>, index: Accessor<number>): NeonNode => (ch: Host, cp: HostNode, cb: HostNode | null): void => {
			const v = note();
			builds[0] = builds[0] + 1;
			el("p", [], [], text(v + item()))(ch, cp, cb);
		};
		Loading({ children: ForKeyedBy({ each: items, keyed: (s: string): string => s, children: row }), fallback: loadingB })(h, parent, before);
	};
	const dispose = render(app, host, root);
	await release(gate);
	assert shown() === "<root><p>notea</p><p>noteb</p><p>notec</p></root>", "settled: " + shown();
	const rowNodes = (): MockNode[] => {
		const found: MockNode[] = [];
		for (const n of (root as unknown as MockNode).children) { if (n.tag === "p") { found.push(n); } }
		return found;
	};
	const before = rowNodes();
	const built = builds[0];
	setItems(["c", "a", "b"]);
	flush();
	assert shown() === "<root><p>notec</p><p>notea</p><p>noteb</p></root>", "reordered: " + shown();
	const after = rowNodes();
	assert after[0] === before[2] && after[1] === before[0] && after[2] === before[1], "the same nodes moved";
	assert builds[0] === built, "no row was built again: " + builds[0].toString() + " vs " + built.toString();
	dispose();
}
