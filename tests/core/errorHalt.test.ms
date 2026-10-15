// Pins for what an uncaught error does to the reactive system. Reference: solid-next packages/signals/tests/errorHalt.test.ts (A5)
// and effect-error-phases.test.ts. An error that escapes every handler halts scheduling until resetErrorHalt: app state is
// undefined after it, so the scheduler stops accepting work instead of applying half of an update.
// The reference also asserts what console.error was called with; a test here cannot observe the console, so the halt message
// and the cause logged beside it are not pinned.
import { createSignal, Accessor } from "../../src/core/signal";
import { createAsyncMemo } from "../../src/core/memo";
import { createEffect, createRenderEffect, EffectBundle } from "../../src/core/effect";
import { createRoot } from "../../src/core/owner";
import { createErrorBoundary } from "../../src/core/boundary";
import { flush, resetErrorHalt } from "../../src/core/runtime";
import { Cleanup } from "../../src/core/types";
import { Gate, rejectedWhenOpen, release } from "./asyncClock";

// errorHalt.test.ts "flush() after a halt is a no-op rather than a throw"
test "flush after a halt does nothing and does not throw" {
	const [a, setA] = createSignal<int32>(0);
	createRoot((d) => {
		createEffect<int32>((p: int32 | null): int32 => a(), (v: int32, p: int32 | null): Cleanup | null => { if (v === 1) { throw new Error("boom"); } return null; });
		return 0;
	});
	let message = "";
	try { setA(1); } catch (e) { message = e.message; }
	assert message === "boom", "the first throw reaches the caller: [" + message + "]";
	let again = "";
	try { flush(); } catch (e) { again = e.message; }
	assert again === "", "a halted flush is quiet: [" + again + "]";
	resetErrorHalt();
}

// errorHalt.test.ts "does not halt when an error boundary handles the error"
test "a handled effect-phase error does not halt the system" {
	const [a, setA] = createSignal<int32>(0);
	const [c, setC] = createSignal<int32>(0);
	const seenC: int32[] = [];
	const handled: string[] = [];
	createRoot((d) => {
		const shown = createErrorBoundary<string>(
			(): string => {
				createEffect<int32>((p: int32 | null): int32 => a(), (v: int32, p: int32 | null): Cleanup | null => { if (v === 1) { throw new Error("boom"); } return null; });
				return "content";
			},
			(e: Accessor<Error>, reset: () => void): string => { handled.push(e().message); return "errored"; },
		);
		createRenderEffect<string>((p: string | null): string => shown(), (v: string, p: string | null): Cleanup | null => null);
		createEffect<int32>((p: int32 | null): int32 => c(), (v: int32, p: int32 | null): Cleanup | null => { seenC.push(v); return null; });
		return 0;
	});
	seenC.length = 0;
	setA(1);
	assert handled.join(",") === "boom", "the boundary took it: " + handled.join(",");
	setC(3);
	assert seenC.join(",") === "3", "and the system kept running: " + seenC.join(",");
}

// errorHalt.test.ts "detaches a throwing cleanup so it never re-fires (#2813)"
test "a cleanup that throws is detached and does not run again after the system is revived" {
	const [n, setN] = createSignal<int32>(0);
	const bodyRuns: int32[] = [];
	const cleanupRuns: int32[] = [];
	createRoot((d) => {
		createEffect<int32>(
			(p: int32 | null): int32 => n(),
			(v: int32, p: int32 | null): Cleanup | null => {
				bodyRuns.push(v);
				return (): void => {
					cleanupRuns.push(v);
					if (v === 0) { throw new Error("cleanup boom"); }
				};
			},
		);
		return 0;
	});
	assert bodyRuns.join(",") === "0", "mounted";
	let message = "";
	try { setN(1); } catch (e) { message = e.message; }
	assert message === "cleanup boom", "got [" + message + "]";
	resetErrorHalt();
	setN(2);
	let zeroRuns = 0;
	for (const v of cleanupRuns) { if (v === 0) { zeroRuns += 1; } }
	assert zeroRuns === 1, "the throwing cleanup ran once: " + cleanupRuns.join(",");
	assert bodyRuns.indexOf(2) >= 0, "and the effect works again: " + bodyRuns.join(",");
}

// effect-error-phases.test.ts "compute-phase throw with no handler: logged, run skipped, system alive", with the throw a rejection
test "an unhandled rejection read by an effect skips its run and leaves the system alive" {
	const gate = new Gate();
	const [beat, setBeat] = createSignal<int32>(0);
	const log: string[] = [];
	createRoot((d) => {
		const m = createAsyncMemo((p: int32 | null): Promise<int32> => rejectedWhenOpen(gate, new Error("boom-reject")));
		createRenderEffect<int32>((p: int32 | null): int32 => beat(), (v: int32, p: int32 | null): Cleanup | null => { log.push("beat=" + v.toString()); return null; });
		createEffect<int32>((p: int32 | null): int32 => m(), (v: int32, p: int32 | null): Cleanup | null => { log.push("effect ran"); return null; });
		return 0;
	});
	assert log.join(",") === "beat=0", "mounted: " + log.join(",");
	await release(gate);
	assert log.join(",") === "beat=0", "the rejected effect did not run: " + log.join(",");
	setBeat(1);
	assert log.join(",") === "beat=0,beat=1", "and the rest of the graph still does: " + log.join(",");
}

// effect-error-phases.test.ts "handler rethrow escalates ...": the error arm of an async rejection that rethrows reaches the nearest boundary
test "an error arm that rethrows a rejection escalates to the nearest boundary" {
	const gate = new Gate();
	const log: string[] = [];
	const bundle: EffectBundle<int32> = {
		effect: (v: int32, p: int32 | null): Cleanup | null => null,
		error: (err: Error, cleanup: Cleanup): void => { log.push("arm saw " + err.message); throw err; },
	};
	createRoot((d) => {
		const shown = createErrorBoundary<string>(
			(): string => {
				const m = createAsyncMemo((p: int32 | null): Promise<int32> => rejectedWhenOpen(gate, new Error("boom-escalate")));
				createEffect<int32>((p: int32 | null): int32 => m(), bundle);
				return "content";
			},
			(e: Accessor<Error>, reset: () => void): string => { log.push("caught " + e().message); return "errored"; },
		);
		createRenderEffect<string>((p: string | null): string => shown(), (v: string, p: string | null): Cleanup | null => null);
		return 0;
	});
	await release(gate);
	assert log.join(",") === "arm saw boom-escalate,caught boom-escalate", "got " + log.join(",");
}
