import { createSignal } from "../../src/core/signal";
import { createRenderEffect } from "../../src/core/effect";
import { onCleanup } from "../../src/core/cleanup";
import { createRoot } from "../../src/core/owner";
import { catchError } from "../../src/core/error";
import { resetErrorHalt } from "../../src/core/runtime";
import { Cleanup } from "../../src/core/types";

test "catchError catches a throw in its own body" {
	const thrown = new Error("boom 7");
	let seen: Error | null = null;
	catchError(() => { throw thrown; }, (err: Error) => { seen = err; });
	assert seen === thrown, "the handler is given the thrown Error itself";
	assert (seen as Error).message === "boom 7", "with its message: [" + (seen as Error).message + "]";
}

test "an effect under catchError routes a later compute throw to the handler" {
	const [a, setA] = createSignal(0);
	const thrown = new Error("late 7");
	let seen: Error | null = null;
	catchError(() => {
		createRenderEffect<int32>(
			(p: int32 | null): int32 => { if (a() === 1) { throw thrown; } return a(); },
			(v: int32, p: int32 | null): Cleanup | null => null,
		);
	}, (err: Error) => { seen = err; });
	assert seen === null, "nothing failed on the first run";
	setA(1);
	assert seen === thrown, "the write re-ran the effect and the owner carried the handler";
	assert (seen as Error).message === "late 7", "with its message: [" + (seen as Error).message + "]";
}

test "an effect under catchError routes a later effect-phase throw to the handler" {
	const [a, setA] = createSignal(0);
	const thrown = new Error("apply 7");
	let seen: Error | null = null;
	catchError(() => {
		createRenderEffect<int32>(
			(p: int32 | null): int32 => a(),
			(v: int32, p: int32 | null): Cleanup | null => { if (v === 1) { throw thrown; } return null; },
		);
	}, (err: Error) => { seen = err; });
	assert seen === null, "nothing failed on the first run";
	setA(1);
	assert seen === thrown, "the throw in the effect phase reached the owner's handler";
}

test "the nearest handler wins" {
	const thrown = new Error("boom");
	let outer: Error | null = null;
	let inner: Error | null = null;
	catchError(() => {
		catchError(() => { throw thrown; }, (err: Error) => { inner = err; });
	}, (err: Error) => { outer = err; });
	assert inner === thrown, "the inner handler ran";
	assert outer === null, "the outer handler was not reached";
}

test "a throw with no handler still escapes" {
	const [a, setA] = createSignal(0);
	createRenderEffect<int32>(
		(p: int32 | null): int32 => { if (a() === 1) { throw new Error("loud"); } return a(); },
		(v: int32, p: int32 | null): Cleanup | null => null,
	);
	let escaped = "";
	try { setA(1); } catch (e) { escaped = e.message; }
	assert escaped === "loud", "an unhandled throw is never swallowed: [" + escaped + "]";
	resetErrorHalt();
}

test "an effect-phase throw with no handler still escapes" {
	const [a, setA] = createSignal(0);
	createRenderEffect<int32>(
		(p: int32 | null): int32 => a(),
		(v: int32, p: int32 | null): Cleanup | null => { if (v === 1) { throw new Error("loud apply"); } return null; },
	);
	let escaped = "";
	try { setA(1); } catch (e) { escaped = e.message; }
	assert escaped === "loud apply", "an unhandled throw is never swallowed: [" + escaped + "]";
	resetErrorHalt();
}

test "a computation that threw is disposed, not re-run" {
	const [a, setA] = createSignal(0);
	let runs = 0;
	let handled = 0;
	let cleaned = 0;
	catchError(() => {
		createRenderEffect<int32>(
			(p: int32 | null): int32 => {
				runs = runs + 1;
				onCleanup(() => { cleaned = cleaned + 1; });
				if (a() > 0) { throw new Error("boom"); }
				return a();
			},
			(v: int32, p: int32 | null): Cleanup | null => null,
		);
	}, (err: Error) => { handled = handled + 1; });
	setA(1);
	assert runs === 2 && handled === 1, "it ran twice and failed once: runs=" + runs.toString();
	setA(2);
	assert runs === 2, "a failed computation does not run again: runs=" + runs.toString();
	assert handled === 1, "and does not fire the handler again";
	assert cleaned > 0, "its cleanups ran";
}

test "a thrown string reaches the handler as an Error carrying it" {
	let seen: Error | null = null;
	catchError(() => { throw "bare 7"; }, (err: Error) => { seen = err; });
	assert seen !== null && (seen as Error) instanceof Error, "the string arrives boxed in an Error";
	assert (seen as Error).message === "bare 7", "with the string as its message: [" + (seen as Error).message + "]";
}

test "catchError restores the owner it ran under" {
	createRoot((dispose) => {
		let sameOwner = false;
		let ran = 0;
		catchError(() => { throw new Error("boom"); }, (err: Error) => { ran = ran + 1; });
		createRenderEffect<boolean>(
			(p: boolean | null): boolean => { sameOwner = true; ran = ran + 1; return true; },
			(v: boolean, p: boolean | null): Cleanup | null => null,
		);
		assert ran === 2, "the scope did not leak: ran=" + ran.toString();
		assert sameOwner, "an effect still mounts after a caught error";
		dispose();
		return 0;
	});
}
