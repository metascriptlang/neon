import { createSignal } from "../../src/core/signal";
import { createEffect } from "../../src/core/effect";
import { onCleanup } from "../../src/core/cleanup";
import { createRoot } from "../../src/core/owner";
import { getOwner } from "../../src/core/runtime";
import { Computation } from "../../src/core/types";

test "effect re-tracks and re-runs on signal change" {
	const [count, setCount] = createSignal(0);
	let runs = 0;
	let lastSeen = -1;
	createEffect(() => {
		lastSeen = count();
		runs = runs + 1;
	});
	assert runs === 1, "ran once on creation";
	assert lastSeen === 0, "saw initial 0";
	setCount(1);
	assert runs === 2, "re-ran on set(1)";
	assert lastSeen === 1, "saw 1";
}

test "onCleanup runs before each re-track and on dispose" {
	const [count, setCount] = createSignal(0);
	let cleanups = 0;
	const dispose = createEffect(() => {
		onCleanup(() => { cleanups = cleanups + 1; });
		count();
	});
	setCount(1);
	setCount(2);
	assert cleanups === 2, "cleanup ran before each re-track";
	dispose();
	assert cleanups === 3, "cleanup ran on dispose";
}

test "dispose severs the signal-to-computation edge" {
	const [count, setCount] = createSignal(0);
	let runs = 0;
	let lastSeen = -1;
	const dispose = createEffect(() => {
		lastSeen = count();
		runs = runs + 1;
	});
	dispose();
	setCount(3);
	assert runs === 1, "no re-run after dispose";
	assert lastSeen === 0, "never saw 3";
}

test "createRoot disposal cascades to owned effects" {
	let innerRuns = 0;
	const [tick, setTick] = createSignal(0);
	const disposers: (() => void)[] = [];
	createRoot((d) => {
		createEffect(() => { tick(); innerRuns = innerRuns + 1; });
		disposers.push(d);
	});
	assert innerRuns === 1, "owned effect ran once";
	setTick(1);
	assert innerRuns === 2, "owned effect re-ran";
	disposers[0]();
	setTick(2);
	assert innerRuns === 2, "owned effect disposed via root cascade";
}

test "a nested createRoot keeps the owner it was created under" {
	createRoot((outerDispose) => {
		const outer = getOwner();
		let seen: Computation | null = null;
		createRoot((innerDispose) => {
			const inner = getOwner() as Computation;
			seen = inner.owner;
			innerDispose();
		});
		assert seen === outer, "the inner root points at the outer owner";
		outerDispose();
	});
}

test "a nested createRoot is not disposed with the owner it was created under" {
	let cleaned = 0;
	let disposeInner: (() => void) | null = null;
	createRoot((outerDispose) => {
		createRoot((innerDispose) => {
			disposeInner = innerDispose;
			onCleanup(() => { cleaned = cleaned + 1; });
		});
		outerDispose();
	});
	assert cleaned === 0, "disposing the outer owner left the inner root alive";
	(disposeInner as () => void)();
	assert cleaned === 1, "the inner root tears down through its own dispose";
}

test "disposing a root drops its owner link" {
	createRoot((outerDispose) => {
		let inner: Computation | null = null;
		createRoot((innerDispose) => {
			inner = getOwner();
			innerDispose();
		});
		assert (inner as Computation).owner === null, "a disposed root no longer points at its owner";
		outerDispose();
	});
}
