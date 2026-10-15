// Pins for createLoadingBoundary and for the two boundaries composed. Reference: solid-next packages/signals/tests/createLoadingBoundary.test.ts
// and createErrorBoundary.test.ts @ 84dada77, each test cites its line. A promise is held by a Gate (on C an already-settled promise
// continues synchronously: compiler card 2026-10-15-await-of-a-settled-promise-continues-synchronously-on-c), and the async memo
// lives outside the boundary's content, as the reference's tests place it. Left out: `on` (re-arming goes through a held frame, and
// this core has no frames), projections (no store here), the fresh-boundary-around-updating-source group (:655-1050, held lanes) and
// "holds every queued run behind the fallback" (:1191).
import { createSignal, Accessor } from "../../src/core/signal";
import { createAsyncMemo } from "../../src/core/memo";
import { createEffect, createRenderEffect } from "../../src/core/effect";
import { createRoot } from "../../src/core/owner";
import { createErrorBoundary, createLoadingBoundary } from "../../src/core/boundary";
import { flush } from "../../src/core/runtime";
import { Cleanup } from "../../src/core/types";
import { Gate, gated, opened, rejectedWhenOpen, release } from "./asyncClock";

class Shown {
	text: string = "";
	runs: int32 = 0;
}

function show(shown: Shown, read: Accessor<string>): void {
	createRenderEffect<string>(
		(p: string | null): string => read(),
		(v: string, p: string | null): Cleanup | null => { shown.text = v; shown.runs += 1; return null; },
	);
}

// createLoadingBoundary.test.ts:559-590 (same value, different value) and :32
test "a pending read shows the fallback and then the content" {
	const gate = new Gate();
	const shown = new Shown();
	createRoot((d) => {
		const data = createAsyncMemo((p: int32 | null): Promise<int32> => gated(gate, 101));
		show(shown, createLoadingBoundary<string>((): string => data().toString(), (): string => "loading"));
		return 0;
	});
	assert shown.text === "loading", "the fallback shows while the read is pending: [" + shown.text + "]";
	await release(gate);
	assert shown.text === "101", "the content shows once it landed: [" + shown.text + "]";
}

// createLoadingBoundary.test.ts:620
test "the content is not made again when its read lands" {
	const gate = new Gate();
	const shown = new Shown();
	let computes = 0;
	let contents = 0;
	createRoot((d) => {
		const data = createAsyncMemo((p: int32 | null): Promise<int32> => { computes += 1; return gated(gate, 100); });
		show(shown, createLoadingBoundary<string>((): string => { contents += 1; return data().toString(); }, (): string => "loading"));
		return 0;
	});
	assert computes === 1 && shown.text === "loading", "fallback, one compute: computes=" + computes.toString();
	const madeBefore = contents;
	await release(gate);
	assert shown.text === "100", "content: [" + shown.text + "]";
	assert computes === 1, "the source was not asked again: " + computes.toString();
	assert contents === madeBefore + 1, "the content ran once more to read the landed value, not once per reader: " + contents.toString();
}

// createLoadingBoundary.test.ts:436
test "a reader of the boundary runs for the fallback and again for the content" {
	const gate = new Gate();
	const shown = new Shown();
	createRoot((d) => {
		const data = createAsyncMemo((p: int32 | null): Promise<int32> => gated(gate, 1));
		show(shown, createLoadingBoundary<string>((): string => data().toString(), (): string => "loading"));
		return 0;
	});
	assert shown.runs === 1 && shown.text === "loading", "the first run shows the fallback: runs=" + shown.runs.toString();
	await release(gate);
	assert shown.runs === 2 && shown.text === "1", "the second run shows the content: runs=" + shown.runs.toString();
}

// createLoadingBoundary.test.ts:139
test "two boundaries over two reads clear independently" {
	const gateA = new Gate();
	const gateB = new Gate();
	const first = new Shown();
	const second = new Shown();
	createRoot((d) => {
		const a = createAsyncMemo((p: int32 | null): Promise<int32> => gated(gateA, 1));
		const b = createAsyncMemo((p: int32 | null): Promise<int32> => gated(gateB, 2));
		show(first, createLoadingBoundary<string>((): string => a().toString(), (): string => "loading"));
		show(second, createLoadingBoundary<string>((): string => b().toString(), (): string => "loading"));
		return 0;
	});
	assert first.text === "loading" && second.text === "loading", "both wait";
	await release(gateA);
	assert first.text === "1" && second.text === "loading", "only the first cleared: [" + first.text + "][" + second.text + "]";
	await release(gateB);
	assert first.text === "1" && second.text === "2", "then the second: [" + first.text + "][" + second.text + "]";
}

// createLoadingBoundary.test.ts:183
test "the nearest Loading catches the pending read" {
	const gate = new Gate();
	const outerShown = new Shown();
	const innerShown = new Shown();
	createRoot((d) => {
		const data = createAsyncMemo((p: int32 | null): Promise<int32> => gated(gate, 1));
		show(outerShown, createLoadingBoundary<string>(
			(): string => {
				show(innerShown, createLoadingBoundary<string>((): string => data().toString(), (): string => "inner-loading"));
				return "outer-content";
			},
			(): string => "outer-loading",
		));
		return 0;
	});
	assert innerShown.text === "inner-loading", "the inner one waits: [" + innerShown.text + "]";
	assert outerShown.text === "outer-content", "the outer one shows its content: [" + outerShown.text + "]";
	await release(gate);
	assert innerShown.text === "1" && outerShown.text === "outer-content", "[" + innerShown.text + "][" + outerShown.text + "]";
}

// createLoadingBoundary.test.ts:229 (Loading > Errored and Errored > Loading, one rejection)
test "a rejection reaches the Errored in either nesting order" {
	const gate = new Gate();
	const loadingOutside = new Shown();
	const erroredOutside = new Shown();
	createRoot((d) => {
		const source = createAsyncMemo((p: int32 | null): Promise<int32> => rejectedWhenOpen(gate, new Error("rejected")));
		show(loadingOutside, createLoadingBoundary<string>(
			(): string => createErrorBoundary<string>((): string => source().toString(), (e: Accessor<Error>, reset: () => void): string => "error1")(),
			(): string => "waiting",
		));
		show(erroredOutside, createErrorBoundary<string>(
			(): string => createLoadingBoundary<string>((): string => source().toString(), (): string => "waiting")(),
			(e: Accessor<Error>, reset: () => void): string => "error2",
		));
		return 0;
	});
	assert loadingOutside.text === "waiting" && erroredOutside.text === "waiting", "both wait: [" + loadingOutside.text + "][" + erroredOutside.text + "]";
	await release(gate);
	assert loadingOutside.text === "error1", "Loading outside: [" + loadingOutside.text + "]";
	assert erroredOutside.text === "error2", "Errored outside: [" + erroredOutside.text + "]";
}

// createLoadingBoundary.test.ts:1106
test "a pending child that is dropped stops the loading" {
	const gate = new Gate();
	const shown = new Shown();
	const [showAsync, setShowAsync] = createSignal<boolean>(true);
	createRoot((d) => {
		show(shown, createLoadingBoundary<string>(
			(): string => {
				if (!showAsync()) { return "sync"; }
				const data = createAsyncMemo((p: int32 | null): Promise<int32> => gated(gate, 1));
				return data().toString();
			},
			(): string => "loading",
		));
		return 0;
	});
	assert shown.text === "loading", "waiting on the child: [" + shown.text + "]";
	setShowAsync(false);
	flush();
	assert shown.text === "sync", "the child was dropped and the boundary stopped waiting: [" + shown.text + "]";
	await release(gate);
	assert shown.text === "sync", "and its landing changes nothing: [" + shown.text + "]";
}

// createLoadingBoundary.test.ts:1144
test "a second reader going pending does not rebuild the fallback" {
	const gateA = new Gate();
	const gateB = new Gate();
	const shown = new Shown();
	let fallbackRuns = 0;
	const [wantB, setWantB] = createSignal<boolean>(false);
	createRoot((d) => {
		const dataA = createAsyncMemo((p: int32 | null): Promise<int32> => gated(gateA, 1));
		const dataB = createAsyncMemo((p: int32 | null): Promise<int32> => gated(gateB, 2));
		show(shown, createLoadingBoundary<string>(
			(): string => {
				createRenderEffect<int32>((p: int32 | null): int32 => dataA(), (v: int32, q: int32 | null): Cleanup | null => null);
				createRenderEffect<int32>((p: int32 | null): int32 => wantB() ? dataB() : 0, (v: int32, q: int32 | null): Cleanup | null => null);
				return "ready";
			},
			(): string => { fallbackRuns += 1; return "loading"; },
		));
		return 0;
	});
	assert shown.text === "loading" && fallbackRuns === 1, "first show: runs=" + fallbackRuns.toString();
	setWantB(true);
	flush();
	assert fallbackRuns === 1, "a second reader suspends and the fallback is kept: " + fallbackRuns.toString();
	await release(gateA);
	assert shown.text === "loading" && fallbackRuns === 1, "still waiting on the second: [" + shown.text + "] " + fallbackRuns.toString();
	await release(gateB);
	assert shown.text === "ready" && fallbackRuns === 1, "ready: [" + shown.text + "] " + fallbackRuns.toString();
}

// createLoadingBoundary.test.ts:1191
test "queued runs wait behind the fallback and go once at the reveal" {
	const gate = new Gate();
	const shown = new Shown();
	const log: string[] = [];
	const [count, setCount] = createSignal<int32>(0);
	createRoot((d) => {
		const data = createAsyncMemo((p: int32 | null): Promise<int32> => gated(gate, 7));
		show(shown, createLoadingBoundary<string>(
			(): string => {
				createRenderEffect<int32>((p: int32 | null): int32 => data(), (v: int32, q: int32 | null): Cleanup | null => null);
				createRenderEffect<int32>((p: int32 | null): int32 => count(), (v: int32, q: int32 | null): Cleanup | null => { log.push("render " + v.toString()); return null; });
				createEffect<int32>((p: int32 | null): int32 => count(), (v: int32, q: int32 | null): Cleanup | null => { log.push("user " + v.toString()); return null; });
				return "ready";
			},
			(): string => "loading",
		));
		return 0;
	});
	assert shown.text === "loading", "[" + shown.text + "]";
	assert log.join(",") === "render 0", "the render effect's first run is synchronous, the user effect's waits: " + log.join(",");
	setCount(1);
	flush();
	assert log.join(",") === "render 0", "a queued update waits too: " + log.join(",");
	await release(gate);
	assert shown.text === "ready", "[" + shown.text + "]";
	assert log.join(",") === "render 0,render 1,user 1", "one run each with the latest value, the render update first: " + log.join(",");
	setCount(2);
	flush();
	assert log.join(",") === "render 0,render 1,user 1,render 2,user 2", "then they run as usual: " + log.join(",");
}

// createErrorBoundary.test.ts:939
test "a content error goes past a Loading to the outer Errored" {
	const shown = new Shown();
	createRoot((d) => {
		show(shown, createErrorBoundary<string>(
			(): string => createLoadingBoundary<string>((): string => { throw new Error("boom on mount"); }, (): string => "loading")(),
			(e: Accessor<Error>, reset: () => void): string => "outer caught",
		));
		return 0;
	});
	flush();
	assert shown.text === "outer caught", "[" + shown.text + "]";
}

// createErrorBoundary.test.ts:963
test "a later content error goes past a committed Loading to the outer Errored" {
	const shown = new Shown();
	const [boom, setBoom] = createSignal<boolean>(false);
	createRoot((d) => {
		show(shown, createErrorBoundary<string>(
			(): string => createLoadingBoundary<string>((): string => { if (boom()) { throw new Error("boom"); } return "ok"; }, (): string => "loading")(),
			(e: Accessor<Error>, reset: () => void): string => "outer caught",
		));
		return 0;
	});
	flush();
	assert shown.text === "ok", "[" + shown.text + "]";
	setBoom(true);
	flush();
	assert shown.text === "outer caught", "[" + shown.text + "]";
}

// createErrorBoundary.test.ts:868 and :877
test "an inner Errored inside a Loading inside an Errored catches its own content" {
	const onMount = new Shown();
	const later = new Shown();
	const [boom, setBoom] = createSignal<boolean>(false);
	createRoot((d) => {
		show(onMount, createErrorBoundary<string>(
			(): string => createLoadingBoundary<string>(
				(): string => createErrorBoundary<string>((): string => { throw new Error("boom on mount"); }, (e: Accessor<Error>, reset: () => void): string => "inner caught")(),
				(): string => "loading",
			)(),
			(e: Accessor<Error>, reset: () => void): string => "outer caught",
		));
		show(later, createErrorBoundary<string>(
			(): string => createLoadingBoundary<string>(
				(): string => createErrorBoundary<string>((): string => { if (boom()) { throw new Error("boom"); } return "ok"; }, (e: Accessor<Error>, reset: () => void): string => "inner caught")(),
				(): string => "loading",
			)(),
			(e: Accessor<Error>, reset: () => void): string => "outer caught",
		));
		return 0;
	});
	flush();
	assert onMount.text === "inner caught", "on mount: [" + onMount.text + "]";
	assert later.text === "ok", "healthy first: [" + later.text + "]";
	setBoom(true);
	flush();
	assert later.text === "inner caught", "after a healthy commit: [" + later.text + "]";
}

// createErrorBoundary.test.ts:892
test "an async rejection is caught at the inner Errored of Errored > Loading > Errored" {
	const gate = new Gate();
	const shown = new Shown();
	createRoot((d) => {
		const data = createAsyncMemo((p: int32 | null): Promise<int32> => rejectedWhenOpen(gate, new Error("boom async")));
		show(shown, createErrorBoundary<string>(
			(): string => createLoadingBoundary<string>(
				(): string => createErrorBoundary<string>((): string => "value: " + data().toString(), (e: Accessor<Error>, reset: () => void): string => "inner caught")(),
				(): string => "loading",
			)(),
			(e: Accessor<Error>, reset: () => void): string => "outer caught",
		));
		return 0;
	});
	assert shown.text === "loading", "[" + shown.text + "]";
	await release(gate);
	assert shown.text === "inner caught", "[" + shown.text + "]";
}

// createErrorBoundary.test.ts:493 (the async arm of "recover when a memo errors, its input changes and the boundary resets").
// Parked on ~/metascript/.inbox/compiler/2026-10-16-awaiting-a-late-rejected-string-promise-held-in-a-parameter-segfaults-on-c.md: the
// reference's string payload ("Test Item") segfaults on C when the promise rejects, so this runs with an int32 payload.
test "reset recovers an async memo whose input changed" {
	let gate = new Gate();
	const shown = new Shown();
	const [id, setId] = createSignal<int32>(0);
	let resetFn: (() => void) | null = null;
	createRoot((d) => {
		const data = createAsyncMemo((p: int32 | null): Promise<int32> => gatedLookup(gate, id()));
		show(shown, createErrorBoundary<string>(
			(): string => createLoadingBoundary<string>((): string => data().toString(), (): string => "loading")(),
			(e: Accessor<Error>, reset: () => void): string => { resetFn = reset; return "error: " + e().message; },
		));
		return 0;
	});
	assert shown.text === "loading", "[" + shown.text + "]";
	await release(gate);
	assert shown.text === "error: Item 0 not found", "[" + shown.text + "]";
	gate = new Gate();
	setId(1);
	(resetFn as () => void)();
	flush();
	await release(gate);
	assert shown.text === "42", "recovered: [" + shown.text + "]";
}

async function gatedLookup(gate: Gate, id: int32): Promise<int32> {
	await opened(gate);
	if (id !== 1) { throw new Error("Item " + id.toString() + " not found"); }
	return 42;
}
