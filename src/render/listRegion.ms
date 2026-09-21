import { createEffect } from "../core/effect";
import { onCleanup } from "../core/cleanup";
import { createRoot } from "../core/owner";
import { Accessor, Signal, accessor, untrack } from "../core/signal";
import { List, ListOp, listInsert, listMove, listRemove, listSet } from "../core/list";
import { Host, HostNode, NeonNode } from "./hostTypes";
import { Row, makeRow, place, needsStartMarker, mountAt, moveRow, removeRow, reconcileArrays } from "./reconcile";

// The region's stores live in one object passed to every step, never captured by a nested
// closure: src/core/array.ms keeps mapArray's stores as parameters for the same reason.
interface Region<Item> {
	host: Host;
	parent: HostNode;
	anchor: HostNode;
	list: List<Item>;
	row: (item: Accessor<Item>) => NeonNode;
	// Zero or one key function: a nullable function of Item in a field of this generic interface is
	// the shape that does not reach its Maybe carrier on C
	// (~/metascript/.inbox/compiler/2026-09-21-value-into-a-union-parameter-passes-the-raw-address.md).
	keys: ((item: Item) => number)[];
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
function buildRow<Item>(
	g: Region<Item>,
	v: Item,
	rowStore: Row[],
	cellStore: Signal<Item>[],
	dispStore: (() => void)[],
): void {
	const r = createRoot((d) => {
		dispStore.push(d);
		const cell = new Signal<Item>(v);
		cellStore.push(cell);
		return makeRow(g.row(accessor((): Item => cell.get())));
	});
	rowStore.push(r);
}

function insertRow<Item>(g: Region<Item>, i: number, v: Item): void {
	buildRow<Item>(g, v, g.rows, g.cells, g.disposers);
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

// Each new row takes the old row that carries the same item — by number key when the list has one,
// by item identity otherwise, which is what <For> does. A row's DOM and its reactive scope belong to
// the item, not to the slot, so a replaceAll that reorders moves nodes instead of rewriting values.
function matchByIds<K>(oldIds: K[], newIds: K[], out: number[]): void {
	const byId = new Map<K, number>();
	for (let i = 0; i < oldIds.length; i += 1) {
		const k = oldIds[i];
		if (byId.has(k)) { continue; }
		byId.set(k, i);
	}
	for (let j = 0; j < newIds.length; j += 1) {
		const k = newIds[j];
		if (!byId.has(k)) {
			out[j] = -1;
			continue;
		}
		const at = byId.get(k) as number;
		out[j] = at;
		byId.set(k, -1);
	}
}

function resetTo<Item>(g: Region<Item>, items: Item[]): void {
	const have = g.rows.length;
	const n = items.length;

	const reuse: number[] = [];
	for (let j = 0; j < n; j += 1) { reuse.push(-1); }
	if (g.keys.length > 0) {
		const keyOf = g.keys[0];
		const oldIds: number[] = [];
		for (let i = 0; i < have; i += 1) { oldIds.push(keyOf(g.cells[i].peek())); }
		const newIds: number[] = [];
		const seen = new Map<number, number>();
		for (let j = 0; j < n; j += 1) {
			const k = keyOf(items[j]);
			if (seen.has(k)) {
				throw new Error("ForList: the key " + k.toString() + " is used by rows "
					+ (seen.get(k) as number).toString() + " and " + j.toString());
			}
			seen.set(k, j);
			newIds.push(k);
		}
		matchByIds<number>(oldIds, newIds, reuse);
	} else {
		const oldIds: Item[] = [];
		for (let i = 0; i < have; i += 1) { oldIds.push(g.cells[i].peek()); }
		matchByIds<Item>(oldIds, items, reuse);
	}

	const nextRows: Row[] = [];
	const nextCells: Signal<Item>[] = [];
	const nextDisposers: (() => void)[] = [];
	const kept: boolean[] = [];
	for (let i = 0; i < have; i += 1) { kept.push(false); }

	for (let j = 0; j < n; j += 1) {
		const from = reuse[j];
		if (from < 0) {
			buildRow<Item>(g, items[j], nextRows, nextCells, nextDisposers);
			continue;
		}
		nextRows.push(g.rows[from]);
		nextCells.push(g.cells[from]);
		nextDisposers.push(g.disposers[from]);
		kept[from] = true;
		g.cells[from].set(items[j]);
	}

	for (let i = 0; i < have; i += 1) {
		if (!kept[i]) { g.disposers[i](); }
	}

	reconcileArrays(g.host, g.parent, g.rows, nextRows, g.anchor);
	g.rows = nextRows;
	g.cells = nextCells;
	g.disposers = nextDisposers;
}

function applyOp<Item>(g: Region<Item>, op: ListOp<Item>): void {
	if (op.kind === listInsert) { insertRow<Item>(g, op.a, op.v); return; }
	if (op.kind === listMove) { moveRowTo<Item>(g, op.a, op.b); return; }
	if (op.kind === listRemove) { removeRowAt<Item>(g, op.a); return; }
	if (op.kind === listSet) { g.cells[op.a].set(op.v); return; }
	throw new Error("ForList: list op kind " + op.kind.toString() + " has no region case");
}

export function listRegion<Item>(
	list: List<Item>,
	row: (item: Accessor<Item>) => NeonNode,
	keyOf: ((item: Item) => number) | null,
): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		if (needsStartMarker(parent)) { place(host, parent, host.createText(""), before); }
		const anchor = host.createText("");
		place(host, parent, anchor, before);

		const g: Region<Item> = {
			host: host,
			parent: parent,
			anchor: anchor,
			list: list,
			row: row,
			keys: keyOf === null ? [] : [keyOf as (item: Item) => number],
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
