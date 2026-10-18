// Reactivity test suite — fine-grained signal/effect behavior.

import { createSignal } from "../src/core/signal";
import { createEffect } from "../src/core/effect";
import { flush } from "../src/core/runtime";
import { Cleanup } from "../src/core/types";

test "signal get/set basics" {
	const [count, setCount] = createSignal(0);
	flush();
	assert count() === 0 : "initial value is 0";
	setCount(5);
	flush();
	assert count() === 5 : "value after set is 5";
	setCount(10);
	flush();
	assert count() === 10 : "value after second set is 10";
}

test "effect auto-runs on creation" {
	let effectRan = 0;
	const [a, setA] = createSignal(1);
	createEffect<int32>(
		(prev: int32 | null): int32 => a(),
		(value: int32, prev: int32 | null): Cleanup | null => { effectRan = effectRan + 1; return null; },
	);
	flush();
	assert effectRan === 1 : "effect ran once on creation";
}

test "effect re-runs on signal change" {
	let effectCount = 0;
	const [b, setB] = createSignal(0);
	createEffect<int32>(
		(prev: int32 | null): int32 => b(),
		(value: int32, prev: int32 | null): Cleanup | null => { effectCount = effectCount + 1; return null; },
	);
	flush();
	assert effectCount === 1 : "effect ran once initially";
	setB(1);
	flush();
	assert effectCount === 2 : "effect re-ran after setB(1)";
	setB(2);
	flush();
	assert effectCount === 3 : "effect re-ran after setB(2)";
}

test "effect reads correct signal value" {
	let lastSeen = -1;
	const [c, setC] = createSignal(42);
	createEffect<int32>(
		(prev: int32 | null): int32 => c(),
		(value: int32, prev: int32 | null): Cleanup | null => { lastSeen = value; return null; },
	);
	flush();
	assert lastSeen === 42 : "effect saw initial value 42";
	setC(99);
	flush();
	assert lastSeen === 99 : "effect saw updated value 99";
}

test "multiple effects on same signal" {
	let effect1Count = 0;
	let effect2Count = 0;
	const [d, setD] = createSignal(0);
	createEffect<int32>(
		(prev: int32 | null): int32 => d(),
		(value: int32, prev: int32 | null): Cleanup | null => { effect1Count = effect1Count + 1; return null; },
	);
	createEffect<int32>(
		(prev: int32 | null): int32 => d(),
		(value: int32, prev: int32 | null): Cleanup | null => { effect2Count = effect2Count + 1; return null; },
	);
	flush();
	assert effect1Count === 1 : "effect1 ran once initially";
	assert effect2Count === 1 : "effect2 ran once initially";
	setD(1);
	flush();
	assert effect1Count === 2 : "effect1 re-ran after change";
	assert effect2Count === 2 : "effect2 re-ran after change";
}
