// Signal Tests
// Unit tests for reactive signal primitive

import { createSignal, Accessor } from "../../src/core/signal";
import { createEffect } from "../../src/core/effect";

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

	createEffect(() => {
		count(); // Subscribe
		effectRuns++;
	});

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
