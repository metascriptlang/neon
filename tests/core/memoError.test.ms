// Pins for a memo whose compute throws. Reference: solid-next packages/signals/src/core/core.ts:1794-1804: an errored node keeps
// its error and every read rethrows that same error; the node is not disposed and a later successful run clears it.
import { createSignal, Accessor } from "../../src/core/signal";
import { createAsyncMemo, createMemo } from "../../src/core/memo";
import { createEffect, createRenderEffect, EffectBundle } from "../../src/core/effect";
import { createRoot } from "../../src/core/owner";
import { createErrorBoundary } from "../../src/core/boundary";
import { flush } from "../../src/core/runtime";
import { Cleanup } from "../../src/core/types";
import { Gate, gated, rejectedWhenOpen, release } from "./asyncClock";

function failureOf<T>(read: () => T): Error | null {
	try {
		read();
	} catch (e) {
		return e;
	}
	return null;
}

test "a memo that throws on its first run rethrows the same error to every read and is not disposed" {
	const [fail, setFail] = createSignal<boolean>(true);
	const boom = new Error("first-run");
	const m = createRoot((d) => createMemo((p: int32 | null): int32 => { if (fail()) { throw boom; } return 5; }));
	assert failureOf<int32>(m) === boom, "the first read throws the compute's error";
	assert failureOf<int32>(m) === boom, "the second read throws the same object, not a different error";
	setFail(false);
	assert m() === 5, "the memo recomputed: it was not disposed";
	assert failureOf<int32>(m) === null, "and reads clean again";
}

test "a memo that throws on a later run rethrows the same error to every read and is not disposed" {
	const [fail, setFail] = createSignal<boolean>(false);
	const boom = new Error("later-run");
	const m = createRoot((d) => createMemo((p: string | null): string => { if (fail()) { throw boom; } return "fine"; }));
	assert m() === "fine", "first run";
	setFail(true);
	assert failureOf<string>(m) === boom, "the first read after the throw";
	assert failureOf<string>(m) === boom, "the second read";
	setFail(false);
	assert m() === "fine", "recovered, not disposed";
}

// boundaries.ts:161 caught: the boundary hears the compute's error once; a bare read afterwards rethrows it without a second report
test "under a boundary a first-run memo throw reaches the fallback once and later reads do not report it again" {
	const [fail, setFail] = createSignal<boolean>(true);
	const boom = new Error("handled-first");
	const seen: Error[] = [];
	let m: (() => int32) | null = null;
	createRoot((d) => {
		const memo = createMemo((p: int32 | null): int32 => { if (fail()) { throw boom; } return 5; });
		m = (): int32 => memo();
		const shown = createErrorBoundary<int32>(
			(): int32 => memo(),
			(e: Accessor<Error>, reset: () => void): int32 => { seen.push(e()); return -1; },
		);
		createRenderEffect<int32>((p: int32 | null): int32 => shown(), (v: int32, p: int32 | null): Cleanup | null => null);
		return 0;
	});
	flush();
	const read = m as () => int32;
	assert seen.length === 1 && seen[0] === boom, "the fallback heard the compute's error once: " + seen.length.toString();
	assert failureOf<int32>(read) === boom, "a bare read rethrows it";
	assert failureOf<int32>(read) === boom, "twice";
	assert seen.length === 1, "and a bare read does not build the fallback again: " + seen.length.toString();
	setFail(false);
	assert read() === 5, "the memo was not disposed by the boundary";
}

test "under a boundary a later-run memo throw reaches the fallback once and later reads do not report it again" {
	const [fail, setFail] = createSignal<boolean>(false);
	const boom = new Error("handled-later");
	const seen: Error[] = [];
	const applied: string[] = [];
	let m: (() => string) | null = null;
	createRoot((d) => {
		const memo = createMemo((p: string | null): string => { if (fail()) { throw boom; } return "fine"; });
		m = (): string => memo();
		const shown = createErrorBoundary<string>(
			(): string => memo(),
			(e: Accessor<Error>, reset: () => void): string => { seen.push(e()); return "fallback"; },
		);
		createRenderEffect<string>((p: string | null): string => shown(), (v: string, p: string | null): Cleanup | null => { applied.push(v); return null; });
		return 0;
	});
	const read = m as () => string;
	assert applied.join(",") === "fine" && seen.length === 0, "first run applied";
	setFail(true);
	assert seen.length === 1 && seen[0] === boom, "the fallback heard it once: " + seen.length.toString();
	assert failureOf<string>(read) === boom && failureOf<string>(read) === boom, "both bare reads rethrow the same error";
	assert seen.length === 1, "reads did not report it again";
	setFail(false);
	assert read() === "fine", "recovered, not disposed";
}

// core.ts:1794-1804: "Only a genuine reactive re-read may retry an errored source: tracking, and on a later cycle than the one the error was found".
test "a tracked read of an errored memo on a later cycle runs it again and a bare read does not" {
	const [tick, setTick] = createSignal<int32>(0);
	let attempts = 0;
	const m = createRoot((d) => createMemo((p: int32 | null): int32 => {
		attempts += 1;
		if (attempts < 2) { throw new Error("attempt " + attempts.toString()); }
		return attempts * 10;
	}));
	assert attempts === 1, "the first run threw";
	assert failureOf<int32>(m) !== null && failureOf<int32>(m) !== null, "bare reads see the error";
	assert attempts === 1, "and do not run it again: " + attempts.toString();
	setTick(1);
	assert attempts === 1, "a cycle passing alone does not run it either: " + attempts.toString();
	const seen: int32[] = [];
	createRoot((d) => {
		createRenderEffect<int32>((p: int32 | null): int32 => m(), (v: int32, p: int32 | null): Cleanup | null => { seen.push(v); return null; });
		return 0;
	});
	assert attempts === 2, "a reader that tracks it on a later cycle retried it: " + attempts.toString();
	assert seen.join(",") === "20", "got " + seen.join(",");
}

// Second axis: an errored async memo is asked again by a new tracked reader, and its landing reaches the reader that saw the error.
test "a tracked read of a rejected async memo on a later cycle asks again" {
	const gate = new Gate();
	const [tick, setTick] = createSignal<int32>(0);
	const boom = new Error("boom-retry");
	let attempts = 0;
	const log: string[] = [];
	const bundle: EffectBundle<int32> = {
		effect: (v: int32, p: int32 | null): Cleanup | null => { log.push("ok " + v.toString()); return null; },
		error: (err: Error, cleanup: Cleanup): void => { log.push("err " + err.message); },
	};
	const m = createRoot((d) => {
		const memo = createAsyncMemo((p: int32 | null): Promise<int32> => {
			attempts += 1;
			return attempts === 1 ? rejectedWhenOpen(gate, boom) : gated(gate, 9);
		});
		createEffect<int32>((p: int32 | null): int32 => memo(), bundle);
		return memo;
	});
	await release(gate);
	assert log.join(",") === "err boom-retry" && attempts === 1, "rejected: " + log.join(",");
	assert failureOf<int32>(m) === boom && attempts === 1, "a bare read sees it without asking again";
	gate.open = false;
	setTick(1);
	createRoot((d) => {
		createRenderEffect<int32>((p: int32 | null): int32 => m(), (v: int32, p: int32 | null): Cleanup | null => { log.push("second " + v.toString()); return null; });
		return 0;
	});
	assert attempts === 2, "the new tracked reader asked again: " + attempts.toString();
	await release(gate);
	assert log.join(",") === "err boom-retry,second 9,ok 9", "got " + log.join(",");
}
