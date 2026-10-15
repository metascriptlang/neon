import { createSignal } from "../../src/core/signal";
import { createEffect } from "../../src/core/effect";
import { createRoot } from "../../src/core/owner";

test "an unannotated compute and effect infer T from the compute" {
	const [a, setA] = createSignal(1);
	const seen: number[] = [];
	createRoot((d) => {
		createEffect(() => a() * 2, (v) => { seen.push(v); return null; });
		return 0;
	});
	setA(2);
	assert seen.join(",") === "2,4", "got " + seen.join(",");
}
