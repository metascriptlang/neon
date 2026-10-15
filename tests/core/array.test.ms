import { mapArray, mapArrayKeyedBy, mapArrayByPosition, repeat } from "../../src/core/array";
import { createSignal, accessor, Accessor } from "../../src/core/signal";
import { createRoot } from "../../src/core/owner";
import { onCleanup } from "../../src/core/cleanup";
import { createRenderEffect } from "../../src/core/effect";

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
	createRoot((d) => {
		const ia: Id = { id: "a" };
		const ib: Id = { id: "b" };
		const ic: Id = { id: "c" };
		const [src, setSrc] = createSignal<Id[]>([ia, ib, ic]);
		let computed = 0;
		const m = mapArray<Id, Mapped>(src, (v, i) => { computed = computed + 1; return new Mapped(v.id, i); });
		const first = m();
		const a = first[0];
		const b = first[1];
		const c = first[2];
		assert a.id === "a" && a.index() === 0, "row a";
		assert b.id === "b" && b.index() === 1, "row b";
		assert c.id === "c" && c.index() === 2, "row c";
		assert computed === 3, "three rows built";

		setSrc([ib, ia, ic]);
		const second = m();
		assert second[0].id === "b" && second[0].index() === 0, "b moved to 0 and its index followed";
		assert second[1].id === "a" && second[1].index() === 1, "a moved to 1 and its index followed";
		assert second[2].id === "c" && second[2].index() === 2, "c stayed";
		assert second[1] === a && second[0] === b && second[2] === c, "rows are the same objects";
		assert computed === 3, "a reorder builds nothing";

		const id: Id = { id: "d" };
		setSrc([ib, ia, ic, id]);
		const third = m();
		assert third.length === 4 && third[3].id === "d" && third[3].index() === 3, "d appended at 3";
		assert computed === 4, "one build for d";

		setSrc([ia, ic, id]);
		const fourth = m();
		assert fourth.length === 3 && fourth[0] === a, "b removed, a keeps its row";
		assert computed === 4, "a removal builds nothing";

		setSrc([]);
		assert m().length === 0, "emptied";
		assert computed === 4, "emptying builds nothing";
		d();
	});
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
	createRoot((d) => {
		const [src, setSrc] = createSignal<number[]>([1, 2, 3]);
		const m = mapArray<number, number>(src, (v, i) => v);
		let runs = 0;
		let seen = 0;
		createRenderEffect(() => { seen = m().length; runs = runs + 1; });
		assert runs === 1 && seen === 3, "first run";
		setSrc([2, 3]);
		assert runs === 2 && seen === 2, "re-ran once with the shorter list";
		d();
	});
}

test "map.ts:493 default mode pairs equal items by occurrence order" {
	createRoot((d) => {
		const [src, setSrc] = createSignal<number[]>([7, 7, 7, 1]);
		let built = 0;
		let disposed = 0;
		const m = mapArray<number, number>(src, (v, i) => {
			built = built + 1;
			const at = built;
			onCleanup(() => { disposed = disposed + 1; });
			return at;
		});
		const first = m();
		assert first.length === 4 && built === 4, "four rows";
		setSrc([7, 7, 1]);
		const second = m();
		assert second[0] === first[0] && second[1] === first[1] && second[2] === first[3], "the first two 7 rows and the 1 row stay";
		assert built === 4, "nothing rebuilt";
		assert disposed === 1, "the third 7 row is the one that goes: " + disposed.toString();
		setSrc([1, 7, 7, 7, 7]);
		const third = m();
		assert third[0] === first[3] && third[1] === first[0] && third[2] === first[1], "survivors keep their rows";
		assert built === 6, "two new 7 rows";
		d();
	});
}

test "mapArray creates new, disposes removed" {
	createRoot((d) => {
		const [src, setSrc] = createSignal<number[]>([1, 2, 3]);
		let calls = 0;
		let disposed = 0;
		const m = mapArray<number, number>(src, (v, i) => {
			calls = calls + 1;
			onCleanup(() => { disposed = disposed + 1; });
			return v;
		});
		m();
		setSrc([1, 2, 3, 4]);
		m();
		assert calls === 4 && disposed === 0, "one new for 4, none disposed";
		setSrc([1, 2]);
		m();
		assert calls === 4 && disposed === 2, "two rows disposed";
		d();
	});
}

test "mapArray index reflects a move when read before AND after the move" {
	createRoot((d) => {
		const [src, setSrc] = createSignal<number[]>([1, 2, 3]);
		const m = mapArray<number, Accessor<number>>(src, (v, i) => i);
		const out = m();
		assert out[0]() === 0, "early read creates the signal";
		setSrc([2, 1, 3]);
		m();
		assert out[0]() === 1, "the same accessor reads the new index";
		d();
	});
}

test "map.ts:358 default mode fallback shows on empty, is dropped when rows return and rebuilt on the next empty" {
	createRoot((d) => {
		const [src, setSrc] = createSignal<number[]>([]);
		let fbBuilt = 0;
		let fbDisposed = 0;
		const m = mapArray<number, string>(src, (v, i) => v.toString(), () => {
			fbBuilt = fbBuilt + 1;
			onCleanup(() => { fbDisposed = fbDisposed + 1; });
			return "empty";
		});
		assert m().join(",") === "empty" && fbBuilt === 1, "fallback from the start";
		assert m().join(",") === "empty" && fbBuilt === 1, "a second pass over an empty list builds it once";
		setSrc([1, 2]);
		assert m().join(",") === "1,2" && fbDisposed === 1, "rows replace the fallback and dispose it";
		setSrc([]);
		assert m().join(",") === "empty" && fbBuilt === 2, "rebuilt on the next empty";
		setSrc([3]);
		assert m().join(",") === "3" && fbDisposed === 2, "dropped again";
		d();
	});
}

test "map.ts:111 a row that throws mid-pass commits nothing and disposes only the rows that pass built" {
	createRoot((d) => {
		const [src, setSrc] = createSignal<number[]>([1, 2, 3]);
		let armed = false;
		const live: boolean[] = [false, false, false, false, false, false];
		let built = 0;
		let disposed = 0;
		const m = mapArray<number, number>(src, (v, i) => {
			if (armed && v === 4) { throw new Error("row 4"); }
			built = built + 1;
			live[v] = true;
			onCleanup(() => { disposed = disposed + 1; live[v] = false; });
			return v;
		});
		const before = m();
		assert built === 3, "three rows";
		armed = true;
		setSrc([3, 5, 4, 1]);
		let caught = "";
		try { m(); } catch (e) { caught = e.toString(); }
		assert caught.includes("row 4"), "the row's error reaches the caller: " + caught;
		assert disposed === 1 && live[5] === false, "only the row built in the aborted pass (5) was disposed: " + disposed.toString();
		assert live[1] && live[2] && live[3], "surviving rows are untouched, including the one the new list drops (2)";
		armed = false;
		const after = m();
		assert after.length === 4 && after[0] === 3 && after[1] === 5 && after[2] === 4 && after[3] === 1, "the retry maps the new list";
		assert live[1] && !live[2] && live[3] && live[4] && live[5], "balance after the retry: " + disposed.toString();
		assert built === 3 + 1 + 1 + 1, "the retry built 5 and 4, the aborted pass had built 5: " + built.toString();
		d();
	});
}

test "mapArray lets a row that throws reach the caller" {
	createRoot((d) => {
		const [src, setSrc] = createSignal<number[]>([1, 2, 3]);
		const m = mapArray<number, number>(src, (v, i) => { throw new Error("row " + v.toString()); });
		let caught = "";
		try { m(); } catch (e) { caught = e.toString(); }
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
	createRoot((d) => {
		const [src, setSrc] = createSignal<number[]>([1, 2, 3]);
		let computed = 0;
		const m = mapArrayByPosition<number, Positioned>(src, (v, i) => { computed = computed + 1; return new Positioned(v, i); });
		const first = m();
		const a = first[0];
		const b = first[1];
		const c = first[2];
		assert a.index === 0 && a.value() === 1, "row 0";
		assert b.index === 1 && b.value() === 2, "row 1";
		assert c.index === 2 && c.value() === 3, "row 2";
		assert computed === 3, "three rows";

		setSrc([3, 2, 1]);
		const second = m();
		assert second[0] === a && second[1] === b && second[2] === c, "rows stay at their positions";
		assert a.value() === 3 && b.value() === 2 && c.value() === 1, "values changed in place";
		assert computed === 3, "no rebuild";

		setSrc([3, 2, 1, 4]);
		const third = m();
		assert third.length === 4 && third[3].index === 3 && third[3].value() === 4, "append builds one row";
		assert computed === 4, "one build";

		setSrc([2, 1, 4]);
		const fourth = m();
		assert fourth.length === 3 && fourth[0] === a && a.value() === 2, "shrink keeps the head rows and rewrites their values";

		setSrc([]);
		assert m().length === 0, "emptied";
		assert computed === 4, "no builds on shrink";
		d();
	});
}

test "mapArray.test.ts:290 keyed false keeps a row's value accessor live across a reorder" {
	createRoot((d) => {
		const [src, setSrc] = createSignal<string[]>(["a", "b"]);
		let first: Accessor<string> | null = null;
		const m = mapArrayByPosition<string, number>(src, (v, i) => {
			if (i === 0) { first = v; }
			return i;
		});
		m();
		assert (first as Accessor<string>)() === "a", "first value";
		setSrc(["b", "a"]);
		m();
		assert (first as Accessor<string>)() === "b", "the first row's accessor follows its slot";
		d();
	});
}

test "map.ts:358 keyed false fallback shows on empty and yields to rows" {
	createRoot((d) => {
		const [src, setSrc] = createSignal<number[]>([]);
		const m = mapArrayByPosition<number, string>(src, (v, i) => v().toString(), () => "empty");
		assert m().join(",") === "empty", "fallback";
		setSrc([4, 5]);
		assert m().join(",") === "4,5", "rows";
		setSrc([]);
		assert m().join(",") === "empty", "fallback again";
		d();
	});
}

test "mapArray.test.ts:198 keyed by a function passes accessors for both arguments and keeps a row per key" {
	createRoot((d) => {
		const [src, setSrc] = createSignal<Id[]>([{ id: "a" }, { id: "b" }, { id: "c" }]);
		let computed = 0;
		const m = mapArrayKeyedBy<Id, string, Slot>(src, (x) => x.id, (item, i) => { computed = computed + 1; return new Slot(item, i); });
		const first = m();
		const a = first[0];
		const b = first[1];
		const c = first[2];
		assert a.item().id === "a" && a.index() === 0, "row a";
		assert c.item().id === "c" && c.index() === 2, "row c";
		assert computed === 3, "three rows";

		setSrc([{ id: "b" }, { id: "a" }, { id: "c" }]);
		const second = m();
		assert second[0] === b && second[1] === a && second[2] === c, "the rows of the same keys moved, fresh objects notwithstanding";
		assert a.index() === 1 && b.index() === 0, "index accessors followed";
		assert computed === 3, "a reorder builds nothing";

		setSrc([{ id: "b" }, { id: "a" }, { id: "c" }, { id: "d" }]);
		const third = m();
		assert third.length === 4 && third[3].item().id === "d" && third[3].index() === 3, "d appended";
		assert computed === 4, "one build";

		setSrc([{ id: "a" }, { id: "c" }, { id: "d" }]);
		const fourth = m();
		assert fourth.length === 3 && fourth[0] === a, "b removed";
		assert computed === 4, "nothing rebuilt";

		setSrc([]);
		assert m().length === 0, "emptied";
		d();
	});
}

test "BUGS.md <For key> keyed by a function updates the kept row's item in place when the key stays" {
	createRoot((d) => {
		const [src, setSrc] = createSignal<Item[]>([{ id: 1, label: "a" }, { id: 2, label: "b" }]);
		let calls = 0;
		const m = mapArrayKeyedBy<Item, number, Labelled>(src, (r) => r.id, (item, i) => {
			calls = calls + 1;
			return new Labelled(accessor((): string => item().label));
		});
		const out = m();
		assert out[0].label() === "a" && out[1].label() === "b", "initial labels";
		setSrc([{ id: 2, label: "b2" }, { id: 1, label: "a2" }]);
		const out2 = m();
		assert out2[0].label() === "b2" && out2[1].label() === "a2", "the rows moved and show the new items: " + out2[0].label() + "," + out2[1].label();
		assert out2[0] === out[1] && out2[1] === out[0], "they are the same rows";
		assert calls === 2, "no row was rebuilt";
		d();
	});
}

test "keyed by a function writes an item replaced under a kept key at every position: prefix, window and suffix" {
	createRoot((d) => {
		const [src, setSrc] = createSignal<Item[]>([
			{ id: 1, label: "p" }, { id: 2, label: "w1" }, { id: 3, label: "w2" }, { id: 4, label: "s" },
		]);
		const m = mapArrayKeyedBy<Item, number, Labelled>(src, (r) => r.id, (item, i) => new Labelled(accessor((): string => item().label)));
		const out = m();
		setSrc([
			{ id: 1, label: "p2" }, { id: 3, label: "w2b" }, { id: 2, label: "w1b" }, { id: 4, label: "s2" },
		]);
		const out2 = m();
		assert out2[0].label() === "p2", "prefix row rewritten: " + out2[0].label();
		assert out2[1].label() === "w2b" && out2[2].label() === "w1b", "window rows rewritten: " + out2[1].label() + "," + out2[2].label();
		assert out2[3].label() === "s2", "suffix row rewritten: " + out2[3].label();
		assert out2[1] === out[2] && out2[2] === out[1], "window rows swapped, not rebuilt";
		d();
	});
}

test "map.ts:493 keyed by a function pairs rows that share a key by occurrence order" {
	createRoot((d) => {
		const [src, setSrc] = createSignal<Item[]>([{ id: 1, label: "x" }, { id: 1, label: "y" }, { id: 2, label: "z" }]);
		let built = 0;
		let disposed = 0;
		const m = mapArrayKeyedBy<Item, number, Labelled>(src, (r) => r.id, (item, i) => {
			built = built + 1;
			onCleanup(() => { disposed = disposed + 1; });
			return new Labelled(accessor((): string => item().label));
		});
		const first = m();
		assert first.length === 3 && built === 3, "a shared key does not raise";
		setSrc([{ id: 2, label: "z2" }, { id: 1, label: "x2" }]);
		const second = m();
		assert second[0] === first[2] && second[1] === first[0], "the earlier row of key 1 is the one that stays";
		assert second[0].label() === "z2" && second[1].label() === "x2", "both rewritten";
		assert built === 3 && disposed === 1, "the later row of key 1 went";
		d();
	});
}

test "keyed by a function takes a string key as well as a number key" {
	createRoot((d) => {
		const [src, setSrc] = createSignal<Id[]>([{ id: "x" }, { id: "y" }]);
		let built = 0;
		const m = mapArrayKeyedBy<Id, string, Slot>(src, (r) => r.id, (item, i) => { built = built + 1; return new Slot(item, i); });
		const first = m();
		setSrc([{ id: "y" }, { id: "z" }, { id: "x" }]);
		const second = m();
		assert second[0] === first[1] && second[2] === first[0], "string keys match across fresh objects";
		assert built === 3, "only z is new";
		assert second[1].item().id === "z", "z mapped";
		d();
	});
}

test "keyed by a function keeps the index accessor right across insert and remove" {
	createRoot((d) => {
		const [src, setSrc] = createSignal<Item[]>([{ id: 1, label: "a" }, { id: 2, label: "b" }]);
		const m = mapArrayKeyedBy<Item, number, Accessor<number>>(src, (r) => r.id, (item, i) => i);
		const out = m();
		assert out[0]() === 0, "first row reads index 0";
		setSrc([{ id: 3, label: "c" }, { id: 1, label: "a" }, { id: 2, label: "b" }]);
		const out2 = m();
		assert out2[0]() === 0 && out2[1]() === 1 && out2[2]() === 2, "the inserted key sits at 0 and the others followed";
		setSrc([{ id: 2, label: "b" }]);
		const out3 = m();
		assert out3.length === 1 && out3[0]() === 0, "the survivor reads index 0";
		d();
	});
}

test "keyed by a function disposes every row when the list empties" {
	createRoot((d) => {
		const [src, setSrc] = createSignal<Item[]>([{ id: 1, label: "a" }, { id: 2, label: "b" }]);
		let disposed = 0;
		const m = mapArrayKeyedBy<Item, number, number>(src, (r) => r.id, (item, i) => { onCleanup(() => { disposed = disposed + 1; }); return 0; });
		m();
		setSrc([]);
		assert m().length === 0 && disposed === 2, "both rows disposed: " + disposed.toString();
		d();
	});
}

test "map.ts:358 keyed by a function fallback shows on empty and yields to rows" {
	createRoot((d) => {
		const [src, setSrc] = createSignal<Item[]>([]);
		const m = mapArrayKeyedBy<Item, number, string>(src, (r) => r.id, (item, i) => item().label, () => "empty");
		assert m().join(",") === "empty", "fallback";
		setSrc([{ id: 1, label: "a" }]);
		assert m().join(",") === "a", "rows";
		d();
	});
}

test "repeat.test.ts:11 repeat builds one row per index and keeps rows when only the count changes" {
	createRoot((d) => {
		const [src, setSrc] = createSignal<Id[]>([{ id: "a" }, { id: "b" }, { id: "c" }]);
		let computed = 0;
		const m = repeat<Windowed>(() => src().length, (i) => { computed = computed + 1; return new Windowed(i, src); });
		const first = m();
		const a = first[0];
		const b = first[1];
		const c = first[2];
		assert a.id() === "a" && a.index === 0, "row 0";
		assert c.id() === "c" && c.index === 2, "row 2";
		assert computed === 3, "three rows";

		setSrc([{ id: "b" }, { id: "a" }, { id: "c" }]);
		const second = m();
		assert second[0] === a && second[1] === b && second[2] === c, "same count keeps every row";
		assert a.id() === "b" && b.id() === "a", "rows read the data at their index";
		assert computed === 3, "no rebuild";

		setSrc([{ id: "b" }, { id: "a" }, { id: "c" }, { id: "d" }]);
		const third = m();
		assert third.length === 4 && third[3].index === 3 && third[3].id() === "d", "a fourth row";
		assert computed === 4, "one build";

		setSrc([{ id: "b" }, { id: "a" }, { id: "c" }]);
		const fourth = m();
		assert fourth.length === 3 && fourth[0] === a, "pop keeps the head rows";
		assert computed === 4, "no build";

		setSrc([]);
		assert m().length === 0 && computed === 4, "emptied";
		d();
	});
}

test "repeat.test.ts:94 a consumer that reads the repeated list re-runs when the count changes" {
	createRoot((d) => {
		const [n, setN] = createSignal<number>(3);
		const m = repeat<number>(n, (i) => i);
		let runs = 0;
		let seen = 0;
		createRenderEffect(() => { seen = m().length; runs = runs + 1; });
		assert runs === 1 && seen === 3, "first run";
		setN(2);
		assert runs === 2 && seen === 2, "re-ran with the smaller count";
		d();
	});
}

test "repeat.test.ts:187 repeat disposes the rows that leave the window when from advances from a non-zero offset" {
	createRoot((d) => {
		const [from, setFrom] = createSignal<number>(1);
		const cleanups: number[] = [];
		const m = repeat<number>(() => 3, (i) => { onCleanup(() => { cleanups.push(i); }); return i; }, from);
		assert m().join(",") === "1,2,3", "window 1..3";
		setFrom(3);
		assert m().join(",") === "3,4,5", "window 3..5";
		assert cleanups.length === 2 && cleanups.includes(1) && cleanups.includes(2), "rows 1 and 2 left, row 3 stayed: " + cleanups.join(",");
		d();
	});
}

test "repeat.test.ts:212 repeat retains instances when only from changes" {
	createRoot((d) => {
		const [count, setCount] = createSignal<number>(3);
		const [from, setFrom] = createSignal<number>(0);
		let computed = 0;
		const m = repeat<number>(count, (i) => { computed = computed + 1; return i; }, from);
		assert m().join(",") === "0,1,2" && computed === 3, "initial";
		setFrom(2);
		assert m().join(",") === "2,3,4" && computed === 5, "slide to 2: rows 3 and 4 are new";
		setFrom(1);
		assert m().join(",") === "1,2,3" && computed === 6, "slide back to 1: only row 1 is new";
		setCount(4);
		assert m().join(",") === "1,2,3,4" && computed === 7, "grow: only row 4 is new";
		d();
	});
}

test "repeat.test.ts:288 repeat recovers when count goes to 0, from changes, and count comes back nonzero" {
	createRoot((d) => {
		const [count, setCount] = createSignal<number>(2);
		const [from, setFrom] = createSignal<number>(2);
		const m = repeat<number>(count, (i) => i, from);
		assert m().join(",") === "2,3", "initial";
		setCount(0);
		assert m().length === 0, "cleared";
		setFrom(0);
		setCount(1);
		assert m().join(",") === "0", "row 0 after the offset reset";
		d();
	});
}

test "repeat.test.ts:317 repeat slides the window backwards: departing rows are disposed, the overlap is retained" {
	createRoot((d) => {
		const [from, setFrom] = createSignal<number>(3);
		const disposed: number[] = [];
		const m = repeat<Windowed>(() => 3, (i) => { onCleanup(() => { disposed.push(i); }); return new Windowed(i, accessor((): Id[] => [])); }, from);
		const first = m();
		assert first[0].index === 3 && first[2].index === 5, "window 3..5";
		const retained = first[0];
		setFrom(1);
		const second = m();
		assert second[0].index === 1 && second[1].index === 2 && second[2].index === 3, "window 1..3";
		assert second[2] === retained, "the overlap row is the same instance, now at the tail";
		assert disposed.length === 2 && disposed.includes(4) && disposed.includes(5), "only the departing rows were disposed: " + disposed.join(",");
		d();
	});
}

test "repeat.test.ts:378 disjoint window jumps build only the window and do not accumulate live rows" {
	createRoot((d) => {
		const [from, setFrom] = createSignal<number>(0);
		let created = 0;
		let cleaned = 0;
		const m = repeat<number>(() => 3, (i) => { created = created + 1; onCleanup(() => { cleaned = cleaned + 1; }); return i; }, from);
		assert m().join(",") === "0,1,2" && created - cleaned === 3, "initial window";
		setFrom(10);
		assert m().join(",") === "10,11,12" && created - cleaned === 3, "forward jump";
		setFrom(20);
		assert m().join(",") === "20,21,22" && created - cleaned === 3, "second jump";
		setFrom(0);
		assert m().join(",") === "0,1,2" && created - cleaned === 3, "backward jump";
		d();
	});
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
	createRoot((d) => {
		const [n, setN] = createSignal<number>(0);
		let fbBuilt = 0;
		let fbDisposed = 0;
		const m = repeat<string>(n, (i) => i.toString(), null, () => {
			fbBuilt = fbBuilt + 1;
			onCleanup(() => { fbDisposed = fbDisposed + 1; });
			return "empty";
		});
		assert m().join(",") === "empty" && m().join(",") === "empty" && fbBuilt === 1, "fallback built once";
		setN(2);
		assert m().join(",") === "0,1" && fbDisposed === 1, "rows replace the fallback";
		setN(0);
		assert m().join(",") === "empty" && fbBuilt === 2, "fallback again";
		d();
	});
}

test "map.ts:692 repeat that throws mid-pass commits nothing and disposes only what the pass built" {
	createRoot((d) => {
		const [n, setN] = createSignal<number>(2);
		let armed = false;
		let disposed = 0;
		const m = repeat<number>(n, (i) => {
			if (armed && i === 3) { throw new Error("row 3"); }
			onCleanup(() => { disposed = disposed + 1; });
			return i;
		});
		m();
		armed = true;
		setN(5);
		let caught = "";
		try { m(); } catch (e) { caught = e.toString(); }
		assert caught.includes("row 3"), "the error reaches the caller: " + caught;
		assert disposed === 1, "only row 2, built by the aborted pass, was disposed: " + disposed.toString();
		armed = false;
		assert m().join(",") === "0,1,2,3,4", "the retry keeps rows 0 and 1";
		d();
	});
}

test "repeat refuses a count that is not a non-negative integer" {
	createRoot((d) => {
		const [n, setN] = createSignal<number>(2.5);
		const m = repeat<number>(n, (i) => i);
		let caught = "";
		try { m(); } catch (e) { caught = e.toString(); }
		assert caught.includes("Repeat: count"), "fractional count named: " + caught;
		setN(-1);
		caught = "";
		try { m(); } catch (e) { caught = e.toString(); }
		assert caught.includes("Repeat: count"), "negative count named: " + caught;
		d();
	});
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
	createRoot((d) => {
		const [src, setSrc] = createSignal<number[]>([1, 2, 3]);
		const gone: boolean[] = [];
		let live = 0;
		const m = mapArray<number, Tracked>(src, (v, i) => {
			const id = gone.length;
			gone.push(false);
			live = live + 1;
			onCleanup(() => {
				assert !gone[id], "row " + id.toString() + " disposed twice";
				gone[id] = true;
				live = live - 1;
			});
			return new Tracked(id, v, accessor((): number => v), i);
		});
		m();
		let cur: number[] = [1, 2, 3];
		for (let step = 0; step < 400; step += 1) {
			cur = nextList(cur, false);
			setSrc(cur);
			const out = m();
			assert out.length === cur.length, "step " + step.toString() + ": length";
			assert live === cur.length, "step " + step.toString() + ": live rows " + live.toString() + " for " + cur.length.toString() + " items";
			for (let j = 0; j < cur.length; j += 1) {
				assert out[j].value === cur[j], "step " + step.toString() + ": row " + j.toString() + " maps its item";
				assert out[j].index() === j, "step " + step.toString() + ": row " + j.toString() + " index";
			}
		}
		d();
	});
}

test "map.ts:391 keyed by a function survives random edits: rows follow keys, items and indexes are current" {
	createRoot((d) => {
		const [src, setSrc] = createSignal<Item[]>([{ id: 1, label: "1.0" }, { id: 2, label: "2.0" }]);
		const gone: boolean[] = [];
		const serialOfKey = new Map<number, number>();
		let live = 0;
		let version = 0;
		const m = mapArrayKeyedBy<Item, number, Tracked>(src, (r) => r.id, (item, i) => {
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
		});
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
		d();
	});
}

test "map.ts:391 keyed false survives random edits: rows stay per position and show the current value" {
	createRoot((d) => {
		const [src, setSrc] = createSignal<number[]>([1, 2, 3]);
		const gone: boolean[] = [];
		let live = 0;
		const m = mapArrayByPosition<number, Tracked>(src, (v, i) => {
			const id = gone.length;
			gone.push(false);
			live = live + 1;
			onCleanup(() => {
				assert !gone[id], "row " + id.toString() + " disposed twice";
				gone[id] = true;
				live = live - 1;
			});
			return new Tracked(id, i, v, accessor((): number => i));
		});
		let prev = m();
		let cur: number[] = [1, 2, 3];
		for (let step = 0; step < 400; step += 1) {
			cur = nextList(cur, false);
			setSrc(cur);
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
		d();
	});
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
		let caught = "";
		try { m(); } catch (e) { caught = e.toString(); }
		assert caught.includes("no index accessor"), "reading the index of a row emitted as index-free raises: " + caught;
		d();
	});
}

test "map.ts:97 keyed by a function told the row never reads its index refuses a row that does" {
	createRoot((d) => {
		const [src, setSrc] = createSignal<Item[]>([{ id: 1, label: "a" }]);
		const m = mapArrayKeyedBy<Item, number, number>(src, (r) => r.id, (item, i) => i(), null, false);
		let caught = "";
		try { m(); } catch (e) { caught = e.toString(); }
		assert caught.includes("no index accessor"), "reading the index of a row emitted as index-free raises: " + caught;
		d();
	});
}

test "map.ts:330 told the row reads its index, both modes keep the live index" {
	createRoot((d) => {
		const [ids, setIds] = createSignal<number[]>([5, 6, 7]);
		const byIdentity = mapArray<number, Mapped>(ids, (v, i) => new Mapped(v.toString(), i), null, true);
		const [items, setItems] = createSignal<Item[]>([{ id: 1, label: "a" }, { id: 2, label: "b" }]);
		const byKey = mapArrayKeyedBy<Item, number, Mapped>(items, (r) => r.id, (item, i) => new Mapped(item().id.toString(), i), null, true);
		const a = byIdentity();
		const b = byKey();
		setIds([7, 5]);
		setItems([{ id: 2, label: "b" }, { id: 1, label: "a" }]);
		const a2 = byIdentity();
		const b2 = byKey();
		assert a2[0].index() === 0 && a2[1].index() === 1, "identity rows follow the reorder";
		assert b2[0].index() === 0 && b2[1].index() === 1, "keyed rows follow the reorder";
		assert a[0] === a2[1] && b[0] === b2[1], "the rows were kept, only their index moved";
		d();
	});
}

test "map.ts:330 default mode without the index reorders, rebuilds the empty fallback and disposes" {
	createRoot((d) => {
		const [src, setSrc] = createSignal<number[]>([1, 2, 3]);
		let built = 0;
		let disposed = 0;
		const m = mapArray<number, number>(src, (v, i) => { built = built + 1; onCleanup(() => { disposed = disposed + 1; }); return v * 10; }, () => -1, false);
		const out = m();
		assert out[0] === 10 && out[2] === 30, "mapped without an index";
		setSrc([3, 1, 2]);
		const out2 = m();
		assert built === 3, "a reorder builds nothing: " + built.toString();
		assert out2[0] === 30 && out2[1] === 10 && out2[2] === 20, "rows followed the reorder";
		setSrc([2]);
		assert m()[0] === 20 && disposed === 2, "removed rows disposed: " + disposed.toString();
		setSrc([]);
		assert m()[0] === -1 && disposed === 3, "the fallback shows and the last row is gone: " + disposed.toString();
		setSrc([4, 5]);
		const out3 = m();
		assert out3.length === 2 && out3[1] === 50 && built === 5, "rows return after the fallback: " + built.toString();
		d();
	});
}

test "map.ts:330 keyed by a function without the index keeps rows per key and the item live" {
	createRoot((d) => {
		const [src, setSrc] = createSignal<Item[]>([{ id: 1, label: "a" }, { id: 2, label: "b" }, { id: 3, label: "c" }]);
		let built = 0;
		let disposed = 0;
		const m = mapArrayKeyedBy<Item, number, Labelled>(src, (r) => r.id, (item, i) => { built = built + 1; onCleanup(() => { disposed = disposed + 1; }); return new Labelled(accessor((): string => item().label)); }, () => new Labelled(accessor((): string => "empty")), false);
		const out = m();
		setSrc([{ id: 3, label: "c2" }, { id: 1, label: "a" }, { id: 4, label: "d" }]);
		const out2 = m();
		assert built === 4, "only key 4 is new: " + built.toString();
		assert disposed === 1, "only key 2 is gone: " + disposed.toString();
		assert out2[0] === out[2] && out2[1] === out[0], "rows follow their keys";
		assert out2[0].label() === "c2" && out2[2].label() === "d", "kept rows show the current item";
		setSrc([]);
		assert m()[0].label() === "empty" && disposed === 4, "the fallback shows after the last row: " + disposed.toString();
		d();
	});
}

test "map.ts:391 default mode without the index survives random edits: every row maps its item, none leaks" {
	createRoot((d) => {
		const [src, setSrc] = createSignal<number[]>([1, 2, 3]);
		const gone: boolean[] = [];
		let live = 0;
		const m = mapArray<number, Plain>(src, (v, i) => {
			const id = gone.length;
			gone.push(false);
			live = live + 1;
			onCleanup(() => {
				assert !gone[id], "row " + id.toString() + " disposed twice";
				gone[id] = true;
				live = live - 1;
			});
			return new Plain(id, v);
		}, null, false);
		m();
		let cur: number[] = [1, 2, 3];
		for (let step = 0; step < 400; step += 1) {
			cur = nextList(cur, false);
			setSrc(cur);
			const out = m();
			assert out.length === cur.length, "step " + step.toString() + ": length";
			assert live === cur.length, "step " + step.toString() + ": live rows " + live.toString() + " for " + cur.length.toString() + " items";
			for (let j = 0; j < cur.length; j += 1) {
				assert out[j].value === cur[j], "step " + step.toString() + ": row " + j.toString() + " maps its item";
			}
		}
		d();
	});
}

test "map.ts:391 keyed by a function without the index survives random edits: rows follow keys and items" {
	createRoot((d) => {
		const [src, setSrc] = createSignal<Item[]>([{ id: 1, label: "1.0" }, { id: 2, label: "2.0" }]);
		const gone: boolean[] = [];
		const serialOfKey = new Map<number, number>();
		let live = 0;
		let version = 0;
		const m = mapArrayKeyedBy<Item, number, Tracked>(src, (r) => r.id, (item, i) => {
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
		}, null, false);
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
			const out = m();
			assert out.length === keys.length, "step " + step.toString() + ": length";
			assert live === keys.length, "step " + step.toString() + ": live rows " + live.toString() + " for " + keys.length.toString() + " keys";
			for (let j = 0; j < keys.length; j += 1) {
				assert out[j].value === keys[j], "step " + step.toString() + ": slot " + j.toString() + " holds the row of its key";
				assert out[j].item() === items[j].label.length, "step " + step.toString() + ": slot " + j.toString() + " shows the current item";
				if (before.has(keys[j])) { assert out[j].id === before.get(keys[j]) as number, "step " + step.toString() + ": key " + keys[j].toString() + " kept its row"; }
			}
		}
		d();
	});
}
