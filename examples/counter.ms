// Counter Example
// Basic reactive counter demonstrating signals and effects

import { createSignal } from "../src/core/signal";
import { createEffect } from "../src/core/effect";

function main(): void {
	console.log("Counter Example");

	// Create reactive state
	const [count, setCount] = createSignal(0);

	// Create effect that logs count changes
	createEffect(() => {
		console.log("Count:", count());
	});

	// Update count
	console.log("Setting count to 5...");
	setCount(5);

	console.log("Setting count to 10...");
	setCount(10);

	console.log("Counter example complete");
}
