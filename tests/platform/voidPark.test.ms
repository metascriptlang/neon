// Parking on the void host. tests/platform/void.test.ms does not compile while its
// "parseFlexStyle maps numeric + enum keys" cell is parked (BUGS.md), so these cells live here.

import { createSignal } from "../../src/core/signal";
import { render } from "../../src/render/host";
import { el, text, regionNode } from "../../src/render/node";
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
