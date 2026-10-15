import { createSignal } from "../../src/core/signal";
import { createEffect, createRenderEffect } from "../../src/core/effect";
import { createRoot } from "../../src/core/owner";
import { flush, resetErrorHalt } from "../../src/core/runtime";
import { Dispose, Cleanup } from "../../src/core/types";

test "flush(fn) batches writes into one effect run" {
	const [x, setX] = createSignal(10);
	let runs = 0;
	createRoot((d) => {
		createEffect<int32>((p: int32 | null): int32 => x(), (v: int32, p: int32 | null): Cleanup | null => { runs += 1; return null; });
	});
	flush();
	assert runs === 1;
	flush(() => {
		setX(20);
		setX(30);
		setX(40);
		assert runs === 1, "no effect inside the batch";
	});
	assert runs === 2, "one run for three writes: " + runs.toString();
}

test "an effect runs once per flush, not once per write" {
	const [x, setX] = createSignal(10);
	let runs = 0;
	createRoot((d) => {
		createEffect<int32>((p: int32 | null): int32 => x(), (v: int32, p: int32 | null): Cleanup | null => { runs += 1; return null; });
	});
	flush();
	setX(20);
	assert runs === 2;
	setX(30);
	assert runs === 3;
}

test "flush() inside an effect is a no-op" {
	const [a, setA] = createSignal(10);
	let runs = 0;
	createRoot((d) => {
		createEffect<int32>((p: int32 | null): int32 => a(), (v: int32, p: int32 | null): Cleanup | null => { runs += 1; flush(); return null; });
	});
	flush();
	assert runs === 1;
	setA(20);
	assert runs === 2, "ran " + runs.toString();
}

test "flush(fn) returns the value of fn after draining" {
	const [x, setX] = createSignal(10);
	let seen = 0;
	createRoot((d) => {
		createEffect<int32>((p: int32 | null): int32 => x(), (v: int32, p: int32 | null): Cleanup | null => { seen = v; return null; });
	});
	flush();
	const result = flush(() => {
		setX(20);
		assert seen === 10;
		return "done";
	});
	assert result === "done";
	assert seen === 20;
}

test "a nested flush(fn) drains at each level" {
	const [x, setX] = createSignal(10);
	const [y, setY] = createSignal(10);
	let runs = 0;
	let sum = 0;
	createRoot((d) => {
		createEffect<int32>(
			(p: int32 | null): int32 => x() + y(),
			(v: int32, p: int32 | null): Cleanup | null => { sum = v; runs += 1; return null; },
		);
	});
	flush();
	flush(() => {
		setX(20);
		assert runs === 1;
		const inner = flush(() => {
			setY(30);
			assert runs === 1;
			return 1;
		});
		assert inner === 1;
		assert runs === 2, "the inner flush drained";
		assert sum === 50;
	});
	assert runs === 2, "the outer drain found nothing: " + runs.toString();
}

test "an effect created inside flush(fn) first runs when the flush ends" {
	const log: string[] = [];
	flush(() => {
		createEffect<boolean>((p: boolean | null): boolean => true, (v: boolean, p: boolean | null): Cleanup | null => { log.push("effect"); return null; });
		log.push("body");
	});
	assert log.join(",") === "body,effect", "got " + log.join(",");
}

test "a render effect runs before the user effects of the same flush" {
	const [x, setX] = createSignal(0);
	const log: string[] = [];
	createRoot((d) => {
		createEffect<int32>((p: int32 | null): int32 => x(), (v: int32, p: int32 | null): Cleanup | null => { log.push("user " + v.toString()); return null; });
		createRenderEffect<int32>((p: int32 | null): int32 => x(), (v: int32, p: int32 | null): Cleanup | null => { log.push("render " + v.toString()); return null; });
	});
	flush();
	log.push("--");
	setX(1);
	assert log.join(",") === "render 0,user 0,--,render 1,user 1", "got " + log.join(",");
}

test "flush(fn) leaves the scheduler usable after an effect throws" {
	const [a, setA] = createSignal(0);
	const [c, setC] = createSignal(0);
	let seenC = -1;
	let message = "";
	createRoot((d) => {
		createEffect<int32>(
			(p: int32 | null): int32 => a(),
			(v: int32, p: int32 | null): Cleanup | null => { if (v === 1) { throw new Error("boom"); } return null; },
		);
		createEffect<int32>((p: int32 | null): int32 => c(), (v: int32, p: int32 | null): Cleanup | null => { seenC = v; return null; });
	});
	flush();
	try {
		flush(() => { setA(1); });
	} catch (e) {
		message = e.message;
	}
	assert message === "boom", "got " + message;
	setC(3);
	assert seenC !== 3, "the halted scheduler drains nothing";
	resetErrorHalt();
	setC(4);
	assert seenC === 4, "a later write drains once the halt is reset: " + seenC.toString();
}

test "flush(fn) leaves the scheduler usable after fn itself throws" {
	const [c, setC] = createSignal(0);
	let seenC = -1;
	let message = "";
	createRoot((d) => {
		createEffect<int32>((p: int32 | null): int32 => c(), (v: int32, p: int32 | null): Cleanup | null => { seenC = v; return null; });
	});
	flush();
	try {
		flush(() => { throw new Error("body"); });
	} catch (e) {
		message = e.message;
	}
	assert message === "body";
	setC(5);
	assert seenC === 5, "a later write still drains: " + seenC.toString();
}

test "a loop that keeps rescheduling itself is stopped with an error" {
	const [x, setX] = createSignal(0);
	const [y, setYy] = createSignal(0);
	let message = "";
	let stop: Dispose | null = null;
	try {
		createRoot((d) => {
			stop = d;
			createEffect<int32>((p: int32 | null): int32 => x(), (v: int32, p: int32 | null): Cleanup | null => { setYy(v + 1); return null; });
			createEffect<int32>((p: int32 | null): int32 => y(), (v: int32, p: int32 | null): Cleanup | null => { setX(v + 1); return null; });
		});
	} catch (e) {
		message = e.message;
	}
	assert message.startsWith("Potential Infinite Loop Detected"), "got " + message;
	const s = stop;
	assert s !== null;
	s();
	flush();
	let seen = -1;
	const [z, setZ] = createSignal(0);
	createRoot((d) => {
		createEffect<int32>((p: int32 | null): int32 => z(), (v: int32, p: int32 | null): Cleanup | null => { seen = v; return null; });
	});
	setZ(4);
	assert seen === 4, "the scheduler recovered: " + seen.toString();
}
