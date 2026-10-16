import { createSignal, Accessor } from "../../src/core/signal";
import { flush, resetErrorHalt } from "../../src/core/runtime";
import { createEffect, createRenderEffect, EffectBundle } from "../../src/core/effect";
import { createRoot } from "../../src/core/owner";
import { createErrorBoundary } from "../../src/core/boundary";
import { Cleanup } from "../../src/core/types";

test "a compute throw with no handler skips the run and leaves the system alive" {
	const log: string[] = [];
	const [beat, setBeat] = createSignal(0);
	const [armed, setArmed] = createSignal(false);
	createRoot((d) => {
		createRenderEffect<int32>(
			(p: int32 | null): int32 => beat(),
			(v: int32, p: int32 | null): Cleanup | null => { log.push("beat=" + v.toString()); return null; },
		);
		createEffect<int32>(
			(p: int32 | null): int32 => { if (armed()) { throw new Error("boom-compute"); } return 0; },
			(v: int32, p: int32 | null): Cleanup | null => { log.push("effect ran"); return null; },
		);
		return 0;
	});
	assert log.join(",") === "beat=0,effect ran", "got " + log.join(",");
	log.length = 0;
	let escaped = false;
	try { setArmed(true); } catch (e) { escaped = true; }
	assert !escaped, "a user effect's compute failing does not escape the flush";
	assert log.length === 0, "the run was skipped: " + log.join(",");
	setBeat(1);
	assert log.join(",") === "beat=1", "the rest of the graph still runs: " + log.join(",");
}

test "the same unhandled compute throw in a render effect escapes" {
	const [armed, setArmed] = createSignal(false);
	createRoot((d) => {
		createRenderEffect<int32>(
			(p: int32 | null): int32 => { if (armed()) { throw new Error("boom-render"); } return 0; },
			(v: int32, p: int32 | null): Cleanup | null => null,
		);
		return 0;
	});
	let escaped = "";
	try { setArmed(true); } catch (e) { escaped = e.message; }
	assert escaped === "boom-render", "a render effect keeps its compute error loud: [" + escaped + "]";
	resetErrorHalt();
}

test "a bundle handler receives the thrown Error and no other arm runs" {
	const boom = new Error("boom-identity");
	const [armed, setArmed] = createSignal(false);
	let received: Error | null = null;
	let applied = 0;
	const bundle: EffectBundle<int32> = {
		effect: (v: int32, p: int32 | null): Cleanup | null => { applied += 1; return null; },
		error: (err: Error, cleanup: Cleanup): void => { received = err; },
	};
	createRoot((d) => {
		createEffect<int32>((p: int32 | null): int32 => { if (armed()) { throw boom; } return 0; }, bundle);
		return 0;
	});
	assert applied === 1 && received === null, "the first run took the success arm";
	setArmed(true);
	assert received === boom, "the handler holds the object the compute threw";
	assert applied === 1, "the success arm skipped the failed run";
}

test "a bundle handler takes the success arm again once the compute recovers" {
	const [armed, setArmed] = createSignal(false);
	const log: string[] = [];
	const bundle: EffectBundle<int32> = {
		effect: (v: int32, p: int32 | null): Cleanup | null => { log.push("ok"); return null; },
		error: (err: Error, cleanup: Cleanup): void => { log.push("err " + err.message); },
	};
	createRoot((d) => {
		createEffect<int32>((p: int32 | null): int32 => { if (armed()) { throw new Error("boom"); } return 0; }, bundle);
		return 0;
	});
	setArmed(true);
	setArmed(false);
	assert log.join(",") === "ok,err boom,ok", "got " + log.join(",");
}

test "the handler runs in a writable scope" {
	const [armed, setArmed] = createSignal(false);
	const [message, setMessage] = createSignal("");
	const views: string[] = [];
	const bundle: EffectBundle<int32> = {
		effect: (v: int32, p: int32 | null): Cleanup | null => null,
		error: (err: Error, cleanup: Cleanup): void => { setMessage(err.message); },
	};
	createRoot((d) => {
		createEffect<int32>((p: int32 | null): int32 => { if (armed()) { throw new Error("boom-write"); } return 0; }, bundle);
		createRenderEffect<string>(
			(p: string | null): string => message(),
			(v: string, p: string | null): Cleanup | null => { views.push(v); return null; },
		);
		return 0;
	});
	assert views.join("|") === "", "the view starts empty: " + views.join("|");
	setArmed(true);
	assert message() === "boom-write", "the handler's write landed";
	assert views.join("|") === "|boom-write", "and reached its dependents: " + views.join("|");
}

test "an error that recovers before the effect phase never reaches the handler" {
	const [source, setSource] = createSignal(0);
	const handled: string[] = [];
	const ran: string[] = [];
	const bundle: EffectBundle<int32> = {
		effect: (v: int32, p: int32 | null): Cleanup | null => { ran.push(v.toString()); return null; },
		error: (err: Error, cleanup: Cleanup): void => { handled.push(err.message); },
	};
	createRoot((d) => {
		createEffect<int32>(
			(p: int32 | null): int32 => { const v = source(); if (v === 1) { throw new Error("transient"); } return v; },
			bundle,
		);
		return 0;
	});
	assert ran.join(",") === "0", "got " + ran.join(",");
	flush(() => { setSource(1); setSource(2); });
	assert handled.length === 0, "the transient error was never settled: " + handled.join(",");
	assert ran.join(",") === "0,2", "the success arm saw the recovered value: " + ran.join(",");
	setSource(1);
	assert handled.join(",") === "transient", "a settled error does reach it: " + handled.join(",");
	assert ran.join(",") === "0,2", "and skips the success arm: " + ran.join(",");
}

// effect.ts:152-244 notifyEffectStatus: an error arm that rethrows passes the error on to the nearest boundary
test "an error arm that rethrows escalates to the nearest boundary" {
	const [armed, setArmed] = createSignal(false);
	const log: string[] = [];
	const bundle: EffectBundle<int32> = {
		effect: (v: int32, p: int32 | null): Cleanup | null => null,
		error: (err: Error, cleanup: Cleanup): void => { log.push("handler saw it"); throw err; },
	};
	createRoot((d) => {
		const shown = createErrorBoundary<string>(
			(): string => {
				createEffect<int32>((p: int32 | null): int32 => { if (armed()) { throw new Error("boom-compute"); } return 0; }, bundle);
				return "content";
			},
			(e: Accessor<Error>, reset: () => void): string => { log.push("caught:" + e().message); return "errored"; },
		);
		createRenderEffect<string>((p: string | null): string => shown(), (v: string, p: string | null): Cleanup | null => null);
		return 0;
	});
	assert log.length === 0, "nothing failed yet";
	setArmed(true);
	assert log.join(",") === "handler saw it,caught:boom-compute", "got " + log.join(",");
}

// createErrorBoundary.test.ts:404
test "an effect-phase throw is not routed to the error arm but to the boundary" {
	const [armed, setArmed] = createSignal(false);
	const log: string[] = [];
	const bundle: EffectBundle<boolean> = {
		effect: (on: boolean, p: boolean | null): Cleanup | null => { if (on) { throw new Error("boom-effect"); } return null; },
		error: (err: Error, cleanup: Cleanup): void => { log.push("handler:" + err.message); },
	};
	createRoot((d) => {
		const shown = createErrorBoundary<string>(
			(): string => {
				createEffect<boolean>((p: boolean | null): boolean => armed(), bundle);
				return "content";
			},
			(e: Accessor<Error>, reset: () => void): string => { log.push("caught:" + e().message); return "errored"; },
		);
		createRenderEffect<string>((p: string | null): string => shown(), (v: string, p: string | null): Cleanup | null => null);
		return 0;
	});
	setArmed(true);
	assert log.join(",") === "caught:boom-effect", "got " + log.join(",");
}

test "an effect-phase throw with no boundary escapes and halts the scheduler" {
	const log: string[] = [];
	const [beat, setBeat] = createSignal(0);
	const [armed, setArmed] = createSignal(false);
	const bundle: EffectBundle<boolean> = {
		effect: (on: boolean, p: boolean | null): Cleanup | null => { if (on) { throw new Error("boom-effect"); } return null; },
		error: (err: Error, cleanup: Cleanup): void => { log.push("handler must not fire"); },
	};
	createRoot((d) => {
		createRenderEffect<int32>(
			(p: int32 | null): int32 => beat(),
			(v: int32, p: int32 | null): Cleanup | null => { log.push("beat=" + v.toString()); return null; },
		);
		createEffect<boolean>((p: boolean | null): boolean => armed(), bundle);
		return 0;
	});
	log.length = 0;
	let escaped = "";
	try { setArmed(true); } catch (e) { escaped = e.message; }
	assert escaped === "boom-effect", "the throw reached the caller: [" + escaped + "]";
	assert log.length === 0, "the bundle handler did not fire: " + log.join(",");
	setBeat(1);
	assert log.length === 0, "a halted scheduler runs nothing: " + log.join(",");
	resetErrorHalt();
	setBeat(2);
	assert log.join(",") === "beat=2", "reset lets the graph run again: " + log.join(",");
}
