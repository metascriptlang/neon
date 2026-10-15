import { createSignal } from "../../src/core/signal";
import { createMemo } from "../../src/core/memo";
import { createEffect, createRenderEffect } from "../../src/core/effect";
import { createRoot, runWithOwner } from "../../src/core/owner";
import { onCleanup } from "../../src/core/cleanup";
import { flush, getOwner, disposeNode } from "../../src/core/runtime";
import { Computation, Dispose, Cleanup } from "../../src/core/types";

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
		createEffect<boolean>((p: boolean | null): boolean => { memo(); return true; }, (v: boolean, p: boolean | null): Cleanup | null => null);
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
		createEffect<boolean>((p: boolean | null): boolean => { onCleanup(() => { order.push("D"); }); return true; }, (v: boolean, p: boolean | null): Cleanup | null => null);
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
		createEffect<boolean>(
			(p: boolean | null): boolean => {
				onCleanup(() => { order.push("parent"); });
				createEffect<boolean>((q: boolean | null): boolean => { onCleanup(() => { order.push("a"); }); return true; }, (v: boolean, q: boolean | null): Cleanup | null => null);
				createEffect<boolean>((q: boolean | null): boolean => { onCleanup(() => { order.push("b"); }); return true; }, (v: boolean, q: boolean | null): Cleanup | null => null);
				return true;
			},
			(v: boolean, p: boolean | null): Cleanup | null => null,
		);
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
			createEffect<boolean>((p: boolean | null): boolean => { onCleanup(() => { order.push("+A1"); }); return true; }, (v: boolean, p: boolean | null): Cleanup | null => null);
			createEffect<boolean>((p: boolean | null): boolean => { onCleanup(() => { order.push("+B1"); }); return true; }, (v: boolean, p: boolean | null): Cleanup | null => null);
		});
		createRoot((d2) => {
			onCleanup(() => { order.push("SUBTREE 2"); });
			createEffect<boolean>((p: boolean | null): boolean => { onCleanup(() => { order.push("+A2"); }); return true; }, (v: boolean, p: boolean | null): Cleanup | null => null);
			createEffect<boolean>((p: boolean | null): boolean => { onCleanup(() => { order.push("+B2"); }); return true; }, (v: boolean, p: boolean | null): Cleanup | null => null);
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
		createEffect<boolean>((p: boolean | null): boolean => { onCleanup(() => { fired += 1; }); return true; }, (v: boolean, p: boolean | null): Cleanup | null => null);
		let stop: Dispose | null = null;
		createRoot((d2) => {
			stop = d2;
			createEffect<boolean>((p: boolean | null): boolean => true, (v: boolean, p: boolean | null): Cleanup | null => null);
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
	let middle: Computation | null = null;
	let ran = "";
	createRoot((d) => {
		owner = getOwner();
		createEffect<boolean>((p: boolean | null): boolean => { onCleanup(() => { ran += "a"; }); return true; }, (v: boolean, p: boolean | null): Cleanup | null => null);
		createEffect<boolean>((p: boolean | null): boolean => { middle = getOwner(); onCleanup(() => { ran += "b"; }); return true; }, (v: boolean, p: boolean | null): Cleanup | null => null);
		createEffect<boolean>((p: boolean | null): boolean => { onCleanup(() => { ran += "c"; }); return true; }, (v: boolean, p: boolean | null): Cleanup | null => null);
	});
	flush();
	const o = owner;
	const m = middle;
	assert o !== null && m !== null;
	assert childrenOf(o) === 3;
	disposeNode(m);
	assert childrenOf(o) === 2, "the middle child left the chain";
	assert ran === "b";
	flush();
	assert childrenOf(o) === 2;
}

test "disposing the first or the last child unlinks it from the chain" {
	let owner: Computation | null = null;
	let first: Computation | null = null;
	let last: Computation | null = null;
	createRoot((d) => {
		owner = getOwner();
		createEffect<boolean>((p: boolean | null): boolean => { first = getOwner(); return true; }, (v: boolean, p: boolean | null): Cleanup | null => null);
		createEffect<boolean>((p: boolean | null): boolean => true, (v: boolean, p: boolean | null): Cleanup | null => null);
		createEffect<boolean>((p: boolean | null): boolean => { last = getOwner(); return true; }, (v: boolean, p: boolean | null): Cleanup | null => null);
	});
	flush();
	const o = owner;
	const f = first;
	const l = last;
	assert o !== null && f !== null && l !== null;
	assert childrenOf(o) === 3;
	disposeNode(f);
	assert childrenOf(o) === 2;
	disposeNode(l);
	assert childrenOf(o) === 1;
}

test "a lazy memo that loses its reader leaves the chain and its siblings stay owned" {
	let owner: Computation | null = null;
	const [read, setRead] = createSignal(true);
	const [tick, setTick] = createSignal(0);
	createRoot((d) => {
		owner = getOwner();
		createEffect<boolean>((p: boolean | null): boolean => { tick(); return true; }, (v: boolean, p: boolean | null): Cleanup | null => null);
		const m1 = createMemo<int32>((): int32 => tick() * 2, { lazy: true });
		createRenderEffect<boolean>((p: boolean | null): boolean => { if (read()) { m1(); } return true; }, (v: boolean, p: boolean | null): Cleanup | null => null);
		createEffect<boolean>((p: boolean | null): boolean => { tick(); return true; }, (v: boolean, p: boolean | null): Cleanup | null => null);
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
		createRenderEffect<boolean>(
			(p: boolean | null): boolean => {
				const e = getOwner();
				inside = e !== null && e !== owner && e.parent === owner;
				return true;
			},
			(v: boolean, p: boolean | null): Cleanup | null => null,
		);
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
		createRenderEffect<boolean>(
			(p: boolean | null): boolean => {
				runs += 1;
				runWithOwner(o, () => x());
				return true;
			},
			(v: boolean, p: boolean | null): Cleanup | null => null,
		);
	});
	setX(1);
	flush();
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
