// Effect — a computation that auto-tracks signal reads and re-runs on change.
// Returns a Dispose that unlinks it from every signal and runs its cleanups.

import { Dispose } from "./types";
import { createComputation, runComputation, cleanNode, onServer, deferringUserEffects, queueUserEffect } from "./runtime";
import { untrack } from "./signal";

function noop(): void {}

export function createEffect(fn: () => void): Dispose {
	if (onServer()) { return noop; }
	const comp = createComputation(fn, false);
	comp.user = true;
	if (deferringUserEffects()) { queueUserEffect(comp); } else { runComputation(comp); }
	return () => { cleanNode(comp, true); };
}

export function onMount(fn: () => void): void {
	createEffect((): void => { untrack(fn); });
}

export function createRenderEffect(fn: () => void): Dispose {
	const comp = createComputation(fn, false);
	runComputation(comp);
	return () => { cleanNode(comp, true); };
}

export function createBindingEffect(fn: () => void): Dispose {
	const comp = createComputation(fn, false, true);
	runComputation(comp);
	return () => { cleanNode(comp, true); };
}
