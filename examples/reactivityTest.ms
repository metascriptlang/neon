// Reactivity test suite — fine-grained signal/effect behavior.

import { createSignal } from "../src/core/signal";
import { createEffect } from "../src/core/effect";

test "signal get/set basics" {
	const [count, setCount] = createSignal(0);
	assert count() === 0 : "initial value is 0";
	setCount(5);
	assert count() === 5 : "value after set is 5";
	setCount(10);
	assert count() === 10 : "value after second set is 10";
}

test "effect auto-runs on creation" {
	let effectRan = 0;
	const [a, setA] = createSignal(1);
	createEffect(() => {
		a();
		effectRan = effectRan + 1;
	});
	assert effectRan === 1 : "effect ran once on creation";
}

test "effect re-runs on signal change" {
	let effectCount = 0;
	const [b, setB] = createSignal(0);
	createEffect(() => {
		b();
		effectCount = effectCount + 1;
	});
	assert effectCount === 1 : "effect ran once initially";
	setB(1);
	assert effectCount === 2 : "effect re-ran after setB(1)";
	setB(2);
	assert effectCount === 3 : "effect re-ran after setB(2)";
}

test "effect reads correct signal value" {
	let lastSeen = -1;
	const [c, setC] = createSignal(42);
	createEffect(() => {
		lastSeen = c();
	});
	assert lastSeen === 42 : "effect saw initial value 42";
	setC(99);
	assert lastSeen === 99 : "effect saw updated value 99";
}

test "multiple effects on same signal" {
	let effect1Count = 0;
	let effect2Count = 0;
	const [d, setD] = createSignal(0);
	createEffect(() => {
		d();
		effect1Count = effect1Count + 1;
	});
	createEffect(() => {
		d();
		effect2Count = effect2Count + 1;
	});
	assert effect1Count === 1 : "effect1 ran once initially";
	assert effect2Count === 1 : "effect2 ran once initially";
	setD(1);
	assert effect1Count === 2 : "effect1 re-ran after change";
	assert effect2Count === 2 : "effect2 re-ran after change";
}
