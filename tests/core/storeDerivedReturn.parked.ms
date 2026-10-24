import { createEffect } from "../../src/core/effect";
import { createRoot } from "../../src/core/owner";
import { createSignal } from "../../src/core/signal";
import { flush } from "../../src/core/runtime";
import { Cleanup } from "../../src/core/types";
import { createStore, createProjection } from "../../src/core/store";

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

interface Fork { v: number; }

test "a projection whose derive returns a signal's value forks it" {
	const [x, setX] = createSignal<Fork>({ v: 1 });
	const seen: number[] = [];
	createRoot((d) => {
		const a = createProjection<Fork>((draft) => x(), { v: 0 });
		createEffect<number>((p: number | null): number => a.v, (v: number, p: number | null): Cleanup | null => { seen.push(v); return null; });
	});
	flush();
	setX({ v: 2 });
	flush();
	assert seen.join(",") === "1,2", "seen: " + seen.join(",");
}
