// A header Slot row that reads a pending value under a Loading is built in the compute that makes it, like every other region row
// (packages/solid/src/client/flow.ts:226 Show, packages/signals/src/map.ts:362 mapArray), so the pending read is that compute's pending status.
import { el, text, dynText, NeonNode } from "../../src/render/node";
import { Host, HostNode, MockNode, mockHost, render, mockToString } from "../../src/render/host";
import { Accessor, accessor, createSignal } from "../../src/core/signal";
import { createAsyncMemo } from "../../src/core/memo";
import { Loading, Show } from "../../src/macros/ui/flow";
import { Slot } from "../../src/navigation/header";
import { Gate, gated, release } from "../core/asyncClock";

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

test "a header Slot whose node reads a pending value shows the fallback, then the node, and stays reactive" {
	const gate = new Gate();
	const [tail, setTail] = createSignal("!");
	const [host, root, shown] = mockRoot();
	const app: NeonNode = (h: Host, parent: HostNode, before: HostNode | null): void => {
		const note = pendingNote(gate);
		const node = accessor((): NeonNode | null => readsInBody(note, tail));
		Loading({ children: Slot({ node }), fallback: loadingB })(h, parent, before);
	};
	const dispose = render(app, host, root);
	assert shown() === "<root><b>loading</b></root>", "the fallback shows while pending: " + shown();
	await release(gate);
	assert shown() === "<root><p>note!</p></root>", "the node shows once it landed: " + shown();
	setTail("?");
	assert shown() === "<root><p>note?</p></root>", "a later write still updates the page: " + shown();
	dispose();
}

test "a header Slot nested in a Show swaps its node and leaves with it" {
	const gate = new Gate();
	const [on, setOn] = createSignal(true);
	const [which, setWhich] = createSignal(true);
	const [tail, setTail] = createSignal("!");
	const [host, root, shown] = mockRoot();
	const app: NeonNode = (h: Host, parent: HostNode, before: HostNode | null): void => {
		const note = pendingNote(gate);
		const node = accessor((): NeonNode | null => which() ? readsInBody(note, tail) : el("i", [], [], text("other")));
		Loading({ children: Show({ when: on, children: el("div", [], [], Slot({ node })) }), fallback: loadingB })(h, parent, before);
	};
	const dispose = render(app, host, root);
	assert shown() === "<root><b>loading</b></root>", "the fallback shows while pending: " + shown();
	await release(gate);
	assert shown() === "<root><div><p>note!</p></div></root>", "the node shows once it landed: " + shown();
	setWhich(false);
	assert shown() === "<root><div><i>other</i></div></root>", "the other node replaces it: " + shown();
	setWhich(true);
	setTail("?");
	assert shown() === "<root><div><p>note?</p></div></root>", "and back, alive: " + shown();
	setOn(false);
	assert shown() === "<root></root>", "the Show takes it away: " + shown();
	dispose();
}
