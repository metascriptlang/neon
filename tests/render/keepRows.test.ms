import { el, text, dynText, regionNode, builtRow, NeonNode } from "../../src/render/node";
import { Host, HostNode, MockNode, mockHost, render, mockToString } from "../../src/render/host";
import { Row } from "../../src/render/reconcile";
import { mapArray } from "../../src/core/array";
import { createMemo } from "../../src/core/memo";
import { createSignal, Accessor } from "../../src/core/signal";
import { runWithOwner } from "../../src/core/owner";
import { getOwner } from "../../src/core/runtime";
import { createList } from "../../src/core/list";
import { ForList } from "../../src/macros/ui/flow";

function shown(node: HostNode): string {
	return mockToString(node as unknown as MockNode);
}

function firstOf(node: HostNode): MockNode {
	return (node as unknown as MockNode).children[0];
}

function countedView(runs: number[]): NeonNode {
	return (h: Host, p: HostNode, before: HostNode | null): void => {
		runs[0] = runs[0] + 1;
		el("p", [], [], text("kept"))(h, p, before);
	};
}

test "a dropped row with a keeper is parked in its holder and comes back as the same nodes" {
	const host = mockHost();
	const holder = host.createElement("holder");
	const runs: number[] = [0];
	let kept: Row | null = null;
	const [on, setOn] = createSignal(true);
	const region = regionNode((h, home) => createMemo<Row[]>(() => {
		if (!on()) { return [] as Row[]; }
		if (kept === null) {
			kept = builtRow(h, home, countedView(runs));
			(kept as Row).keep = holder;
		}
		return [kept as Row];
	}));
	const root = host.createElement("root");
	const dispose = render(region, host, root);
	const row = kept as Row;
	const node = firstOf(root);
	assert shown(root) === "<root><p>kept</p></root>", shown(root);

	setOn(false);
	assert shown(root) === "<root></root>", "the root lost the row: " + shown(root);
	assert shown(holder) === "<holder><p>kept</p></holder>", "the holder took it: " + shown(holder);
	assert firstOf(holder) === node, "parked nodes are the same nodes";
	assert row.parent === holder, "the row records where it is parked";

	setOn(true);
	assert shown(root) === "<root><p>kept</p></root>", shown(root);
	assert shown(holder) === "<holder></holder>", "the holder gave it back: " + shown(holder);
	assert firstOf(root) === node, "the row came back as the same node";
	assert runs[0] === 1, "the view ran once: " + runs[0].toString();
	assert row.parent === root, "the row records its region's parent again";
	dispose();
}

test "a dropped row without a keeper is dead, and a later row builds fresh" {
	const host = mockHost();
	const runs: number[] = [0];
	let shownRow: Row | null = null;
	const [on, setOn] = createSignal(true);
	const region = regionNode((h, home) => createMemo<Row[]>(() => {
		if (!on()) { return [] as Row[]; }
		shownRow = builtRow(h, home, countedView(runs));
		return [shownRow as Row];
	}));
	const root = host.createElement("root");
	const dispose = render(region, host, root);
	const row = shownRow as Row;
	const node = firstOf(root);

	setOn(false);
	assert shown(root) === "<root></root>", shown(root);
	assert row.start === null && row.end === null, "a removed row holds no nodes";

	setOn(true);
	assert shown(root) === "<root><p>kept</p></root>", shown(root);
	assert firstOf(root) !== node, "the row built new nodes instead of reusing dead ones";
	assert runs[0] === 2, "the view ran again: " + runs[0].toString();
	dispose();
}

test "a region at the top of a parked row updates into the holder and shows it when the row returns" {
	const host = mockHost();
	const holder = host.createElement("holder");
	const [items, setItems] = createSignal<string[]>(["a"]);
	const inner = regionNode((h, home) => mapArray<string, Row>(() => items(), (v, i) => builtRow(h, home, el("li", [], [], text(v)))));
	let kept: Row | null = null;
	const [on, setOn] = createSignal(true);
	const region = regionNode((h, home) => {
		const owner = getOwner();
		return createMemo<Row[]>(() => {
			if (!on()) { return [] as Row[]; }
			if (kept === null) {
				kept = runWithOwner(owner, (): Row => builtRow(h, home, inner));
				(kept as Row).keep = holder;
			}
			return [kept as Row];
		});
	});
	const root = host.createElement("root");
	const dispose = render(region, host, root);
	assert shown(root) === "<root><li>a</li></root>", shown(root);

	setOn(false);
	setItems(["a", "b", "c"]);
	assert shown(root) === "<root></root>", "nothing leaked into the old parent: " + shown(root);
	assert shown(holder) === "<holder><li>a</li><li>b</li><li>c</li></holder>", "the update landed in the holder: " + shown(holder);

	setOn(true);
	assert shown(root) === "<root><li>a</li><li>b</li><li>c</li></root>", shown(root);
	assert shown(holder) === "<holder></holder>", shown(holder);

	setItems(["c"]);
	assert shown(root) === "<root><li>c</li></root>", "the region updates in its parent again: " + shown(root);
	dispose();
}

function listItem(item: Accessor<string>): NeonNode {
	return el("li", [], [], dynText((): string => item()));
}

test "a ForList at the top of a parked row updates into the holder and shows it when the row returns" {
	const host = mockHost();
	const holder = host.createElement("holder");
	const items = createList<string>(["a"]);
	let kept: Row | null = null;
	const [on, setOn] = createSignal(true);
	const region = regionNode((h, home) => {
		const owner = getOwner();
		return createMemo<Row[]>(() => {
			if (!on()) { return [] as Row[]; }
			if (kept === null) {
				kept = runWithOwner(owner, (): Row => builtRow(h, home, ForList<string>({ each: items, children: listItem })));
				(kept as Row).keep = holder;
			}
			return [kept as Row];
		});
	});
	const root = host.createElement("root");
	const dispose = render(region, host, root);
	assert shown(root) === "<root><li>a</li></root>", shown(root);

	setOn(false);
	items.push("b");
	items.replaceAll(["c", "b", "a"]);
	assert shown(root) === "<root></root>", "nothing leaked into the old parent: " + shown(root);
	assert shown(holder) === "<holder><li>c</li><li>b</li><li>a</li></holder>", "the update landed in the holder: " + shown(holder);

	setOn(true);
	assert shown(root) === "<root><li>c</li><li>b</li><li>a</li></root>", shown(root);
	items.remove(1);
	assert shown(root) === "<root><li>c</li><li>a</li></root>", "the list updates in its parent again: " + shown(root);
	dispose();
}
