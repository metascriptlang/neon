// Counter Example
// Basic reactive counter demonstrating signals and effects

import { createSignal } from "../src/core/signal";
import { createEffect } from "../src/core/effect";
import { Cleanup } from "../src/core/types";

function main(): void {
	console.log("Counter Example");

	// Create reactive state
	const [count, setCount] = createSignal(0);

	// Create effect that logs count changes
	createEffect<int32>(
		(prev: int32 | null): int32 => count(),
		(value: int32, prev: int32 | null): Cleanup | null => {
			console.log("Count:", value);
			return null;
		},
	);

	// Update count
	console.log("Setting count to 5...");
	setCount(5);

	console.log("Setting count to 10...");
	setCount(10);

	console.log("Counter example complete");
}
