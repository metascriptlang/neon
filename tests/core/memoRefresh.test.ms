// Pins for refresh(target). Reference: solid-next packages/signals/tests/createMemo.test.ts (the refresh cases from :640),
// src/signals.ts:876 for the target rules. refresh takes an Accessor, so the reference's unbranded-function and
// non-source-object rejections (INVALID_REFRESH_TARGET) are compile errors here and have no runtime pin.
import { createSignal } from "../../src/core/signal";
import { createAsyncMemo, createMemo, refresh } from "../../src/core/memo";
import { createEffect, createRenderEffect, EffectBundle } from "../../src/core/effect";
import { createRoot } from "../../src/core/owner";
import { flush, isPending } from "../../src/core/runtime";
import { Cleanup } from "../../src/core/types";
import { Gate, gated, rejectedWhenOpen, release } from "./asyncClock";

// createMemo.test.ts:640 "should handle refreshes"
test "a refresh with no input change is a quiet re-ask: never pending, the new value just reveals" {
	const gate = new Gate();
	let n: int32 = 1;
	const log: string[] = [];
	const a = createRoot((d) => {
		const m = createAsyncMemo((p: int32 | null): Promise<int32> => { const v = n; n += 1; return gated(gate, v); });
		createRenderEffect<string>(
			(p: string | null): string => isPending((): int32 => m()) ? "stale" : m().toString(),
			(v: string, p: string | null): Cleanup | null => { log.push(v); return null; },
		);
		return m;
	});
	assert log.length === 0, "the first load shows nothing yet";
	await release(gate);
	assert log.join(",") === "1", "got " + log.join(",");
	gate.open = false;
	refresh(a);
	flush();
	assert log.join(",") === "1", "a re-ask in flight is not stale: " + log.join(",");
	await release(gate);
	assert log.join(",") === "1,2", "got " + log.join(",");
	gate.open = false;
	refresh(a);
	flush();
	assert log.join(",") === "1,2", "again quiet: " + log.join(",");
	await release(gate);
	assert log.join(",") === "1,2,3", "got " + log.join(",");
}

// Second axis: a chain of two async memos refreshed at the upstream one. The re-ask is quiet until its answer changes the input of the
// downstream one, which then is a new question.
test "refreshing the upstream memo of a chain is quiet until its new answer reaches the downstream memo" {
	const gateA = new Gate();
	const gateB = new Gate();
	let n: int32 = 1;
	const log: string[] = [];
	const a = createRoot((d) => {
		const upstream = createAsyncMemo((p: int32 | null): Promise<int32> => { const v = n; n += 1; return gated(gateA, v); });
		const downstream = createAsyncMemo((p: int32 | null): Promise<int32> => gated(gateB, upstream() * 10));
		createRenderEffect<string>(
			(p: string | null): string => isPending((): int32 => downstream()) ? "stale" : downstream().toString(),
			(v: string, p: string | null): Cleanup | null => { log.push(v); return null; },
		);
		return upstream;
	});
	await release(gateA);
	await release(gateB);
	assert log.join(",") === "10", "got " + log.join(",");
	gateA.open = false;
	gateB.open = false;
	refresh(a);
	flush();
	assert log.join(",") === "10", "the re-ask alone is quiet: " + log.join(",");
	await release(gateA);
	assert log.join(",") === "10,stale", "the changed answer makes the downstream memo's run a new question: " + log.join(",");
	await release(gateB);
	assert log.join(",") === "10,stale,20", "got " + log.join(",");
}

// createMemo.test.ts:672 "should only refresh the targeted memo, not its upstream memos (#2691)"
test "refresh runs the target again and leaves the memos it reads alone" {
	let upstreamRuns = 0;
	let downstreamRuns = 0;
	const downstream = createRoot((d) => {
		const upstream = createMemo((p: int32 | null): int32 => { upstreamRuns += 1; return 0; });
		const memo = createMemo((p: int32 | null): int32 => { downstreamRuns += 1; return upstream(); });
		return memo;
	});
	flush();
	assert upstreamRuns === 1 && downstreamRuns === 1, "mounted";
	refresh(downstream);
	flush();
	assert upstreamRuns === 1, "upstream stayed: " + upstreamRuns.toString();
	assert downstreamRuns === 2, "downstream ran again: " + downstreamRuns.toString();
}

// createMemo.test.ts:697 "should refresh explicit targets but not their deps (#2691)"
test "refreshing two targets runs each of them and none of their dependencies" {
	let aRuns = 0;
	let bRuns = 0;
	let aDepRuns = 0;
	let bDepRuns = 0;
	const [s, setS] = createSignal<string>("s");
	const targets = createRoot((d) => {
		const aDep = createMemo((p: string | null): string => { aDepRuns += 1; return s() + "a"; });
		const bDep = createMemo((p: string | null): string => { bDepRuns += 1; return s() + "b"; });
		const a = createMemo((p: string | null): string => { aRuns += 1; return aDep(); });
		const b = createMemo((p: string | null): string => { bRuns += 1; return bDep(); });
		return [a, b];
	});
	flush();
	assert aRuns === 1 && bRuns === 1 && aDepRuns === 1 && bDepRuns === 1, "mounted";
	refresh(targets[0]);
	refresh(targets[1]);
	flush();
	assert aRuns === 2 && bRuns === 2, "both targets ran again";
	assert aDepRuns === 1 && bDepRuns === 1, "neither dependency did";
}

// createMemo.test.ts:738 "coalesces multiple refreshes of the same target in one flush"
test "three refreshes of one target in one flush run it once" {
	let runs = 0;
	const target = createRoot((d) => createMemo((p: int32 | null): int32 => { runs += 1; return runs; }));
	flush();
	assert runs === 1, "mounted";
	flush((): void => {
		refresh(target);
		refresh(target);
		refresh(target);
	});
	assert runs === 2, "got " + runs.toString();
}

// createMemo.test.ts:797 "refresh() does not throw upstream pending reads from a plain memo (#2694)"
test "refresh of a memo whose input is a pending async memo does not throw" {
	const never = new Gate();
	const target = createRoot((d) => {
		const source = createAsyncMemo((p: int32 | null): Promise<int32> => gated(never, 1));
		const memo = createMemo((p: int32 | null): int32 => source() + 1);
		createRenderEffect<int32>((p: int32 | null): int32 => memo(), (v: int32, p: int32 | null): Cleanup | null => null);
		return memo;
	});
	let threw = false;
	try { refresh(target); } catch (e) { threw = true; }
	assert !threw, "the pending read of the input was not thrown at the caller";
	never.open = true;
	await release(never);
}

// createMemo.test.ts:833 "refresh() treats plain signal accessors as no-op targets"
test "refresh of a plain signal accessor is a no-op" {
	const [count, setCount] = createSignal<string>("zero");
	let effects = 0;
	createRoot((d) => {
		createEffect<string>((p: string | null): string => count(), (v: string, p: string | null): Cleanup | null => { effects += 1; return null; });
		return 0;
	});
	refresh(count);
	flush();
	assert count() === "zero" && effects === 1, "nothing ran again: " + effects.toString();
}

// signals.ts:876 and core.ts markRefresh: an invalidation is not a thing a computation may do.
test "refresh inside an owned scope is refused" {
	const target = createRoot((d) => createMemo((p: int32 | null): int32 => 1));
	let message = "";
	createRoot((d) => {
		try { refresh(target); } catch (e) { message = e.message; }
		return 0;
	});
	assert message.indexOf("REACTIVE_WRITE_IN_OWNED_SCOPE") >= 0, "got [" + message + "]";
}

// recompute-preserves-disposed-3621.test.ts: refresh() does not re-run a disposed memo
test "refresh of a memo whose owner is disposed does not run it" {
	let runs = 0;
	let stop: (() => void) | null = null;
	const target = createRoot((d) => {
		stop = d;
		return createMemo((p: string | null): string => { runs += 1; return "x"; });
	});
	flush();
	assert runs === 1, "mounted";
	if (stop !== null) { stop(); }
	refresh(target);
	flush();
	assert runs === 1, "a disposed memo stays quiet: " + runs.toString();
}

// A refresh after a rejection runs the compute again, and the landing clears the error.
test "refresh of a rejected async memo asks again and a landing clears the error" {
	const gate = new Gate();
	const boom = new Error("boom-refresh");
	let attempt: int32 = 0;
	const log: string[] = [];
	const bundle: EffectBundle<int32> = {
		effect: (v: int32, p: int32 | null): Cleanup | null => { log.push("ok " + v.toString()); return null; },
		error: (err: Error, cleanup: Cleanup): void => { log.push("err " + err.message); },
	};
	const target = createRoot((d) => {
		const m = createAsyncMemo((p: int32 | null): Promise<int32> => {
			attempt += 1;
			return attempt === 1 ? rejectedWhenOpen(gate, boom) : gated(gate, attempt);
		});
		createEffect<int32>((p: int32 | null): int32 => m(), bundle);
		return m;
	});
	await release(gate);
	assert log.join(",") === "err boom-refresh", "rejected: " + log.join(",");
	gate.open = false;
	refresh(target);
	await release(gate);
	assert log.join(",") === "err boom-refresh,ok 2", "got " + log.join(",");
}
