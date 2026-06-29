// Signal Tests
// Unit tests for reactive signal primitive

import { createSignal } from "../../src/core/signal";
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
