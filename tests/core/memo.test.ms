import { createMemo } from "../../src/core/memo";
import { createSignal, Accessor } from "../../src/core/signal";
import { createEffect, createRenderEffect } from "../../src/core/effect";
import { createRoot } from "../../src/core/owner";
import { flush } from "../../src/core/runtime";

test "memo without equals propagates every distinct value" {
	const [n, setN] = createSignal(1);
	const m = createMemo<int32>((): int32 => n());
	let runs = 0;
	createEffect(() => { m(); runs = runs + 1; });
	assert runs === 1, "ran once on creation";
	setN(2);
	assert runs === 2, "downstream re-ran on change";
}

test "memo with truthiness equals collapses truthy to truthy" {
	const [n, setN] = createSignal(1);
	const cond = createMemo<int32>((): int32 => n(), { equals: (a: int32, b: int32): boolean => (a !== 0) === (b !== 0) });
	let runs = 0;
	createEffect(() => { cond(); runs = runs + 1; });
	assert runs === 1, "ran once on creation";
	setN(2);
	assert runs === 1, "no downstream re-run when truthiness unchanged";
	setN(0);
	assert runs === 2, "re-ran when truthiness flipped to falsy";
}

test "memo initializes boolean without a forged null value" {
	const [read, write] = createSignal<boolean>(false);
	const memo = createMemo<boolean>(() => read());
	assert !memo();
	write(true);
	assert memo();
}

test "memo permits a real nullable result" {
	const [read, write] = createSignal<string | null>(null);
	const memo = createMemo<string | null>(() => read());
	assert memo() === null;
	write("ready");
	assert memo() === "ready";
	write(null);
	assert memo() === null;
}

test "createMemo returns a nominal Accessor" {
	const [n, setN] = createSignal<number>(1);
	const m: Accessor<number> = createMemo<number>(() => n() * 2);
	assert m() === 2;
	setN(3);
	assert m() === 6;
}

test "a memo stores its value and keeps it across reads" {
	const [x] = createSignal(1);
	const [y] = createSignal(1);
	const a = createMemo<int32>((): int32 => x() + y());
	assert a() === 2;
	flush();
	assert a() === 2;
}

test "a deep memo chain follows its signal" {
	const [x, setX] = createSignal(10);
	const [y] = createSignal(10);
	const a = createMemo<int32>((): int32 => x() + y());
	const b = createMemo<int32>((): int32 => a());
	const c = createMemo<int32>((): int32 => b());
	setX(20);
	flush();
	assert c() === 30;
}

test "an ownerless memo recomputes only when read after a write" {
	let computed = 0;
	const [x, setX] = createSignal(10);
	const [y, setY] = createSignal(10);
	const a = createMemo<int32>((): int32 => { computed += 1; return x() + y(); });
	assert computed === 1;
	a();
	assert computed === 1, "a read serves the cache";
	setX(20);
	flush();
	assert computed === 1, "a write does not run a memo nothing observes";
	assert a() === 30;
	assert computed === 2;
	setY(20);
	flush();
	assert computed === 2;
	assert a() === 40;
	assert computed === 3;
}

test "an ownerless memo read twice in one tick runs once" {
	let computed = 0;
	const [x, setX] = createSignal(0);
	const a = createMemo<int32>((): int32 => { computed += 1; return x(); });
	assert a() === 0 && a() === 0;
	assert computed === 1;
	setX(1);
	flush();
	assert computed === 1, "the sweep released it before the write ran";
	assert a() === 1;
	assert computed === 2;
	assert a() === 1;
	assert computed === 2;
}

test "an ownerless chain recomputes together on a direct read" {
	let aRuns = 0;
	let bRuns = 0;
	const [x, setX] = createSignal(10);
	const [y, setY] = createSignal(10);
	const a = createMemo<int32>((): int32 => { aRuns += 1; return x(); });
	const b = createMemo<int32>((): int32 => { bRuns += 1; return y(); });
	const c = createMemo<int32>((): int32 => a() + b());
	assert aRuns === 1 && bRuns === 1;
	assert c() === 20;
	setX(20);
	flush();
	assert aRuns === 1 && bRuns === 1;
	assert c() === 30;
	assert aRuns === 2 && bRuns === 2;
	setY(20);
	flush();
	assert aRuns === 2 && bRuns === 2;
	assert c() === 40;
	assert aRuns === 3 && bRuns === 3;
}

test "an observed ownerless memo stays subscribed" {
	let aRuns = 0;
	let bRuns = 0;
	let value = 0;
	const [x, setX] = createSignal(10);
	const [y, setY] = createSignal(10);
	createRoot((d) => {
		const a = createMemo<int32>((): int32 => { aRuns += 1; return x(); });
		const b = createMemo<int32>((): int32 => { bRuns += 1; return y(); });
		const c = createMemo<int32>((): int32 => a() + b());
		createRenderEffect(() => { value = c(); });
	});
	flush();
	assert value === 20 && aRuns === 1 && bRuns === 1;
	setX(20);
	flush();
	assert value === 30 && aRuns === 2 && bRuns === 1, "only the changed branch ran";
	setY(20);
	flush();
	assert value === 40 && aRuns === 2 && bRuns === 2;
}

test "a memo discovers new dependencies" {
	const [x, setX] = createSignal(1);
	const [y, setY] = createSignal(0);
	const c = createMemo<int32>((): int32 => {
		if (x() !== 0) { return x(); }
		return y();
	});
	assert c() === 1;
	setX(0);
	flush();
	assert c() === 0;
	setY(10);
	flush();
	assert c() === 10;
}

test "a memo equals skips a value it counts as unchanged" {
	const [x, setX] = createSignal(0);
	const a = createMemo<int32>((): int32 => x(), { equals: (prev: int32, next: int32): boolean => prev + 1 === next });
	let runs = 0;
	createRoot((d) => {
		createEffect(() => { a(); runs += 1; });
	});
	flush();
	assert a() === 0 && runs === 1;
	setX(2);
	flush();
	assert a() === 2 && runs === 2;
	setX(3);
	flush();
	assert a() === 2 && runs === 2, "3 follows 2 and is skipped";
}

test "a memo ignores equals on its first value" {
	const [x] = createSignal(1);
	const a = createMemo<int32>((): int32 => x(), { equals: (prev: int32, next: int32): boolean => true });
	assert a() === 1;
}

test "a memo with equals false wakes its subscriber on every recompute" {
	const [x, setX] = createSignal(1);
	const a = createMemo<int32>((): int32 => { x(); return 7; }, { equals: false });
	let runs = 0;
	createRoot((d) => {
		createEffect(() => { a(); runs += 1; });
	});
	flush();
	assert runs === 1;
	setX(2);
	flush();
	assert runs === 2, "ran " + runs.toString();
}

test "a lazy memo computes when first read inside another computation" {
	const [x, setX] = createSignal(0);
	let innerRuns = 0;
	let outer: Accessor<int32> | null = null;
	createRoot((d) => {
		const lazy = createMemo<int32>((): int32 => { innerRuns += 1; return x() + 1; }, { lazy: true });
		assert innerRuns === 0, "a lazy memo does not run at creation";
		const o = createMemo<int32>((): int32 => lazy() * 2);
		outer = o;
		assert innerRuns === 1;
		assert o() === 2;
	});
	setX(5);
	flush();
	assert innerRuns === 2;
	const o = outer;
	assert o !== null && o() === 12;
}

test "nested lazy memos compute when first read inside another computation" {
	const [x, setX] = createSignal(0);
	let eager: Accessor<int32> | null = null;
	createRoot((d) => {
		const lazyOuter = createMemo<int32>((): int32 => x() + 1, { lazy: true });
		const lazyInner = createMemo<int32>((): int32 => lazyOuter() * 10, { lazy: true });
		const e = createMemo<int32>((): int32 => lazyInner() + 100);
		eager = e;
		assert e() === 110;
	});
	setX(5);
	flush();
	const e = eager;
	assert e !== null && e() === 160;
}

test "a memo reports its previous value to its next compute" {
	const [x, setX] = createSignal(1);
	let seen = -1;
	let first = false;
	const a = createMemo<int32>((prev: int32 | null): int32 => {
		if (prev === null) { first = true; } else { seen = prev; }
		return x();
	});
	createRoot((d) => {
		createEffect(() => { a(); });
	});
	flush();
	assert first, "the first run saw null";
	setX(2);
	flush();
	assert seen === 1, "the second run saw the first value: " + seen.toString();
}

test "unobserved fires when the last subscriber of a memo goes away" {
	const [x] = createSignal(1);
	let fired = 0;
	const m = createMemo<int32>((): int32 => x(), { unobserved: (): void => { fired += 1; } });
	let dispose: (() => void) | null = null;
	createRoot((d) => {
		dispose = d;
		createRenderEffect(() => { m(); });
	});
	flush();
	assert fired === 0, "an observed memo stays";
	const stop = dispose;
	assert stop !== null;
	stop();
	flush();
	assert fired === 1, "fired " + fired.toString();
}
