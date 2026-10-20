import { createEffect } from "../../src/core/effect";
import { createRoot } from "../../src/core/owner";
import { flush } from "../../src/core/runtime";
import { Cleanup } from "../../src/core/types";
import { createStore } from "../../src/core/store";

test "one array under two keys is one store: a write through one re-runs the reader of the other" {
	const shared: number[] = [1];
	const [state, setState] = createStore<{ x: number[], y: number[] }>({ x: shared, y: shared });
	const seen: number[] = [];
	createRoot((d) => {
		createEffect<number>((p: number | null): number => state.y[0], (v: number, p: number | null): Cleanup | null => { seen.push(v); return null; });
	});
	flush();
	setState((s) => { s.x[0] = 2; });
	flush();
	assert seen.join(",") === "1,2", "seen: " + seen.join(",");
}
