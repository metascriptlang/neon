// Pins for a write that arrives while a chain of two async memos is in flight.
// Reference: solid-next packages/signals/tests/async-chain-supersession.test.ts (#3373, #3376), whose clock this file reproduces
// with tests/core/asyncClock.ms. The reference also holds the write itself until the chain lands; this core has no transactions,
// so the pinned contract is the part that survives without them: a stale landing never commits, and an effect reading the chain
// waits for it instead of publishing a mixed frame.
import { createSignal } from "../../src/core/signal";
import { createAsyncMemo } from "../../src/core/memo";
import { createRenderEffect } from "../../src/core/effect";
import { createRoot } from "../../src/core/owner";
import { isPending } from "../../src/core/runtime";
import { Cleanup } from "../../src/core/types";
import { Clock, delay, advanceTo, settle } from "./asyncClock";

class Published {
	log: string[] = [];
	when: int32[] = [];
	last: string = "";
}

function text(out: Published, clock: Clock, fn: () => string): void {
	createRenderEffect<string>(
		(p: string | null): string => fn(),
		(v: string, p: string | null): Cleanup | null => {
			if (v !== out.last) {
				out.last = v;
				out.log.push(v);
				out.when.push(clock.now);
			}
			return null;
		},
	);
}

// async-chain-supersession.test.ts "#3373 the stale first-hop landing does not commit the newer signal value"
test "a stale first-hop landing does not commit beside the newer signal value" {
	const clock = new Clock();
	const out = new Published();
	const [count, setCount] = createSignal<int32>(0);
	createRoot((d) => {
		const a = createAsyncMemo((p: int32 | null): Promise<int32> => delay(clock, 1000, count()));
		const b = createAsyncMemo((p: int32 | null): Promise<int32> => delay(clock, 1000, a()));
		text(out, clock, (): string => count().toString() + " / " + b().toString());
		return 0;
	});
	await settle(clock);
	await advanceTo(clock, 2500);
	setCount(1);
	await settle(clock);
	await advanceTo(clock, 4000);
	setCount(2);
	await settle(clock);
	await advanceTo(clock, 9000);
	assert out.log.join("|") === "0 / 0|2 / 2", "b1 landing at 4500 must not publish 2 / 1: " + out.log.join("|");
}

// Second axis: the chain carries strings, and the first hop collapses the new inputs to one value ("the held first-hop answer
// reveals when the re-asked input lands unchanged"): the second flight of a lands the value b1 was computed from, so nothing recomputes.
test "a first-hop answer stays valid when the re-asked input lands unchanged" {
	const clock = new Clock();
	const out = new Published();
	const [count, setCount] = createSignal<int32>(0);
	let runsB = 0;
	createRoot((d) => {
		const a = createAsyncMemo((p: int32 | null): Promise<int32> => delay(clock, 1000, count() < 1 ? count() : 1));
		const b = createAsyncMemo((p: string | null): Promise<string> => { runsB += 1; return delay(clock, 1000, "b" + a().toString()); });
		text(out, clock, (): string => count().toString() + " / " + b());
		return 0;
	});
	await settle(clock);
	await advanceTo(clock, 2500);
	assert runsB === 2, "b ran once pending on a and once after it landed";
	setCount(1);
	await settle(clock);
	await advanceTo(clock, 4000);
	setCount(2);
	await settle(clock);
	await advanceTo(clock, 9000);
	assert out.log.join("|") === "0 / b0|2 / b1", "got " + out.log.join("|");
	assert out.when.map((t: int32): string => t.toString()).join(",") === "2000,5000", "b1 (landed 4500) reveals when a confirms at 5000";
	assert runsB === 3, "the unchanged re-ask did not run b again after a1 landed: " + runsB.toString();
}

// async-chain-supersession.test.ts "#3376 isPending stays true across the stale first-hop landing"
test "isPending of the chain stays true across the stale first-hop landing" {
	const clock = new Clock();
	const out = new Published();
	const [count, setCount] = createSignal<int32>(0);
	createRoot((d) => {
		const a = createAsyncMemo((p: int32 | null): Promise<int32> => delay(clock, 400, count()));
		const b = createAsyncMemo((p: int32 | null): Promise<int32> => delay(clock, 400, a()));
		text(out, clock, (): string => "Pending: " + isPending((): int32 => b()).toString());
		return 0;
	});
	await settle(clock);
	await advanceTo(clock, 1000);
	setCount(1);
	await settle(clock);
	await advanceTo(clock, 1600);
	setCount(2);
	await settle(clock);
	await advanceTo(clock, 5000);
	assert out.log.join("|") === "Pending: false|Pending: true|Pending: false", "got " + out.log.join("|");
}

// Nested owner: the chain lives in a child root of the effect's owner; the same write sequence.
test "a stale first-hop landing is dropped when the chain lives in a nested owner" {
	const clock = new Clock();
	const out = new Published();
	const [count, setCount] = createSignal<int32>(0);
	createRoot((d) => {
		createRoot((inner) => {
			const a = createAsyncMemo((p: int32 | null): Promise<int32> => delay(clock, 1000, count()));
			const b = createAsyncMemo((p: int32 | null): Promise<int32> => delay(clock, 1000, a()));
			text(out, clock, (): string => count().toString() + " / " + b().toString());
			return 0;
		});
		return 0;
	});
	await settle(clock);
	await advanceTo(clock, 2500);
	setCount(1);
	await settle(clock);
	await advanceTo(clock, 4000);
	setCount(2);
	await settle(clock);
	await advanceTo(clock, 9000);
	assert out.log.join("|") === "0 / 0|2 / 2", "got " + out.log.join("|");
}
