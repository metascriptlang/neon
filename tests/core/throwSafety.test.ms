import { createSignal, untrack, batch } from "../../src/core/signal";
import { createEffect } from "../../src/core/effect";
import { createRoot, runWithOwner } from "../../src/core/owner";
import { getOwner } from "../../src/core/runtime";

test "a throw inside batch does not freeze later reactivity" {
	const [a, setA] = createSignal(0);
	let runs = 0;
	createEffect(() => { a(); runs = runs + 1; });
	const before = runs;
	try { batch(() => { throw new Error("boom"); }); } catch (e) { }
	setA(1);
	assert runs > before, "a leaked batch depth stops every future drain";
}

test "a throw inside an effect does not kill the scheduler" {
	const [a, setA] = createSignal(0);
	const [b, setB] = createSignal(0);
	createEffect(() => { if (a() === 1) { throw new Error("boom"); } });
	let seen = 0;
	createEffect(() => { b(); seen = seen + 1; });
	try { setA(1); } catch (e) { }
	const before = seen;
	setB(1);
	assert seen > before, "a leaked running flag makes runQueue a permanent no-op";
}

test "a throw inside untrack restores the listener" {
	const [a, setA] = createSignal(0);
	let runs = 0;
	createEffect(() => {
		runs = runs + 1;
		try { untrack(() => { throw new Error("boom"); }); } catch (e) { }
		a();
	});
	const before = runs;
	setA(1);
	assert runs > before, "a leaked null listener stops the reads after it from tracking";
}

test "a throw inside createRoot restores the owner" {
	const before = getOwner();
	try {
		createRoot((dispose) => { throw new Error("boom"); return 0; });
	} catch (e) { }
	assert getOwner() === before, "owner must be restored";
}

test "a throw inside runWithOwner restores the owner" {
	let restored = false;
	createRoot((dispose) => {
		const scope = getOwner();
		try { runWithOwner(null, () => { throw new Error("boom"); return 0; }); } catch (e) { }
		restored = getOwner() === scope;
		return 0;
	});
	assert restored, "owner must be restored";
}
