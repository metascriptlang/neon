import { createSignal } from "../../src/core/signal";
import { createMemo } from "../../src/core/memo";
import { createEffect, createRenderEffect } from "../../src/core/effect";
import { createRoot, runWithOwner } from "../../src/core/owner";
import { onCleanup } from "../../src/core/cleanup";
import { flush, getOwner } from "../../src/core/runtime";
import { Computation, Dispose } from "../../src/core/types";

function childrenOf(owner: Computation): int32 {
	let n: int32 = 0;
	for (let c = owner.firstChild; c !== null; c = c.nextSibling) { n += 1; }
	return n;
}

test "disposing a root disposes the computations inside it for good" {
	let runs = 0;
	const [x, setX] = createSignal(10);
	createRoot((dispose) => {
		createMemo<int32>((): int32 => { runs += 1; return x() + 10; });
		dispose();
	});
	assert runs === 1;
	flush();
	setX(50);
	flush();
	assert runs === 1, "a disposed memo never runs again: " + runs.toString();
}

test "createRoot returns the body's result even when the body disposed it" {
	const result = createRoot((dispose) => {
		dispose();
		return 10;
	});
	assert result === 10;
}

test "a root body does not subscribe to what it reads" {
	let runs = 0;
	const [x, setX] = createSignal(0);
	createRoot((d) => {
		x();
		runs += 1;
	});
	setX(1);
	flush();
	assert runs === 1, "ran " + runs.toString();
}

test "a root created under a null owner outlives its creator" {
	let cleaned = 0;
	let stop: Dispose | null = null;
	createRoot((outerDispose) => {
		runWithOwner(null, () => {
			createRoot((innerDispose) => {
				stop = innerDispose;
				onCleanup(() => { cleaned += 1; });
			});
		});
		outerDispose();
	});
	assert cleaned === 0, "the detached root is still alive";
	const s = stop;
	assert s !== null;
	s();
	assert cleaned === 1;
}

test "disposing a root from its own cleanup does not run it twice" {
	let cleaned = 0;
	createRoot((dispose) => {
		onCleanup(() => { cleaned += 1; dispose(); });
		dispose();
	});
	assert cleaned === 1, "cleaned " + cleaned.toString();
}

test "a cleanup that disposes its root during a memo recompute runs once" {
	const [version, setVersion] = createSignal(0);
	let cleanups = 0;
	createRoot((dispose) => {
		const memo = createMemo<int32>((): int32 => {
			const current = version();
			if (current === 0) {
				onCleanup(() => { cleanups += 1; dispose(); });
			}
			return current;
		});
		createEffect(() => { memo(); });
	});
	flush();
	setVersion(1);
	flush();
	assert cleanups === 1, "cleanups " + cleanups.toString();
}

test "cleanups unwind children first, later registrations before earlier" {
	const order: string[] = [];
	let stop: Dispose | null = null;
	createRoot((dispose) => {
		stop = dispose;
		onCleanup(() => { order.push("A"); });
		onCleanup(() => { order.push("B"); });
		createRoot((d2) => { onCleanup(() => { order.push("C"); }); });
		createEffect(() => { onCleanup(() => { order.push("D"); }); });
	});
	flush();
	const s = stop;
	assert s !== null;
	s();
	assert order.join(",") === "D,C,B,A", "got " + order.join(",");
}

test "nested effects clean up newest first, then their parent" {
	const order: string[] = [];
	let stop: Dispose | null = null;
	createRoot((dispose) => {
		stop = dispose;
		createEffect(() => {
			onCleanup(() => { order.push("parent"); });
			createEffect(() => { onCleanup(() => { order.push("a"); }); });
			createEffect(() => { onCleanup(() => { order.push("b"); }); });
		});
	});
	flush();
	const s = stop;
	assert s !== null;
	s();
	assert order.join(",") === "b,a,parent", "got " + order.join(",");
}

test "sibling roots unwind newest first, each as children then its own cleanup" {
	const order: string[] = [];
	let stop: Dispose | null = null;
	createRoot((dispose) => {
		stop = dispose;
		createRoot((d2) => {
			onCleanup(() => { order.push("SUBTREE 1"); });
			createEffect(() => { onCleanup(() => { order.push("+A1"); }); });
			createEffect(() => { onCleanup(() => { order.push("+B1"); }); });
		});
		createRoot((d2) => {
			onCleanup(() => { order.push("SUBTREE 2"); });
			createEffect(() => { onCleanup(() => { order.push("+A2"); }); });
			createEffect(() => { onCleanup(() => { order.push("+B2"); }); });
		});
		onCleanup(() => { order.push("ROOT"); });
	});
	flush();
	const s = stop;
	assert s !== null;
	s();
	assert order.join(",") === "+B2,+A2,SUBTREE 2,+B1,+A1,SUBTREE 1,ROOT", "got " + order.join(",");
}

test "a cleanup of an inner root does not fire for an unrelated disposal" {
	let fired = 0;
	createRoot((d) => {
		createEffect(() => { onCleanup(() => { fired += 1; }); });
		let stop: Dispose | null = null;
		createRoot((d2) => {
			stop = d2;
			createEffect(() => {});
		});
		const s = stop;
		assert s !== null;
		s();
		flush();
		assert fired === 0;
	});
}

test "disposing one child leaves its siblings linked to their owner" {
	let owner: Computation | null = null;
	let disposeMiddle: Dispose | null = null;
	let ran = "";
	createRoot((d) => {
		owner = getOwner();
		createEffect(() => { onCleanup(() => { ran += "a"; }); });
		disposeMiddle = createEffect(() => { onCleanup(() => { ran += "b"; }); });
		createEffect(() => { onCleanup(() => { ran += "c"; }); });
	});
	flush();
	const o = owner;
	const m = disposeMiddle;
	assert o !== null && m !== null;
	assert childrenOf(o) === 3;
	m();
	assert childrenOf(o) === 2, "the middle child left the chain";
	assert ran === "b";
	flush();
	assert childrenOf(o) === 2;
}

test "disposing the first or the last child unlinks it from the chain" {
	let owner: Computation | null = null;
	let stopFirst: Dispose | null = null;
	let stopLast: Dispose | null = null;
	createRoot((d) => {
		owner = getOwner();
		stopFirst = createEffect(() => {});
		createEffect(() => {});
		stopLast = createEffect(() => {});
	});
	flush();
	const o = owner;
	const f = stopFirst;
	const l = stopLast;
	assert o !== null && f !== null && l !== null;
	assert childrenOf(o) === 3;
	f();
	assert childrenOf(o) === 2;
	l();
	assert childrenOf(o) === 1;
}

test "a lazy memo that loses its reader leaves the chain and its siblings stay owned" {
	let owner: Computation | null = null;
	const [read, setRead] = createSignal(true);
	const [tick, setTick] = createSignal(0);
	createRoot((d) => {
		owner = getOwner();
		createEffect(() => { tick(); });
		const m1 = createMemo<int32>((): int32 => tick() * 2, { lazy: true });
		createRenderEffect(() => { if (read()) { m1(); } });
		createEffect(() => { tick(); });
	});
	flush();
	const o = owner;
	assert o !== null;
	assert childrenOf(o) === 4;
	setRead(false);
	flush();
	assert childrenOf(o) === 3, "the unobserved memo left the chain";
	setRead(true);
	flush();
	setRead(false);
	flush();
	assert childrenOf(o) === 3, "a second dormancy leaves the siblings owned";
}

test "getOwner inside an effect is a new owner under the root's" {
	createRoot((d) => {
		const owner = getOwner();
		assert owner !== null;
		let inside = false;
		createRenderEffect(() => {
			const e = getOwner();
			inside = e !== null && e !== owner && e.parent === owner;
		});
		assert inside;
	});
}

test "runWithOwner runs under the given owner and returns the value" {
	let owner: Computation | null = null;
	createRoot((d) => { owner = getOwner(); });
	const o = owner;
	assert runWithOwner(o, () => getOwner() === o);
	assert runWithOwner(null, () => 100) === 100;
	assert getOwner() === null;
}

test "runWithOwner reads do not subscribe the computation that called it" {
	const [x, setX] = createSignal(0);
	let owner: Computation | null = null;
	createRoot((d) => { owner = getOwner(); });
	const o = owner;
	let runs = 0;
	createRoot((d) => {
		createRenderEffect(() => {
			runs += 1;
			runWithOwner(o, () => x());
		});
	});
	setX(1);
	flush();
	assert runs === 1, "ran " + runs.toString();
}

test "a signal written inside a root's body reaches an effect created in it once" {
	const [x, setX] = createSignal(0);
	let runs = 0;
	createRoot((d) => {
		createEffect(() => { x(); runs += 1; });
		setX(1);
		setX(2);
	});
	assert runs === 1, "ran " + runs.toString();
}

test "onCleanup hands back the function it registered" {
	let n = 0;
	createRoot((d) => {
		const f = (): void => { n += 1; };
		const back = onCleanup(f);
		back();
		assert n === 1;
		d();
	});
	assert n === 2, "the registered cleanup also ran at disposal: " + n.toString();
}

test "onCleanup outside any owner throws instead of dropping the function" {
	let message = "";
	try {
		onCleanup(() => {});
	} catch (e) {
		message = e.message;
	}
	assert message.includes("outside a reactive context"), "got [" + message + "]";
}

test "onCleanup under a null owner inside a root throws too" {
	let message = "";
	createRoot((d) => {
		runWithOwner(null, () => {
			try {
				onCleanup(() => {});
			} catch (e) {
				message = e.message;
			}
		});
	});
	assert message.includes("outside a reactive context"), "got [" + message + "]";
}
