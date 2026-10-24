import { createEffect } from "../../src/core/effect";
import { createRoot } from "../../src/core/owner";
import { createSignal } from "../../src/core/signal";
import { flush } from "../../src/core/runtime";
import { Cleanup } from "../../src/core/types";
import { createStore } from "../../src/core/store";

interface Count { count: number; label: string; }

test "a derive that returns a value reconciles it into the store" {
	const [source, setSource] = createSignal(1);
	const [state, setState] = createRoot((d) => {
		return createStore<Count>((draft) => ({ count: source(), label: "x" }), { count: 0, label: "" });
	});
	assert state.count === 1 && state.label === "x", "first";
	let labelRuns = 0;
	createRoot((d) => {
		createEffect<string>((p: string | null): string => { labelRuns += 1; return state.label; }, (v: string, p: string | null): Cleanup | null => null);
	});
	flush();
	setSource(5);
	flush();
	assert state.count === 5 && labelRuns === 1, "count " + state.count.toString() + " labelRuns " + labelRuns.toString();
}
