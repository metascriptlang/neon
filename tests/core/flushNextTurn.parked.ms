import { createSignal } from "../../src/core/signal";
import { createEffect } from "../../src/core/effect";
import { createRoot } from "../../src/core/owner";
import { Cleanup } from "../../src/core/types";

// Parked on ~/metascript/.inbox/compiler/2026-10-18-await-of-a-settled-promise-in-a-sync-context-skips-queued-callbacks-on-c.md: rename into the suite once it passes on C.
test "a write outside flush(fn) applies before the next timer, as Solid's microtask flush does" {
	const [x, setX] = createSignal(10);
	let seen = 0;
	createRoot((d) => {
		createEffect<int32>((p: int32 | null): int32 => x(), (v: int32, p: int32 | null): Cleanup | null => { seen = v; return null; });
	});
	await Promise.resolve(0);
	assert seen === 10, "the first run came on its own: " + seen.toString();
	setX(20);
	await Promise.resolve(0);
	assert seen === 20, "the write applied on its own: " + seen.toString();
}
