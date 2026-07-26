// Memo - Cached Computation Primitive
// Like a derived signal that only recomputes when dependencies change

import { Signal } from "./signal";
import { createComputation, runComputation } from "./runtime";

export function createMemo<T>(fn: () => T, equals: ((a: T, b: T) => boolean) | null = null): () => T {
	const signal = new Signal<T>(undefined as T);
	let initialized = false;
	let prev: T = undefined as T;

	// Pure computation → drains in the updates phase before effects, so a downstream
	// effect never reads a stale memo (no glitch). Owned by the current scope.
	const comp = createComputation(() => {
		const value = fn();
		if (initialized && equals !== null && equals(prev, value)) { return; }
		prev = value;
		signal.set(value);
		initialized = true;
	}, true);
	runComputation(comp);

	return () => {
		if (!initialized) {
			throw new Error("Memo accessed before initialization");
		}
		return signal.get();
	};
}
