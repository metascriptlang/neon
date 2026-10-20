import { createMemo } from "../../src/core/memo";
import { createRoot } from "../../src/core/owner";
import { flush } from "../../src/core/runtime";
import { createStore } from "../../src/core/store";

test "a function-valued field re-runs its readers when replaced" {
	const [state, setState] = createStore<{ fn: () => number }>({ fn: (): number => 1 });
	let value: () => number = () => 0;
	createRoot((d) => {
		value = createMemo<number>((): number => state.fn());
	});
	assert value() === 1;
	setState((s) => { s.fn = (): number => 2; });
	flush();
	assert value() === 2, "value: " + value().toString();
}
