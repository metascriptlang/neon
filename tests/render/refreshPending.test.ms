// A hot-reloaded view that reads a pending value under a Loading: Solid's refresh builds the new component in the memo
// that wraps it (packages/solid/src/refresh/index.ts createProxy), so the pending read is that memo's pending status
// and the Loading keeps what it showed until the value settles.
import { el, text, dynText, NeonNode } from "../../src/render/node";
import { Host, HostNode, MockNode, mockHost, render, mockToString } from "../../src/render/host";
import { Accessor, createSignal } from "../../src/core/signal";
import { createAsyncMemo } from "../../src/core/memo";
import { Loading } from "../../src/macros/ui/flow";
import { refreshTemplate0, refreshRegion, refreshModule, refreshReset } from "../../src/render/refresh";
import { Gate, gated, release } from "../core/asyncClock";

const loadingB: NeonNode = el("b", [], [], text("loading"));

function pendingNote(gate: Gate, tag: Accessor<string>): Accessor<string> {
	return createAsyncMemo((p: string | null): Promise<string> => gated(gate, "note" + tag()));
}

function unit(): boolean {
	return false;
}

function view(label: string, note: (() => string) | null, tail: () => string): (env: boolean) => NeonNode {
	return (env: boolean): NeonNode => (h: Host, parent: HostNode, before: HostNode | null): void => {
		const v = note === null ? label : label + (note as () => string)();
		el("p", [], [], dynText((): string => v + tail()))(h, parent, before);
	};
}

test "a hot-reloaded view that reads a pending value keeps what shows, then swaps in, and stays reactive" {
	refreshReset();
	const gate = new Gate();
	const [tag, setTag] = createSignal("");
	const [tail, setTail] = createSignal("!");
	const host = mockHost();
	const root = host.createElement("root");
	const shown = (): string => mockToString(root as unknown as MockNode);
	refreshTemplate0("app.ms", "r0", view("one:", null, tail), (): string => "v1", unit);
	const app: NeonNode = (h: Host, parent: HostNode, before: HostNode | null): void => {
		Loading({ children: refreshRegion("app.ms", "r0", view("one:", null, tail), (): string => "v1", false), fallback: loadingB })(h, parent, before);
	};
	const dispose = render(app, host, root);
	assert shown() === "<root><p>one:!</p></root>", "v1 shows: " + shown();
	const note = pendingNote(gate, tag);
	gate.open = false;
	setTag("2");
	refreshTemplate0("app.ms", "r0", view("two:", note, tail), (): string => "v2", unit);
	refreshModule("app.ms");
	assert shown() === "<root><p>one:!</p></root>", "v1 stays while v2 waits: " + shown();
	await release(gate);
	assert shown() === "<root><p>two:note2!</p></root>", "v2 shows once it landed: " + shown();
	setTail("?");
	assert shown() === "<root><p>two:note2?</p></root>", "and is reactive: " + shown();
	dispose();
}
