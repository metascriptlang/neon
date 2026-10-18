import { createSignal } from "../../src/core/signal";
import { createEffect } from "../../src/core/effect";
import { onCleanup } from "../../src/core/cleanup";
import { createRoot } from "../../src/core/owner";
import { getOwner, flush } from "../../src/core/runtime";
import { Computation, Cleanup } from "../../src/core/types";

test "effect re-tracks and re-runs on signal change" {
	const [count, setCount] = createSignal(0);
	let runs = 0;
	let lastSeen = -1;
	createEffect<int32>(
		(p: int32 | null): int32 => count(),
		(v: int32, p: int32 | null): Cleanup | null => {
			lastSeen = v;
			runs = runs + 1;
			return null;
		},
	);
	flush();
	assert runs === 1, "ran once on creation";
	assert lastSeen === 0, "saw initial 0";
	setCount(1);
	flush();
	assert runs === 2, "re-ran on set(1)";
	assert lastSeen === 1, "saw 1";
}

test "onCleanup runs before each re-track and on dispose" {
	const [count, setCount] = createSignal(0);
	let cleanups = 0;
	let dispose: (() => void) | null = null;
	createRoot((d) => {
		dispose = d;
		createEffect<int32>(
			(p: int32 | null): int32 => {
				onCleanup(() => { cleanups = cleanups + 1; });
				return count();
			},
			(v: int32, p: int32 | null): Cleanup | null => null,
		);
	});
	flush();
	setCount(1);
	flush();
	setCount(2);
	flush();
	assert cleanups === 2, "cleanup ran before each re-track";
	(dispose as () => void)();
	assert cleanups === 3, "cleanup ran on dispose";
}

test "dispose severs the signal-to-computation edge" {
	const [count, setCount] = createSignal(0);
	let runs = 0;
	let lastSeen = -1;
	let dispose: (() => void) | null = null;
	createRoot((d) => {
		dispose = d;
		createEffect<int32>(
			(p: int32 | null): int32 => count(),
			(v: int32, p: int32 | null): Cleanup | null => {
				lastSeen = v;
				runs = runs + 1;
				return null;
			},
		);
	});
	flush();
	(dispose as () => void)();
	setCount(3);
	flush();
	assert runs === 1, "no re-run after dispose";
	assert lastSeen === 0, "never saw 3";
}

test "createRoot disposal cascades to owned effects" {
	let innerRuns = 0;
	const [tick, setTick] = createSignal(0);
	const disposers: (() => void)[] = [];
	createRoot((d) => {
		createEffect<int32>(
			(p: int32 | null): int32 => tick(),
			(v: int32, p: int32 | null): Cleanup | null => { innerRuns = innerRuns + 1; return null; },
		);
		disposers.push(d);
	});
	flush();
	assert innerRuns === 1, "owned effect ran once";
	setTick(1);
	flush();
	assert innerRuns === 2, "owned effect re-ran";
	disposers[0]();
	setTick(2);
	flush();
	assert innerRuns === 2, "owned effect disposed via root cascade";
}

test "a nested createRoot keeps the owner it was created under" {
	createRoot((outerDispose) => {
		const outer = getOwner();
		let seen: Computation | null = null;
		createRoot((innerDispose) => {
			const inner = getOwner() as Computation;
			seen = inner.parent;
			innerDispose();
		});
		assert seen === outer, "the inner root points at the outer owner";
		outerDispose();
	});
}

test "a nested createRoot is disposed with the owner it was created under" {
	let cleaned = 0;
	createRoot((outerDispose) => {
		createRoot((innerDispose) => {
			onCleanup(() => { cleaned = cleaned + 1; });
		});
		outerDispose();
	});
	assert cleaned === 1, "disposing the outer owner tore down the inner root";
}

test "disposing a root drops its owner link" {
	createRoot((outerDispose) => {
		let inner: Computation | null = null;
		createRoot((innerDispose) => {
			inner = getOwner();
			innerDispose();
		});
		assert (inner as Computation).parent === null, "a disposed root no longer points at its owner";
		outerDispose();
	});
}
