// Pins for an async compute on the 2.0 core. Reference: solid-next packages/signals/tests/createMemo.test.ts
// (the async section) and src/core/core.ts:1757-1804 (a pending read throws NotReadyError, an errored one rethrows its error).
// A promise here is held by a Gate: the compute returns a promise that stays unsettled until the test opens it, because
// on C an already-settled promise continues synchronously (compiler card 2026-10-15-await-of-a-settled-promise-continues-synchronously-on-c).
import { createSignal } from "../../src/core/signal";
import { createAsyncMemo } from "../../src/core/memo";
import { createEffect, createRenderEffect, EffectBundle } from "../../src/core/effect";
import { createRoot } from "../../src/core/owner";
import { Cleanup, NotReadyError } from "../../src/core/types";
import { Gate, gated, rejectedWhenOpen, release } from "./asyncClock";

class Point {
	x: int32;
	y: int32;

	constructor(x: int32, y: int32) {
		this.x = x;
		this.y = y;
	}
}

function isNotReady<T>(read: () => T): boolean {
	try {
		read();
	} catch (e) {
		return e instanceof NotReadyError;
	}
	return false;
}

function failureOf<T>(read: () => T): Error | null {
	try {
		read();
	} catch (e) {
		return e;
	}
	return null;
}

// createMemo.test.ts:383 "should throw when reading uninitialized async computed outside reactive scope"
test "an async memo read outside any scope throws NotReadyError until its promise lands" {
	const gate = new Gate();
	const a = createRoot((d) => {
		const m = createAsyncMemo((p: int32 | null): Promise<int32> => gated(gate, 42));
		createRenderEffect<int32>((p: int32 | null): int32 => m(), (v: int32, p: int32 | null): Cleanup | null => null);
		return m;
	});
	assert isNotReady<int32>(a), "an unresolved first run is NotReadyError to a bare reader";
	await release(gate);
	assert a() === 42, "after it lands the same accessor reads the value";
}

// Second axis: a string value, and a reader that is itself a computation (the pending state reaches it as a pending read).
test "a string async memo keeps its reader pending, then lands the string" {
	const gate = new Gate();
	const log: string[] = [];
	createRoot((d) => {
		const m = createAsyncMemo((p: string | null): Promise<string> => gated(gate, "ready"));
		createRenderEffect<string>(
			(p: string | null): string => m() + "!",
			(v: string, p: string | null): Cleanup | null => { log.push(v); return null; },
		);
		return 0;
	});
	assert log.length === 0, "the effect has not applied while its source is pending";
	await release(gate);
	assert log.join(",") === "ready!", "got " + log.join(",");
}

// createMemo.test.ts:396 "should return stale value when reading re-pending async computed outside reactive scope"
test "a re-pending async memo read outside any scope returns the value it last held" {
	const gate = new Gate();
	const [s, set] = createSignal<int32>(1);
	const a = createRoot((d) => {
		const m = createAsyncMemo((p: int32 | null): Promise<int32> => gated(gate, s()));
		createRenderEffect<int32>((p: int32 | null): int32 => m(), (v: int32, p: int32 | null): Cleanup | null => null);
		return m;
	});
	await release(gate);
	assert a() === 1, "the first run landed";
	gate.open = false;
	set(2);
	assert a() === 1, "while the second run is in flight a bare read sees the previous value";
	await release(gate);
	assert a() === 2, "and the new value once it lands";
}

// Second axis: a struct value.
test "a struct async memo is stale while pending and replaced when it lands" {
	const gate = new Gate();
	const [s, set] = createSignal<int32>(1);
	const a = createRoot((d) => {
		const m = createAsyncMemo((p: Point | null): Promise<Point> => gated(gate, new Point(s(), s() * 10)));
		createRenderEffect<Point>((p: Point | null): Point => m(), (v: Point, p: Point | null): Cleanup | null => null);
		return m;
	});
	await release(gate);
	assert a().x === 1 && a().y === 10, "first landing";
	gate.open = false;
	set(2);
	assert a().x === 1 && a().y === 10, "stale while pending";
	await release(gate);
	assert a().x === 2 && a().y === 20, "second landing";
}

// createMemo.test.ts:415 "diamond should not cause waterfalls on read"
test "a diamond of two async memos starts both runs together and applies once per round" {
	const gate = new Gate();
	const [s, set] = createSignal<int32>(1);
	let runsB = 0;
	let runsC = 0;
	const seen: string[] = [];
	createRoot((d) => {
		const b = createAsyncMemo((p: int32 | null): Promise<int32> => { runsB += 1; return gated(gate, s()); });
		const c = createAsyncMemo((p: int32 | null): Promise<int32> => { runsC += 1; return gated(gate, s()); });
		createEffect<string>(
			(p: string | null): string => b().toString() + "," + c().toString(),
			(v: string, p: string | null): Cleanup | null => { seen.push(v); return null; },
		);
		return 0;
	});
	assert runsB === 1 && runsC === 1 && seen.length === 0, "both started, nothing applied: " + runsB.toString() + runsC.toString();
	await release(gate);
	assert runsB === 1 && runsC === 1, "no waterfall rerun: " + runsB.toString() + runsC.toString();
	assert seen.join("|") === "1,1", "got " + seen.join("|");
	gate.open = false;
	set(2);
	assert runsB === 2 && runsC === 2 && seen.length === 1, "the write restarted both together: " + runsB.toString() + runsC.toString();
	await release(gate);
	assert runsB === 2 && runsC === 2, "still one run each";
	assert seen.join("|") === "1,1|2,2", "got " + seen.join("|");
}

// createMemo.test.ts:554 "should waterfall when dependent on another async with shared source"
test "an async memo that reads another async memo waits for it, then runs again" {
	const gateA = new Gate();
	const gateB = new Gate();
	const [s, set] = createSignal<int32>(1);
	let runsA = 0;
	let runsB = 0;
	const seen: int32[] = [];
	createRoot((d) => {
		const a = createAsyncMemo((p: int32 | null): Promise<int32> => { runsA += 1; return gated(gateA, s()); });
		const b = createAsyncMemo((p: int32 | null): Promise<int32> => { runsB += 1; return gated(gateB, s() + a()); });
		createEffect<int32>(
			(p: int32 | null): int32 => b(),
			(v: int32, p: int32 | null): Cleanup | null => { seen.push(v); return null; },
		);
		return 0;
	});
	assert runsA === 1 && runsB === 1 && seen.length === 0, "b started and stopped at the pending read of a";
	await release(gateA);
	assert runsA === 1 && runsB === 2, "a landing re-ran b";
	await release(gateB);
	assert seen.join(",") === "2", "got " + seen.join(",");
	gateA.open = false;
	gateB.open = false;
	set(2);
	assert runsA === 2 && runsB === 3 && seen.length === 1, "the write ran a, and b up to a's pending read";
	await release(gateA);
	assert runsA === 2 && runsB === 4, "a landing re-ran b again";
	await release(gateB);
	assert seen.join(",") === "2,4", "got " + seen.join(",");
}

// core.ts:1794-1804: an errored node keeps its error and every read rethrows that same error.
test "a rejection is the error every reader sees, and the memo is not disposed" {
	const gate = new Gate();
	const boom = new Error("boom-async");
	const handled: Error[] = [];
	const bundle: EffectBundle<int32> = {
		effect: (v: int32, p: int32 | null): Cleanup | null => null,
		error: (err: Error, cleanup: Cleanup): void => { handled.push(err); },
	};
	const a = createRoot((d) => {
		const m = createAsyncMemo((p: int32 | null): Promise<int32> => rejectedWhenOpen(gate, boom));
		createEffect<int32>((p: int32 | null): int32 => m(), bundle);
		return m;
	});
	assert isNotReady<int32>(a), "pending first";
	await release(gate);
	assert handled.length === 1 && handled[0] === boom, "the error arm got the rejection itself, once";
	assert failureOf<int32>(a) === boom, "a bare read throws the rejection";
	assert failureOf<int32>(a) === boom, "a second read throws the same object";
	assert handled.length === 1, "reading it again did not report it again";
}

// Second axis: a chain of two async memos, the second reads the rejected first.
test "a rejection reaches an async memo downstream as the same error" {
	const gate = new Gate();
	const boom = new Error("boom-chain");
	const handled: Error[] = [];
	const bundle: EffectBundle<int32> = {
		effect: (v: int32, p: int32 | null): Cleanup | null => null,
		error: (err: Error, cleanup: Cleanup): void => { handled.push(err); },
	};
	createRoot((d) => {
		const a = createAsyncMemo((p: int32 | null): Promise<int32> => rejectedWhenOpen(gate, boom));
		const b = createAsyncMemo((p: int32 | null): Promise<int32> => gated(gate, a() + 1));
		createEffect<int32>((p: int32 | null): int32 => b(), bundle);
		return 0;
	});
	await release(gate);
	assert handled.length === 1 && handled[0] === boom, "the error arm got the rejection once, unwrapped: " + handled.length.toString();
}

// A run that fails and a later run that lands: the error state clears.
test "a later successful run clears a rejection" {
	const gate = new Gate();
	const [fail, setFail] = createSignal<boolean>(true);
	const boom = new Error("boom-once");
	const log: string[] = [];
	const bundle: EffectBundle<int32> = {
		effect: (v: int32, p: int32 | null): Cleanup | null => { log.push("ok " + v.toString()); return null; },
		error: (err: Error, cleanup: Cleanup): void => { log.push("err " + err.message); },
	};
	const a = createRoot((d) => {
		const m = createAsyncMemo((p: int32 | null): Promise<int32> => fail() ? rejectedWhenOpen(gate, boom) : gated(gate, 7));
		createEffect<int32>((p: int32 | null): int32 => m(), bundle);
		return m;
	});
	await release(gate);
	assert failureOf<int32>(a) === boom, "errored";
	gate.open = false;
	setFail(false);
	await release(gate);
	assert failureOf<int32>(a) === null && a() === 7, "recovered";
	assert log.join(",") === "err boom-once,ok 7", "got " + log.join(",");
}

// async-chain-supersession.test.ts: the newer run wins and the older result never lands.
test "a newer run supersedes an in-flight one and the older result never lands" {
	const gate1 = new Gate();
	const gate2 = new Gate();
	const [s, set] = createSignal<int32>(1);
	const seen: int32[] = [];
	const a = createRoot((d) => {
		const m = createAsyncMemo((p: int32 | null): Promise<int32> => {
			const v = s();
			return gated(v === 1 ? gate1 : gate2, v * 100);
		});
		createRenderEffect<int32>((p: int32 | null): int32 => m(), (v: int32, p: int32 | null): Cleanup | null => { seen.push(v); return null; });
		return m;
	});
	set(2);
	await release(gate1);
	assert seen.length === 0, "the superseded run landed nowhere: " + seen.join(",");
	assert isNotReady<int32>(a), "the memo still waits for the newer run";
	await release(gate2);
	assert seen.join(",") === "200", "got " + seen.join(",");
}

// Second axis: the newer run settles first, then the older one settles late.
test "an older run that settles after the newer one is dropped" {
	const gate1 = new Gate();
	const gate2 = new Gate();
	const [s, set] = createSignal<string>("a");
	const seen: string[] = [];
	const a = createRoot((d) => {
		const m = createAsyncMemo((p: string | null): Promise<string> => {
			const v = s();
			return gated(v === "a" ? gate1 : gate2, v + "!");
		});
		createRenderEffect<string>((p: string | null): string => m(), (v: string, p: string | null): Cleanup | null => { seen.push(v); return null; });
		return m;
	});
	set("b");
	await release(gate2);
	assert seen.join(",") === "b!", "the newer run landed: " + seen.join(",");
	await release(gate1);
	assert seen.join(",") === "b!" && a() === "b!", "the older one did not overwrite it: " + seen.join(",");
}

// Nested owner: the owner that holds the memo is disposed while a run is in flight.
test "disposing the owner of an in-flight async memo drops its result" {
	const gate = new Gate();
	const seen: int32[] = [];
	let stop: (() => void) | null = null;
	createRoot((d) => {
		stop = d;
		const m = createAsyncMemo((p: int32 | null): Promise<int32> => gated(gate, 5));
		createRenderEffect<int32>((p: int32 | null): int32 => m(), (v: int32, p: int32 | null): Cleanup | null => { seen.push(v); return null; });
		return 0;
	});
	if (stop !== null) { stop(); }
	await release(gate);
	assert seen.length === 0, "a disposed memo applies nothing: " + seen.join(",");
}
