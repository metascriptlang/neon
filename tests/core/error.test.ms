import { createSignal } from "../../src/core/signal";
import { createEffect } from "../../src/core/effect";
import { onCleanup } from "../../src/core/cleanup";
import { createRoot } from "../../src/core/owner";
import { catchError } from "../../src/core/error";

test "catchError catches a throw in its own body" {
	let seen = "";
	catchError(() => { throw new Error("boom 7"); }, (err: string) => { seen = err; });
	assert seen === "boom 7", "the handler is given the error itself: [" + seen + "]";
}

test "an effect under catchError routes a later throw to the handler" {
	const [a, setA] = createSignal(0);
	let seen = "";
	catchError(() => {
		createEffect(() => { if (a() === 1) { throw new Error("late 7"); } });
	}, (err: string) => { seen = err; });
	assert seen === "", "nothing failed on the first run";
	setA(1);
	assert seen === "late 7", "the write re-ran the effect and the owner carried the handler: [" + seen + "]";
}

test "the nearest handler wins" {
	let outer = "";
	let inner = "";
	catchError(() => {
		catchError(() => { throw new Error("boom"); }, (err: string) => { inner = err; });
	}, (err: string) => { outer = err; });
	assert inner === "boom", "the inner handler ran";
	assert outer === "", "the outer handler was not reached";
}

test "a throw with no handler still escapes" {
	const [a, setA] = createSignal(0);
	createEffect(() => { if (a() === 1) { throw new Error("loud"); } });
	let escaped = "";
	try { setA(1); } catch (e) { escaped = e.message; }
	assert escaped === "loud", "an unhandled throw is never swallowed: [" + escaped + "]";
}

test "a computation that threw is disposed, not re-run" {
	const [a, setA] = createSignal(0);
	let runs = 0;
	let handled = 0;
	let cleaned = 0;
	catchError(() => {
		createEffect(() => {
			runs = runs + 1;
			onCleanup(() => { cleaned = cleaned + 1; });
			if (a() > 0) { throw new Error("boom"); }
		});
	}, (err: string) => { handled = handled + 1; });
	setA(1);
	assert runs === 2 && handled === 1, "it ran twice and failed once: runs=" + runs.toString();
	setA(2);
	assert runs === 2, "a failed computation does not run again: runs=" + runs.toString();
	assert handled === 1, "and does not fire the handler again";
	assert cleaned > 0, "its cleanups ran";
}

test "a bare throw still reaches the handler" {
	let ran = 0;
	catchError(() => { throw "bare 7"; }, (err: string) => { ran = ran + 1; });
	assert ran === 1, "a non-Error throw is routed, not lost";
}

test "catchError restores the owner it ran under" {
	createRoot((dispose) => {
		let sameOwner = false;
		let ran = 0;
		catchError(() => { throw new Error("boom"); }, (err: string) => { ran = ran + 1; });
		createEffect(() => { sameOwner = true; ran = ran + 1; });
		assert ran === 2, "the scope did not leak: ran=" + ran.toString();
		assert sameOwner, "an effect still mounts after a caught error";
		dispose();
		return 0;
	});
}
