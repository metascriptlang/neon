// Memo - Cached Computation Primitive
// Like a derived signal that only recomputes when dependencies change

import { Signal, Accessor, accessor } from "./signal";
import { createComputation, runComputation } from "./runtime";

export function createMemo<T>(fn: () => T, equals: ((a: T, b: T) => boolean) | null = null): Accessor<T> {
	let signal: Signal<T> | null = null;

	// Pure computation → drains in the updates phase before effects, so a downstream
	// effect never reads a stale memo (no glitch). Owned by the current scope.
	const comp = createComputation(() => {
		const value = fn();
		const held = signal;
		if (held === null) {
			signal = new Signal<T>(value);
			return;
		}
		if (equals !== null && equals(held.peek(), value)) { return; }
		held.set(value);
	}, true);
	runComputation(comp);

	return accessor(() => {
		const held = signal;
		if (held === null) {
			throw new Error("Memo accessed before initialization");
		}
		return held.get();
	});
}
