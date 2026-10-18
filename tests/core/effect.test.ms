import { createSignal } from "../../src/core/signal";
import { createMemo } from "../../src/core/memo";
import { flush } from "../../src/core/runtime";
import { createEffect, createRenderEffect } from "../../src/core/effect";
import { onCleanup } from "../../src/core/cleanup";
import { createRoot } from "../../src/core/owner";
import { Cleanup } from "../../src/core/types";

function show(v: int32 | null): string {
	return v === null ? "none" : (v as int32).toString();
}

test "the effect gets the compute's value and the previous one, after the compute" {
	const [x, setX] = createSignal(0);
	const log: string[] = [];
	createRoot((d) => {
		createEffect<int32>(
			(p: int32 | null): int32 => { log.push("compute"); return x(); },
			(v: int32, p: int32 | null): Cleanup | null => { log.push("effect " + v.toString() + "/" + show(p)); return null; },
		);
		log.push("body");
		return 0;
	});
	flush();
	setX(1);
	flush();
	assert log.join(",") === "compute,body,effect 0/none,compute,effect 1/0", "got " + log.join(",");
}

test "a render effect applies at once and gets the same pair" {
	const [x, setX] = createSignal(0);
	const log: string[] = [];
	createRoot((d) => {
		createRenderEffect<int32>(
			(p: int32 | null): int32 => { log.push("compute"); return x(); },
			(v: int32, p: int32 | null): Cleanup | null => { log.push("effect " + v.toString() + "/" + show(p)); return null; },
		);
		log.push("body");
		return 0;
	});
	flush();
	setX(1);
	flush();
	assert log.join(",") === "compute,effect 0/none,body,compute,effect 1/0", "got " + log.join(",");
}

test "only the compute is tracked" {
	const [x, setX] = createSignal(0);
	const [y, setY] = createSignal(0);
	let user = 0;
	let render = 0;
	createRoot((d) => {
		createEffect<int32>(
			(p: int32 | null): int32 => x(),
			(v: int32, p: int32 | null): Cleanup | null => { y(); user += 1; return null; },
		);
		createRenderEffect<int32>(
			(p: int32 | null): int32 => x(),
			(v: int32, p: int32 | null): Cleanup | null => { y(); render += 1; return null; },
		);
		return 0;
	});
	flush();
	setY(1);
	flush();
	assert user === 1 && render === 1, "a read in the effect phase subscribes nothing: " + user.toString() + "," + render.toString();
	setX(1);
	flush();
	assert user === 2 && render === 2, "the compute's source still runs both: " + user.toString() + "," + render.toString();
}

test "a render effect runs before a user effect created ahead of it" {
	const [x, setX] = createSignal(0);
	let mark = "";
	createRoot((d) => {
		createEffect<int32>(
			(p: int32 | null): int32 => x(),
			(v: int32, p: int32 | null): Cleanup | null => { mark += "b"; return null; },
		);
		createRenderEffect<int32>(
			(p: int32 | null): int32 => x(),
			(v: int32, p: int32 | null): Cleanup | null => { mark += "a"; return null; },
		);
		return 0;
	});
	assert mark === "a", "the render effect applied at creation: " + mark;
	flush();
	assert mark === "ab", "got " + mark;
	setX(1);
	flush();
	assert mark === "abab", "got " + mark;
}

test "an effect created at the top level first applies on the next flush, as one in a root does" {
	let runs = 0;
	createEffect<boolean>(
		(p: boolean | null): boolean => true,
		(v: boolean, p: boolean | null): Cleanup | null => { runs += 1; return null; },
	);
	assert runs === 0, "nothing applies before the flush";
	flush();
	assert runs === 1;
}

test "an effect created in a root applies after the root body" {
	const log: string[] = [];
	createRoot((d) => {
		createEffect<boolean>((p: boolean | null): boolean => true, (v: boolean, p: boolean | null): Cleanup | null => { log.push("effect"); return null; });
		createRenderEffect<boolean>((p: boolean | null): boolean => true, (v: boolean, p: boolean | null): Cleanup | null => { log.push("render"); return null; });
		log.push("body");
		return 0;
	});
	assert log.join(",") === "render,body", "got " + log.join(",");
	flush();
	assert log.join(",") === "render,body,effect", "got " + log.join(",");
}

test "effects apply in creation order after a nested root" {
	const log: string[] = [];
	createRoot((d) => {
		createEffect<boolean>((p: boolean | null): boolean => true, (v: boolean, p: boolean | null): Cleanup | null => { log.push("outer"); return null; });
		createRoot((d2) => {
			createEffect<boolean>((p: boolean | null): boolean => true, (v: boolean, p: boolean | null): Cleanup | null => { log.push("inner"); return null; });
			return 0;
		});
		log.push("body");
		return 0;
	});
	flush();
	assert log.join(",") === "body,outer,inner", "got " + log.join(",");
}

test "an effect created in flush(fn) applies when it ends" {
	const log: string[] = [];
	flush(() => {
		createEffect<boolean>((p: boolean | null): boolean => true, (v: boolean, p: boolean | null): Cleanup | null => { log.push("effect"); return null; });
		log.push("body");
	});
	assert log.join(",") === "body,effect", "got " + log.join(",");
}

test "a render effect writing the host runs before an effect reading it back" {
	const [count, setCount] = createSignal(0);
	let host = -1;
	const seen: number[] = [];
	createRoot((d) => {
		createEffect<int32>(
			(p: int32 | null): int32 => count(),
			(v: int32, p: int32 | null): Cleanup | null => { seen.push(host); return null; },
		);
		createRenderEffect<int32>(
			(p: int32 | null): int32 => count(),
			(v: int32, p: int32 | null): Cleanup | null => { host = v; return null; },
		);
		return 0;
	});
	flush();
	setCount(5);
	flush();
	assert seen.join(",") === "0,5", "got " + seen.join(",");
}

test "a disposed root drops its pending effect" {
	let runs = 0;
	createRoot((d) => {
		createEffect<boolean>((p: boolean | null): boolean => true, (v: boolean, p: boolean | null): Cleanup | null => { runs += 1; return null; });
		d();
		return 0;
	});
	assert runs === 0, "disposed before it applied";
}

test "defer skips the first apply and the next change applies" {
	const [x, setX] = createSignal(0);
	let user = "";
	let render = "";
	createRoot((d) => {
		createEffect<int32>(
			(p: int32 | null): int32 => x(),
			(v: int32, p: int32 | null): Cleanup | null => { user += "u" + v.toString() + "/" + show(p) + " "; return null; },
			{ defer: true },
		);
		createRenderEffect<int32>(
			(p: int32 | null): int32 => x(),
			(v: int32, p: int32 | null): Cleanup | null => { render += "r" + v.toString() + "/" + show(p) + " "; return null; },
			{ defer: true },
		);
		return 0;
	});
	flush();
	assert user === "" && render === "", "nothing applied at creation";
	setX(1);
	flush();
	assert user === "u1/none " && render === "r1/none ", "the deferred first apply sees no previous: [" + user + "][" + render + "]";
}

test "a cleanup registered in the compute and the returned cleanup run before each new run" {
	const [x, setX] = createSignal(0);
	let applied = 0;
	let computeCleanups = 0;
	let returned = 0;
	createRoot((d) => {
		createEffect<int32>(
			(p: int32 | null): int32 => {
				onCleanup(() => { computeCleanups += 1; });
				return x();
			},
			(v: int32, p: int32 | null): Cleanup | null => {
				applied += 1;
				return () => { returned += 1; };
			},
		);
		return 0;
	});
	flush();
	assert applied === 1 && computeCleanups === 0 && returned === 0, "first run cleans nothing";
	for (let i = 1; i <= 3; i += 1) {
		setX(i);
		flush();
		assert applied === i + 1, "applied " + applied.toString() + " at " + i.toString();
		assert computeCleanups === i, "compute cleanups " + computeCleanups.toString() + " at " + i.toString();
		assert returned === i, "returned cleanups " + returned.toString() + " at " + i.toString();
	}
}

test "the last returned cleanup runs once at disposal, on both effect kinds" {
	const [x, setX] = createSignal(0);
	let user = 0;
	let render = 0;
	let dispose: (() => void) | null = null;
	createRoot((d) => {
		dispose = d;
		createEffect<int32>((p: int32 | null): int32 => x(), (v: int32, p: int32 | null): Cleanup | null => () => { user += 1; });
		createRenderEffect<int32>((p: int32 | null): int32 => x(), (v: int32, p: int32 | null): Cleanup | null => () => { render += 1; });
		return 0;
	});
	flush();
	assert user === 0 && render === 0, "nothing cleaned yet";
	setX(1);
	flush();
	assert user === 1 && render === 1, "the previous run's cleanup: " + user.toString() + "," + render.toString();
	(dispose as () => void)();
	assert user === 2 && render === 2, "the final cleanup, once: " + user.toString() + "," + render.toString();
	setX(2);
	flush();
	assert user === 2 && render === 2, "a disposed effect neither applies nor cleans again";
}

test "the final cleanups unwind newest first around the owner's own" {
	const order: string[] = [];
	let dispose: (() => void) | null = null;
	createRoot((d) => {
		dispose = d;
		onCleanup(() => { order.push("before"); });
		createRenderEffect<boolean>((p: boolean | null): boolean => true, (v: boolean, p: boolean | null): Cleanup | null => () => { order.push("A"); });
		createRenderEffect<boolean>((p: boolean | null): boolean => true, (v: boolean, p: boolean | null): Cleanup | null => () => { order.push("B"); });
		onCleanup(() => { order.push("after"); });
		return 0;
	});
	(dispose as () => void)();
	assert order.join(",") === "B,A,after,before", "got " + order.join(",");
}

test "disposing an inner root runs the cleanup once and the outer disposal does not repeat it" {
	let cleaned = 0;
	let disposeInner: (() => void) | null = null;
	let disposeOuter: (() => void) | null = null;
	createRoot((outer) => {
		disposeOuter = outer;
		createRoot((inner) => {
			disposeInner = inner;
			createRenderEffect<boolean>((p: boolean | null): boolean => true, (v: boolean, p: boolean | null): Cleanup | null => () => { cleaned += 1; });
			return 0;
		});
		return 0;
	});
	(disposeInner as () => void)();
	assert cleaned === 1, "the inner disposal ran it";
	(disposeOuter as () => void)();
	assert cleaned === 1, "the outer disposal finds nothing left: " + cleaned.toString();
}

test "an effect that disposes its own root runs the cleanup it returns" {
	let cleaned = 0;
	createRoot((d) => {
		createRenderEffect<boolean>(
			(p: boolean | null): boolean => true,
			(v: boolean, p: boolean | null): Cleanup | null => {
				d();
				return () => { cleaned += 1; };
			},
		);
		return 0;
	});
	assert cleaned === 1, "a cleanup returned by a disposed effect is not dropped: " + cleaned.toString();
}

test "a child effect created in the compute is rebuilt by the parent and runs once per change" {
	const [x, setX] = createSignal(0);
	const gate = createMemo<int32>((): int32 => x());
	let calls = 0;
	createRoot((d) => {
		createEffect<int32>(
			(p: int32 | null): int32 => {
				createEffect<int32>(
					(q: int32 | null): int32 => x(),
					(v: int32, q: int32 | null): Cleanup | null => { calls += 1; return null; },
				);
				return gate();
			},
			(v: int32, p: int32 | null): Cleanup | null => null,
		);
		return 0;
	});
	flush();
	calls = 0;
	setX(1);
	flush();
	assert calls === 1, "the parent rebuilt the child, which applied once: " + calls.toString();
}

test "disposing the root drops a nested effect" {
	const [x, setX] = createSignal(0);
	let inner = 0;
	let dispose: (() => void) | null = null;
	createRoot((d) => {
		dispose = d;
		createEffect<boolean>(
			(p: boolean | null): boolean => {
				createEffect<int32>(
					(q: int32 | null): int32 => x(),
					(v: int32, q: int32 | null): Cleanup | null => { inner += 1; return null; },
				);
				return true;
			},
			(v: boolean, p: boolean | null): Cleanup | null => null,
		);
		return 0;
	});
	const before = inner;
	(dispose as () => void)();
	setX(10);
	assert inner === before, "the inner effect did not apply after its root was disposed";
}
