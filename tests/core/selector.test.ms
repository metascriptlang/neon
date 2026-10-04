import { createSignal, batch, untrack } from "../../src/core/signal";
import { createEffect } from "../../src/core/effect";
import { createMemo } from "../../src/core/memo";
import { createRoot } from "../../src/core/owner";
import { createSelector } from "../../src/core/selector";

function scoped(fn: () => void): void {
	createRoot((dispose: () => void): void => {
		try { fn(); } finally { dispose(); }
	});
}

class SelectionItem {
	id: int32;

	constructor(id: int32) { this.id = id; }
}

test "a thousand rows update only the entering and leaving selection" {
	scoped(() => {
		const [id, setId] = createSignal<int32>(-1);
		const selected = createSelector(id);
		const values: boolean[] = new Array(1000);
		let runs = 0;
		function mountRow(key: int32): void {
			createEffect(() => {
				values[key] = selected(key);
				runs += 1;
			});
		}
		for (let key = 0; key < 1000; key += 1) { mountRow(key); }
		assert runs === 1000;
		runs = 0;
		setId(0);
		assert runs === 1 && values[0], "first selection updates only row zero";
		runs = 0;
		setId(999);
		assert runs === 2 && !values[0] && values[999], "old and new selection update";
		runs = 0;
		setId(999);
		assert runs === 0, "equal selection does not update any row";
		setId(-1);
		assert runs === 1 && !values[999], "clearing selection updates only its old row";
	});
}

test "multiple listeners share a key and repeated reads do not duplicate notifications" {
	scoped(() => {
		const [id, setId] = createSignal<int32>(-1);
		const selected = createSelector(id);
		let firstRuns = 0;
		let secondRuns = 0;
		let first = false;
		let second = false;
		const stopFirst = createEffect(() => {
			const once = selected(0);
			first = selected(0);
			assert once === first;
			firstRuns += 1;
		});
		createEffect(() => { second = selected(0); secondRuns += 1; });
		setId(0);
		assert firstRuns === 2 && secondRuns === 2 && first && second;
		stopFirst();
		setId(1);
		assert firstRuns === 2 && first, "disposed listener keeps its last value";
		assert secondRuns === 3 && !second, "other listener on the same key remains live";
	});
}

test "a custom comparator notifies only keys whose matching state changes" {
	scoped(() => {
		const [id, setId] = createSignal<int32>(0);
		const selected = createSelector(id, (key: int32, value: int32): boolean => key <= value);
		let firstRuns = 0;
		let secondRuns = 0;
		let first = false;
		let second = false;
		createEffect(() => { first = selected(1); firstRuns += 1; });
		createEffect(() => { second = selected(2); secondRuns += 1; });
		setId(1);
		assert firstRuns === 2 && first && secondRuns === 1 && !second;
		setId(2);
		assert firstRuns === 2 && secondRuns === 2 && first && second;
		setId(3);
		assert firstRuns === 2 && secondRuns === 2, "different source, same matching states";
		setId(0);
		assert firstRuns === 3 && secondRuns === 3 && !first && !second;
	});
}

test "a comparator can use a key type different from its source" {
	scoped(() => {
		const [id, setId] = createSignal<int32>(0);
		const selected = createSelector<int32, string>(
			id,
			(key: string, value: int32): boolean => key === value.toString(),
		);
		let runs = 0;
		let first = false;
		let second = false;
		createEffect(() => { first = selected("1"); runs += 1; });
		createEffect(() => { second = selected("2"); runs += 1; });
		runs = 0;
		setId(1);
		assert runs === 1 && first && !second;
		runs = 0;
		setId(2);
		assert runs === 2 && !first && second;
	});
}

test "retracking replaces an old key subscription and disposal removes the new one" {
	scoped(() => {
		const [id, setId] = createSignal<int32>(-1);
		const [key, setKey] = createSignal<int32>(0);
		const selected = createSelector(id);
		let runs = 0;
		let value = false;
		const stop = createEffect(() => { value = selected(key()); runs += 1; });
		setKey(2);
		assert runs === 2 && !value;
		setId(0);
		assert runs === 2, "old key no longer owns this computation";
		setId(2);
		assert runs === 3 && value;
		stop();
		setId(0);
		assert runs === 3 && value, "disposed computation is not queued";
		createEffect(() => { value = selected(0); runs += 1; });
		assert runs === 4 && value;
		setId(2);
		assert runs === 5 && !value, "a removed key can be subscribed again";
	});
}

test "untracked selector reads see the latest value without subscribing their caller" {
	scoped(() => {
		const [id, setId] = createSignal<int32>(0);
		const selected = createSelector(id);
		let runs = 0;
		createEffect(() => { untrack(() => selected(1)); runs += 1; });
		setId(1);
		assert runs === 1 && selected(1) && !selected(0);
	});
}

test "selector and derived memos settle before an effect reading the source" {
	scoped(() => {
		const [id, setId] = createSignal<int32>(0);
		const selected = createSelector(id);
		const label = createMemo(() => selected(1) ? "chosen" : "idle");
		let seen = "";
		let runs = 0;
		createEffect(() => { seen = id().toString() + ":" + label(); runs += 1; });
		assert seen === "0:idle";
		setId(1);
		assert seen === "1:chosen" && runs === 2;
		setId(2);
		assert seen === "2:idle" && runs === 3;
	});
}

test "a batched selection change skips its intermediate key" {
	scoped(() => {
		const [id, setId] = createSignal<int32>(1);
		const selected = createSelector(id);
		let first = false;
		let middle = false;
		let last = false;
		let runs = 0;
		createEffect(() => { first = selected(1); runs += 1; });
		createEffect(() => { middle = selected(2); runs += 1; });
		createEffect(() => { last = selected(3); runs += 1; });
		runs = 0;
		batch(() => { setId(2); setId(3); });
		assert runs === 2 && !first && !middle && last;
	});
}

test "disposing the selector owner stops its source and preserves the cached selection" {
	scoped(() => {
		const [id, setId] = createSignal<int32>(1);
		let stopSelector: () => void = (): void => {};
		const selected = createRoot((dispose: () => void): (key: int32) => boolean => {
			stopSelector = dispose;
			return createSelector(id);
		});
		let runs = 0;
		let value = false;
		const stopReader = createEffect(() => { value = selected(1); runs += 1; });
		setId(2);
		assert runs === 2 && !value;
		stopSelector();
		setId(1);
		assert runs === 2 && !value && selected(2) && !selected(1);
		stopReader();
	});
}

test "object keys compare by identity even when their fields match" {
	scoped(() => {
		const firstKey = new SelectionItem(7);
		const secondKey = new SelectionItem(7);
		const [item, setItem] = createSignal<SelectionItem>(firstKey);
		const selected = createSelector(item);
		let first = false;
		let second = false;
		let runs = 0;
		createEffect(() => { first = selected(firstKey); runs += 1; });
		createEffect(() => { second = selected(secondKey); runs += 1; });
		assert first && !second;
		runs = 0;
		setItem(secondKey);
		assert runs === 2 && !first && second;
	});
}
