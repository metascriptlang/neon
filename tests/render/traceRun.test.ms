import { traceRun } from "../../src/render/traceRun";
import { createSignal } from "../../src/core/signal";
import { createEffect } from "../../src/core/effect";
import { createRoot } from "../../src/core/owner";
import { Cleanup } from "../../src/core/types";
import { flush } from "../../src/core/runtime";

test "traceRun runs the function once and discards what it returns" {
	let runs = 0;
	traceRun((): string => { runs += 1; return "kept nowhere"; });
	assert runs === 1, "the function ran " + runs.toString() + " times";
}

test "a read inside traceRun is tracked by the computation that called it" {
	const [n, setN] = createSignal(1);
	let computes = 0;
	let effects = 0;
	createRoot((dispose) => {
		createEffect<int32>(
			(p: int32 | null): int32 => {
				computes += 1;
				traceRun((): int32 => n());
				return computes;
			},
			(v: int32, p: int32 | null): Cleanup | null => { effects += 1; return null; });
		return dispose;
	});
	flush();
	assert computes === 1 && effects === 1, "the effect ran once on creation";
	setN(2);
	flush();
	assert computes === 2 && effects === 2, "a write to the traced signal re-ran the computation";
}

test "traceRun lets a throw out of the function reach its caller" {
	let caught = "";
	try {
		traceRun((): int32 => { throw new Error("from the trace"); });
	} catch (e) {
		caught = (e as Error).message;
	}
	assert caught === "from the trace", caught;
	let runs = 0;
	traceRun((): int32 => { runs += 1; return 1; });
	assert runs === 1, "a later trace run still works";
}
