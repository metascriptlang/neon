// Parking on the void host. tests/platform/void.test.ms does not compile while its
// "parseFlexStyle maps numeric + enum keys" cell is parked (BUGS.md), so these cells live here.

import { Accessor, accessor, createSignal } from "../../src/core/signal";
import { createAsyncMemo } from "../../src/core/memo";
import { createRenderEffect } from "../../src/core/effect";
import { Cleanup } from "../../src/core/types";
import { onCleanup } from "../../src/core/cleanup";
import { Errored, Loading } from "../../src/macros/ui/flow";
import { Gate, gated, release } from "../core/asyncClock";
import { render } from "../../src/render/host";
import { Host, HostNode } from "../../src/render/hostTypes";
import { el, text, regionNode, NeonNode } from "../../src/render/node";
import { Row, makeRow } from "../../src/render/reconcile";
import { createMemo } from "../../src/core/memo";
import { createVoidHost, VoidNode } from "../../src/platform/void/host";
import { HOST_PARK_CONTRACT, hostParkContract } from "../render/hostContract";

test "the void host keeps the park contract and release frees the parked nodes" {
	const vh = createVoidHost();
	const got = hostParkContract(vh.host);
	assert got === HOST_PARK_CONTRACT, got;

	const holder = vh.host.createElement("view");
	const parked = vh.host.createElement("view");
	const inner = vh.host.createElement("view");
	vh.host.append(parked, inner);
	vh.host.insertBefore(holder, parked, null);
	assert (parked as VoidNode).ref.isLive(), "a parked node is alive";
	vh.host.release(holder);
	assert !(holder as VoidNode).ref.isLive() && (holder as VoidNode).disposed, "the holder is freed";
	assert !(parked as VoidNode).ref.isLive() && (parked as VoidNode).disposed, "the parked child is freed with it";
	assert !(inner as VoidNode).ref.isLive() && (inner as VoidNode).disposed, "the parked child's subtree is freed with it";
}

test "a dropped row without a keeper is freed on the void host, and a later row mounts fresh" {
	const vh = createVoidHost();
	const row = makeRow(el("view", [], [], text("hi")));
	const [on, setOn] = createSignal(true);
	render(regionNode((h) => createMemo<Row[]>(() => on() ? [row] : [] as Row[])), vh.host, vh.root);
	const first = (vh.root as VoidNode).children[0];
	assert first.ref.isLive(), "the row is alive while shown";

	setOn(false);
	assert (vh.root as VoidNode).children.indexOf(first) < 0, "the row left the root";
	assert first.disposed && !first.ref.isLive(), "the dropped row's node is freed";
	assert first.children[0].disposed, "its subtree is freed";

	setOn(true);
	const second = (vh.root as VoidNode).children[0];
	assert second !== first && second.ref.isLive(), "the row is built again, never revived from freed nodes";
}

function failsWhenOne(a: () => int32): void {
	createRenderEffect<int32>(
		(p: int32 | null): int32 => a(),
		(v: int32, p: int32 | null): Cleanup | null => { if (v === 1) { throw new Error("late"); } return null; },
	);
}

const caughtView = (err: Accessor<Error>, reset: () => void): NeonNode => el("view", [], [], text("caught"));

test "an Errored that fails while its content mounts frees the partial nodes, and reset mounts fresh ones" {
	const vh = createVoidHost();
	let attempts = 0;
	const seen: VoidNode[] = [];
	let again: (() => void) | null = null;
	const content: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		attempts = attempts + 1;
		el("view", [], [], text("partial"))(host, parent, before);
		seen.push((vh.root as VoidNode).children[0]);
		if (attempts < 2) { throw new Error("attempt"); }
	};
	render(Errored({
		children: content,
		fallback: (err: Accessor<Error>, reset: () => void): NeonNode => { again = reset; return caughtView(err, reset); },
	}), vh.host, vh.root);
	assert seen.length === 1 && seen[0].disposed && !seen[0].ref.isLive(), "the partial content is freed, not parked";
	(again as () => void)();
	assert seen.length === 2 && seen[1] !== seen[0] && seen[1].ref.isLive(), "reset built fresh content";
}

test "disposing an Errored with its content parked frees the parked nodes after the content cleanup" {
	const vh = createVoidHost();
	const [a, setA] = createSignal(0);
	let node: VoidNode | null = null;
	let liveAtCleanup = false;
	const content: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		onCleanup(() => { liveAtCleanup = (node as VoidNode).ref.isLive(); });
		failsWhenOne(a);
		el("view", [], [], text("ok"))(host, parent, before);
		node = (vh.root as VoidNode).children[0];
	};
	const dispose = render(Errored({ children: content, fallback: caughtView }), vh.host, vh.root);
	const parked = node as VoidNode;
	setA(1);
	assert parked.ref.isLive() && (vh.root as VoidNode).children.indexOf(parked) < 0, "the content is parked and alive";
	dispose();
	assert liveAtCleanup, "the content cleanup ran while its nodes were alive";
	assert parked.disposed && !parked.ref.isLive(), "the parked nodes are freed with the Errored";
}

test "a focused TextInput in content that gets parked loses focus, and the node survives" {
	const vh = createVoidHost();
	const [a, setA] = createSignal(0);
	let again: (() => void) | null = null;
	const content: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		failsWhenOne(a);
		el("textinput", [], [], text(""))(host, parent, before);
	};
	render(Errored({
		children: content,
		fallback: (err: Accessor<Error>, reset: () => void): NeonNode => { again = reset; return caughtView(err, reset); },
	}), vh.host, vh.root);
	const input = (vh.root as VoidNode).children[0];
	vh.focus(input);
	assert vh.focused() === input, "the input is focused";
	setA(1);
	assert vh.focused() === null, "parking took the focus away";
	assert input.ref.isLive(), "the parked input is alive";
	setA(0);
	(again as () => void)();
	assert (vh.root as VoidNode).children.indexOf(input) >= 0, "the same input came back";
	assert vh.focused() === null, "and is not focused again";
}

test "a Loading whose content read a pending value frees the partial nodes and shows the new ones when it settles" {
	const vh = createVoidHost();
	const gate = new Gate();
	const partial: VoidNode[] = [];
	const content = (data: Accessor<int32>): NeonNode => (host: Host, parent: HostNode, before: HostNode | null): void => {
		el("view", [], [], text("partial"))(host, parent, before);
		partial.push((parent as VoidNode).children[0]);
		const v = data();
		el("view", [], [], text(v.toString()))(host, parent, before);
	};
	const app: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {
		const data = createAsyncMemo((p: int32 | null): Promise<int32> => gated(gate, 7));
		Loading({ children: content(data), fallback: caughtView(accessor((): Error => new Error("x")), (): void => {}) })(host, parent, before);
	};
	const dispose = render(app, vh.host, vh.root);
	assert partial.length === 1 && partial[0].disposed && !partial[0].ref.isLive(), "the first attempt's partial node is freed, not left parked";
	assert (vh.root as VoidNode).children[0].children[0].chars === "caught", "the fallback shows";
	await release(gate);
	assert partial.length === 2 && partial[1].ref.isLive(), "the settled attempt built its own nodes";
	assert (vh.root as VoidNode).children.indexOf(partial[1]) >= 0, "and they are in the root";
	dispose();
}
