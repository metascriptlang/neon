import { createSignal } from "../../src/core/signal";
import { createEffect } from "../../src/core/effect";
import { createRoot } from "../../src/core/owner";
import { createSelector } from "../../src/core/selector";

function scoped(fn: () => void): void {
	createRoot((dispose: () => void): void => {
		try { fn(); } finally { dispose(); }
	});
}

test "a nullable source can enter and clear a selection" {
	scoped(() => {
		const [id, setId] = createSignal<int32 | null>(null);
		const selected = createSelector(id);
		let value = false;
		let runs = 0;
		createEffect(() => { value = selected(0); runs += 1; });
		assert !value && runs === 1;
		setId(0);
		assert value && runs === 2;
		setId(null);
		assert !value && runs === 3;
	});
}
