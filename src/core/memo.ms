// Memo - Cached Computation Primitive
// Like a derived signal that only recomputes when dependencies change

import { Signal } from "./signal";
import { createEffect } from "./effect";

export function createMemo<T>(fn: () => T): () => T {
	const signal = new Signal<T>(undefined as T);
	let initialized = false;

	createEffect(() => {
		const value = fn();
		signal.set(value);
		initialized = true;
	});

	return () => {
		if (!initialized) {
			throw new Error("Memo accessed before initialization");
		}
		return signal.get();
	};
}
