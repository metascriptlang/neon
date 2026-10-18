// Pins for a pending status that reaches a dependent while an equal value is still on its way.
// Reference: solid-next packages/signals/tests/late-pending-equality.test.ts, with an async memo where the reference uses
// createProjection (the projection is not on this core yet) and without the write holds the reference's first case depends on.
import { createSignal } from "../../src/core/signal";
import { createAsyncMemo, createMemo } from "../../src/core/memo";
import { createEffect, createRenderEffect } from "../../src/core/effect";
import { createRoot } from "../../src/core/owner";
import { flush, isPending } from "../../src/core/runtime";
import { Cleanup } from "../../src/core/types";
import { Gate, gated, release } from "./asyncClock";

function openGate(): Gate {
	const gate = new Gate();
	gate.open = true;
	return gate;
}

// late-pending-equality.test.ts:15 "commits an effect write when a pending source is superseded with its cached value"
test "a flight superseded by a run that lands the cached value changes nothing when the abandoned promise lands" {
	const abandoned = new Gate();
	const open = openGate();
	const [version, setVersion] = createSignal<int32>(0);
	const [derived, setDerived] = createSignal<int32>(0);
	const applied: int32[] = [];
	let direct = -1;
	let displayedDerived = -1;
	createRoot((d) => {
		const data = createAsyncMemo((p: int32 | null): Promise<int32> => {
			const v = version();
			return v === 1 ? gated(abandoned, 1) : gated(open, 1);
		});
		createEffect<int32>(
			(p: int32 | null): int32 => data(),
			(v: int32, p: int32 | null): Cleanup | null => { applied.push(v); setDerived(v); return null; },
		);
		createRenderEffect<int32>((p: int32 | null): int32 => data(), (v: int32, p: int32 | null): Cleanup | null => { direct = v; return null; });
		createRenderEffect<int32>((p: int32 | null): int32 => derived(), (v: int32, p: int32 | null): Cleanup | null => { displayedDerived = v; return null; });
		return 0;
	});
	await release(open);
	assert applied.join(",") === "1" && derived() === 1 && displayedDerived === 1, "mounted: " + applied.join(",");
	setVersion(1);
	assert applied.join(",") === "1", "the abandoned-to-be flight is pending, nothing applies";
	setVersion(2);
	await release(open);
	assert applied.join(",") === "1", "the run that landed the cached value did not re-apply: " + applied.join(",");
	assert direct === 1 && derived() === 1 && displayedDerived === 1, "and nothing was left held";
	await release(abandoned);
	assert applied.join(",") === "1" && direct === 1 && derived() === 1 && displayedDerived === 1, "the abandoned promise landing changes nothing: " + applied.join(",");
}

// late-pending-equality.test.ts:116 "does not rerun an unchanged dependent that only inherited pending status"
test "a dependent whose input stays equal is not rerun when the pending source drops out" {
	const gate = new Gate();
	const open = openGate();
	const [request, setRequest] = createSignal<boolean>(false);
	const [virtual, setVirtual] = createSignal<boolean>(false);
	let computes = 0;
	const values: string[] = [];
	createRoot((d) => {
		const data = createAsyncMemo((p: boolean | null): Promise<boolean> => gated(request() ? gate : open, false));
		const enabled = createMemo((p: boolean | null): boolean => !virtual() && data());
		const attributes = createMemo((p: string | null): string => {
			const value = enabled();
			computes += 1;
			return "enabled=" + value.toString();
		});
		createRenderEffect<string>((p: string | null): string => attributes(), (v: string, p: string | null): Cleanup | null => { values.push(v); return null; });
		return 0;
	});
	await release(open);
	setRequest(true);
	flush();
	setVirtual(true);
	flush();
	await release(gate);
	assert computes === 1, "attributes computed once: " + computes.toString();
	assert values.join("|") === "enabled=false", "got " + values.join("|");
}

// Second axis: a string-valued dependent.
test "a string dependent whose input stays equal is not rerun when the pending source drops out" {
	const gate = new Gate();
	const open = openGate();
	const [request, setRequest] = createSignal<boolean>(false);
	const [virtual, setVirtual] = createSignal<boolean>(false);
	let computes = 0;
	const values: string[] = [];
	createRoot((d) => {
		const data = createAsyncMemo((p: boolean | null): Promise<boolean> => gated(request() ? gate : open, false));
		const label = createMemo((p: string | null): string => !virtual() && data() ? "on" : "off");
		const decorated = createMemo((p: string | null): string => { const shown = label(); computes += 1; return "[" + shown + "]"; });
		createRenderEffect<string>((p: string | null): string => decorated(), (v: string, p: string | null): Cleanup | null => { values.push(v); return null; });
		return 0;
	});
	await release(open);
	assert computes === 1, "mounted";
	setRequest(true);
	flush();
	setVirtual(true);
	flush();
	await release(gate);
	assert computes === 1, "decorated computed once: " + computes.toString();
	assert values.join("|") === "[off]", "got " + values.join("|");
}

async function keepsPendingThroughAnotherPath(indirect: boolean): Promise<string> {
	const gate = new Gate();
	const open = openGate();
	const [request, setRequest] = createSignal<boolean>(false);
	const [virtual, setVirtual] = createSignal<boolean>(false);
	const values: string[] = [];
	let pending: (() => boolean) | null = null;
	createRoot((d) => {
		const data = createAsyncMemo((p: boolean | null): Promise<boolean> => request() ? gated(gate, true) : gated(open, false));
		const enabled = createMemo((p: boolean | null): boolean => !virtual() && data());
		const viaMemo = createMemo((p: boolean | null): boolean => data());
		const other = (): boolean => indirect ? viaMemo() : data();
		const combined = createMemo((p: string | null): string => enabled().toString() + "/" + other().toString());
		const probe = createMemo((p: boolean | null): boolean => isPending((): string => combined()));
		pending = (): boolean => probe();
		createRenderEffect<string>((p: string | null): string => combined(), (v: string, p: string | null): Cleanup | null => { values.push(v); return null; });
		createRenderEffect<boolean>((p: boolean | null): boolean => probe(), (v: boolean, p: boolean | null): Cleanup | null => null);
		return 0;
	});
	await release(open);
	const isPendingNow = pending as () => boolean;
	if (!(values.join("|") === "false/false")) { return "mounted: " + values.join("|"); }
	setRequest(true);
	flush();
	if (!(isPendingNow())) { return "the request makes the combination pending"; }
	setVirtual(true);
	flush();
	if (!(isPendingNow())) { return "dropping one path leaves the other pending"; }
	if (!(values.join("|") === "false/false")) { return "and nothing applied meanwhile: " + values.join("|"); }
	await release(gate);
	if (!(!isPendingNow())) { return "landed"; }
	if (!(values[values.length - 1] === "false/true")) { return "got " + values.join("|"); }
	return "";
}

// late-pending-equality.test.ts:182 "keeps a dependent pending through another path (indirect: false)"
test "a dependent stays pending through a direct path after another path drops the source" {
	const verdict = await keepsPendingThroughAnotherPath(false);
	assert verdict === "", verdict;
}

// late-pending-equality.test.ts:182 "keeps a dependent pending through another path (indirect: true)"
test "a dependent stays pending through a memo path after another path drops the source" {
	const verdict = await keepsPendingThroughAnotherPath(true);
	assert verdict === "", verdict;
}

async function dropsPendingSources(count: int32): Promise<string> {
	const open = openGate();
	const gates: Gate[] = [];
	for (let i = 0; i < count; i += 1) { gates.push(new Gate()); }
	const [request, setRequest] = createSignal<boolean>(false);
	const [virtual, setVirtual] = createSignal<boolean>(false);
	const values: string[] = [];
	let pending: (() => boolean) | null = null;
	createRoot((d) => {
		const reads: (() => boolean)[] = [];
		for (let i = 0; i < count; i += 1) {
			const gate = gates[i];
			const data = createAsyncMemo((p: boolean | null): Promise<boolean> => request() ? gated(gate, true) : gated(open, false));
			reads.push((): boolean => data());
		}
		const enabled = createMemo((p: boolean | null): boolean => {
			if (virtual()) { return false; }
			let any = false;
			for (const read of reads) { if (read()) { any = true; } }
			return any;
		});
		const handler = createMemo((p: string | null): string => enabled() ? "handler" : "none");
		const probe = createMemo((p: boolean | null): boolean => isPending((): string => handler()));
		pending = (): boolean => probe();
		createRenderEffect<string>((p: string | null): string => handler(), (v: string, p: string | null): Cleanup | null => { values.push(v); return null; });
		createRenderEffect<boolean>((p: boolean | null): boolean => probe(), (v: boolean, p: boolean | null): Cleanup | null => null);
		return 0;
	});
	await release(open);
	const isPendingNow = pending as () => boolean;
	if (!(values.join("|") === "none")) { return "mounted: " + values.join("|"); }
	setRequest(true);
	flush();
	if (!(isPendingNow())) { return "every source is in flight"; }
	setVirtual(true);
	flush();
	if (!(!isPendingNow())) { return "the branch that dropped all of them settles at once"; }
	for (const gate of gates) { await release(gate); }
	if (!(!isPendingNow())) { return "and stays settled when the abandoned promises land"; }
	if (!(values.join("|") === "none")) { return "with no further apply: " + values.join("|"); }
	return "";
}

// late-pending-equality.test.ts:225 "settles a branch immediately after it drops %i pending sources" (2)
test "a branch settles at once after it drops two pending sources" {
	const verdict = await dropsPendingSources(2);
	assert verdict === "", verdict;
}

// late-pending-equality.test.ts:225 "settles a branch immediately after it drops %i pending sources" (3)
test "a branch settles at once after it drops three pending sources" {
	const verdict = await dropsPendingSources(3);
	assert verdict === "", verdict;
}

// late-pending-equality.test.ts:277 "settles converging unchanged branches before their shared source resolves"
test "two converging unchanged branches settle before their shared source lands" {
	const gate = new Gate();
	const open = openGate();
	const [request, setRequest] = createSignal<boolean>(false);
	const [virtual, setVirtual] = createSignal<boolean>(false);
	const [shown, setShown] = createSignal<boolean>(false);
	const values: string[] = [];
	let pending: (() => boolean) | null = null;
	createRoot((d) => {
		const data = createAsyncMemo((p: boolean | null): Promise<boolean> => request() ? gated(gate, true) : gated(open, false));
		const enabled = createMemo((p: boolean | null): boolean => !virtual() && data());
		const left = createMemo((p: boolean | null): boolean => enabled());
		const right = createMemo((p: boolean | null): boolean => enabled());
		const combined = createMemo((p: string | null): string => left().toString() + "," + right().toString());
		const probe = createMemo((p: boolean | null): boolean => isPending((): string => combined()));
		pending = (): boolean => probe();
		createRenderEffect<string>((p: string | null): string => combined(), (v: string, p: string | null): Cleanup | null => null);
		createRenderEffect<boolean>((p: boolean | null): boolean => probe(), (v: boolean, p: boolean | null): Cleanup | null => null);
		createRenderEffect<string>((p: string | null): string => shown() ? combined() : "-", (v: string, p: string | null): Cleanup | null => { values.push(v); return null; });
		return 0;
	});
	await release(open);
	const isPendingNow = pending as () => boolean;
	setRequest(true);
	flush();
	setShown(true);
	flush();
	assert isPendingNow(), "the shared source is in flight";
	assert values.join("|") === "-", "the reader waits for it: " + values.join("|");
	setVirtual(true);
	flush();
	assert !isPendingNow(), "both branches dropped the source and settled";
	assert values.join("|") === "-|false,false", "and the reader applied without waiting for it: " + values.join("|");
	await release(gate);
	assert values.join("|") === "-|false,false", "the abandoned promise landing changes nothing: " + values.join("|");
}
