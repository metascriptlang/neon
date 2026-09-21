import { createEffect } from "../core/effect";
import { onCleanup } from "../core/cleanup";
import { createRoot } from "../core/owner";
import { Accessor, Signal, accessor, untrack } from "../core/signal";
import { List, ListOp, listInsert, listMove, listRemove, listSet } from "../core/list";
import { Host, HostNode, NeonNode } from "./hostTypes";
import { Row, makeRow, place, needsStartMarker, mountAt, moveRow, removeRow } from "./reconcile";

// The region's stores live in one object passed to every step, never captured by a nested
// closure: src/core/array.ms keeps mapArray's stores as parameters for the same reason.
interface Region<Item> {
	host: Host;
	parent: HostNode;
	anchor: HostNode;
	row: (item: Accessor<Item>) => NeonNode;
	rows: Row[];
	cells: Signal<Item>[];
	disposers: (() => void)[];
}

function anchorAt<Item>(g: Region<Item>, i: number): HostNode | null {
	if (i >= g.rows.length) { return g.anchor; }
	return g.rows[i].start;
}

// The stores are filled by push, never by assigning past the end, and the row is appended
// only once its body has run: a slot of an array longer than what it holds is a segfault,
// not an undefined (src/core/array.ms indexArray).
function buildRow<Item>(g: Region<Item>, v: Item): void {
	const r = createRoot((d) => {
		g.disposers.push(d);
		const cell = new Signal<Item>(v);
		g.cells.push(cell);
		return makeRow(g.row(accessor((): Item => cell.get())));
	});
	g.rows.push(r);
}

function insertRow<Item>(g: Region<Item>, i: number, v: Item): void {
	buildRow<Item>(g, v);
	const last = g.rows.length - 1;
	const r = g.rows[last];
	const c = g.cells[last];
	const d = g.disposers[last];
	for (let j = last; j > i; j -= 1) {
		g.rows[j] = g.rows[j - 1];
		g.cells[j] = g.cells[j - 1];
		g.disposers[j] = g.disposers[j - 1];
	}
	g.rows[i] = r;
	g.cells[i] = c;
	g.disposers[i] = d;
	mountAt(g.host, g.parent, anchorAt<Item>(g, i + 1), r);
}

function removeRowAt<Item>(g: Region<Item>, i: number): void {
	g.disposers[i]();
	removeRow(g.host, g.parent, g.rows[i]);
	const last = g.rows.length - 1;
	for (let j = i; j < last; j += 1) {
		g.rows[j] = g.rows[j + 1];
		g.cells[j] = g.cells[j + 1];
		g.disposers[j] = g.disposers[j + 1];
	}
	g.rows.pop();
	g.cells.pop();
	g.disposers.pop();
}

function moveRowTo<Item>(g: Region<Item>, from: number, to: number): void {
	const r = g.rows[from];
	const c = g.cells[from];
	const d = g.disposers[from];
	if (from < to) {
		for (let j = from; j < to; j += 1) {
			g.rows[j] = g.rows[j + 1];
			g.cells[j] = g.cells[j + 1];
			g.disposers[j] = g.disposers[j + 1];
		}
	} else {
		for (let j = from; j > to; j -= 1) {
			g.rows[j] = g.rows[j - 1];
			g.cells[j] = g.cells[j - 1];
			g.disposers[j] = g.disposers[j - 1];
		}
	}
	g.rows[to] = r;
	g.cells[to] = c;
	g.disposers[to] = d;
	moveRow(g.host, g.parent, r, anchorAt<Item>(g, to + 1));
}

function resetTo<Item>(g: Region<Item>, items: Item[]): void {
	const n = items.length;
	const have = g.rows.length;
	const keep = have < n ? have : n;
	for (let i = 0; i < keep; i += 1) { g.cells[i].set(items[i]); }
	for (let i = have - 1; i >= n; i -= 1) { removeRowAt<Item>(g, i); }
	for (let i = have; i < n; i += 1) { insertRow<Item>(g, i, items[i]); }
}

function applyOp<Item>(g: Region<Item>, op: ListOp<Item>): void {
	if (op.kind === listInsert) { insertRow<Item>(g, op.a, op.v); return; }
	if (op.kind === listMove) { moveRowTo<Item>(g, op.a, op.b); return; }
	if (op.kind === listRemove) { removeRowAt<Item>(g, op.a); return; }
	if (op.kind === listSet) { g.cells[op.a].set(op.v); return; }
	throw new Error("ForList: list op kind " + op.kind.toString() + " has no region case");
}

export function listRegion<Item>(list: List<Item>, row: (item: Accessor<Item>) => NeonNode): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		if (needsStartMarker(parent)) { place(host, parent, host.createText(""), before); }
		const anchor = host.createText("");
		place(host, parent, anchor, before);

		const g: Region<Item> = {
			host: host,
			parent: parent,
			anchor: anchor,
			row: row,
			rows: [],
			cells: [],
			disposers: [],
		};

		const q = list.attach();
		onCleanup(() => {
			list.detach(q);
			for (const d of g.disposers) { d(); }
		});

		const initial = untrack((): Item[] => list.read());
		for (let i = 0; i < initial.length; i += 1) { insertRow<Item>(g, i, initial[i]); }

		createEffect(() => {
			const items = list.read();
			untrack((): number => {
				if (q.reset) {
					resetTo<Item>(g, items);
				} else {
					for (let k = 0; k < q.ops.length; k += 1) { applyOp<Item>(g, q.ops[k]); }
				}
				q.ops = [];
				q.reset = false;
				return 0;
			});
		});
	};
}
