// Pins for a source that recovers from an error to the value it last committed (#2949).
// Reference: solid-next packages/signals/tests/error-silent-recovery.test.ts and core.ts settleErroredDependents.
// A dependent that re-ran while the error stood absorbed its fresh sibling values without committing them, and an unchanged
// recovery sends it no value notification; the sweep at the end of the source's recompute re-runs it once. The reference reads the
// outcome through createErrorBoundary; here the outcome is the success or error arm of one user effect.
import { createSignal } from "../../src/core/signal";
import { flush } from "../../src/core/runtime";
import { createAsyncMemo, createMemo } from "../../src/core/memo";
import { createEffect, EffectBundle } from "../../src/core/effect";
import { createRoot } from "../../src/core/owner";
import { Cleanup } from "../../src/core/types";
import { Gate, gated, rejectedWhenOpen, release } from "./asyncClock";

class Rig {
	out: string = "";
	sumRuns: int32 = 0;
	setA: (v: int32) => void = (v: int32): void => { };
	setB: (v: int32) => void = (v: int32): void => { };
	setC: (v: int32) => void = (v: int32): void => { };
}

function arms(rig: Rig): EffectBundle<string> {
	return {
		effect: (v: string, p: string | null): Cleanup | null => { rig.out = "ok:" + v; return null; },
		error: (err: Error, cleanup: Cleanup): void => { rig.out = "err:" + err.message; },
	};
}

function mount(rig: Rig): void {
	const [a, setA] = createSignal<int32>(0);
	const [b, setB] = createSignal<int32>(0);
	rig.setA = (v: int32): void => { setA(v); flush(); };
	rig.setB = (v: int32): void => { setB(v); flush(); };
	createRoot((d) => {
		const ma = createMemo((p: int32 | null): int32 => a());
		const mb = createMemo((p: int32 | null): int32 => {
			const v = b();
			if (v < 0) { throw new Error("b=" + v.toString()); }
			return v;
		});
		const sum = createMemo((p: int32 | null): int32 => { rig.sumRuns += 1; return ma() + mb(); });
		createEffect<string>((p: string | null): string => sum().toString(), arms(rig));
		return 0;
	});
}

// error-silent-recovery.test.ts "boundary reveals fresh sibling values after unchanged-value recovery"
test "an unchanged-value recovery reveals the sibling value that changed while the error stood" {
	const rig = new Rig();
	mount(rig);
	flush();
	assert rig.out === "ok:0", "mounted: " + rig.out;
	rig.setB(-1);
	assert rig.out === "err:b=-1", "errored: " + rig.out;
	rig.setA(10);
	rig.setB(0);
	assert rig.out === "ok:10", "got " + rig.out;
}

// error-silent-recovery.test.ts "unchanged-value recovery with no sibling change reveals the same value"
test "an unchanged-value recovery re-runs the errored dependent once" {
	const rig = new Rig();
	mount(rig);
	flush();
	const before = rig.sumRuns;
	rig.setB(-1);
	assert rig.out === "err:b=-1", "errored: " + rig.out;
	rig.setB(0);
	assert rig.out === "ok:0", "got " + rig.out;
	assert rig.sumRuns === before + 1, "the error reached it as a status and only the sweep re-ran it: " + (rig.sumRuns - before).toString();
}

// error-silent-recovery.test.ts "changed-value recovery still rides normal notification"
test "a changed-value recovery reveals the new sum" {
	const rig = new Rig();
	mount(rig);
	flush();
	rig.setB(-1);
	rig.setA(10);
	rig.setB(5);
	assert rig.out === "ok:15", "got " + rig.out;
}

// error-silent-recovery.test.ts "a dependent with another still-broken source re-errors on its sweep re-run"
test "a dependent with another still-broken source errors again on its sweep re-run" {
	const rig = new Rig();
	const [b, setB] = createSignal<int32>(0);
	const [c, setC] = createSignal<int32>(0);
	createRoot((d) => {
		const mb = createMemo((p: int32 | null): int32 => { const v = b(); if (v < 0) { throw new Error("b=" + v.toString()); } return v; });
		const mc = createMemo((p: int32 | null): int32 => { const v = c(); if (v < 0) { throw new Error("c=" + v.toString()); } return v; });
		const sum = createMemo((p: int32 | null): int32 => mb() + mc());
		createEffect<string>((p: string | null): string => sum().toString(), arms(rig));
		return 0;
	});
	flush();
	assert rig.out === "ok:0", "mounted: " + rig.out;
	setB(-1);
	flush();
	assert rig.out === "err:b=-1", "b first: " + rig.out;
	setC(-2);
	flush();
	setB(0);
	flush();
	assert rig.out === "err:c=-2", "b recovered unchanged but c still stands: " + rig.out;
	setC(3);
	flush();
	assert rig.out === "ok:3", "got " + rig.out;
}

// error-silent-recovery.test.ts "cascade: intermediate memo also recovers to an unchanged value"
test "the sweep cascades through an intermediate memo that also recovers unchanged" {
	const rig = new Rig();
	const [a, setA] = createSignal<int32>(0);
	const [b, setB] = createSignal<int32>(0);
	createRoot((d) => {
		const mb = createMemo((p: int32 | null): int32 => { const v = b(); if (v < 0) { throw new Error("b=" + v.toString()); } return v; });
		const mid = createMemo((p: int32 | null): int32 => mb() > 0 ? 1 : 0);
		const outer = createMemo((p: string | null): string => a().toString() + "|" + mid().toString());
		createEffect<string>((p: string | null): string => outer(), arms(rig));
		return 0;
	});
	flush();
	assert rig.out === "ok:0|0", "mounted: " + rig.out;
	setB(-1);
	flush();
	assert rig.out === "err:b=-1", "errored: " + rig.out;
	setA(7);
	flush();
	setB(0);
	flush();
	assert rig.out === "ok:7|0", "got " + rig.out;
}

// error-silent-recovery.test.ts "async flavor: rejected async memo recovering to unchanged value reveals fresh siblings"
test "a rejected async memo recovering to its committed value reveals the sibling that changed meanwhile" {
	const rig = new Rig();
	const gate = new Gate();
	const [a, setA] = createSignal<int32>(0);
	const [b, setB] = createSignal<int32>(0);
	createRoot((d) => {
		const ma = createMemo((p: int32 | null): int32 => a());
		const mb = createAsyncMemo((p: int32 | null): Promise<int32> => {
			const v = b();
			return v < 0 ? rejectedWhenOpen(gate, new Error("b=" + v.toString())) : gated(gate, v);
		});
		const sum = createMemo((p: int32 | null): int32 => ma() + mb());
		createEffect<string>((p: string | null): string => sum().toString(), arms(rig));
		return 0;
	});
	flush();
	await release(gate);
	assert rig.out === "ok:0", "mounted: " + rig.out;
	gate.open = false;
	setB(-1);
	flush();
	await release(gate);
	assert rig.out === "err:b=-1", "errored: " + rig.out;
	gate.open = false;
	setA(10);
	flush();
	await release(gate);
	assert rig.out === "err:b=-1", "the sibling change re-ran the dependent, which re-asked the rejected source and was rejected again: " + rig.out;
	gate.open = false;
	setB(0);
	flush();
	await release(gate);
	assert rig.out === "ok:10", "got " + rig.out;
}

// error-silent-recovery.test.ts "plain effects (no boundary) re-run after unchanged-value recovery"
test "an effect with no error arm runs again after an unchanged-value recovery" {
	const [a, setA] = createSignal<int32>(0);
	const [b, setB] = createSignal<int32>(0);
	const seen: string[] = [];
	createRoot((d) => {
		const mb = createMemo((p: int32 | null): int32 => { const v = b(); if (v < 0) { throw new Error("b=" + v.toString()); } return v; });
		const sum = createMemo((p: int32 | null): int32 => a() + mb());
		createEffect<int32>((p: int32 | null): int32 => sum(), (v: int32, p: int32 | null): Cleanup | null => { seen.push("v:" + v.toString()); return null; });
		return 0;
	});
	flush();
	assert seen.join(",") === "v:0", "mounted: " + seen.join(",");
	setB(-1);
	flush();
	setA(4);
	flush();
	setB(0);
	flush();
	assert seen[seen.length - 1] === "v:4", "got " + seen.join(",");
}
