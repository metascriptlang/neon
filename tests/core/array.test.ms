import { mapArray, mapArrayKeyedBy, mapArrayByPosition, repeat, smallMoveHits } from "../../src/core/array";
import { createSignal, accessor, Accessor, Setter } from "../../src/core/signal";
import { createRoot, runWithOwner } from "../../src/core/owner";
import { getOwner, flush } from "../../src/core/runtime";
import { onCleanup } from "../../src/core/cleanup";
import { createRenderEffect } from "../../src/core/effect";
import { createMemo } from "../../src/core/memo";
import { Cleanup, Computation, Dispose } from "../../src/core/types";

class Scope {
	owner: Computation | null;
	dispose: Dispose;

	constructor() {
		this.owner = null;
		this.dispose = (): void => {};
	}
}

function openScope(): Scope {
	const scope = new Scope();
	createRoot((dispose: Dispose): number => {
		scope.owner = getOwner();
		scope.dispose = dispose;
		return 0;
	});
	return scope;
}

function failure(fn: () => void): string {
	let caught = "";
	try { fn(); } catch (e) { caught = e.toString(); }
	flush();
	return caught;
}

interface Id {
	id: string;
}

interface Item {
	id: number;
	label: string;
}

class Mapped {
	id: string;
	index: Accessor<number>;

	constructor(id: string, index: Accessor<number>) {
		this.id = id;
		this.index = index;
	}
}

class Slot {
	item: Accessor<Id>;
	index: Accessor<number>;

	constructor(item: Accessor<Id>, index: Accessor<number>) {
		this.item = item;
		this.index = index;
	}
}

class Labelled {
	label: Accessor<string>;

	constructor(label: Accessor<string>) {
		this.label = label;
	}
}

class Positioned {
	value: Accessor<number>;
	index: number;

	constructor(value: Accessor<number>, index: number) {
		this.value = value;
		this.index = index;
	}
}

class Windowed {
	index: number;
	items: Accessor<Id[]>;

	constructor(index: number, items: Accessor<Id[]>) {
		this.index = index;
		this.items = items;
	}

	id(): string {
		return this.items()[this.index].id;
	}
}

test "mapArray.test.ts:3 default mode passes the raw item and an index accessor, and keeps a row per identity" {
	const scope = openScope();
	const ia: Id = { id: "a" };
	const ib: Id = { id: "b" };
	const ic: Id = { id: "c" };
	const [src, setSrc] = createSignal<Id[]>([ia, ib, ic]);
	let computed = 0;
	const m = runWithOwner(scope.owner, () => mapArray<Id, Mapped>(src, (v, i) => { computed = computed + 1; return new Mapped(v.id, i); }));
	const first = m();
	const a = first[0];
	const b = first[1];
	const c = first[2];
	assert a.id === "a" && a.index() === 0, "row a";
	assert b.id === "b" && b.index() === 1, "row b";
	assert c.id === "c" && c.index() === 2, "row c";
	assert computed === 3, "three rows built";

	setSrc([ib, ia, ic]);
	flush();
	const second = m();
	assert second[0].id === "b" && second[0].index() === 0, "b moved to 0 and its index followed";
	assert second[1].id === "a" && second[1].index() === 1, "a moved to 1 and its index followed";
	assert second[2].id === "c" && second[2].index() === 2, "c stayed";
	assert second[1] === a && second[0] === b && second[2] === c, "rows are the same objects";
	assert computed === 3, "a reorder builds nothing";

	const id: Id = { id: "d" };
	setSrc([ib, ia, ic, id]);
	flush();
	const third = m();
	assert third.length === 4 && third[3].id === "d" && third[3].index() === 3, "d appended at 3";
	assert computed === 4, "one build for d";

	setSrc([ia, ic, id]);
	flush();
	const fourth = m();
	assert fourth.length === 3 && fourth[0] === a, "b removed, a keeps its row";
	assert computed === 4, "a removal builds nothing";

	setSrc([]);
	flush();
	assert m().length === 0, "emptied";
	assert computed === 4, "emptying builds nothing";
	scope.dispose();
}

test "mapArray.test.ts:277 default mode hands the row the very item, not a copy or an accessor" {
	createRoot((d) => {
		const item: Id = { id: "a" };
		const [src, setSrc] = createSignal<Id[]>([item]);
		let received: Id | null = null;
		mapArray<Id, string>(src, (v, i) => { received = v; return v.id; })();
		assert received === item, "the row received the item itself";
		d();
	});
}

test "mapArray.test.ts:76 a consumer that reads the mapped list re-runs when the list changes" {
	const scope = openScope();
	const [src, setSrc] = createSignal<number[]>([1, 2, 3]);
	const m = runWithOwner(scope.owner, () => mapArray<number, number>(src, (v, i) => v));
	let runs = 0;
	let seen = 0;
	runWithOwner(scope.owner, (): number => {
		createRenderEffect<int32>(
			(p: int32 | null): int32 => m().length,
			(n: int32, p: int32 | null): Cleanup | null => { seen = n; runs = runs + 1; return null; },
		);
		return 0;
	});
	assert runs === 1 && seen === 3, "first run";
	setSrc([2, 3]);
	flush();
	assert runs === 2 && seen === 2, "re-ran once with the shorter list";
	scope.dispose();
}

test "map.ts:493 default mode pairs equal items by occurrence order" {
	const scope = openScope();
	const [src, setSrc] = createSignal<number[]>([7, 7, 7, 1]);
	let built = 0;
	let disposed = 0;
	const m = runWithOwner(scope.owner, () => mapArray<number, number>(src, (v, i) => {
		built = built + 1;
		const at = built;
		onCleanup(() => { disposed = disposed + 1; });
		return at;
	}));
	const first = m();
	assert first.length === 4 && built === 4, "four rows";
	setSrc([7, 7, 1]);
	flush();
	const second = m();
	assert second[0] === first[0] && second[1] === first[1] && second[2] === first[3], "the first two 7 rows and the 1 row stay";
	assert built === 4, "nothing rebuilt";
	assert disposed === 1, "the third 7 row is the one that goes: " + disposed.toString();
	setSrc([1, 7, 7, 7, 7]);
	flush();
	const third = m();
	assert third[0] === first[3] && third[1] === first[0] && third[2] === first[1], "survivors keep their rows";
	assert built === 6, "two new 7 rows";
	scope.dispose();
}

test "mapArray creates new, disposes removed" {
	const scope = openScope();
	const [src, setSrc] = createSignal<number[]>([1, 2, 3]);
	let calls = 0;
	let disposed = 0;
	const m = runWithOwner(scope.owner, () => mapArray<number, number>(src, (v, i) => {
		calls = calls + 1;
		onCleanup(() => { disposed = disposed + 1; });
		return v;
	}));
	m();
	setSrc([1, 2, 3, 4]);
	flush();
	m();
	assert calls === 4 && disposed === 0, "one new for 4, none disposed";
	setSrc([1, 2]);
	flush();
	m();
	assert calls === 4 && disposed === 2, "two rows disposed";
	scope.dispose();
}

test "mapArray index reflects a move when read before AND after the move" {
	const scope = openScope();
	const [src, setSrc] = createSignal<number[]>([1, 2, 3]);
	const m = runWithOwner(scope.owner, () => mapArray<number, Accessor<number>>(src, (v, i) => i));
	const out = m();
	assert out[0]() === 0, "early read creates the signal";
	setSrc([2, 1, 3]);
	flush();
	m();
	assert out[0]() === 1, "the same accessor reads the new index";
	scope.dispose();
}

test "map.ts:358 default mode fallback shows on empty, is dropped when rows return and rebuilt on the next empty" {
	const scope = openScope();
	const [src, setSrc] = createSignal<number[]>([]);
	let fbBuilt = 0;
	let fbDisposed = 0;
	const m = runWithOwner(scope.owner, () => mapArray<number, string>(src, (v, i) => v.toString(), () => {
		fbBuilt = fbBuilt + 1;
		onCleanup(() => { fbDisposed = fbDisposed + 1; });
		return "empty";
	}));
	assert m().join(",") === "empty" && fbBuilt === 1, "fallback from the start";
	assert m().join(",") === "empty" && fbBuilt === 1, "a second pass over an empty list builds it once";
	setSrc([1, 2]);
	flush();
	assert m().join(",") === "1,2" && fbDisposed === 1, "rows replace the fallback and dispose it";
	setSrc([]);
	flush();
	assert m().join(",") === "empty" && fbBuilt === 2, "rebuilt on the next empty";
	setSrc([3]);
	flush();
	assert m().join(",") === "3" && fbDisposed === 2, "dropped again";
	scope.dispose();
}

test "map.ts:111 a row that throws mid-pass commits nothing and disposes only the rows that pass built" {
	const scope = openScope();
	const [src, setSrc] = createSignal<number[]>([1, 2, 3]);
	let armed = false;
	const live: boolean[] = [false, false, false, false, false, false];
	let built = 0;
	let disposed = 0;
	const m = runWithOwner(scope.owner, () => mapArray<number, number>(src, (v, i) => {
		if (armed && v === 4) { throw new Error("row 4"); }
		built = built + 1;
		live[v] = true;
		onCleanup(() => { disposed = disposed + 1; live[v] = false; });
		return v;
	}));
	const before = m();
	assert built === 3, "three rows";
	armed = true;
	setSrc([3, 5, 4, 1]);
	flush();
	const caught = failure(() => { m(); });
	assert caught.includes("row 4"), "the row's error reaches the reader: " + caught;
	assert disposed === 1 && live[5] === false, "only the row built in the aborted pass (5) was disposed: " + disposed.toString();
	assert live[1] && live[2] && live[3], "surviving rows are untouched, including the one the new list drops (2)";
	armed = false;
	setSrc([3, 5, 4, 1]);
	flush();
	const after = m();
	assert after.length === 4 && after[0] === 3 && after[1] === 5 && after[2] === 4 && after[3] === 1, "the retry maps the new list";
	assert live[1] && !live[2] && live[3] && live[4] && live[5], "balance after the retry: " + disposed.toString();
	assert built === 3 + 1 + 1 + 1, "the retry built 5 and 4, the aborted pass had built 5: " + built.toString();
	scope.dispose();
}

test "mapArray lets a row that throws reach the reader" {
	createRoot((d) => {
		const [src, setSrc] = createSignal<number[]>([1, 2, 3]);
		const m = mapArray<number, number>(src, (v, i) => { throw new Error("row " + v.toString()); });
		const caught = failure(() => { m(); });
		assert caught.includes("row 1"), "the first row is the one that raised: " + caught;
		d();
	});
}

test "mapArray disposes every row when its owner is disposed" {
	let disposed = 0;
	createRoot((outer) => {
		const [src, setSrc] = createSignal<number[]>([1, 2, 3]);
		const m = mapArray<number, number>(src, (v, i) => { onCleanup(() => { disposed = disposed + 1; }); return v; });
		m();
		outer();
	});
	assert disposed === 3, "all three rows disposed with the owner: " + disposed.toString();
}

test "mapArray.test.ts:96 keyed false passes an item accessor and a plain index, rows live per position" {
	const scope = openScope();
	const [src, setSrc] = createSignal<number[]>([1, 2, 3]);
	let computed = 0;
	const m = runWithOwner(scope.owner, () => mapArrayByPosition<number, Positioned>(src, (v, i) => { computed = computed + 1; return new Positioned(v, i); }));
	const first = m();
	const a = first[0];
	const b = first[1];
	const c = first[2];
	assert a.index === 0 && a.value() === 1, "row 0";
	assert b.index === 1 && b.value() === 2, "row 1";
	assert c.index === 2 && c.value() === 3, "row 2";
	assert computed === 3, "three rows";

	setSrc([3, 2, 1]);
	flush();
	const second = m();
	assert second[0] === a && second[1] === b && second[2] === c, "rows stay at their positions";
	assert a.value() === 3 && b.value() === 2 && c.value() === 1, "values changed in place";
	assert computed === 3, "no rebuild";

	setSrc([3, 2, 1, 4]);
	flush();
	const third = m();
	assert third.length === 4 && third[3].index === 3 && third[3].value() === 4, "append builds one row";
	assert computed === 4, "one build";

	setSrc([2, 1, 4]);
	flush();
	const fourth = m();
	assert fourth.length === 3 && fourth[0] === a && a.value() === 2, "shrink keeps the head rows and rewrites their values";

	setSrc([]);
	flush();
	assert m().length === 0, "emptied";
	assert computed === 4, "no builds on shrink";
	scope.dispose();
}

test "mapArray.test.ts:290 keyed false keeps a row's value accessor live across a reorder" {
	const scope = openScope();
	const [src, setSrc] = createSignal<string[]>(["a", "b"]);
	let first: Accessor<string> | null = null;
	const m = runWithOwner(scope.owner, () => mapArrayByPosition<string, number>(src, (v, i) => {
		if (i === 0) { first = v; }
		return i;
	}));
	m();
	assert (first as Accessor<string>)() === "a", "first value";
	setSrc(["b", "a"]);
	flush();
	m();
	assert (first as Accessor<string>)() === "b", "the first row's accessor follows its slot";
	scope.dispose();
}

test "map.ts:358 keyed false fallback shows on empty and yields to rows" {
	const scope = openScope();
	const [src, setSrc] = createSignal<number[]>([]);
	const m = runWithOwner(scope.owner, () => mapArrayByPosition<number, string>(src, (v, i) => v().toString(), () => "empty"));
	assert m().join(",") === "empty", "fallback";
	setSrc([4, 5]);
	flush();
	assert m().join(",") === "4,5", "rows";
	setSrc([]);
	flush();
	assert m().join(",") === "empty", "fallback again";
	scope.dispose();
}

test "mapArray.test.ts:198 keyed by a function passes accessors for both arguments and keeps a row per key" {
	const scope = openScope();
	const [src, setSrc] = createSignal<Id[]>([{ id: "a" }, { id: "b" }, { id: "c" }]);
	let computed = 0;
	const m = runWithOwner(scope.owner, () => mapArrayKeyedBy<Id, string, Slot>(src, (x) => x.id, (item, i) => { computed = computed + 1; return new Slot(item, i); }));
	const first = m();
	const a = first[0];
	const b = first[1];
	const c = first[2];
	assert a.item().id === "a" && a.index() === 0, "row a";
	assert c.item().id === "c" && c.index() === 2, "row c";
	assert computed === 3, "three rows";

	setSrc([{ id: "b" }, { id: "a" }, { id: "c" }]);
	flush();
	const second = m();
	assert second[0] === b && second[1] === a && second[2] === c, "the rows of the same keys moved, fresh objects notwithstanding";
	assert a.index() === 1 && b.index() === 0, "index accessors followed";
	assert computed === 3, "a reorder builds nothing";

	setSrc([{ id: "b" }, { id: "a" }, { id: "c" }, { id: "d" }]);
	flush();
	const third = m();
	assert third.length === 4 && third[3].item().id === "d" && third[3].index() === 3, "d appended";
	assert computed === 4, "one build";

	setSrc([{ id: "a" }, { id: "c" }, { id: "d" }]);
	flush();
	const fourth = m();
	assert fourth.length === 3 && fourth[0] === a, "b removed";
	assert computed === 4, "nothing rebuilt";

	setSrc([]);
	flush();
	assert m().length === 0, "emptied";
	scope.dispose();
}

test "BUGS.md <For key> keyed by a function updates the kept row's item in place when the key stays" {
	const scope = openScope();
	const [src, setSrc] = createSignal<Item[]>([{ id: 1, label: "a" }, { id: 2, label: "b" }]);
	let calls = 0;
	const m = runWithOwner(scope.owner, () => mapArrayKeyedBy<Item, number, Labelled>(src, (r) => r.id, (item, i) => {
		calls = calls + 1;
		return new Labelled(accessor((): string => item().label));
	}));
	const out = m();
	assert out[0].label() === "a" && out[1].label() === "b", "initial labels";
	setSrc([{ id: 2, label: "b2" }, { id: 1, label: "a2" }]);
	flush();
	const out2 = m();
	assert out2[0].label() === "b2" && out2[1].label() === "a2", "the rows moved and show the new items: " + out2[0].label() + "," + out2[1].label();
	assert out2[0] === out[1] && out2[1] === out[0], "they are the same rows";
	assert calls === 2, "no row was rebuilt";
	scope.dispose();
}

test "keyed by a function writes an item replaced under a kept key at every position: prefix, window and suffix" {
	const scope = openScope();
	const [src, setSrc] = createSignal<Item[]>([
		{ id: 1, label: "p" }, { id: 2, label: "w1" }, { id: 3, label: "w2" }, { id: 4, label: "s" },
	]);
	const m = runWithOwner(scope.owner, () => mapArrayKeyedBy<Item, number, Labelled>(src, (r) => r.id, (item, i) => new Labelled(accessor((): string => item().label))));
	const out = m();
	setSrc([
		{ id: 1, label: "p2" }, { id: 3, label: "w2b" }, { id: 2, label: "w1b" }, { id: 4, label: "s2" },
	]);
	flush();
	const out2 = m();
	assert out2[0].label() === "p2", "prefix row rewritten: " + out2[0].label();
	assert out2[1].label() === "w2b" && out2[2].label() === "w1b", "window rows rewritten: " + out2[1].label() + "," + out2[2].label();
	assert out2[3].label() === "s2", "suffix row rewritten: " + out2[3].label();
	assert out2[1] === out[2] && out2[2] === out[1], "window rows swapped, not rebuilt";
	scope.dispose();
}

test "map.ts:493 keyed by a function pairs rows that share a key by occurrence order" {
	const scope = openScope();
	const [src, setSrc] = createSignal<Item[]>([{ id: 1, label: "x" }, { id: 1, label: "y" }, { id: 2, label: "z" }]);
	let built = 0;
	let disposed = 0;
	const m = runWithOwner(scope.owner, () => mapArrayKeyedBy<Item, number, Labelled>(src, (r) => r.id, (item, i) => {
		built = built + 1;
		onCleanup(() => { disposed = disposed + 1; });
		return new Labelled(accessor((): string => item().label));
	}));
	const first = m();
	assert first.length === 3 && built === 3, "a shared key does not raise";
	setSrc([{ id: 2, label: "z2" }, { id: 1, label: "x2" }]);
	flush();
	const second = m();
	assert second[0] === first[2] && second[1] === first[0], "the earlier row of key 1 is the one that stays";
	assert second[0].label() === "z2" && second[1].label() === "x2", "both rewritten";
	assert built === 3 && disposed === 1, "the later row of key 1 went";
	scope.dispose();
}

test "keyed by a function takes a string key as well as a number key" {
	const scope = openScope();
	const [src, setSrc] = createSignal<Id[]>([{ id: "x" }, { id: "y" }]);
	let built = 0;
	const m = runWithOwner(scope.owner, () => mapArrayKeyedBy<Id, string, Slot>(src, (r) => r.id, (item, i) => { built = built + 1; return new Slot(item, i); }));
	const first = m();
	setSrc([{ id: "y" }, { id: "z" }, { id: "x" }]);
	flush();
	const second = m();
	assert second[0] === first[1] && second[2] === first[0], "string keys match across fresh objects";
	assert built === 3, "only z is new";
	assert second[1].item().id === "z", "z mapped";
	scope.dispose();
}

test "keyed by a function keeps the index accessor right across insert and remove" {
	const scope = openScope();
	const [src, setSrc] = createSignal<Item[]>([{ id: 1, label: "a" }, { id: 2, label: "b" }]);
	const m = runWithOwner(scope.owner, () => mapArrayKeyedBy<Item, number, Accessor<number>>(src, (r) => r.id, (item, i) => i));
	const out = m();
	assert out[0]() === 0, "first row reads index 0";
	setSrc([{ id: 3, label: "c" }, { id: 1, label: "a" }, { id: 2, label: "b" }]);
	flush();
	const out2 = m();
	assert out2[0]() === 0 && out2[1]() === 1 && out2[2]() === 2, "the inserted key sits at 0 and the others followed";
	setSrc([{ id: 2, label: "b" }]);
	flush();
	const out3 = m();
	assert out3.length === 1 && out3[0]() === 0, "the survivor reads index 0";
	scope.dispose();
}

test "keyed by a function disposes every row when the list empties" {
	const scope = openScope();
	const [src, setSrc] = createSignal<Item[]>([{ id: 1, label: "a" }, { id: 2, label: "b" }]);
	let disposed = 0;
	const m = runWithOwner(scope.owner, () => mapArrayKeyedBy<Item, number, number>(src, (r) => r.id, (item, i) => { onCleanup(() => { disposed = disposed + 1; }); return 0; }));
	m();
	setSrc([]);
	flush();
	assert m().length === 0 && disposed === 2, "both rows disposed: " + disposed.toString();
	scope.dispose();
}

test "map.ts:358 keyed by a function fallback shows on empty and yields to rows" {
	const scope = openScope();
	const [src, setSrc] = createSignal<Item[]>([]);
	const m = runWithOwner(scope.owner, () => mapArrayKeyedBy<Item, number, string>(src, (r) => r.id, (item, i) => item().label, () => "empty"));
	assert m().join(",") === "empty", "fallback";
	setSrc([{ id: 1, label: "a" }]);
	flush();
	assert m().join(",") === "a", "rows";
	scope.dispose();
}

test "repeat.test.ts:11 repeat builds one row per index and keeps rows when only the count changes" {
	const scope = openScope();
	const [src, setSrc] = createSignal<Id[]>([{ id: "a" }, { id: "b" }, { id: "c" }]);
	let computed = 0;
	const m = runWithOwner(scope.owner, () => repeat<Windowed>(() => src().length, (i) => { computed = computed + 1; return new Windowed(i, src); }));
	const first = m();
	const a = first[0];
	const b = first[1];
	const c = first[2];
	assert a.id() === "a" && a.index === 0, "row 0";
	assert c.id() === "c" && c.index === 2, "row 2";
	assert computed === 3, "three rows";

	setSrc([{ id: "b" }, { id: "a" }, { id: "c" }]);
	flush();
	const second = m();
	assert second[0] === a && second[1] === b && second[2] === c, "same count keeps every row";
	assert a.id() === "b" && b.id() === "a", "rows read the data at their index";
	assert computed === 3, "no rebuild";

	setSrc([{ id: "b" }, { id: "a" }, { id: "c" }, { id: "d" }]);
	flush();
	const third = m();
	assert third.length === 4 && third[3].index === 3 && third[3].id() === "d", "a fourth row";
	assert computed === 4, "one build";

	setSrc([{ id: "b" }, { id: "a" }, { id: "c" }]);
	flush();
	const fourth = m();
	assert fourth.length === 3 && fourth[0] === a, "pop keeps the head rows";
	assert computed === 4, "no build";

	setSrc([]);
	flush();
	assert m().length === 0 && computed === 4, "emptied";
	scope.dispose();
}

test "repeat.test.ts:94 a consumer that reads the repeated list re-runs when the count changes" {
	const scope = openScope();
	const [n, setN] = createSignal<number>(3);
	const m = runWithOwner(scope.owner, () => repeat<number>(n, (i) => i));
	let runs = 0;
	let seen = 0;
	runWithOwner(scope.owner, (): number => {
		createRenderEffect<int32>(
			(p: int32 | null): int32 => m().length,
			(n: int32, p: int32 | null): Cleanup | null => { seen = n; runs = runs + 1; return null; },
		);
		return 0;
	});
	assert runs === 1 && seen === 3, "first run";
	setN(2);
	flush();
	assert runs === 2 && seen === 2, "re-ran with the smaller count";
	scope.dispose();
}

test "repeat.test.ts:187 repeat disposes the rows that leave the window when from advances from a non-zero offset" {
	const scope = openScope();
	const [from, setFrom] = createSignal<number>(1);
	const cleanups: number[] = [];
	const m = runWithOwner(scope.owner, () => repeat<number>(() => 3, (i) => { onCleanup(() => { cleanups.push(i); }); return i; }, from));
	assert m().join(",") === "1,2,3", "window 1..3";
	setFrom(3);
	flush();
	assert m().join(",") === "3,4,5", "window 3..5";
	assert cleanups.length === 2 && cleanups.includes(1) && cleanups.includes(2), "rows 1 and 2 left, row 3 stayed: " + cleanups.join(",");
	scope.dispose();
}

test "repeat.test.ts:212 repeat retains instances when only from changes" {
	const scope = openScope();
	const [count, setCount] = createSignal<number>(3);
	const [from, setFrom] = createSignal<number>(0);
	let computed = 0;
	const m = runWithOwner(scope.owner, () => repeat<number>(count, (i) => { computed = computed + 1; return i; }, from));
	assert m().join(",") === "0,1,2" && computed === 3, "initial";
	setFrom(2);
	flush();
	assert m().join(",") === "2,3,4" && computed === 5, "slide to 2: rows 3 and 4 are new";
	setFrom(1);
	flush();
	assert m().join(",") === "1,2,3" && computed === 6, "slide back to 1: only row 1 is new";
	setCount(4);
	flush();
	assert m().join(",") === "1,2,3,4" && computed === 7, "grow: only row 4 is new";
	scope.dispose();
}

test "repeat.test.ts:288 repeat recovers when count goes to 0, from changes, and count comes back nonzero" {
	const scope = openScope();
	const [count, setCount] = createSignal<number>(2);
	const [from, setFrom] = createSignal<number>(2);
	const m = runWithOwner(scope.owner, () => repeat<number>(count, (i) => i, from));
	assert m().join(",") === "2,3", "initial";
	setCount(0);
	flush();
	assert m().length === 0, "cleared";
	setFrom(0);
	flush();
	setCount(1);
	flush();
	assert m().join(",") === "0", "row 0 after the offset reset";
	scope.dispose();
}

test "repeat.test.ts:317 repeat slides the window backwards: departing rows are disposed, the overlap is retained" {
	const scope = openScope();
	const [from, setFrom] = createSignal<number>(3);
	const disposed: number[] = [];
	const m = runWithOwner(scope.owner, () => repeat<Windowed>(() => 3, (i) => { onCleanup(() => { disposed.push(i); }); return new Windowed(i, accessor((): Id[] => [])); }, from));
	const first = m();
	assert first[0].index === 3 && first[2].index === 5, "window 3..5";
	const retained = first[0];
	setFrom(1);
	flush();
	const second = m();
	assert second[0].index === 1 && second[1].index === 2 && second[2].index === 3, "window 1..3";
	assert second[2] === retained, "the overlap row is the same instance, now at the tail";
	assert disposed.length === 2 && disposed.includes(4) && disposed.includes(5), "only the departing rows were disposed: " + disposed.join(",");
	scope.dispose();
}

test "repeat.test.ts:378 disjoint window jumps build only the window and do not accumulate live rows" {
	const scope = openScope();
	const [from, setFrom] = createSignal<number>(0);
	let created = 0;
	let cleaned = 0;
	const m = runWithOwner(scope.owner, () => repeat<number>(() => 3, (i) => { created = created + 1; onCleanup(() => { cleaned = cleaned + 1; }); return i; }, from));
	assert m().join(",") === "0,1,2" && created - cleaned === 3, "initial window";
	setFrom(10);
	flush();
	assert m().join(",") === "10,11,12" && created - cleaned === 3, "forward jump";
	setFrom(20);
	flush();
	assert m().join(",") === "20,21,22" && created - cleaned === 3, "second jump";
	setFrom(0);
	flush();
	assert m().join(",") === "0,1,2" && created - cleaned === 3, "backward jump";
	scope.dispose();
}

test "repeat.test.ts:403 repeat with a non-zero from on the first pass maps only the window" {
	createRoot((d) => {
		const [from, setFrom] = createSignal<number>(10);
		let created = 0;
		const m = repeat<number>(() => 3, (i) => { created = created + 1; return i; }, from);
		assert m().join(",") === "10,11,12" && created === 3, "only the window was built";
		d();
	});
}

test "map.ts:661 repeat fallback shows when count is 0 and yields to rows" {
	const scope = openScope();
	const [n, setN] = createSignal<number>(0);
	let fbBuilt = 0;
	let fbDisposed = 0;
	const m = runWithOwner(scope.owner, () => repeat<string>(n, (i) => i.toString(), null, () => {
		fbBuilt = fbBuilt + 1;
		onCleanup(() => { fbDisposed = fbDisposed + 1; });
		return "empty";
	}));
	assert m().join(",") === "empty" && m().join(",") === "empty" && fbBuilt === 1, "fallback built once";
	setN(2);
	flush();
	assert m().join(",") === "0,1" && fbDisposed === 1, "rows replace the fallback";
	setN(0);
	flush();
	assert m().join(",") === "empty" && fbBuilt === 2, "fallback again";
	scope.dispose();
}

test "map.ts:692 repeat that throws mid-pass commits nothing and disposes only what the pass built" {
	const scope = openScope();
	const [n, setN] = createSignal<number>(2);
	let armed = false;
	let disposed = 0;
	const m = runWithOwner(scope.owner, () => repeat<number>(n, (i) => {
		if (armed && i === 3) { throw new Error("row 3"); }
		onCleanup(() => { disposed = disposed + 1; });
		return i;
	}));
	m();
	armed = true;
	setN(5);
	flush();
	const caught = failure(() => { m(); });
	assert caught.includes("row 3"), "the error reaches the reader: " + caught;
	assert disposed === 1, "only row 2, built by the aborted pass, was disposed: " + disposed.toString();
	armed = false;
	setN(4);
	flush();
	assert m().join(",") === "0,1,2,3", "the retry keeps rows 0 and 1";
	scope.dispose();
}

test "repeat refuses a count that is not a non-negative integer" {
	const scope = openScope();
	const [first, setFirst] = createSignal<number>(2.5);
	const fractional = runWithOwner(scope.owner, () => repeat<number>(first, (i) => i));
	let caught = failure(() => { fractional(); });
	assert caught.includes("Repeat: count"), "a fractional count at creation named: " + caught;
	const [n, setN] = createSignal<number>(2);
	let built = 0;
	const m = runWithOwner(scope.owner, () => repeat<number>(n, (i) => { built = built + 1; return i; }));
	assert m().join(",") === "0,1", "a whole count maps";
	setN(2.5);
	flush();
	caught = failure(() => { m(); });
	assert caught.includes("Repeat: count"), "a fractional count written later named: " + caught;
	setN(-1);
	flush();
	caught = failure(() => { m(); });
	assert caught.includes("Repeat: count"), "a negative count written later named: " + caught;
	setN(2);
	flush();
	assert m().join(",") === "0,1" && built === 2, "the refused counts left the rows as they were: " + built.toString();
	scope.dispose();
}

test "repeat disposes every row when its owner is disposed" {
	let disposed = 0;
	createRoot((outer) => {
		const m = repeat<number>(() => 3, (i) => { onCleanup(() => { disposed = disposed + 1; }); return i; });
		m();
		outer();
	});
	assert disposed === 3, "all rows disposed with the owner: " + disposed.toString();
}

class Tracked {
	id: number;
	value: number;
	item: Accessor<number>;
	index: Accessor<number>;

	constructor(id: number, value: number, item: Accessor<number>, index: Accessor<number>) {
		this.id = id;
		this.value = value;
		this.item = item;
		this.index = index;
	}
}

let seed: int64 = 20261015;

function pick(n: number): number {
	seed = (seed * 48271) % 2147483647;
	return (seed % (n as int64)) as number;
}

function nextList(prev: number[], distinct: boolean): number[] {
	const out: number[] = [];
	for (const v of prev) { out.push(v); }
	const ops = 1 + pick(3);
	for (let k = 0; k < ops; k += 1) {
		const op = pick(6);
		if (op === 0 && out.length > 0) {
			out.splice(pick(out.length), 1);
		} else if (op === 1) {
			out.splice(pick(out.length + 1), 0, distinct ? 100 + pick(1000000) : pick(6));
		} else if (op === 2 && out.length > 1) {
			for (let i = out.length - 1; i > 0; i -= 1) {
				const j = pick(i + 1);
				const t = out[i];
				out[i] = out[j];
				out[j] = t;
			}
		} else if (op === 3 && out.length > 1) {
			const from = pick(out.length);
			const moved = out[from];
			out.splice(from, 1);
			out.splice(pick(out.length + 1), 0, moved);
		} else if (op === 4 && pick(8) === 0) {
			out.splice(0, out.length);
		} else if (op === 5 && out.length > 0) {
			out[pick(out.length)] = distinct ? 100 + pick(1000000) : pick(6);
		}
	}
	return out;
}

function noDuplicates(list: number[]): number[] {
	const seen = new Map<number, boolean>();
	const out: number[] = [];
	for (const v of list) {
		if (!seen.has(v)) { seen.set(v, true); out.push(v); }
	}
	return out;
}

test "map.ts:391 default mode survives random edits: every row maps its item, none leaks, none is disposed twice" {
	const scope = openScope();
	const [src, setSrc] = createSignal<number[]>([1, 2, 3]);
	const gone: boolean[] = [];
	let live = 0;
	const m = runWithOwner(scope.owner, () => mapArray<number, Tracked>(src, (v, i) => {
		const id = gone.length;
		gone.push(false);
		live = live + 1;
		onCleanup(() => {
			assert !gone[id], "row " + id.toString() + " disposed twice";
			gone[id] = true;
			live = live - 1;
		});
		return new Tracked(id, v, accessor((): number => v), i);
	}));
	m();
	let cur: number[] = [1, 2, 3];
	for (let step = 0; step < 400; step += 1) {
		cur = nextList(cur, false);
		setSrc(cur);
		flush();
		const out = m();
		assert out.length === cur.length, "step " + step.toString() + ": length";
		assert live === cur.length, "step " + step.toString() + ": live rows " + live.toString() + " for " + cur.length.toString() + " items";
		for (let j = 0; j < cur.length; j += 1) {
			assert out[j].value === cur[j], "step " + step.toString() + ": row " + j.toString() + " maps its item";
			assert out[j].index() === j, "step " + step.toString() + ": row " + j.toString() + " index";
		}
	}
	scope.dispose();
}

test "map.ts:391 keyed by a function survives random edits: rows follow keys, items and indexes are current" {
	const scope = openScope();
	const [src, setSrc] = createSignal<Item[]>([{ id: 1, label: "1.0" }, { id: 2, label: "2.0" }]);
	const gone: boolean[] = [];
	const serialOfKey = new Map<number, number>();
	let live = 0;
	let version = 0;
	const m = runWithOwner(scope.owner, () => mapArrayKeyedBy<Item, number, Tracked>(src, (r) => r.id, (item, i) => {
		const id = gone.length;
		gone.push(false);
		live = live + 1;
		serialOfKey.set(item().id, id);
		onCleanup(() => {
			assert !gone[id], "row " + id.toString() + " disposed twice";
			gone[id] = true;
			live = live - 1;
		});
		return new Tracked(id, item().id, accessor((): number => item().label.length), i);
	}));
	m();
	let keys: number[] = [1, 2];
	for (let step = 0; step < 400; step += 1) {
		keys = noDuplicates(nextList(keys, false));
		version = version + 1;
		const items: Item[] = [];
		for (const k of keys) { items.push({ id: k, label: k.toString() + "." + version.toString() }); }
		const before = new Map<number, number>();
		for (const k of keys) { if (serialOfKey.has(k) && !gone[serialOfKey.get(k) as number]) { before.set(k, serialOfKey.get(k) as number); } }
		setSrc(items);
		flush();
		const out = m();
		assert out.length === keys.length, "step " + step.toString() + ": length";
		assert live === keys.length, "step " + step.toString() + ": live rows " + live.toString() + " for " + keys.length.toString() + " keys";
		for (let j = 0; j < keys.length; j += 1) {
			assert out[j].value === keys[j], "step " + step.toString() + ": slot " + j.toString() + " holds the row of its key";
			assert out[j].index() === j, "step " + step.toString() + ": slot " + j.toString() + " index";
			assert out[j].item() === items[j].label.length, "step " + step.toString() + ": slot " + j.toString() + " shows the current item";
			if (before.has(keys[j])) { assert out[j].id === before.get(keys[j]) as number, "step " + step.toString() + ": key " + keys[j].toString() + " kept its row"; }
		}
	}
	scope.dispose();
}

test "map.ts:391 keyed false survives random edits: rows stay per position and show the current value" {
	const scope = openScope();
	const [src, setSrc] = createSignal<number[]>([1, 2, 3]);
	const gone: boolean[] = [];
	let live = 0;
	const m = runWithOwner(scope.owner, () => mapArrayByPosition<number, Tracked>(src, (v, i) => {
		const id = gone.length;
		gone.push(false);
		live = live + 1;
		onCleanup(() => {
			assert !gone[id], "row " + id.toString() + " disposed twice";
			gone[id] = true;
			live = live - 1;
		});
		return new Tracked(id, i, v, accessor((): number => i));
	}));
	let prev = m();
	let cur: number[] = [1, 2, 3];
	for (let step = 0; step < 400; step += 1) {
		cur = nextList(cur, false);
		setSrc(cur);
		flush();
		const out = m();
		assert out.length === cur.length, "step " + step.toString() + ": length";
		assert live === cur.length, "step " + step.toString() + ": live rows " + live.toString() + " for " + cur.length.toString() + " items";
		for (let j = 0; j < cur.length; j += 1) {
			assert out[j].value === j, "step " + step.toString() + ": row " + j.toString() + " position";
			assert out[j].item() === cur[j], "step " + step.toString() + ": row " + j.toString() + " shows the current value";
			if (j < prev.length) { assert out[j].id === prev[j].id, "step " + step.toString() + ": row " + j.toString() + " kept"; }
		}
		prev = out;
	}
	scope.dispose();
}

class Plain {
	id: number;
	value: number;

	constructor(id: number, value: number) {
		this.id = id;
		this.value = value;
	}
}

test "map.ts:75 default mode told the row never reads its index refuses a row that does" {
	createRoot((d) => {
		const [src, setSrc] = createSignal<number[]>([1, 2]);
		const m = mapArray<number, number>(src, (v, i) => i(), null, false);
		const caught = failure(() => { m(); });
		assert caught.includes("no index accessor"), "reading the index of a row emitted as index-free raises: " + caught;
		d();
	});
}

test "map.ts:97 keyed by a function told the row never reads its index refuses a row that does" {
	createRoot((d) => {
		const [src, setSrc] = createSignal<Item[]>([{ id: 1, label: "a" }]);
		const m = mapArrayKeyedBy<Item, number, number>(src, (r) => r.id, (item, i) => i(), null, false);
		const caught = failure(() => { m(); });
		assert caught.includes("no index accessor"), "reading the index of a row emitted as index-free raises: " + caught;
		d();
	});
}

test "map.ts:330 told the row reads its index, both modes keep the live index" {
	const scope = openScope();
	const [ids, setIds] = createSignal<number[]>([5, 6, 7]);
	const byIdentity = runWithOwner(scope.owner, () => mapArray<number, Mapped>(ids, (v, i) => new Mapped(v.toString(), i), null, true));
	const [items, setItems] = createSignal<Item[]>([{ id: 1, label: "a" }, { id: 2, label: "b" }]);
	const byKey = runWithOwner(scope.owner, () => mapArrayKeyedBy<Item, number, Mapped>(items, (r) => r.id, (item, i) => new Mapped(item().id.toString(), i), null, true));
	const a = byIdentity();
	const b = byKey();
	setIds([7, 5]);
	flush();
	setItems([{ id: 2, label: "b" }, { id: 1, label: "a" }]);
	flush();
	const a2 = byIdentity();
	const b2 = byKey();
	assert a2[0].index() === 0 && a2[1].index() === 1, "identity rows follow the reorder";
	assert b2[0].index() === 0 && b2[1].index() === 1, "keyed rows follow the reorder";
	assert a[0] === a2[1] && b[0] === b2[1], "the rows were kept, only their index moved";
	scope.dispose();
}

test "map.ts:330 default mode without the index reorders, rebuilds the empty fallback and disposes" {
	const scope = openScope();
	const [src, setSrc] = createSignal<number[]>([1, 2, 3]);
	let built = 0;
	let disposed = 0;
	const m = runWithOwner(scope.owner, () => mapArray<number, number>(src, (v, i) => { built = built + 1; onCleanup(() => { disposed = disposed + 1; }); return v * 10; }, () => -1, false));
	const out = m();
	assert out[0] === 10 && out[2] === 30, "mapped without an index";
	setSrc([3, 1, 2]);
	flush();
	const out2 = m();
	assert built === 3, "a reorder builds nothing: " + built.toString();
	assert out2[0] === 30 && out2[1] === 10 && out2[2] === 20, "rows followed the reorder";
	setSrc([2]);
	flush();
	assert m()[0] === 20 && disposed === 2, "removed rows disposed: " + disposed.toString();
	setSrc([]);
	flush();
	assert m()[0] === -1 && disposed === 3, "the fallback shows and the last row is gone: " + disposed.toString();
	setSrc([4, 5]);
	flush();
	const out3 = m();
	assert out3.length === 2 && out3[1] === 50 && built === 5, "rows return after the fallback: " + built.toString();
	scope.dispose();
}

test "map.ts:330 keyed by a function without the index keeps rows per key and the item live" {
	const scope = openScope();
	const [src, setSrc] = createSignal<Item[]>([{ id: 1, label: "a" }, { id: 2, label: "b" }, { id: 3, label: "c" }]);
	let built = 0;
	let disposed = 0;
	const m = runWithOwner(scope.owner, () => mapArrayKeyedBy<Item, number, Labelled>(src, (r) => r.id, (item, i) => { built = built + 1; onCleanup(() => { disposed = disposed + 1; }); return new Labelled(accessor((): string => item().label)); }, () => new Labelled(accessor((): string => "empty")), false));
	const out = m();
	setSrc([{ id: 3, label: "c2" }, { id: 1, label: "a" }, { id: 4, label: "d" }]);
	flush();
	const out2 = m();
	assert built === 4, "only key 4 is new: " + built.toString();
	assert disposed === 1, "only key 2 is gone: " + disposed.toString();
	assert out2[0] === out[2] && out2[1] === out[0], "rows follow their keys";
	assert out2[0].label() === "c2" && out2[2].label() === "d", "kept rows show the current item";
	setSrc([]);
	flush();
	assert m()[0].label() === "empty" && disposed === 4, "the fallback shows after the last row: " + disposed.toString();
	scope.dispose();
}

test "map.ts:391 default mode without the index survives random edits: every row maps its item, none leaks" {
	const scope = openScope();
	const [src, setSrc] = createSignal<number[]>([1, 2, 3]);
	const gone: boolean[] = [];
	let live = 0;
	const m = runWithOwner(scope.owner, () => mapArray<number, Plain>(src, (v, i) => {
		const id = gone.length;
		gone.push(false);
		live = live + 1;
		onCleanup(() => {
			assert !gone[id], "row " + id.toString() + " disposed twice";
			gone[id] = true;
			live = live - 1;
		});
		return new Plain(id, v);
	}, null, false));
	m();
	let cur: number[] = [1, 2, 3];
	for (let step = 0; step < 400; step += 1) {
		cur = nextList(cur, false);
		setSrc(cur);
		flush();
		const out = m();
		assert out.length === cur.length, "step " + step.toString() + ": length";
		assert live === cur.length, "step " + step.toString() + ": live rows " + live.toString() + " for " + cur.length.toString() + " items";
		for (let j = 0; j < cur.length; j += 1) {
			assert out[j].value === cur[j], "step " + step.toString() + ": row " + j.toString() + " maps its item";
		}
	}
	scope.dispose();
}

test "map.ts:391 keyed by a function without the index survives random edits: rows follow keys and items" {
	const scope = openScope();
	const [src, setSrc] = createSignal<Item[]>([{ id: 1, label: "1.0" }, { id: 2, label: "2.0" }]);
	const gone: boolean[] = [];
	const serialOfKey = new Map<number, number>();
	let live = 0;
	let version = 0;
	const m = runWithOwner(scope.owner, () => mapArrayKeyedBy<Item, number, Tracked>(src, (r) => r.id, (item, i) => {
		const id = gone.length;
		gone.push(false);
		live = live + 1;
		serialOfKey.set(item().id, id);
		onCleanup(() => {
			assert !gone[id], "row " + id.toString() + " disposed twice";
			gone[id] = true;
			live = live - 1;
		});
		return new Tracked(id, item().id, accessor((): number => item().label.length), accessor((): number => 0));
	}, null, false));
	m();
	let keys: number[] = [1, 2];
	for (let step = 0; step < 400; step += 1) {
		keys = noDuplicates(nextList(keys, false));
		version = version + 1;
		const items: Item[] = [];
		for (const k of keys) { items.push({ id: k, label: k.toString() + "." + version.toString() }); }
		const before = new Map<number, number>();
		for (const k of keys) { if (serialOfKey.has(k) && !gone[serialOfKey.get(k) as number]) { before.set(k, serialOfKey.get(k) as number); } }
		setSrc(items);
		flush();
		const out = m();
		assert out.length === keys.length, "step " + step.toString() + ": length";
		assert live === keys.length, "step " + step.toString() + ": live rows " + live.toString() + " for " + keys.length.toString() + " keys";
		for (let j = 0; j < keys.length; j += 1) {
			assert out[j].value === keys[j], "step " + step.toString() + ": slot " + j.toString() + " holds the row of its key";
			assert out[j].item() === items[j].label.length, "step " + step.toString() + ": slot " + j.toString() + " shows the current item";
			if (before.has(keys[j])) { assert out[j].id === before.get(keys[j]) as number, "step " + step.toString() + ": key " + keys[j].toString() + " kept its row"; }
		}
	}
	scope.dispose();
}

class Ledger {
	log: string[];

	constructor() {
		this.log = [];
	}

	build(id: number): void {
		const log = this.log;
		log.push("+" + id.toString());
		onCleanup(() => { log.push("-" + id.toString()); });
	}

	count(mark: string, id: number): number {
		const want = mark + id.toString();
		let n = 0;
		for (const entry of this.log) { if (entry === want) { n += 1; } }
		return n;
	}

	made(id: number): number {
		return this.count("+", id);
	}

	live(id: number): number {
		return this.count("+", id) - this.count("-", id);
	}
}

function ensure(ok: boolean, why: string): void {
	if (!ok) { throw new Error(why); }
}

class Fault {
	bad: number[];

	constructor() {
		this.bad = [];
	}

	check(v: number): void {
		for (const b of this.bad) {
			if (b === v) { throw new Error("row " + v.toString()); }
		}
	}
}

function engine(mode: number, src: Accessor<number[]>, led: Ledger, fault: Fault, fallback: (() => number) | null): () => number[] {
	if (mode === 0) {
		return mapArray<number, number>(src, (v, i) => { led.build(v); fault.check(v); return v; }, fallback, false);
	}
	return mapArrayKeyedBy<number, number, number>(src, (x) => x, (item, i) => {
		const v = item();
		led.build(v);
		fault.check(v);
		return v;
	}, fallback, false);
}

function allGone(led: Ledger, ids: number[]): void {
	for (const id of ids) { ensure(led.live(id) === 0, "row " + id.toString() + " is disposed when the list is: " + led.live(id).toString()); }
}

function survivorsKeepTheirOwners(mode: number): void {
	const scope = openScope();
	const led = new Ledger();
	const fault = new Fault();
	const [src, setSrc] = createSignal<number[]>([1, 2, 3]);
	const m = runWithOwner(scope.owner, () => engine(mode, src, led, fault, null));
	const before = m();
	ensure(before.join(",") === "1,2,3", "first pass");
	fault.bad = [9];
	setSrc([3, 9, 1, 2]);
	flush();
	const caught = failure(() => { m(); });
	ensure(caught.includes("row 9"), "the row's error reaches the reader: " + caught);
	ensure(led.live(1) === 1 && led.live(2) === 1 && led.live(3) === 1, "surviving rows keep their owners");
	ensure(led.made(9) === 1 && led.live(9) === 0, "the owner the aborted pass created is disposed with it");
	setSrc([1, 2, 3]);
	flush();
	ensure(m() === before, "the engine still holds the list from before the aborted pass");
	fault.bad = [];
	setSrc([3, 9, 1, 2]);
	flush();
	ensure(m().join(",") === "3,9,1,2", "the retry maps the new list");
	ensure(led.made(1) === 1 && led.made(2) === 1 && led.made(3) === 1, "no surviving row is rebuilt");
	ensure(led.made(9) === 2 && led.live(9) === 1, "the failed row is built again by the retry");
	scope.dispose();
	allGone(led, [1, 2, 3, 9]);
}

function removalWhileStillFailing(mode: number): void {
	const scope = openScope();
	const led = new Ledger();
	const fault = new Fault();
	const [src, setSrc] = createSignal<number[]>([1, 2, 3]);
	const m = runWithOwner(scope.owner, () => engine(mode, src, led, fault, null));
	m();
	fault.bad = [9];
	setSrc([1, 2, 9, 3]);
	flush();
	ensure(failure(() => { m(); }).includes("row 9"), "a failing insert before 3 aborts");
	setSrc([1, 2, 9]);
	flush();
	ensure(failure(() => { m(); }).includes("row 9"), "dropping 3 while 9 still fails aborts again");
	ensure(led.live(3) === 1, "an aborted pass disposes no row it removes");
	fault.bad = [];
	setSrc([1, 2, 9]);
	flush();
	ensure(m().join(",") === "1,2,9", "the retry lands");
	ensure(led.made(3) === 1 && led.count("-", 3) === 1, "the real row 3 is disposed exactly once");
	scope.dispose();
	allGone(led, [1, 2, 3, 9]);
}

function initialCreateRetries(mode: number): void {
	createRoot((d) => {
		const led = new Ledger();
		const fault = new Fault();
		fault.bad = [9];
		const [src, setSrc] = createSignal<number[]>([1, 9, 2]);
		const broken = engine(mode, src, led, fault, null);
		ensure(failure(() => { broken(); }).includes("row 9"), "the first pass fails at creation");
		allGone(led, [1, 2, 9]);
		fault.bad = [];
		const m = engine(mode, src, led, fault, null);
		ensure(m().join(",") === "1,9,2", "a second engine over the same list builds it");
		ensure(led.live(1) === 1 && led.live(9) === 1 && led.live(2) === 1, "one live owner per row, none left by the aborted pass");
		d();
		allGone(led, [1, 2, 9]);
	});
}

function abortedFallbackLeaksNothing(mode: number): void {
	const scope = openScope();
	const led = new Ledger();
	const fault = new Fault();
	const fbFault = new Fault();
	const [src, setSrc] = createSignal<number[]>([1]);
	const m = runWithOwner(scope.owner, () => engine(mode, src, led, fault, () => { led.build(0); fbFault.check(0); return 0; }));
	ensure(m().join(",") === "1", "one row");
	fbFault.bad = [0];
	setSrc([]);
	flush();
	ensure(failure(() => { m(); }).includes("row 0"), "the fallback's error reaches the reader");
	ensure(led.made(0) === 1 && led.live(0) === 0, "the aborted fallback's owner is disposed");
	fbFault.bad = [];
	setSrc([]);
	flush();
	ensure(m().join(",") === "0", "the retry shows the fallback");
	ensure(led.live(0) === 1, "one live fallback owner: " + led.live(0).toString());
	setSrc([4]);
	flush();
	ensure(m().join(",") === "4" && led.live(0) === 0, "rows replace the fallback and dispose it");
	scope.dispose();
	allGone(led, [0, 1, 4]);
}

function failingRowsAbortTogether(mode: number): void {
	const scope = openScope();
	const led = new Ledger();
	const fault = new Fault();
	const [src, setSrc] = createSignal<number[]>([1, 2]);
	const m = runWithOwner(scope.owner, () => engine(mode, src, led, fault, null));
	m();
	fault.bad = [7, 8];
	setSrc([7, 1, 8, 2]);
	flush();
	ensure(failure(() => { m(); }).includes("row 7"), "the first failing row raises");
	ensure(led.live(1) === 1 && led.live(2) === 1 && led.live(7) === 0 && led.live(8) === 0, "nothing the pass built survives it");
	fault.bad = [];
	setSrc([7, 1, 8, 2]);
	flush();
	ensure(m().join(",") === "7,1,8,2", "both rows land together on the retry");
	ensure(led.made(1) === 1 && led.made(2) === 1, "rows 1 and 2 were never rebuilt");
	scope.dispose();
	allGone(led, [1, 2, 7, 8]);
}

function removedRowsOutliveTheNewOnes(mode: number): void {
	const scope = openScope();
	const led = new Ledger();
	const fault = new Fault();
	const [src, setSrc] = createSignal<number[]>([1, 2, 3]);
	const m = runWithOwner(scope.owner, () => engine(mode, src, led, fault, null));
	m();
	const at = led.log.length;
	setSrc([1, 9, 3]);
	flush();
	m();
	ensure(led.log.slice(at, led.log.length).join(" ") === "+9 -2", "the new row is built before the removed row is disposed: " + led.log.slice(at, led.log.length).join(" "));
	fault.bad = [8];
	setSrc([1, 8]);
	flush();
	failure(() => { m(); });
	ensure(led.live(9) === 1 && led.live(3) === 1, "a pass that fails disposes none of the rows it would have removed");
	scope.dispose();
}

test "notready-safety.test.ts:96 identity mode: a failing insert in a reorder keeps every surviving row" { survivorsKeepTheirOwners(0); }
test "notready-safety.test.ts:96 keyed by a function: a failing insert in a reorder keeps every surviving row" { survivorsKeepTheirOwners(1); }
test "notready-safety.test.ts:125 identity mode: removal while the insert still fails disposes the real row once" { removalWhileStillFailing(0); }
test "notready-safety.test.ts:125 keyed by a function: removal while the insert still fails disposes the real row once" { removalWhileStillFailing(1); }
test "notready-safety.test.ts:152 identity mode: an initial create that fails leaves no row alive" { initialCreateRetries(0); }
test "notready-safety.test.ts:152 keyed by a function: an initial create that fails leaves no row alive" { initialCreateRetries(1); }
test "notready-safety.test.ts:202 identity mode: an aborted fallback leaks no owner across retries" { abortedFallbackLeaksNothing(0); }
test "notready-safety.test.ts:202 keyed by a function: an aborted fallback leaks no owner across retries" { abortedFallbackLeaksNothing(1); }
test "notready-safety.test.ts:446 identity mode: two failing rows in one pass abort and land together" { failingRowsAbortTogether(0); }
test "notready-safety.test.ts:446 keyed by a function: two failing rows in one pass abort and land together" { failingRowsAbortTogether(1); }
test "map.ts:118 identity mode: removed rows are disposed after the pass's new rows are built" { removedRowsOutliveTheNewOnes(0); }
test "map.ts:118 keyed by a function: removed rows are disposed after the pass's new rows are built" { removedRowsOutliveTheNewOnes(1); }

test "notready-safety.test.ts:250 position mode: an aborted grow keeps every row and the engine list, the kept cells carry the scan's write" {
	const scope = openScope();
	const led = new Ledger();
	const fault = new Fault();
	const slots: Accessor<number>[] = [];
	const [src, setSrc] = createSignal<number[]>([10, 20]);
	const m = runWithOwner(scope.owner, () => mapArrayByPosition<number, number>(src, (item, pos) => {
		led.build(pos);
		fault.check(item());
		slots.push(item);
		return pos;
	}));
	const before = m();
	assert before.join(",") === "0,1", "two rows";
	fault.bad = [99];
	setSrc([11, 21, 99]);
	flush();
	assert failure(() => { m(); }).includes("row 99"), "the new position's error reaches the reader";
	assert slots[0]() === 11 && slots[1]() === 21, "map.ts:437 the scan wrote the kept cells before row 2 failed, the abort does not take it back: " + slots[0]().toString() + "," + slots[1]().toString();
	assert led.live(0) === 1 && led.live(1) === 1 && led.made(2) === 1 && led.live(2) === 0, "row owners as before, the aborted row disposed";
	setSrc([10, 20]);
	flush();
	assert m() === before, "the engine still holds the list from before the aborted pass";
	assert slots[0]() === 10 && slots[1]() === 20, "the pass that restores the list writes the kept cells back";
	fault.bad = [];
	setSrc([11, 21, 99]);
	flush();
	assert m().join(",") === "0,1,2", "the retry grows the list";
	assert slots[0]() === 11 && slots[1]() === 21 && slots[2]() === 99, "cells follow the retry";
	assert led.made(0) === 1 && led.made(1) === 1 && led.made(2) === 2, "positions 0 and 1 were never rebuilt";
	scope.dispose();
	allGone(led, [0, 1, 2]);
}

test "notready-safety.test.ts:250 keyed by a function: the scan wrote the kept keys' cells when the new key aborts the pass" {
	const scope = openScope();
	const led = new Ledger();
	const slots: Accessor<number>[] = [];
	const fault = new Fault();
	const [src, setSrc] = createSignal<number[]>([11, 22]);
	const m = runWithOwner(scope.owner, () => mapArrayKeyedBy<number, number, number>(src, (x) => Math.floor(x / 10), (item, i) => {
		const v = item();
		led.build(v);
		fault.check(v);
		slots.push(item);
		return v;
	}, null, false));
	m();
	fault.bad = [99];
	setSrc([12, 23, 99]);
	flush();
	assert failure(() => { m(); }).includes("row 99"), "the new key's error reaches the reader";
	assert slots[0]() === 12 && slots[1]() === 23, "map.ts:437 kept keys show their new item although the pass aborted: " + slots[0]().toString() + "," + slots[1]().toString();
	fault.bad = [];
	setSrc([12, 23, 99]);
	flush();
	assert m().join(",") === "11,22,99", "the retry keeps both built rows and builds only key 9";
	assert slots[0]() === 12 && slots[1]() === 23, "the cells keep the new items";
	scope.dispose();
}

test "notready-safety.test.ts:96 an aborted pass leaves the index cells: the kept row still reads its old index" {
	const scope = openScope();
	const led = new Ledger();
	const fault = new Fault();
	let indexOfOne: Accessor<number> | null = null;
	const [src, setSrc] = createSignal<number[]>([1, 2, 3]);
	const m = runWithOwner(scope.owner, () => mapArray<number, number>(src, (v, i) => {
		led.build(v);
		fault.check(v);
		if (v === 1) { indexOfOne = i; }
		return v;
	}, null, true));
	m();
	const one = indexOfOne as Accessor<number>;
	assert one() === 0, "row 1 sits at 0";
	fault.bad = [9];
	setSrc([3, 9, 1, 2]);
	flush();
	assert failure(() => { m(); }).includes("row 9"), "the pass aborts";
	assert one() === 0, "the aborted pass wrote no index: " + one().toString();
	fault.bad = [];
	setSrc([3, 9, 1, 2]);
	flush();
	assert one() === 2, "the retry moves row 1 to 2: " + one().toString();
	scope.dispose();
}

test "notready-safety.test.ts:352 repeat: a disjoint window shift with a failing row keeps the old rows until commit" {
	const scope = openScope();
	const led = new Ledger();
	const fault = new Fault();
	const [from, setFrom] = createSignal<number>(0);
	const m = runWithOwner(scope.owner, () => repeat<number>(() => 3, (i) => { led.build(i); fault.check(i); return i; }, from));
	assert m().join(",") === "0,1,2", "window 0..2";
	fault.bad = [11];
	setFrom(10);
	flush();
	assert failure(() => { m(); }).includes("row 11"), "row 11 fails";
	assert led.live(0) === 1 && led.live(1) === 1 && led.live(2) === 1, "the old rows are alive until the new window lands";
	assert led.live(10) === 0 && led.live(11) === 0, "what the pass built is gone";
	fault.bad = [];
	setFrom(11);
	flush();
	assert m().join(",") === "11,12,13", "the retry lands the window";
	assert led.live(0) === 0 && led.live(11) === 1 && led.made(0) === 1, "old rows go with the commit";
	scope.dispose();
	allGone(led, [0, 1, 2, 10, 11, 12, 13]);
}

test "notready-safety.test.ts:402 repeat: an aborted fallback leaks no owner across retries" {
	const scope = openScope();
	const led = new Ledger();
	const fbFault = new Fault();
	const [n, setN] = createSignal<number>(1);
	const m = runWithOwner(scope.owner, () => repeat<number>(n, (i) => i, null, () => { led.build(0); fbFault.check(0); return -1; }));
	assert m().join(",") === "0", "one row";
	fbFault.bad = [0];
	setN(0);
	flush();
	assert failure(() => { m(); }).includes("row 0"), "the fallback's error reaches the reader";
	assert led.live(0) === 0, "the aborted fallback's owner is disposed";
	fbFault.bad = [];
	setN(1);
	flush();
	setN(0);
	flush();
	assert m().join(",") === "-1" && led.live(0) === 1, "one live fallback owner: " + led.live(0).toString();
	scope.dispose();
	allGone(led, [0]);
}

function unchangedListKeepsTheMappedArray(mode: number): void {
	const scope = openScope();
	const led = new Ledger();
	const fault = new Fault();
	const [src, setSrc] = createSignal<number[]>([1, 2, 3]);
	const m = runWithOwner(scope.owner, () => engine(mode, src, led, fault, null));
	let memoRuns = 0;
	const mapped = runWithOwner(scope.owner, () => createMemo<number[]>((): number[] => { memoRuns += 1; return m(); }));
	let consumerRuns = 0;
	runWithOwner(scope.owner, (): number => {
		createRenderEffect<number[]>(
			(p: number[] | null): number[] => mapped(),
			(v: number[], p: number[] | null): Cleanup | null => { consumerRuns += 1; return null; },
		);
		return 0;
	});
	ensure(memoRuns === 1 && consumerRuns === 1, "first run");
	setSrc([1, 2, 3]);
	flush();
	ensure(memoRuns === 1 && consumerRuns === 1, "the unchanged list kept the mapped array, so the memo reading it did not re-run: " + memoRuns.toString());
	setSrc([1, 2, 3]);
	flush();
	ensure(memoRuns === 1 && consumerRuns === 1, "again");
	setSrc([2, 1, 3]);
	flush();
	ensure(memoRuns === 2 && consumerRuns === 2, "a reorder is a new mapped array: " + memoRuns.toString() + "," + consumerRuns.toString());
	scope.dispose();
}

test "map.ts:454 identity mode: an unchanged list keeps the mapped array identity, so a consumer does not re-run" { unchangedListKeepsTheMappedArray(0); }
test "map.ts:454 keyed by a function: an unchanged list keeps the mapped array identity, so a consumer does not re-run" { unchangedListKeepsTheMappedArray(1); }

test "map.ts:454 position mode: an unchanged list keeps the mapped array identity and still writes the cells" {
	const scope = openScope();
	const slots: Accessor<number>[] = [];
	const [src, setSrc] = createSignal<number[]>([5, 6]);
	const m = runWithOwner(scope.owner, () => mapArrayByPosition<number, number>(src, (item, pos) => { slots.push(item); return pos; }));
	let memoRuns = 0;
	const mapped = runWithOwner(scope.owner, () => createMemo<number[]>((): number[] => { memoRuns += 1; return m(); }));
	let consumerRuns = 0;
	runWithOwner(scope.owner, (): number => {
		createRenderEffect<number[]>(
			(p: number[] | null): number[] => mapped(),
			(v: number[], p: number[] | null): Cleanup | null => { consumerRuns += 1; return null; },
		);
		return 0;
	});
	setSrc([5, 6]);
	flush();
	assert memoRuns === 1 && consumerRuns === 1, "same values: the memo and the consumer did not re-run: " + memoRuns.toString();
	setSrc([7, 6]);
	flush();
	assert memoRuns === 1 && consumerRuns === 1, "a changed value is a cell write, not a new array: " + memoRuns.toString();
	assert slots[0]() === 7 && slots[1]() === 6, "the cell took the new value";
	scope.dispose();
}

test "map.ts:454 keyed by a function: an item replaced under a kept key writes its cell and keeps the mapped array" {
	const scope = openScope();
	const slots: Accessor<number>[] = [];
	const [src, setSrc] = createSignal<number[]>([11, 22]);
	const m = runWithOwner(scope.owner, () => mapArrayKeyedBy<number, number, number>(src, (x) => Math.floor(x / 10), (item, i) => { slots.push(item); return item(); }, null, false));
	let consumerRuns = 0;
	const mapped = runWithOwner(scope.owner, () => createMemo<number[]>((): number[] => m()));
	runWithOwner(scope.owner, (): number => {
		createRenderEffect<number[]>(
			(p: number[] | null): number[] => mapped(),
			(v: number[], p: number[] | null): Cleanup | null => { consumerRuns += 1; return null; },
		);
		return 0;
	});
	setSrc([12, 23]);
	flush();
	assert consumerRuns === 1, "no new mapped array: " + consumerRuns.toString();
	assert slots[0]() === 12 && slots[1]() === 23, "the cells took the new items";
	scope.dispose();
}

interface Piece {
	id: number;
}

class Born<T> {
	item: T;
	seq: number;

	constructor(item: T, seq: number) {
		this.item = item;
		this.seq = seq;
	}
}

class Side<T> {
	made: number;
	disposed: number[];
	rows: () => Born<T>[];

	constructor() {
		this.made = 0;
		this.disposed = [];
		this.rows = (): Born<T>[] => [];
	}

	make(item: T): Born<T> {
		const born = new Born<T>(item, this.made);
		this.made += 1;
		const disposed = this.disposed;
		const seq = born.seq;
		onCleanup(() => { disposed.push(seq); });
		return born;
	}
}

class Twin<T> {
	fast: Side<T>;
	oracle: Side<T>;
	idOf: (item: T) => number;
	setFast: Setter<T[]>;
	setOracle: Setter<T[]>;

	constructor(initial: T[], idOf: (item: T) => number) {
		this.fast = new Side<T>();
		this.oracle = new Side<T>();
		this.idOf = idOf;
		const [srcFast, setFast] = createSignal<T[]>(initial);
		const [srcOracle, setOracle] = createSignal<T[]>(initial);
		const fast = this.fast;
		const oracle = this.oracle;
		fast.rows = mapArray<T, Born<T>>(srcFast, (item, i) => fast.make(item), null, false);
		oracle.rows = mapArray<T, Born<T>>(srcOracle, (item, i) => oracle.make(item), null, true);
		this.setFast = setFast;
		this.setOracle = setOracle;
		fast.rows();
		oracle.rows();
	}

	items(): T[] {
		const out: T[] = [];
		for (const born of this.oracle.rows()) { out.push(born.item); }
		return out;
	}

	step(next: T[]): void {
		this.setFast(next);
		this.setOracle(next);
		flush();
		this.agree();
	}

	listOf(rows: Born<T>[], seqs: boolean): string {
		const out: number[] = [];
		for (const born of rows) { out.push(seqs ? born.seq : this.idOf(born.item)); }
		return out.join(",");
	}

	agree(): void {
		const f = this.fast.rows();
		const o = this.oracle.rows();
		ensure(f.length === o.length, "length " + f.length.toString() + " against the general path's " + o.length.toString());
		ensure(this.listOf(f, false) === this.listOf(o, false), "items in the same order as the general path");
		ensure(this.listOf(f, true) === this.listOf(o, true), "the same owners at the same positions as the general path");
		ensure(this.fast.disposed.join(",") === this.oracle.disposed.join(","), "the same owners disposed in the same order as the general path");
	}
}

function hitsOf<T>(twin: Twin<T>, next: T[]): number {
	const before = smallMoveHits();
	twin.step(next);
	return smallMoveHits() - before;
}

function expectHits(got: number, want: number, why: string): void {
	ensure(got === want, why + ": " + got.toString() + " fast-path commits, want " + want.toString());
}

function pieces(n: number): Piece[] {
	const out: Piece[] = [];
	for (let i = 0; i < n; i += 1) { out.push({ id: i }); }
	return out;
}

function pieceId(p: Piece): number {
	return p.id;
}

function numberId(n: number): number {
	return n;
}

function rotateFront<T>(a: T[]): T[] {
	const out: T[] = [];
	for (let i = 1; i < a.length; i += 1) { out.push(a[i]); }
	out.push(a[0]);
	return out;
}

function rotateBack<T>(a: T[]): T[] {
	const out: T[] = [a[a.length - 1]];
	for (let i = 0; i < a.length - 1; i += 1) { out.push(a[i]); }
	return out;
}

function reversed<T>(a: T[]): T[] {
	const out: T[] = [];
	for (let i = a.length - 1; i >= 0; i -= 1) { out.push(a[i]); }
	return out;
}

function without<T>(a: T[], at: number): T[] {
	const out: T[] = [];
	for (let i = 0; i < a.length; i += 1) { if (i !== at) { out.push(a[i]); } }
	return out;
}

function displace<T>(a: T[], k: number): T[] {
	const next: T[] = [];
	for (const x of a) { next.push(x); }
	for (let i = 0; i < k; i += 1) {
		const from = Math.floor(((i + 1) * next.length) / (k + 2));
		const row = next[from];
		next.splice(from, 1);
		next.splice((from + 7) % next.length, 0, row);
	}
	return next;
}

function shuffled<T>(a: T[]): T[] {
	const out: T[] = [];
	for (const x of a) { out.push(x); }
	for (let i = out.length - 1; i > 0; i -= 1) {
		const j = pick(i + 1);
		const t = out[i];
		out[i] = out[j];
		out[j] = t;
	}
	return out;
}

function rotationHits(mode: number): number {
	let hits: number = 0;
	const scope = openScope();
	const base = pieces(200);
	const [src, setSrc] = createSignal<Piece[]>(base);
	let m: () => number[] = (): number[] => [];
	runWithOwner(scope.owner, (): number => {
		if (mode === 0) {
			m = mapArray<Piece, number>(src, (p, i) => p.id, null, false);
		} else if (mode === 1) {
			m = mapArray<Piece, number>(src, (p, i) => p.id, null, true);
		} else if (mode === 2) {
			m = mapArrayKeyedBy<Piece, number, number>(src, pieceId, (item, i) => item().id, null, false);
		} else if (mode === 3) {
			m = mapArrayKeyedBy<Piece, number, number>(src, pieceId, (item, i) => item().id, null, true);
		} else {
			m = mapArrayByPosition<Piece, number>(src, (item, pos) => pos);
		}
		return 0;
	});
	m();
	const before = smallMoveHits();
	setSrc(rotateFront(base));
	flush();
	m();
	hits = smallMoveHits() - before;
	scope.dispose();
	return hits;
}

test "smallmove.test.ts:114 only an identity row that reads no index takes the fast path" {
	expectHits(rotationHits(0), 1, "smallmove.test.ts:96 identity rows without an index");
	expectHits(rotationHits(1), 0, "smallmove.test.ts:114 identity rows that read their index");
	expectHits(rotationHits(2), 0, "map.ts:469 keyed rows with cells");
	expectHits(rotationHits(3), 0, "map.ts:469 keyed rows with cells and an index");
	expectHits(rotationHits(4), 0, "map.ts:469 position rows");
}

test "smallmove.test.ts:157 rotating forward and back moves the owners with their items and builds nothing" {
	const scope = openScope();
	const twin = runWithOwner(scope.owner, () => new Twin<Piece>(pieces(300), pieceId));
	for (const forward of [true, false, true, true]) {
		expectHits(hitsOf(twin, forward ? rotateFront(twin.items()) : rotateBack(twin.items())), 1, "smallmove.test.ts:96 a rotation of 300 rows, forward " + forward.toString());
	}
	assert twin.fast.made === 300 && twin.fast.disposed.length === 0, "no row built or disposed: " + twin.fast.made.toString();
	assert twin.fast.rows()[0].item === twin.items()[0], "row 0 holds the item at 0";
	scope.dispose();
}

test "smallmove.test.ts:118 a window of 66 changed rows and a window of 65 both agree with the general path" {
	for (const window of [66, 65]) {
		const scope = openScope();
		const src = pieces(100 + window);
		const twin = runWithOwner(scope.owner, () => new Twin<Piece>(src, pieceId));
		const next: Piece[] = [];
		for (let i = 0; i < 100; i += 1) { next.push(src[i]); }
		const tail: Piece[] = [];
		for (let i = 100; i < src.length; i += 1) { tail.push(src[i]); }
		for (const p of rotateFront(tail)) { next.push(p); }
		expectHits(hitsOf(twin, next), window === 66 ? 1 : 0, "smallmove.test.ts:131 window " + window.toString());
		assert twin.fast.made === src.length, "window " + window.toString() + ": no row built";
		scope.dispose();
	}
}

test "smallmove.test.ts:137 a block of 32 displaced rows and a block of 33 both agree with the general path" {
	for (const k of [32, 33]) {
		const scope = openScope();
		const src = pieces(400);
		const twin = runWithOwner(scope.owner, () => new Twin<Piece>(src, pieceId));
		const next: Piece[] = [];
		for (let i = k; i < src.length; i += 1) { next.push(src[i]); }
		for (let i = 0; i < k; i += 1) { next.push(src[i]); }
		expectHits(hitsOf(twin, next), k === 32 ? 1 : 0, "smallmove.test.ts:148 k=" + k.toString());
		assert twin.fast.made === 400 && twin.fast.disposed.length === 0, "k=" + k.toString() + ": nothing built or disposed";
		scope.dispose();
	}
}

test "smallmove.test.ts:131 the window gate holds when the two ends of the window swap" {
	for (const window of [66, 65]) {
		const scope = openScope();
		const src = pieces(100 + window);
		const twin = runWithOwner(scope.owner, () => new Twin<Piece>(src, pieceId));
		const next: Piece[] = [];
		for (const p of src) { next.push(p); }
		next[100] = src[src.length - 1];
		next[src.length - 1] = src[100];
		expectHits(hitsOf(twin, next), window === 66 ? 1 : 0, "smallmove.test.ts:131 swapped ends, window " + window.toString());
		scope.dispose();
	}
}

test "smallmove.test.ts:148 a block of 32 moved to the front engages and a block of 33 does not" {
	for (const k of [32, 33]) {
		const scope = openScope();
		const src = pieces(400);
		const twin = runWithOwner(scope.owner, () => new Twin<Piece>(src, pieceId));
		const next: Piece[] = [];
		for (let i = src.length - k; i < src.length; i += 1) { next.push(src[i]); }
		for (let i = 0; i < src.length - k; i += 1) { next.push(src[i]); }
		expectHits(hitsOf(twin, next), k === 32 ? 1 : 0, "smallmove.test.ts:148 block to the front, k=" + k.toString());
		assert twin.fast.made === 400 && twin.fast.disposed.length === 0, "k=" + k.toString() + ": nothing built or disposed";
		scope.dispose();
	}
}

test "smallmove.test.ts:170 scattered displacements of 3 to 8 rows agree with the general path" {
	const scope = openScope();
	const twin = runWithOwner(scope.owner, () => new Twin<Piece>(pieces(500), pieceId));
	const before = smallMoveHits();
	for (let k = 3; k <= 8; k += 1) { twin.step(displace(twin.items(), k)); }
	assert smallMoveHits() > before, "smallmove.test.ts:184 the fast path takes some of the scatters: " + (smallMoveHits() - before).toString();
	assert twin.fast.made === 500, "no row built";
	scope.dispose();
}

test "smallmove.test.ts:188 an adjacent swap of rows 1 and 998 agrees with the general path" {
	const scope = openScope();
	const twin = runWithOwner(scope.owner, () => new Twin<Piece>(pieces(1000), pieceId));
	const next = twin.items();
	const t = next[1];
	next[1] = next[998];
	next[998] = t;
	expectHits(hitsOf(twin, next), 1, "smallmove.test.ts:195 swapping rows 1 and 998");
	assert twin.fast.rows()[1].item === next[1] && twin.fast.rows()[998].item === next[998], "the two rows swapped";
	scope.dispose();
}

test "smallmove.test.ts:200 a shrink that drops five rows and rotates the rest disposes the same owners" {
	const scope = openScope();
	const twin = runWithOwner(scope.owner, () => new Twin<Piece>(pieces(300), pieceId));
	const src = twin.items();
	const kept: Piece[] = [];
	for (let i = 0; i < src.length; i += 1) { if (i < 100 || i >= 105) { kept.push(src[i]); } }
	expectHits(hitsOf(twin, rotateFront(kept)), 1, "smallmove.test.ts:207 a shrink that rotates");
	assert twin.fast.disposed.length === 5, "five rows disposed: " + twin.fast.disposed.length.toString();
	scope.dispose();
}

test "smallmove.test.ts:213 a rotation that also grows agrees with the general path" {
	const scope = openScope();
	const twin = runWithOwner(scope.owner, () => new Twin<Piece>(pieces(200), pieceId));
	const next = rotateFront(twin.items());
	next.push({ id: 9999 });
	expectHits(hitsOf(twin, next), 0, "smallmove.test.ts:218 a rotation that grows");
	assert twin.fast.made === 201, "one row built";
	scope.dispose();
}

test "smallmove.test.ts:223 a replacement inside the window builds one row and disposes the old one" {
	const scope = openScope();
	const twin = runWithOwner(scope.owner, () => new Twin<Piece>(pieces(200), pieceId));
	const next = twin.items();
	next[100] = { id: 424242 };
	expectHits(hitsOf(twin, next), 0, "smallmove.test.ts:230 a replacement inside the window");
	assert twin.fast.made === 201 && twin.fast.disposed.length === 1, "one built, one disposed";
	scope.dispose();
}

test "smallmove.test.ts:236 a full replace builds every row and disposes every old one" {
	const scope = openScope();
	const twin = runWithOwner(scope.owner, () => new Twin<Piece>(pieces(1000), pieceId));
	expectHits(hitsOf(twin, pieces(1000)), 0, "smallmove.test.ts:240 a full replace");
	assert twin.fast.made === 2000 && twin.fast.disposed.length === 1000, "a thousand rows each way";
	scope.dispose();
}

test "smallmove.test.ts:248 a displaced identity that also occurs in an aligned run keeps occurrence-order pairing" {
	const scope = openScope();
	const a: Piece = { id: 1 };
	const b: Piece = { id: 2 };
	const c: Piece = { id: 3 };
	const filler: Piece[] = [];
	for (let i = 0; i < 100; i += 1) { filler.push({ id: 1000 + i }); }
	const src: Piece[] = [a, b, a, c];
	for (const f of filler) { src.push(f); }
	const twin = runWithOwner(scope.owner, () => new Twin<Piece>(src, pieceId));
	const next: Piece[] = [b, a, c, a];
	for (const f of rotateFront(filler)) { next.push(f); }
	expectHits(hitsOf(twin, next), 0, "smallmove.test.ts:259 a displaced identity that also sits in an aligned run");
	scope.dispose();
}

test "map.ts:260 the same shape with a distinct row in place of the duplicate takes the fast path" {
	const scope = openScope();
	const a: Piece = { id: 1 };
	const a2: Piece = { id: 1 };
	const b: Piece = { id: 2 };
	const c: Piece = { id: 3 };
	const filler: Piece[] = [];
	for (let i = 0; i < 100; i += 1) { filler.push({ id: 1000 + i }); }
	const src: Piece[] = [a, b, a2, c];
	for (const f of filler) { src.push(f); }
	const twin = runWithOwner(scope.owner, () => new Twin<Piece>(src, pieceId));
	const next: Piece[] = [b, a, c, a2];
	for (const f of rotateFront(filler)) { next.push(f); }
	expectHits(hitsOf(twin, next), 1, "smallmove.test.ts:259 without the duplicate the same move is a small move");
	scope.dispose();
}

test "map.ts:260 a number displaced into an aligned run that holds the same number declines" {
	const scope = openScope();
	const src: number[] = [1, 2, 1, 3];
	for (let i = 0; i < 100; i += 1) { src.push(1000 + i); }
	const twin = runWithOwner(scope.owner, () => new Twin<number>(src, numberId));
	const next: number[] = [2, 1, 3, 1];
	for (let i = 1; i < 100; i += 1) { next.push(1000 + i); }
	next.push(1000);
	expectHits(hitsOf(twin, next), 0, "smallmove.test.ts:259 equal numbers are one identity");
	scope.dispose();
}

test "smallmove.test.ts:264 duplicates only among displaced rows pair ascending on both sides" {
	const scope = openScope();
	const a: Piece = { id: 1 };
	const filler: Piece[] = [];
	for (let i = 0; i < 200; i += 1) { filler.push({ id: 1000 + i }); }
	const src: Piece[] = [a, a];
	for (const f of filler) { src.push(f); }
	const twin = runWithOwner(scope.owner, () => new Twin<Piece>(src, pieceId));
	const next: Piece[] = [];
	for (const f of filler) { next.push(f); }
	next.push(a);
	next.push(a);
	expectHits(hitsOf(twin, next), 1, "map.ts:254 two equal rows that both leave the front, neither inside an aligned run");
	scope.dispose();
}

test "smallmove.test.ts:275 removing one of two equal items disposes the same occurrence as the general path" {
	const scope = openScope();
	const a: Piece = { id: 1 };
	const filler: Piece[] = [];
	for (let i = 0; i < 200; i += 1) { filler.push({ id: 1000 + i }); }
	const src: Piece[] = [a];
	for (let i = 0; i < 100; i += 1) { src.push(filler[i]); }
	src.push(a);
	for (let i = 100; i < 200; i += 1) { src.push(filler[i]); }
	const twin = runWithOwner(scope.owner, () => new Twin<Piece>(src, pieceId));
	const next: Piece[] = [a];
	for (let i = 0; i < 100; i += 1) { next.push(filler[i]); }
	const tail: Piece[] = [];
	for (let i = 100; i < 200; i += 1) { tail.push(filler[i]); }
	for (const f of rotateFront(tail)) { next.push(f); }
	expectHits(hitsOf(twin, next), 1, "map.ts:254 the second of two equal rows leaves, the first sits in the kept prefix");
	assert twin.fast.disposed.length === 1, "one owner disposed";
	scope.dispose();
}

test "smallmove.test.ts:287 random duplicate-heavy reorders always agree with the general path" {
	const scope = openScope();
	const base = pieces(120);
	const start: Piece[] = [];
	for (const p of base) { start.push(p); }
	for (let i = 0; i < 30; i += 1) { start.push(base[i]); }
	const twin = runWithOwner(scope.owner, () => new Twin<Piece>(start, pieceId));
	const before = smallMoveHits();
	for (let round = 0; round < 200; round += 1) {
		const next = twin.items();
		const moves = 1 + pick(6);
		for (let m = 0; m < moves; m += 1) {
			const from = pick(next.length);
			const row = next[from];
			next.splice(from, 1);
			next.splice(pick(next.length), 0, row);
		}
		if (pick(4) === 0) { next.splice(pick(next.length), 1); }
		twin.step(next);
	}
	assert smallMoveHits() > before, "the fuzz reaches the fast path: " + (smallMoveHits() - before).toString();
	scope.dispose();
}

test "map.ts:459 a reverse and a shuffle of a large list agree with the general path" {
	const scope = openScope();
	const twin = runWithOwner(scope.owner, () => new Twin<Piece>(pieces(300), pieceId));
	expectHits(hitsOf(twin, reversed(twin.items())), 0, "map.ts:205 a reverse is past the compare budget");
	expectHits(hitsOf(twin, shuffled(twin.items())), 0, "map.ts:205 a shuffle is past the compare budget");
	expectHits(hitsOf(twin, shuffled(twin.items())), 0, "map.ts:205 a second shuffle");
	assert twin.fast.made === 300 && twin.fast.disposed.length === 0, "a reorder builds and disposes nothing";
	scope.dispose();
}

test "map.ts:459 removing one row from the front, middle and end of a large list disposes that row" {
	for (const at of [0, 150, 299]) {
		const scope = openScope();
		const twin = runWithOwner(scope.owner, () => new Twin<Piece>(pieces(300), pieceId));
		const gone = twin.items()[at];
		expectHits(hitsOf(twin, without(twin.items(), at)), 0, "map.ts:466 removing row " + at.toString() + " leaves the trims a window of nothing, the general path is already cheap");
		assert twin.fast.disposed.length === 1 && twin.fast.disposed[0] === at, "row " + at.toString() + " disposed: " + twin.fast.disposed.join(",");
		assert twin.fast.rows().length === 299, "299 left";
		scope.dispose();
	}
}

test "map.ts:459 number items take the same path: rotate, swap, remove one and a displacement agree" {
	const scope = openScope();
	const start: number[] = [];
	for (let i = 0; i < 1000; i += 1) { start.push(i); }
	const twin = runWithOwner(scope.owner, () => new Twin<number>(start, numberId));
	expectHits(hitsOf(twin, rotateFront(twin.items())), 1, "smallmove.test.ts:96 numbers rotate forward");
	expectHits(hitsOf(twin, rotateBack(twin.items())), 1, "smallmove.test.ts:96 numbers rotate back");
	const swapped = twin.items();
	const t = swapped[1];
	swapped[1] = swapped[998];
	swapped[998] = t;
	expectHits(hitsOf(twin, swapped), 1, "smallmove.test.ts:195 numbers swap");
	expectHits(hitsOf(twin, without(twin.items(), 500)), 0, "map.ts:466 numbers lose one row");
	expectHits(hitsOf(twin, displace(twin.items(), 5)), 1, "smallmove.test.ts:184 numbers displace five");
	assert twin.fast.made === 1000 && twin.fast.disposed.length === 1, "one row disposed, none built";
	scope.dispose();
}

test "map.ts:459 a large list survives random edits and agrees with the general path" {
	const scope = openScope();
	const twin = runWithOwner(scope.owner, () => new Twin<Piece>(pieces(150), pieceId));
	for (let round = 0; round < 150; round += 1) {
		const next = twin.items();
		const ops = 1 + pick(3);
		for (let k = 0; k < ops; k += 1) {
			const op = pick(4);
			if (op === 0 && next.length > 80) {
				next.splice(pick(next.length), 1);
			} else if (op === 1) {
				const fresh: Piece = { id: 100000 + round * 10 + k };
				next.splice(pick(next.length + 1), 0, fresh);
			} else if (op === 2 && next.length > 1) {
				const from = pick(next.length);
				const row = next[from];
				next.splice(from, 1);
				next.splice(pick(next.length + 1), 0, row);
			} else if (next.length > 1) {
				const i = pick(next.length);
				const j = pick(next.length);
				const t = next[i];
				next[i] = next[j];
				next[j] = t;
			}
		}
		twin.step(next);
	}
	scope.dispose();
}

class Trace {
	last: Map<string, string>;
	runs: Map<string, number>;
	cleaned: Map<string, number>;

	constructor() {
		this.last = new Map<string, string>();
		this.runs = new Map<string, number>();
		this.cleaned = new Map<string, number>();
	}

	saw(id: string, v: string): void {
		this.last.set(id, v);
		this.runs.set(id, this.ran(id) + 1);
	}

	left(id: string): void {
		this.cleaned.set(id, this.gone(id) + 1);
	}

	at(id: string): string {
		return this.last.has(id) ? (this.last.get(id) as string) : "-";
	}

	ran(id: string): number {
		return this.runs.has(id) ? (this.runs.get(id) as number) : 0;
	}

	gone(id: string): number {
		return this.cleaned.has(id) ? (this.cleaned.get(id) as number) : 0;
	}

	view(ids: string[]): string {
		const parts: string[] = [];
		for (const id of ids) { parts.push(id + "=" + this.at(id)); }
		return parts.join(" ");
	}
}

class Consumer {
	runs: number;

	constructor() {
		this.runs = 0;
	}
}

function consume<U>(scope: Scope, m: () => U[]): Consumer {
	const c = new Consumer();
	runWithOwner(scope.owner, (): number => {
		createRenderEffect<U[]>(
			(p: U[] | null): U[] => m(),
			(v: U[], p: U[] | null): Cleanup | null => { c.runs += 1; return null; },
		);
		return 0;
	});
	return c;
}

function watch(t: Trace, id: string, read: () => string): void {
	createRenderEffect<string>(
		(p: string | null): string => read(),
		(v: string, p: string | null): Cleanup | null => { t.saw(id, v); return null; },
	);
	onCleanup(() => { t.left(id); });
}

test "map.ts:88 a row effect keeps reading its index through a reorder, an insert and a removal while the list's consumer re-runs" {
	const scope = openScope();
	const a: Id = { id: "a" };
	const b: Id = { id: "b" };
	const c: Id = { id: "c" };
	const d: Id = { id: "d" };
	const [src, setSrc] = createSignal<Id[]>([a, b, c]);
	const t = new Trace();
	const m = runWithOwner(scope.owner, () => mapArray<Id, string>(src, (v, i) => {
		watch(t, v.id, (): string => i().toString());
		return v.id;
	}));
	const consumer = consume<string>(scope, m);
	assert t.view(["a", "b", "c"]) === "a=0 b=1 c=2", "mounted: " + t.view(["a", "b", "c"]);

	setSrc([b, a, c]);
	flush();
	assert consumer.runs === 2, "the reorder re-ran the consumer: " + consumer.runs.toString();
	assert t.view(["a", "b", "c"]) === "a=1 b=0 c=2", "the reorder reached the row effects: " + t.view(["a", "b", "c"]);
	assert t.gone("a") === 0 && t.gone("b") === 0 && t.gone("c") === 0, "a reorder disposes no row";

	setSrc([d, b, a, c]);
	flush();
	assert t.view(["d", "b", "a", "c"]) === "d=0 b=1 a=2 c=3", "the insert reached the row effects: " + t.view(["d", "b", "a", "c"]);
	assert t.gone("a") === 0 && t.gone("b") === 0 && t.gone("c") === 0, "an insert disposes no row";

	const bRuns = t.ran("b");
	const cRuns = t.ran("c");
	setSrc([d, a]);
	flush();
	assert t.view(["d", "a"]) === "d=0 a=1", "the removal reached the row effects: " + t.view(["d", "a"]);
	assert t.gone("b") === 1 && t.gone("c") === 1 && t.gone("a") === 0 && t.gone("d") === 0, "the removed rows' cleanups ran once, the others' not at all";
	setSrc([a, d]);
	flush();
	assert t.ran("b") === bRuns && t.ran("c") === cRuns, "a removed row's effect stays quiet";

	scope.dispose();
	assert t.gone("a") === 1 && t.gone("d") === 1 && t.gone("b") === 1 && t.gone("c") === 1, "disposing the owner disposes each remaining row once";
}

test "map.ts:88 keyed false: a row effect keeps reading its item cell through a reorder, an insert and a removal while the list's consumer re-runs" {
	const scope = openScope();
	const [src, setSrc] = createSignal<number[]>([10, 20, 30]);
	const t = new Trace();
	const m = runWithOwner(scope.owner, () => mapArrayByPosition<number, number>(src, (item, pos) => {
		watch(t, "p" + pos.toString(), (): string => item().toString());
		return pos;
	}));
	const consumer = consume<number>(scope, m);
	assert t.view(["p0", "p1", "p2"]) === "p0=10 p1=20 p2=30", "mounted: " + t.view(["p0", "p1", "p2"]);

	setSrc([20, 10, 30]);
	flush();
	assert t.view(["p0", "p1", "p2"]) === "p0=20 p1=10 p2=30", "the reorder reached the row effects: " + t.view(["p0", "p1", "p2"]);
	assert t.gone("p0") === 0 && t.gone("p1") === 0 && t.gone("p2") === 0, "a reorder disposes no row";
	assert consumer.runs === 1, "positions keep their rows, so the consumer did not re-run: " + consumer.runs.toString();

	setSrc([20, 10, 30, 40]);
	flush();
	assert t.view(["p0", "p1", "p2", "p3"]) === "p0=20 p1=10 p2=30 p3=40", "the append reached the row effects: " + t.view(["p0", "p1", "p2", "p3"]);
	assert consumer.runs === 2, "the append re-ran the consumer: " + consumer.runs.toString();

	const p2Runs = t.ran("p2");
	setSrc([20, 11]);
	flush();
	assert t.view(["p0", "p1"]) === "p0=20 p1=11", "the removal reached the row effects: " + t.view(["p0", "p1"]);
	assert t.gone("p2") === 1 && t.gone("p3") === 1 && t.gone("p0") === 0 && t.gone("p1") === 0, "the removed rows' cleanups ran once, the others' not at all";
	setSrc([21, 12]);
	flush();
	assert t.ran("p2") === p2Runs, "a removed row's effect stays quiet";

	scope.dispose();
	assert t.gone("p0") === 1 && t.gone("p1") === 1 && t.gone("p2") === 1 && t.gone("p3") === 1, "disposing the owner disposes each remaining row once";
}

test "map.ts:88 keyed by a function: a row effect keeps reading its item and index through a reorder, an insert and a removal while the list's consumer re-runs" {
	const scope = openScope();
	const [src, setSrc] = createSignal<Item[]>([{ id: 1, label: "a" }, { id: 2, label: "b" }, { id: 3, label: "c" }]);
	const t = new Trace();
	const m = runWithOwner(scope.owner, () => mapArrayKeyedBy<Item, number, number>(src, (r) => r.id, (item, i) => {
		const id = item().id;
		watch(t, "k" + id.toString(), (): string => item().label + i().toString());
		return id;
	}));
	const consumer = consume<number>(scope, m);
	assert t.view(["k1", "k2", "k3"]) === "k1=a0 k2=b1 k3=c2", "mounted: " + t.view(["k1", "k2", "k3"]);

	setSrc([{ id: 2, label: "B" }, { id: 1, label: "A" }, { id: 3, label: "c" }]);
	flush();
	assert consumer.runs === 2, "the reorder re-ran the consumer: " + consumer.runs.toString();
	assert t.view(["k1", "k2", "k3"]) === "k1=A1 k2=B0 k3=c2", "the reorder and the new items reached the row effects: " + t.view(["k1", "k2", "k3"]);
	assert t.gone("k1") === 0 && t.gone("k2") === 0 && t.gone("k3") === 0, "a reorder disposes no row";

	setSrc([{ id: 4, label: "d" }, { id: 2, label: "B" }, { id: 1, label: "A" }, { id: 3, label: "c" }]);
	flush();
	assert t.view(["k4", "k2", "k1", "k3"]) === "k4=d0 k2=B1 k1=A2 k3=c3", "the insert reached the row effects: " + t.view(["k4", "k2", "k1", "k3"]);

	const k2Runs = t.ran("k2");
	setSrc([{ id: 4, label: "d" }, { id: 1, label: "A" }]);
	flush();
	assert t.view(["k4", "k1"]) === "k4=d0 k1=A1", "the removal reached the row effects: " + t.view(["k4", "k1"]);
	assert t.gone("k2") === 1 && t.gone("k3") === 1 && t.gone("k1") === 0 && t.gone("k4") === 0, "the removed rows' cleanups ran once, the others' not at all";
	setSrc([{ id: 1, label: "Z" }, { id: 4, label: "d" }]);
	flush();
	assert t.ran("k2") === k2Runs, "a removed row's effect stays quiet";
	assert t.view(["k1", "k4"]) === "k1=Z0 k4=d1", "the survivors still follow: " + t.view(["k1", "k4"]);

	scope.dispose();
	assert t.gone("k1") === 1 && t.gone("k4") === 1 && t.gone("k2") === 1 && t.gone("k3") === 1, "disposing the owner disposes each remaining row once";
}

test "map.ts:624 repeat: a row effect keeps reading its own signal through a grow and a shrink while the consumer re-runs" {
	const scope = openScope();
	const [n, setN] = createSignal<number>(2);
	const [tick, setTick] = createSignal<number>(0);
	const t = new Trace();
	const m = runWithOwner(scope.owner, () => repeat<number>(n, (i) => {
		watch(t, "r" + i.toString(), (): string => (tick() + i).toString());
		return i;
	}));
	const consumer = consume<number>(scope, m);
	assert t.view(["r0", "r1"]) === "r0=0 r1=1", "mounted: " + t.view(["r0", "r1"]);

	setN(4);
	flush();
	assert consumer.runs === 2, "the grow re-ran the consumer: " + consumer.runs.toString();
	setTick(10);
	flush();
	assert t.view(["r0", "r1", "r2", "r3"]) === "r0=10 r1=11 r2=12 r3=13", "every row, kept or new, follows its signal: " + t.view(["r0", "r1", "r2", "r3"]);
	assert t.gone("r0") === 0 && t.gone("r1") === 0, "a grow disposes no row";

	const r3Runs = t.ran("r3");
	setN(2);
	flush();
	assert t.gone("r2") === 1 && t.gone("r3") === 1 && t.gone("r0") === 0 && t.gone("r1") === 0, "the shrink ran the leaving rows' cleanups once";
	setTick(20);
	flush();
	assert t.view(["r0", "r1"]) === "r0=20 r1=21", "the rows that stayed follow after the shrink: " + t.view(["r0", "r1"]);
	assert t.ran("r3") === r3Runs, "a removed row's effect stays quiet";

	scope.dispose();
	assert t.gone("r0") === 1 && t.gone("r1") === 1 && t.gone("r2") === 1 && t.gone("r3") === 1, "disposing the owner disposes each remaining row once";
}

function consumerKeepsEveryRow(mode: number): void {
	const scope = openScope();
	const led = new Ledger();
	const fault = new Fault();
	const [src, setSrc] = createSignal<number[]>([1, 2, 3]);
	const m = runWithOwner(scope.owner, () => engine(mode, src, led, fault, null));
	const consumer = consume<number>(scope, m);
	setSrc([3, 1, 2]);
	flush();
	ensure(consumer.runs === 2, "the reorder re-ran the consumer: " + consumer.runs.toString());
	ensure(led.live(1) === 1 && led.live(2) === 1 && led.live(3) === 1, "a reorder leaves every row alive");
	setSrc([3, 1, 2, 4]);
	flush();
	ensure(led.live(4) === 1 && led.live(1) === 1 && led.live(2) === 1 && led.live(3) === 1, "an insert leaves every row alive");
	setSrc([4, 2]);
	flush();
	ensure(led.live(1) === 0 && led.live(3) === 0 && led.live(2) === 1 && led.live(4) === 1, "a removal disposes exactly the removed rows");
	ensure(led.count("-", 1) === 1 && led.count("-", 3) === 1 && led.made(1) === 1 && led.made(3) === 1, "each removed row is disposed once and never rebuilt");
	scope.dispose();
	allGone(led, [1, 2, 3, 4]);
	ensure(led.count("-", 2) === 1 && led.count("-", 4) === 1, "disposing the owner disposes each remaining row once");
}

test "map.ts:88 identity mode: a re-running consumer disposes no row, a removal disposes the removed row once and the owner disposes the rest once" { consumerKeepsEveryRow(0); }
test "map.ts:88 keyed by a function: a re-running consumer disposes no row, a removal disposes the removed row once and the owner disposes the rest once" { consumerKeepsEveryRow(1); }

function ownerSize(n: Computation): number {
	let total: number = 1;
	let child = n.firstChild;
	while (child !== null) {
		total += ownerSize(child as Computation);
		child = (child as Computation).nextSibling;
	}
	return total;
}

test "mapArray.test.ts:165 full replacements keep the map's owner tree the size it was, one owner per live row" {
	const scope = openScope();
	let sample: Computation | null = null;
	const make = (): Id[] => {
		const items: Id[] = [];
		for (let i = 0; i < 50; i += 1) { items.push({ id: i.toString() }); }
		return items;
	};
	const [src, setSrc] = createSignal<Id[]>(make());
	const m = runWithOwner(scope.owner, () => mapArray<Id, number>(src, (v, i) => {
		sample = getOwner();
		return 1;
	}, null, false));
	consume<number>(scope, m);
	const mapOwnerAtMount = (sample as Computation).parent as Computation;
	assert mapOwnerAtMount.parent === scope.owner, "the map's owner is a child of the scope that created the map";
	const initial = ownerSize(scope.owner as Computation);
	for (let round = 0; round < 10; round += 1) {
		setSrc(make());
		flush();
		const rowAfter = sample as Computation;
		const mapOwner = rowAfter.parent as Computation;
		let rows: number = 0;
		let child = mapOwner.firstChild;
		while (child !== null) { rows += 1; child = (child as Computation).nextSibling; }
		assert rows === 50, "the map's owner holds one owner per live row: " + rows.toString();
		assert ownerSize(scope.owner as Computation) === initial, "round " + round.toString() + ": the owner tree did not grow: " + ownerSize(scope.owner as Computation).toString() + " against " + initial.toString();
	}
	scope.dispose();
}
