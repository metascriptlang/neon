import { createSignal, untrack } from "../../src/core/signal";
import { createEffect } from "../../src/core/effect";
import { createRoot, runWithOwner } from "../../src/core/owner";
import { getOwner, flush, resetErrorHalt } from "../../src/core/runtime";
import { Cleanup } from "../../src/core/types";

test "a throw inside flush(fn) does not freeze later reactivity" {
	const [a, setA] = createSignal(0);
	let runs = 0;
	createEffect<int32>((p: int32 | null): int32 => a(), (v: int32, p: int32 | null): Cleanup | null => { runs = runs + 1; return null; });
	flush();
	const before = runs;
	try { flush(() => { throw new Error("boom"); }); } catch (e) { }
	setA(1);
	flush();
	assert runs > before, "a leaked sync depth stops every future drain";
}

test "a throw inside an effect halts the scheduler until it is reset" {
	const [a, setA] = createSignal(0);
	const [b, setB] = createSignal(0);
	createEffect<int32>(
		(p: int32 | null): int32 => a(),
		(v: int32, p: int32 | null): Cleanup | null => { if (v === 1) { throw new Error("boom"); } return null; },
	);
	let seen = 0;
	createEffect<int32>((p: int32 | null): int32 => b(), (v: int32, p: int32 | null): Cleanup | null => { seen = seen + 1; return null; });
	flush();
	try { setA(1); flush(); } catch (e) { }
	const before = seen;
	setB(1);
	flush();
	assert seen === before, "a halted scheduler runs nothing";
	resetErrorHalt();
	setB(2);
	flush();
	assert seen > before, "a reset scheduler drains again: a leaked running flag would make runQueue a permanent no-op";
}

test "a throw inside untrack restores the listener" {
	const [a, setA] = createSignal(0);
	let runs = 0;
	createEffect<int32>(
		(p: int32 | null): int32 => {
			runs = runs + 1;
			try { untrack(() => { throw new Error("boom"); }); } catch (e) { }
			return a();
		},
		(v: int32, p: int32 | null): Cleanup | null => null,
	);
	flush();
	const before = runs;
	setA(1);
	flush();
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
