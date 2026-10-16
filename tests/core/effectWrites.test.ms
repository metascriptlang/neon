import { createSignal } from "../../src/core/signal";
import { createMemo } from "../../src/core/memo";
import { createEffect, createRenderEffect } from "../../src/core/effect";
import { createRoot } from "../../src/core/owner";
import { resetErrorHalt } from "../../src/core/runtime";
import { Cleanup } from "../../src/core/types";

test "an effect reads back the settled value of its own write" {
	const reads: number[] = [];
	createRoot((d) => {
		const [a, setA] = createSignal(0);
		const [b, setB] = createSignal(0);
		createEffect<int32>(
			(p: int32 | null): int32 => a(),
			(v: int32, p: int32 | null): Cleanup | null => { setB(1); reads.push(b()); return null; },
		);
		return 0;
	});
	assert reads.join(",") === "0", "got " + reads.join(",");
}

test "a render effect reads back the settled value of its own write" {
	const reads: number[] = [];
	const [a, setA] = createSignal(0);
	const [b, setB] = createSignal(0);
	createRoot((d) => {
		createRenderEffect<int32>(
			(p: int32 | null): int32 => a(),
			(v: int32, p: int32 | null): Cleanup | null => {
				if (v > 0) { setB(1); reads.push(b()); }
				return null;
			},
		);
		return 0;
	});
	setA(1);
	assert reads.join(",") === "0", "got " + reads.join(",");
}

test "a render effect's first apply runs under its creator, so a write there is refused" {
	const [b, setB] = createSignal(0);
	let message = "";
	try {
		createRoot((d) => {
			createRenderEffect<int32>(
				(p: int32 | null): int32 => 0,
				(v: int32, p: int32 | null): Cleanup | null => { setB(1); return null; },
			);
			return 0;
		});
	} catch (e) { message = e.message; }
	resetErrorHalt();
	assert message.indexOf("REACTIVE_WRITE_IN_OWNED_SCOPE") >= 0, "got [" + message + "]";
	assert b() === 0, "the refused write did not land";
}

test "an effect write reaches the dependents in the same flush" {
	const reads: number[] = [];
	const values: number[] = [];
	createRoot((d) => {
		const [trigger, setTrigger] = createSignal(0);
		const [count, setCount] = createSignal(0);
		createEffect<int32>(
			(p: int32 | null): int32 => count(),
			(v: int32, p: int32 | null): Cleanup | null => { values.push(v); return null; },
		);
		createEffect<int32>(
			(p: int32 | null): int32 => trigger(),
			(v: int32, p: int32 | null): Cleanup | null => {
				reads.push(count());
				setCount(1);
				reads.push(count());
				return null;
			},
		);
		return 0;
	});
	assert reads.join(",") === "0,0", "reads " + reads.join(",");
	assert values.join(",") === "0,1", "values " + values.join(",");
}

test "functional setters in an effect compose against the staged value" {
	const values: number[] = [];
	let readBack = -1;
	createRoot((d) => {
		const [trigger, setTrigger] = createSignal(0);
		const [count, setCount] = createSignal(0);
		createEffect<int32>(
			(p: int32 | null): int32 => count(),
			(v: int32, p: int32 | null): Cleanup | null => { values.push(v); return null; },
		);
		createEffect<int32>(
			(p: int32 | null): int32 => trigger(),
			(v: int32, p: int32 | null): Cleanup | null => {
				setCount((n: int32): int32 => n + 1);
				setCount((n: int32): int32 => n + 1);
				readBack = count();
				return null;
			},
		);
		return 0;
	});
	assert readBack === 0, "reads stay settled: " + readBack.toString();
	assert values.join(",") === "0,2", "the second update composed on the first: " + values.join(",");
}

test "a memo derived from an effect write reads at its settled value" {
	const reads: number[] = [];
	const doubles: number[] = [];
	createRoot((d) => {
		const [trigger, setTrigger] = createSignal(0);
		const [count, setCount] = createSignal(0);
		const doubled = createMemo<int32>((): int32 => count() * 2);
		createEffect<int32>(
			(p: int32 | null): int32 => doubled(),
			(v: int32, p: int32 | null): Cleanup | null => { doubles.push(v); return null; },
		);
		createEffect<int32>(
			(p: int32 | null): int32 => trigger(),
			(v: int32, p: int32 | null): Cleanup | null => { setCount(1); reads.push(doubled()); return null; },
		);
		return 0;
	});
	assert reads.join(",") === "0", "reads " + reads.join(",");
	assert doubles.join(",") === "0,2", "doubles " + doubles.join(",");
}

test "a later effect does not observe an earlier effect's unsettled write in the same phase" {
	const reads: number[] = [];
	createRoot((d) => {
		const [a, setA] = createSignal(0);
		const [x, setX] = createSignal(0);
		createEffect<int32>(
			(p: int32 | null): int32 => a(),
			(v: int32, p: int32 | null): Cleanup | null => { setX(1); return null; },
		);
		createEffect<boolean>(
			(p: boolean | null): boolean => true,
			(v: boolean, p: boolean | null): Cleanup | null => { reads.push(x()); return null; },
		);
		return 0;
	});
	assert reads.join(",") === "0", "got " + reads.join(",");
}
