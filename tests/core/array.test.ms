import { mapArray, indexArray } from "../../src/core/array";
import { createSignal } from "../../src/core/signal";
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
