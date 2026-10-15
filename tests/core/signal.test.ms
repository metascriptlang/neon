import { createSignal, untrack, Accessor } from "../../src/core/signal";
import { createMemo } from "../../src/core/memo";
import { createEffect } from "../../src/core/effect";
import { createRoot } from "../../src/core/owner";
import { Cleanup } from "../../src/core/types";
import { flush } from "../../src/core/runtime";

test "signal creation has correct initial value" {
	const [count, setCount] = createSignal(0);
	assert count() === 0;
}

test "signal update changes value" {
	const [count, setCount] = createSignal(0);
	setCount(5);
	assert count() === 5;
}

test "effect runs on creation and on signal update" {
	const [count, setCount] = createSignal(0);
	let effectRuns = 0;

	createEffect<int32>(
		(p: int32 | null): int32 => count(),
		(v: int32, p: int32 | null): Cleanup | null => { effectRuns++; return null; },
	);

	setCount(1);
	assert effectRuns === 2;
}

test "createSignal returns a nominal Accessor" {
	const [count, setCount] = createSignal<number>(0);
	const a: Accessor<number> = count;
	assert a() === 0;
	setCount(3);
	assert a() === 3;
}

test "an int literal signal is an Accessor<int32>" {
	const [count, setCount] = createSignal(0);
	const a: Accessor<int32> = count;
	setCount(2);
	assert a() === 2;
}

test "an Accessor widens into a thunk slot" {
	const [count, setCount] = createSignal<number>(0);
	const f: () => number = count;
	setCount(4);
	assert f() === 4;
}

test "the setter accepts an updater" {
	const [count, setCount] = createSignal(0);
	setCount(c => c + 1);
	assert count() === 1;
	setCount(c => c * 10);
	assert count() === 10;
}

test "a named updater reads the current value without tracking" {
	const [count, setCount] = createSignal<number>(1);
	const double = (prev: number): number => prev * 2;
	setCount(double);
	setCount(double);
	assert count() === 4;
}

test "an array signal takes a value and an updater" {
	const [items, setItems] = createSignal<number[]>([]);
	setItems([1, 2]);
	assert items().length === 2;
	setItems(prev => [prev.length, prev.length, prev.length]);
	assert items().length === 3;
	assert items()[0] === 2;
}

test "a write inside flush(fn) stays staged until the flush ends" {
	const [x, setX] = createSignal(1);
	flush(() => {
		setX(2);
		assert x() === 1, "an ownerless read sees the committed value: " + x().toString();
	});
	assert x() === 2;
}

test "an updater written inside flush(fn) stages too" {
	const [x, setX] = createSignal(1);
	flush(() => {
		setX(n => n + 1);
		assert x() === 1;
		setX(n => n + 1);
	});
	assert x() === 3, "the second updater saw the staged value: " + x().toString();
}

test "equals compares the next value with the staged one" {
	const [x, setX] = createSignal(1, { equals: (prev: int32, next: int32): boolean => prev + 1 === next });
	setX(11);
	assert x() === 11;
	setX(12);
	assert x() === 11, "12 follows 11 and is skipped";
	setX(13);
	assert x() === 13;
	flush(() => {
		setX(20);
		setX(21);
	});
	assert x() === 20, "21 follows the staged 20 and is skipped: " + x().toString();
}

test "equals false wakes a subscriber on every write" {
	const [x, setX] = createSignal(1, { equals: false });
	let runs = 0;
	createEffect<int32>((p: int32 | null): int32 => x(), (v: int32, p: int32 | null): Cleanup | null => { runs += 1; return null; });
	setX(1);
	setX(1);
	assert runs === 3, "ran " + runs.toString();
}

test "an owned reader sees the staged value while a flush runs" {
	const [x, setX] = createSignal(1);
	let owned = -1;
	let bare = -1;
	createRoot((d) => {
		flush(() => {
			setX(5);
			const m = createMemo<int32>((): int32 => x());
			owned = m();
			bare = x();
		});
		d();
	});
	assert owned === 5, "owned " + owned.toString();
	assert bare === 1, "bare " + bare.toString();
}

test "untrack reads without subscribing" {
	const [x, setX] = createSignal(1);
	const [y, setY] = createSignal(1);
	let runs = 0;
	createEffect<int32>(
		(p: int32 | null): int32 => {
			const seen = x();
			untrack(() => y());
			return seen;
		},
		(v: int32, p: int32 | null): Cleanup | null => { runs += 1; return null; },
	);
	setY(2);
	assert runs === 1, "y is not a dependency";
	setX(2);
	assert runs === 2;
}

test "an effect may write a plain signal" {
	const [x, setX] = createSignal(1);
	createRoot((d) => {
		createEffect<boolean>((p: boolean | null): boolean => true, (v: boolean, p: boolean | null): Cleanup | null => { setX(7); return null; });
		flush();
		d();
	});
	assert x() === 7;
}
