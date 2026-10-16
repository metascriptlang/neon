// Loading keeps its content behind the fallback while it is pending and moves the same row in when it settles
// (Solid: packages/solid/src/client/flow.ts:512 Loading over packages/signals/src/boundaries.ts:739 createLoadingBoundary, without `on`).
import { el, text, dynText, NeonNode } from "../../src/render/node";
import { Host, HostNode, MockNode, mockHost, render, mockToString } from "../../src/render/host";
import { Accessor, createSignal } from "../../src/core/signal";
import { createAsyncMemo } from "../../src/core/memo";
import { Loading } from "../../src/macros/ui/flow";
import { Gate, gated, release } from "../core/asyncClock";

function nodeOf(n: HostNode, tag: string): MockNode {
	const m = n as unknown as MockNode;
	for (const c of m.children) {
		if (c.tag === tag) { return c; }
	}
	throw "no <" + tag + "> under " + mockToString(m);
}

const loadingB: NeonNode = el("b", [], [], text("loading"));

test "pending content shows the fallback and then the same nodes, and its body ran once" {
	const gate = new Gate();
	const bodyRuns = [0];
	const made: MockNode[] = [];
	const host = mockHost();
	const root = host.createElement("root");
	const shown = (): string => mockToString(root as unknown as MockNode);
	const app: NeonNode = (h: Host, parent: HostNode, before: HostNode | null): void => {
		const data = createAsyncMemo((p: int32 | null): Promise<int32> => gated(gate, 101));
		const content: NeonNode = (ch: Host, cp: HostNode, cb: HostNode | null): void => {
			bodyRuns[0] = bodyRuns[0] + 1;
			el("p", [], [], dynText((): string => data().toString()))(ch, cp, cb);
			made.push((cp as unknown as MockNode).children[0]);
		};
		Loading({ children: content, fallback: loadingB })(h, parent, before);
	};
	const dispose = render(app, host, root);
	assert shown().includes("<b>loading</b>") && !shown().includes("<p>"), "the fallback shows while pending: " + shown();
	await release(gate);
	assert shown().includes("<p>101</p>") && !shown().includes("loading"), "the content shows once it landed: " + shown();
	assert nodeOf(root, "p") === made[0], "the content is the node mounted while pending";
	assert bodyRuns[0] === 1, "the body ran once: " + bodyRuns[0].toString();
	dispose();
}

test "a refetch after the content settled keeps it shown" {
	let gate = new Gate();
	const [id, setId] = createSignal<int32>(1);
	const host = mockHost();
	const root = host.createElement("root");
	const shown = (): string => mockToString(root as unknown as MockNode);
	const app: NeonNode = (h: Host, parent: HostNode, before: HostNode | null): void => {
		const data = createAsyncMemo((p: int32 | null): Promise<int32> => gated(gate, id()));
		Loading({ children: el("p", [], [], dynText((): string => data().toString())), fallback: loadingB })(h, parent, before);
	};
	const dispose = render(app, host, root);
	await release(gate);
	assert shown().includes("<p>1</p>"), "settled: " + shown();
	const node = nodeOf(root, "p");
	gate = new Gate();
	setId(2);
	assert shown().includes("<p>") && !shown().includes("loading"), "the refetch keeps the content visible: " + shown();
	await release(gate);
	assert shown().includes("<p>2</p>") && nodeOf(root, "p") === node, "the same node shows the new value: " + shown();
	dispose();
}

test "content whose body reads a pending value is mounted again when it settles, and the partial nodes are gone" {
	const gate = new Gate();
	const bodyRuns = [0];
	const host = mockHost();
	const root = host.createElement("root");
	const shown = (): string => mockToString(root as unknown as MockNode);
	const app: NeonNode = (h: Host, parent: HostNode, before: HostNode | null): void => {
		const data = createAsyncMemo((p: int32 | null): Promise<int32> => gated(gate, 7));
		const content: NeonNode = (ch: Host, cp: HostNode, cb: HostNode | null): void => {
			bodyRuns[0] = bodyRuns[0] + 1;
			el("i", [], [], text("partial"))(ch, cp, cb);
			const v = data();
			el("p", [], [], text(v.toString()))(ch, cp, cb);
		};
		Loading({ children: content, fallback: loadingB })(h, parent, before);
	};
	const dispose = render(app, host, root);
	assert shown() === "<root><b>loading</b></root>", "the fallback shows and the partial nodes are not in the tree: " + shown();
	await release(gate);
	assert shown() === "<root><i>partial</i><p>7</p></root>", "one copy of the content, from the new tree: " + shown();
	assert bodyRuns[0] === 2, "the body ran again for the new tree: " + bodyRuns[0].toString();
	dispose();
}

test "a Loading without a fallback shows nothing while pending" {
	const gate = new Gate();
	const host = mockHost();
	const root = host.createElement("root");
	const shown = (): string => mockToString(root as unknown as MockNode);
	const app: NeonNode = (h: Host, parent: HostNode, before: HostNode | null): void => {
		const data = createAsyncMemo((p: int32 | null): Promise<int32> => gated(gate, 5));
		Loading({ children: el("p", [], [], dynText((): string => data().toString())) })(h, parent, before);
	};
	const dispose = render(app, host, root);
	assert !shown().includes("<p>"), "nothing yet: " + shown();
	await release(gate);
	assert shown().includes("<p>5</p>"), "the content: " + shown();
	dispose();
}

test "disposing a Loading that is still pending releases the content parked in its holder" {
	const gate = new Gate();
	const released: string[] = [];
	const host = mockHost();
	const releaseOne = host.release;
	host.release = (node: HostNode): void => { released.push((node as unknown as MockNode).children.length.toString()); releaseOne(node); };
	const root = host.createElement("root");
	const app: NeonNode = (h: Host, parent: HostNode, before: HostNode | null): void => {
		const data = createAsyncMemo((p: int32 | null): Promise<int32> => gated(gate, 5));
		Loading({ children: el("p", [], [], dynText((): string => data().toString())), fallback: loadingB })(h, parent, before);
	};
	const dispose = render(app, host, root);
	dispose();
	assert released.join(",") === "1", "one release, of a holder that held the content: " + released.join(",");
}
