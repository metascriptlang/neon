// Effect — a computation that auto-tracks signal reads and re-runs on change.
// Returns a Dispose that unlinks it from every signal and runs its cleanups.

import { Dispose } from "./types";
import { createComputation, runComputation, cleanNode } from "./runtime";

export function createEffect(fn: () => void): Dispose {
	const comp = createComputation(fn, false);
	runComputation(comp);
	return () => { cleanNode(comp, true); };
}
