// Pins for isPending and latest over async memos.
// Reference: solid-next packages/signals/tests/latest-async.test.ts (#2829) and createMemo.test.ts (the isPending and latest
// cases from :603). The reference also holds a write to an upstream signal while the async work runs (`$x()` stays committed,
// `isPending($x)` is true); this core has no write holds, so no pin here reads a signal through isPending or latest.
import { createSignal } from "../../src/core/signal";
import { createAsyncMemo, createMemo } from "../../src/core/memo";
import { createRenderEffect } from "../../src/core/effect";
import { createRoot } from "../../src/core/owner";
import { flush, isPending, latest } from "../../src/core/runtime";
import { Cleanup } from "../../src/core/types";
import { Gate, gated, release } from "./asyncClock";

function lastOf(log: string[]): string {
	return log.length === 0 ? "-" : log[log.length - 1];
}

// latest-async.test.ts: "latest(asyncMemo) settles to the resolved value and re-reports pending on each refresh (#2829)"
test "latest of an async memo keeps the stale value while it reloads and isPending reports each reload" {
	const gate = new Gate();
	const [count, setCount] = createSignal<int32>(0);
	const latestLog: string[] = [];
	const pendingLog: string[] = [];
	createRoot((d) => {
		const m = createAsyncMemo((p: string | null): Promise<string> => gated(gate, "AV" + count().toString()));
		createRenderEffect<string>(
			(p: string | null): string => latest<string>((): string => m()),
			(v: string, p: string | null): Cleanup | null => { latestLog.push(v); return null; },
		);
		createRenderEffect<boolean>(
			(p: boolean | null): boolean => isPending((): string => latest<string>((): string => m())),
			(v: boolean, p: boolean | null): Cleanup | null => { pendingLog.push(v.toString()); return null; },
		);
		return 0;
	});
	flush();
	assert latestLog.length === 0, "an initial load has no stale value, so latest suspends its reader: " + latestLog.join(",");
	await release(gate);
	assert lastOf(latestLog) === "AV0" && lastOf(pendingLog) === "false", "settled: " + latestLog.join(",") + " / " + pendingLog.join(",");

	gate.open = false;
	setCount(1);
	flush();
	assert lastOf(pendingLog) === "true", "the first reload reports pending: " + pendingLog.join(",");
	assert lastOf(latestLog) === "AV0", "and latest still shows the stale value: " + latestLog.join(",");
	await release(gate);
	assert lastOf(latestLog) === "AV1" && lastOf(pendingLog) === "false", "landed: " + latestLog.join(",") + " / " + pendingLog.join(",");

	gate.open = false;
	setCount(2);
	flush();
	assert lastOf(pendingLog) === "true" && lastOf(latestLog) === "AV1", "the second reload behaves the same";
	await release(gate);
	assert lastOf(latestLog) === "AV2" && lastOf(pendingLog) === "false", "got " + latestLog.join(",") + " / " + pendingLog.join(",");
	assert latestLog.indexOf("") < 0, "latest never regressed to an empty value: " + latestLog.join(",");
}

// Second axis: two chained async memos of int32, read through the downstream one.
test "latest and isPending of a chain of two async memos track the whole chain" {
	const gateA = new Gate();
	const gateB = new Gate();
	const [x, setX] = createSignal<int32>(1);
	const latestLog: string[] = [];
	const pendingLog: string[] = [];
	createRoot((d) => {
		const a = createAsyncMemo((p: int32 | null): Promise<int32> => gated(gateA, x() * 10));
		const b = createAsyncMemo((p: int32 | null): Promise<int32> => gated(gateB, a() + 1));
		createRenderEffect<int32>(
			(p: int32 | null): int32 => latest<int32>((): int32 => b()),
			(v: int32, p: int32 | null): Cleanup | null => { latestLog.push(v.toString()); return null; },
		);
		createRenderEffect<boolean>(
			(p: boolean | null): boolean => isPending((): int32 => b()),
			(v: boolean, p: boolean | null): Cleanup | null => { pendingLog.push(v.toString()); return null; },
		);
		return 0;
	});
	await release(gateA);
	await release(gateB);
	assert lastOf(latestLog) === "11" && lastOf(pendingLog) === "false", "got " + latestLog.join(",") + " / " + pendingLog.join(",");
	gateA.open = false;
	gateB.open = false;
	setX(2);
	assert lastOf(pendingLog) === "true" && lastOf(latestLog) === "11", "pending from the first hop: " + pendingLog.join(",");
	await release(gateA);
	assert lastOf(pendingLog) === "true" && lastOf(latestLog) === "11", "still pending while the second hop runs";
	await release(gateB);
	assert lastOf(latestLog) === "21" && lastOf(pendingLog) === "false", "got " + latestLog.join(",") + " / " + pendingLog.join(",");
}

// createMemo.test.ts:603 "should should show stale state with `isPending` in graph"
test "a memo that reads isPending of an async memo flips with its reloads" {
	const gate = new Gate();
	const [s, set] = createSignal<int32>(1);
	const a = createRoot((d) => {
		const m = createAsyncMemo((p: int32 | null): Promise<int32> => gated(gate, s()));
		createRenderEffect<int32>((p: int32 | null): int32 => m(), (v: int32, p: int32 | null): Cleanup | null => null);
		return m;
	});
	await release(gate);
	const b = createMemo((p: string | null): string => isPending((): int32 => a()) ? "stale" : "not stale");
	assert b() === "not stale", "settled";
	gate.open = false;
	set(2);
	flush();
	assert b() === "stale", "reloading";
	await release(gate);
	assert b() === "not stale", "landed";
}

// createMemo.test.ts:621 "should should show stale state with `isPending` out of graph"
test "isPending read outside any computation answers false on a first load, true on a reload" {
	const gate = new Gate();
	const [s, set] = createSignal<string>("a");
	const a = createRoot((d) => {
		const m = createAsyncMemo((p: string | null): Promise<string> => gated(gate, s()));
		createRenderEffect<string>((p: string | null): string => m(), (v: string, p: string | null): Cleanup | null => null);
		return m;
	});
	assert !isPending((): string => a()), "a first load has no stale value to report";
	await release(gate);
	assert !isPending((): string => a()), "landed";
	gate.open = false;
	set("b");
	flush();
	assert isPending((): string => a()), "reloading";
	await release(gate);
	assert !isPending((): string => a()), "landed again";
}

// createMemo.test.ts:1542 "isPending with chained async memos"
test "isPending is true on both memos of a chain while the chain reloads" {
	const gateA = new Gate();
	const gateB = new Gate();
	const [x, setX] = createSignal<int32>(1);
	let ra: (() => int32) | null = null;
	let rb: (() => int32) | null = null;
	createRoot((d) => {
		const a = createAsyncMemo((p: int32 | null): Promise<int32> => gated(gateA, x() * 10));
		const b = createAsyncMemo((p: int32 | null): Promise<int32> => gated(gateB, a() + 1));
		ra = (): int32 => a();
		rb = (): int32 => b();
		createRenderEffect<int32>((p: int32 | null): int32 => b(), (v: int32, p: int32 | null): Cleanup | null => null);
		return 0;
	});
	await release(gateA);
	await release(gateB);
	const readA = ra as () => int32;
	const readB = rb as () => int32;
	assert readA() === 10 && readB() === 11, "initial";
	gateA.open = false;
	gateB.open = false;
	setX(2);
	flush();
	assert isPending(readA) && isPending(readB), "both reload";
	await release(gateA);
	await release(gateB);
	assert readA() === 20 && readB() === 21, "landed";
	assert !isPending(readA) && !isPending(readB), "neither is pending after";
}

// createMemo.test.ts:1616 "isPending with sync memo depending on async memo"
test "a sync memo over an async memo serves its stale value and is pending while the async one reloads" {
	const gate = new Gate();
	const [x, setX] = createSignal<int32>(1);
	let rs: (() => int32) | null = null;
	let ra: (() => int32) | null = null;
	createRoot((d) => {
		const m = createAsyncMemo((p: int32 | null): Promise<int32> => gated(gate, x() * 10));
		const sync = createMemo((p: int32 | null): int32 => m() + 1);
		ra = (): int32 => m();
		rs = (): int32 => sync();
		createRenderEffect<int32>((p: int32 | null): int32 => sync(), (v: int32, p: int32 | null): Cleanup | null => null);
		return 0;
	});
	await release(gate);
	const readAsync = ra as () => int32;
	const readSync = rs as () => int32;
	assert readAsync() === 10 && readSync() === 11, "initial";
	gate.open = false;
	setX(2);
	flush();
	assert isPending(readAsync) && isPending(readSync), "both pending";
	assert readSync() === 11, "the sync memo keeps the value it computed from the old async value";
	await release(gate);
	assert readAsync() === 20 && readSync() === 21, "landed";
	assert !isPending(readAsync) && !isPending(readSync), "neither pending after";
}

// createMemo.test.ts:1350 "latest() on upstream vs downstream of async", the part that does not need a write hold
test "latest of the async node is its stale value, latest of a sync memo upstream is already the new one" {
	const gate = new Gate();
	const [x, setX] = createSignal<int32>(1);
	let rs: (() => int32) | null = null;
	let ra: (() => int32) | null = null;
	createRoot((d) => {
		const sync = createMemo((p: int32 | null): int32 => x() * 2);
		const m = createAsyncMemo((p: int32 | null): Promise<int32> => gated(gate, sync() * 10));
		rs = (): int32 => sync();
		ra = (): int32 => m();
		createRenderEffect<int32>((p: int32 | null): int32 => m(), (v: int32, p: int32 | null): Cleanup | null => null);
		return 0;
	});
	await release(gate);
	const readSync = rs as () => int32;
	const readAsync = ra as () => int32;
	assert readSync() === 2 && readAsync() === 20, "initial";
	gate.open = false;
	setX(2);
	flush();
	assert latest(readSync) === 4, "upstream of the async node: the in-flight value";
	assert latest(readAsync) === 20, "the async node itself: no new value yet";
	assert readAsync() === 20, "and a plain read agrees";
	await release(gate);
	assert readAsync() === 40 && readSync() === 4, "landed";
}
