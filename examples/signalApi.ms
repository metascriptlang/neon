// Signal API test suite — peek, untrack, flush.

import { createSignal, untrack } from "../src/core/signal";
import { flush } from "../src/core/runtime";
import { createEffect } from "../src/core/effect";
import { Cleanup } from "../src/core/types";

test "getter returns correct value" {
	const [val, setVal] = createSignal(42);
	assert val() === 42 : "getter returns correct value";
}

test "untrack reads without subscribing" {
	let untrackedEffectCount = 0;
	const [x, setX] = createSignal(10);
	const [y, setY] = createSignal(20);
	createEffect<int32>(
		(prev: int32 | null): int32 => x(),
		(xVal: int32, prev: int32 | null): Cleanup | null => {
			const yVal = untrack(() => y());
			untrackedEffectCount = untrackedEffectCount + 1;
			return null;
		},
	);
	assert untrackedEffectCount === 1 : "effect ran once initially";
	setY(99);
	assert untrackedEffectCount === 1 : "effect did NOT re-run on untracked signal change";
	setX(11);
	assert untrackedEffectCount === 2 : "effect DID re-run on tracked signal change";
}

test "flush(fn) defers effect execution" {
	let batchEffectCount = 0;
	const [a, setA] = createSignal(0);
	createEffect<int32>(
		(prev: int32 | null): int32 => a(),
		(value: int32, prev: int32 | null): Cleanup | null => { batchEffectCount = batchEffectCount + 1; return null; },
	);
	assert batchEffectCount === 1 : "effect ran once initially";
	flush(() => {
		setA(1);
		setA(2);
		setA(3);
	});
	assert batchEffectCount === 2 : "effect ran once after flush (not 3 times)";
	assert a() === 3 : "final value correct after flush";
}

test "flush(fn) with multiple signals" {
	let multiEffectCount = 0;
	const [p, setP] = createSignal(0);
	const [q, setQ] = createSignal(0);
	createEffect<int32>(
		(prev: int32 | null): int32 => p() + q(),
		(sum: int32, prev: int32 | null): Cleanup | null => { multiEffectCount = multiEffectCount + 1; return null; },
	);
	assert multiEffectCount === 1 : "multi-signal effect ran once initially";
	flush(() => {
		setP(10);
		setQ(20);
	});
	assert multiEffectCount === 2 : "multi-signal effect ran once after flush";
	assert p() === 10 : "first signal correct after flush";
	assert q() === 20 : "second signal correct after flush";
}
