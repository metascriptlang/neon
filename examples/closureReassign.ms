// Closure Reassignment Test
// Verifies DRC handles closure variable reassignment (Change 4 fix)
// Before fix: old closure env leaked, new value not incref'd

import { createSignal } from "../src/core/signal";

function main(): void {
	console.log("Closure reassignment test");

	// Create two closures via signals
	const [a, _setA] = createSignal(1);
	const [b, _setB] = createSignal(2);

	// Reassign closure variable — old must be destroyed, new must be incref'd
	let x = a;
	console.log("x() before reassign:", x());

	x = b;  // This was the bug: old x leaked, b not incref'd
	console.log("x() after reassign:", x());

	console.log("Closure reassignment test complete");
}

main();
