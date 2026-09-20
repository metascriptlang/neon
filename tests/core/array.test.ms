import { mapArray, mapArrayKeyed, indexArray } from "../../src/core/array";
import { createSignal, Accessor } from "../../src/core/signal";
import { createRoot } from "../../src/core/owner";
import { onCleanup } from "../../src/core/cleanup";

test "mapArray maps one result per item" {
	createRoot((d) => {
		const [list, setList] = createSignal<number[]>([1, 2, 3]);
		let calls = 0;
		const m = mapArray<number, number>(() => list(), (v, i) => { calls = calls + 1; return v * 10; });
		const out = m();
		assert out.length === 3, "length 3";
		assert out[0] === 10, "first mapped";
		assert out[2] === 30, "last mapped";
		assert calls === 3, "mapFn ran 3x";
		d();
	});
}

test "mapArray reuses rows on pure reorder" {
	createRoot((d) => {
		const [list, setList] = createSignal<number[]>([1, 2, 3]);
		let calls = 0;
		const m = mapArray<number, number>(() => list(), (v, i) => { calls = calls + 1; return v; });
		m();
		assert calls === 3, "initial 3";
		setList([3, 1, 2]);
		const out = m();
		assert calls === 3, "no new mapFn calls on reorder";
		assert out[0] === 3, "reordered out[0]";
		assert out[1] === 1, "reordered out[1]";
		assert out[2] === 2, "reordered out[2]";
		d();
	});
}

test "mapArray index signal updates on move" {
	createRoot((d) => {
		const [list, setList] = createSignal<number[]>([1, 2, 3]);
		const m = mapArray<number, () => number>(() => list(), (v, i) => i);
		m();
		setList([3, 1, 2]);
		const out = m();
		assert out[1]() === 1, "item 1 moved to index 1, its index accessor reads 1";
		assert out[0]() === 0, "item 3 now at index 0";
		d();
	});
}

test "mapArray index reflects a move when read before AND after (lazy signal fires)" {
	createRoot((d) => {
		const [list, setList] = createSignal<number[]>([1, 2, 3]);
		const m = mapArray<number, () => number>(() => list(), (v, i) => i);
		const out = m();
		assert out[0]() === 0, "early read: item 1 at index 0 (creates the signal)";
		setList([2, 1, 3]);
		m();
		assert out[0]() === 1, "same accessor now reads index 1 after the move";
		d();
	});
}

test "mapArray creates new, disposes removed" {
	createRoot((d) => {
		const [list, setList] = createSignal<number[]>([1, 2, 3]);
		let calls = 0;
		let disposed = 0;
		const m = mapArray<number, number>(() => list(), (v, i) => {
			calls = calls + 1;
			onCleanup(() => { disposed = disposed + 1; });
			return v;
		});
		m();
		assert calls === 3, "initial 3";
		setList([1, 2, 3, 4]);
		m();
		assert calls === 4, "one new for item 4";
		assert disposed === 0, "none disposed";
		setList([1, 2]);
		m();
		assert calls === 4, "no new calls on removal";
		assert disposed === 2, "two rows disposed";
		d();
	});
}

test "indexArray updates value signal without recreating row" {
	createRoot((d) => {
		const [list, setList] = createSignal<number[]>([1, 2, 3]);
		let calls = 0;
		const m = indexArray<number, () => number>(() => list(), (v, i) => { calls = calls + 1; return v; });
		const out = m();
		assert calls === 3, "initial 3";
		assert out[0]() === 1, "index 0 value 1";
		setList([9, 2, 3]);
		m();
		assert calls === 3, "no recreate on value change";
		assert out[0]() === 9, "same row, value signal now 9";
		d();
	});
}

test "indexArray grows and shrinks" {
	createRoot((d) => {
		const [list, setList] = createSignal<number[]>([1, 2]);
		let disposed = 0;
		const m = indexArray<number, () => number>(() => list(), (v, i) => {
			onCleanup(() => { disposed = disposed + 1; });
			return v;
		});
		m();
		setList([1, 2, 3]);
		const grown = m();
		assert grown.length === 3, "grew to 3";
		setList([1]);
		const shrunk = m();
		assert shrunk.length === 1, "shrank to 1";
		assert disposed === 2, "two overflow rows disposed";
		d();
	});
}

test "an accessor feeds mapArray directly and the row index is an Accessor" {
	createRoot((d) => {
		const [list, setList] = createSignal<number[]>([5, 6]);
		const m = mapArray<number, number>(list, (v, i) => {
			const idx: Accessor<number> = i;
			return v * 100 + idx();
		});
		const first = m();
		assert first.length === 2;
		assert first[0] === 500;
		assert first[1] === 601;
		setList([6, 5]);
		const second = m();
		assert second[0] === 601;
		assert second[1] === 500;
		d();
	});
}

test "an accessor feeds indexArray directly and the row item is an Accessor" {
	createRoot((d) => {
		const [list, setList] = createSignal<number[]>([1]);
		const m = indexArray<number, () => number>(list, (v, i) => {
			const item: Accessor<number> = v;
			return item;
		});
		const rows = m();
		assert rows[0]() === 1;
		setList([9]);
		m();
		assert rows[0]() === 9;
		d();
	});
}

interface Item {
	id: number;
	label: string;
}

test "mapArrayKeyed reuses a row when the object is replaced but the key stays" {
	createRoot((d) => {
		const [list, setList] = createSignal<Item[]>([{ id: 1, label: "a" }, { id: 2, label: "b" }]);
		let calls = 0;
		const m = mapArrayKeyed<Item, string>(() => list(), (v) => v.id, (v, i) => { calls = calls + 1; return v.label; });
		const out = m();
		assert out.length === 2, "two rows";
		assert calls === 2, "two mapFn calls";
		setList([{ id: 2, label: "b2" }, { id: 1, label: "a2" }]);
		const out2 = m();
		assert calls === 2, "reorder of fresh objects with the same keys creates nothing";
		assert out2[0] === "b", "row of key 2 moved to slot 0, its mapped value is the old one";
		assert out2[1] === "a", "row of key 1 moved to slot 1";
		d();
	});
}

test "mapArrayKeyed inserts, removes and keeps the index accessor right" {
	createRoot((d) => {
		const [list, setList] = createSignal<Item[]>([{ id: 1, label: "a" }, { id: 2, label: "b" }]);
		let calls = 0;
		const m = mapArrayKeyed<Item, () => number>(() => list(), (v) => v.id, (v, i) => { calls = calls + 1; return i; });
		const out = m();
		assert out[0]() === 0, "first row reads index 0";
		setList([{ id: 3, label: "c" }, { id: 1, label: "a" }, { id: 2, label: "b" }]);
		const out2 = m();
		assert calls === 3, "one new row for the inserted key";
		assert out2[0]() === 0, "the new row is at 0";
		assert out2[1]() === 1, "key 1 moved to 1 and its index accessor followed";
		assert out2[2]() === 2, "key 2 moved to 2";
		setList([{ id: 2, label: "b" }]);
		const out3 = m();
		assert out3.length === 1, "two rows removed";
		assert calls === 3, "removal creates nothing";
		assert out3[0]() === 0, "the survivor reads index 0";
		d();
	});
}

test "mapArrayKeyed rejects two rows sharing a key, naming the key" {
	createRoot((d) => {
		const [list, setList] = createSignal<Item[]>([{ id: 1, label: "a" }, { id: 1, label: "b" }]);
		const m = mapArrayKeyed<Item, string>(() => list(), (v) => v.id, (v, i) => v.label);
		let caught = "";
		try { m(); } catch (e) { caught = e.toString(); }
		assert caught !== "", "a duplicate key raises";
		assert caught.includes("1"), "the message names the key value: " + caught;
		d();
	});
}

test "mapArrayKeyed disposes every row when the list empties" {
	createRoot((d) => {
		const [list, setList] = createSignal<Item[]>([{ id: 1, label: "a" }, { id: 2, label: "b" }]);
		let disposed = 0;
		const m = mapArrayKeyed<Item, string>(() => list(), (v) => v.id, (v, i) => { onCleanup(() => { disposed = disposed + 1; }); return v.label; });
		m();
		setList([]);
		const out = m();
		assert out.length === 0, "no rows left";
		assert disposed === 2, "both rows disposed";
		d();
	});
}

test "mapArray told the row never reads its index refuses a row that does" {
	createRoot((d) => {
		const [list, setList] = createSignal<number[]>([1, 2]);
		const m = mapArray<number, number>(() => list(), (v, i) => i(), false);
		let caught = "";
		try { m(); } catch (e) { caught = e.toString(); }
		assert caught !== "", "reading the index of a row emitted as index-free raises";
		assert caught.includes("index"), "the message names the index: " + caught;
		d();
	});
}

test "mapArray without the index still reorders and disposes" {
	createRoot((d) => {
		const [list, setList] = createSignal<number[]>([1, 2, 3]);
		let calls = 0;
		let disposed = 0;
		const m = mapArray<number, number>(() => list(), (v, i) => { calls = calls + 1; onCleanup(() => { disposed = disposed + 1; }); return v * 10; }, false);
		const out = m();
		assert out[0] === 10 && out[2] === 30, "mapped without an index";
		setList([3, 1, 2]);
		const out2 = m();
		assert calls === 3, "reorder reuses rows";
		assert out2[0] === 30 && out2[1] === 10, "rows followed the reorder";
		setList([2]);
		m();
		assert disposed === 2, "removed rows disposed";
		d();
	});
}

test "mapArray lets a row that throws reach the caller" {
	createRoot((d) => {
		const [list, setList] = createSignal<number[]>([1, 2, 3]);
		const m = mapArray<number, number>(() => list(), (v, i) => { throw new Error("row " + v.toString()); });
		let caught = "";
		try { m(); } catch (e) { caught = e.toString(); }
		assert caught !== "", "the row's error reaches the caller instead of killing the process";
		assert caught.includes("row 1"), "the first row is the one that raised: " + caught;
		d();
	});
}
