import { createSignal } from "../../src/core/signal";
import { createMemo } from "../../src/core/memo";
import { createEffect } from "../../src/core/effect";
import { createRoot } from "../../src/core/owner";
import { Cleanup } from "../../src/core/types";
import { flush } from "../../src/core/runtime";

test "a memo reading a signal and a memo of that signal runs once per write" {
	let runs = 0;
	createRoot((d) => {
		const [x, setX] = createSignal(2, { ownedWrite: true });
		const a = createMemo<int32>((): int32 => x() - 1);
		const b = createMemo<int32>((): int32 => x() + a());
		const c = createMemo<string>((): string => { runs += 1; return "c: " + b().toString(); });
		assert c() === "c: 3";
		assert runs === 1, "ran once on creation";
		runs = 0;
		setX(4);
		flush();
		assert runs === 1, "ran once for the write, not once per path: " + runs.toString();
		assert c() === "c: 7";
		d();
	});
}

test "a diamond runs its join once per write" {
	let runs = 0;
	createRoot((d) => {
		const [x, setX] = createSignal("a", { ownedWrite: true });
		const a = createMemo<string>((): string => x());
		const b = createMemo<string>((): string => x());
		const c = createMemo<string>((): string => { runs += 1; return a() + " " + b(); });
		assert c() === "a a";
		setX("aa");
		flush();
		assert c() === "aa aa";
		assert runs === 2, "created once, rewritten once: " + runs.toString();
		d();
	});
}

test "a diamond with a tail runs the tail once per write" {
	let runs = 0;
	createRoot((d) => {
		const [x, setX] = createSignal("a", { ownedWrite: true });
		const a = createMemo<string>((): string => x());
		const b = createMemo<string>((): string => x());
		const c = createMemo<string>((): string => a() + " " + b());
		const tail = createMemo<string>((): string => { runs += 1; return c(); });
		assert tail() === "a a";
		setX("aa");
		flush();
		assert tail() === "aa aa";
		assert runs === 2, "tail ran " + runs.toString();
		d();
	});
}

test "a memo that settles on the same value does not wake its subscriber" {
	let runs = 0;
	createRoot((d) => {
		const [x, setX] = createSignal("a", { ownedWrite: true });
		const a = createMemo<string>((): string => { x(); return "foo"; });
		const b = createMemo<string>((): string => { runs += 1; return a(); });
		assert b() === "foo";
		setX("aa");
		flush();
		assert b() === "foo";
		assert runs === 1, "the subscriber ran " + runs.toString();
		d();
	});
}

test "a jagged diamond with two tails runs every node once per write" {
	let dRuns = 0;
	let eRuns = 0;
	let fRuns = 0;
	createRoot((dispose) => {
		const [x, setX] = createSignal("a", { ownedWrite: true });
		const a = createMemo<string>((): string => x());
		const b = createMemo<string>((): string => x());
		const c = createMemo<string>((): string => b());
		const d = createMemo<string>((): string => { dRuns += 1; return a() + " " + c(); });
		const e = createMemo<string>((): string => { eRuns += 1; return d(); });
		const f = createMemo<string>((): string => { fRuns += 1; return d(); });
		assert e() === "a a" && f() === "a a";
		setX("b");
		flush();
		assert e() === "b b" && f() === "b b" && d() === "b b";
		assert dRuns === 2 && eRuns === 2 && fRuns === 2, "d e f ran " + dRuns.toString() + " " + eRuns.toString() + " " + fRuns.toString();
		setX("c");
		flush();
		assert e() === "c c" && f() === "c c";
		assert dRuns === 3 && eRuns === 3 && fRuns === 3, "d e f ran " + dRuns.toString() + " " + eRuns.toString() + " " + fRuns.toString();
		dispose();
	});
}

test "a subscriber updates when one of its dependencies keeps its value" {
	let runs = 0;
	createRoot((d) => {
		const [x, setX] = createSignal("a", { ownedWrite: true });
		const a = createMemo<string>((): string => x());
		const b = createMemo<string>((): string => { x(); return "c"; });
		const c = createMemo<string>((): string => { runs += 1; return a() + " " + b(); });
		assert c() === "a c";
		setX("aa");
		flush();
		assert c() === "aa c";
		assert runs === 2;
		d();
	});
}

test "a subscriber updates when two of three dependencies keep their value" {
	let runs = 0;
	createRoot((d) => {
		const [x, setX] = createSignal("a", { ownedWrite: true });
		const b = createMemo<string>((): string => x());
		const c = createMemo<string>((): string => { x(); return "c"; });
		const dd = createMemo<string>((): string => { x(); return "d"; });
		const e = createMemo<string>((): string => { runs += 1; return b() + " " + c() + " " + dd(); });
		assert e() === "a c d";
		setX("aa");
		flush();
		assert e() === "aa c d";
		assert runs === 2;
		d();
	});
}

test "memos of one signal run in creation order and their join after them" {
	let seq = "";
	const [a1, setA1] = createSignal(false);
	const b1 = createMemo<int32>((): int32 => { a1(); seq += "b1"; return 0; }, { equals: false });
	const b2 = createMemo<int32>((): int32 => { a1(); seq += "b2"; return 0; }, { equals: false });
	const c1 = createMemo<int32>((): int32 => { b1(); b2(); seq += "c1"; return 0; }, { equals: false });
	seq = "";
	setA1(true);
	flush();
	assert seq === "b1b2c1", "got " + seq;
}

test "five memos of one signal wake their join once" {
	let runs = 0;
	const [d, setD] = createSignal(0);
	const f1 = createMemo<int32>((): int32 => d());
	const f2 = createMemo<int32>((): int32 => d());
	const f3 = createMemo<int32>((): int32 => d());
	const f4 = createMemo<int32>((): int32 => d());
	const f5 = createMemo<int32>((): int32 => d());
	const g = createMemo<int32>((): int32 => { runs += 1; return f1() + f2() + f3() + f4() + f5(); });
	runs = 0;
	setD(1);
	flush();
	assert runs === 1, "the join ran " + runs.toString();
}

test "an exponential convergence wakes the last node once" {
	let runs = 0;
	const [d, setD] = createSignal(0);
	const f1 = createMemo<int32>((): int32 => d());
	const f2 = createMemo<int32>((): int32 => d());
	const f3 = createMemo<int32>((): int32 => d());
	const g1 = createMemo<int32>((): int32 => f1() + f2() + f3());
	const g2 = createMemo<int32>((): int32 => f1() + f2() + f3());
	const g3 = createMemo<int32>((): int32 => f1() + f2() + f3());
	const h = createMemo<int32>((): int32 => { runs += 1; return g1() + g2() + g3(); });
	runs = 0;
	setD(1);
	flush();
	assert runs === 1, "h ran " + runs.toString();
}

test "an equal write does not run downstream, a changed one does" {
	let order = "";
	const [s1, set] = createSignal(1, { equals: false });
	const t1 = createMemo<int32>((): int32 => { order += "t1"; return s1(); });
	const t2 = createMemo<int32>((): int32 => { order += "c1"; t1(); return 0; });
	assert order === "t1c1", "got " + order;
	order = "";
	set(1);
	flush();
	assert order === "t1", "an unchanged memo stops the wave: " + order;
	order = "";
	set(2);
	flush();
	assert order === "t1c1", "got " + order;
}

test "dependees of a changed signal run in creation order" {
	let order = "";
	const [s1, set] = createSignal(0);
	const t1 = createMemo<boolean>((): boolean => { order += "t1"; return s1() === 0; });
	const t2 = createMemo<int32>((): int32 => { order += "c1"; return s1(); });
	const t3 = createMemo<boolean>((): boolean => { order += "c2"; return t1(); });
	assert order === "t1c1c2", "got " + order;
	order = "";
	set(1);
	flush();
	assert order === "t1c1c2", "got " + order;
}

test "a stale chain of four runs top to bottom once" {
	let order = "";
	const [s1, set] = createSignal(1);
	const t1 = createMemo<int32>((): int32 => { order += "t1"; return s1(); });
	const c1 = createMemo<int32>((): int32 => { order += "c1"; return t1(); });
	const c2 = createMemo<int32>((): int32 => { order += "c2"; return c1(); });
	const c3 = createMemo<int32>((): int32 => { order += "c3"; return c2(); });
	order = "";
	set(2);
	flush();
	assert order === "t1c1c2c3", "got " + order;
}

test "stale memos run before the dependee when the trackers keep their value" {
	let order = "";
	const [s1, set] = createSignal(1, { equals: false });
	const t1 = createMemo<boolean>((): boolean => { order += "t1"; return s1() > 2; });
	const t2 = createMemo<boolean>((): boolean => { order += "t2"; return s1() > 2; });
	const c1 = createMemo<int32>((): int32 => { order += "c1"; s1(); return 0; }, { equals: false });
	const c2 = createMemo<int32>((): int32 => { order += "c2"; t1(); t2(); c1(); return 0; });
	order = "";
	set(1);
	flush();
	assert order === "t1t2c1c2", "got " + order;
	order = "";
	set(3);
	flush();
	assert order === "t1t2c1c2", "got " + order;
}

test "a join with a stale and an unchanged branch runs once per write" {
	let count = 0;
	const [s1, set1] = createSignal(1);
	const [s2, set2] = createSignal(false);
	const t1 = createMemo<boolean>((): boolean => s1() > 0);
	const t2 = createMemo<boolean>((): boolean => s1() > 0);
	const c1 = createMemo<int32>((): int32 => s1());
	const t3 = createMemo<boolean>((): boolean => { const a = s1(); const b = s2(); return a > 0 && b; });
	const c3 = createMemo<int32>((): int32 => { t1(); t2(); c1(); t3(); count += 1; return count; });
	set2(true);
	flush();
	assert count === 2, "after the first write: " + count.toString();
	set1(2);
	flush();
	assert count === 3, "after the second write: " + count.toString();
}

test "a memo follows the branch its condition picks" {
	createRoot((d) => {
		const [i, setI] = createSignal(true, { ownedWrite: true });
		const [t, setT] = createSignal(1, { ownedWrite: true });
		const [e, setE] = createSignal(2, { ownedWrite: true });
		let evals = 0;
		const f = createMemo<int32>((): int32 => { evals += 1; return i() ? t() : e(); });
		assert f() === 1;
		evals = 0;
		setT(5);
		flush();
		assert f() === 5 && evals === 1, "the active branch updates";
		evals = 0;
		setE(9);
		flush();
		assert f() === 5 && evals === 0, "the inactive branch does not";
		setI(false);
		flush();
		assert f() === 9;
		evals = 0;
		setT(7);
		flush();
		assert evals === 0, "the dropped branch is unsubscribed";
		setE(4);
		flush();
		assert f() === 4 && evals === 1, "the new branch is subscribed";
		d();
	});
}

test "a dependency discovered mid-run is brought up to date before its reader" {
	createRoot((dispose) => {
		let order = "";
		let readE: (() => int32) | null = null;
		const [a, setA] = createSignal(0, { ownedWrite: true });
		const b = createMemo<int32>((): int32 => { order += "b"; return a() + 1; });
		const c = createMemo<int32>((): int32 => {
			order += "c";
			const check = b();
			if (check !== 0) { return check; }
			const e = readE;
			if (e === null) { return -1; }
			return e();
		});
		const d = createMemo<int32>((): int32 => a());
		const e = createMemo<int32>((): int32 => { order += "d"; return d() + 10; });
		readE = e;
		assert order === "bcd", "got " + order;
		order = "";
		setA(-1);
		flush();
		assert order === "bcd", "got " + order;
		assert c() === 9, "c is " + c().toString();
		order = "";
		setA(0);
		flush();
		assert order === "bdc", "got " + order;
		assert c() === 1;
		dispose();
	});
}

test "a write that lands under a memo's own run schedules it again" {
	createRoot((d) => {
		const [s, setS] = createSignal(0, { ownedWrite: true });
		const [t, setT] = createSignal("later");
		let runs = 0;
		const c = createMemo<int32>((): int32 => {
			runs += 1;
			const v = s();
			t();
			if (v === 0) { setS(1); }
			return v;
		});
		flush();
		assert runs === 2, "ran " + runs.toString();
		assert c() === 1;
		d();
	});
}

test "a same-value write under a memo's own run does not schedule it again" {
	createRoot((d) => {
		const [s, setS] = createSignal(0, { ownedWrite: true });
		let runs = 0;
		const c = createMemo<int32>((): int32 => {
			runs += 1;
			const v = s();
			setS(v);
			return v;
		});
		flush();
		assert runs === 1, "ran " + runs.toString();
		assert c() === 0;
		d();
	});
}

test "an effect reads the value a memo chain settled on" {
	let seen = -1;
	createRoot((d) => {
		const [x, setX] = createSignal(1, { ownedWrite: true });
		const a = createMemo<int32>((): int32 => x() * 2);
		const b = createMemo<int32>((): int32 => a() + 1);
		createEffect<int32>((p: int32 | null): int32 => b(), (v: int32, p: int32 | null): Cleanup | null => { seen = v; return null; });
		flush();
		assert seen === 3, "got " + seen.toString();
		setX(5);
		flush();
		assert seen === 11, "got " + seen.toString();
		d();
	});
}
