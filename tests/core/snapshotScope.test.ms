// Reference: solid-next 3b6f839ec packages/signals/tests/snapshot.test.ts, strict-read-snapshot-scope-3675.test.ts.
import { Computation, Cleanup } from "../../src/core/types";
import { createSignal, untrack, Accessor, accessor } from "../../src/core/signal";
import { createMemo, createAsyncMemo, refresh } from "../../src/core/memo";
import { onSettled } from "../../src/core/effect";
import { createRoot, runWithOwner } from "../../src/core/owner";
import { flush, getOwner, isPending } from "../../src/core/runtime";
import { createErrorBoundary, createLoadingBoundary } from "../../src/core/boundary";
import { createStore } from "../../src/core/store";
import { setSnapshotCapture, markSnapshotScope, releaseSnapshotScope, clearSnapshots } from "../../src/core/snapshotScope";
import { Gate, gated, release } from "./asyncClock";

const unset: Accessor<int32> = accessor((): int32 => -1);

function scopeHere(): Computation {
	const owner = getOwner() as Computation;
	markSnapshotScope(owner);
	return owner;
}

function done(): void {
	clearSnapshots();
	flush();
}

test "a signal created during capture reads its value" {
	setSnapshotCapture(true);
	const [x, setX] = createSignal<int32>(42);
	assert x() === 42, "got " + x().toString();
	done();
}

test "a signal created outside capture is written live" {
	const [x, setX] = createSignal<int32>(1);
	setX(2);
	flush();
	assert x() === 2, "got " + x().toString();
}

test "a snapshot of null is served as null to a scoped reader" {
	let read: Accessor<int32 | null> = accessor((): int32 | null => -1);
	let scope: Computation | null = null;
	const [x, setX] = createSignal<int32 | null>(null);
	createRoot((d) => {
		setSnapshotCapture(true);
		scope = scopeHere();
		read = createMemo<int32 | null>((p: int32 | null): int32 | null => x());
		return 0;
	});
	setX(5);
	flush();
	assert read() === null, "held";
	releaseSnapshotScope(scope as Computation);
	flush();
	assert read() === 5, "released";
	done();
}

test "a memo created during capture reads its first evaluation" {
	createRoot((d) => {
		const [x, setX] = createSignal<int32>(10);
		setSnapshotCapture(true);
		const doubled = createMemo<int32>((p: int32 | null): int32 => x() * 2);
		assert doubled() === 20, "got " + doubled().toString();
		return 0;
	});
	done();
}

test "a scoped computation reads the snapshot instead of the written value" {
	let derived = unset;
	let scope: Computation | null = null;
	const [x, setX] = createSignal<int32>(1);
	createRoot((d) => {
		setSnapshotCapture(true);
		scope = scopeHere();
		derived = createMemo<int32>((p: int32 | null): int32 => x() * 10);
		return 0;
	});
	assert derived() === 10, "first";
	setX(2);
	flush();
	assert derived() === 10, "held: " + derived().toString();
	releaseSnapshotScope(scope as Computation);
	flush();
	assert derived() === 20, "released: " + derived().toString();
	done();
}

test "a signal created before capture keeps its pre-write value from the first write during capture" {
	let derived = unset;
	let scope: Computation | null = null;
	createRoot((d) => {
		const [x, setX] = createSignal<int32>(1);
		setSnapshotCapture(true);
		scope = scopeHere();
		derived = createMemo<int32>((p: int32 | null): int32 => x() * 10);
		onSettled((): Cleanup | null => { setX(5); return null; });
		return 0;
	});
	flush();
	assert derived() === 10, "held: " + derived().toString();
	releaseSnapshotScope(scope as Computation);
	flush();
	assert derived() === 50, "released: " + derived().toString();
	done();
}

test "a scoped reader created after the write reads the pre-write value until release, and an unscoped read sees it live" {
	let late = unset;
	let scope: Computation | null = null;
	const [x, setX] = createSignal<int32>(1);
	createRoot((d) => {
		setSnapshotCapture(true);
		scope = scopeHere();
		return 0;
	});
	setX(5);
	flush();
	runWithOwner(scope, (): int32 => {
		late = createMemo<int32>((p: int32 | null): int32 => x() * 10);
		return 0;
	});
	assert late() === 10, "the late reader holds: " + late().toString();
	assert x() === 5, "an unscoped read is live: " + x().toString();
	releaseSnapshotScope(scope as Computation);
	flush();
	assert late() === 50, "released: " + late().toString();
	done();
}

test "several writes during capture keep the value from before the first, and release shows the last" {
	let derived = unset;
	let runs = 0;
	let scope: Computation | null = null;
	const [x, setX] = createSignal<int32>(1);
	createRoot((d) => {
		setSnapshotCapture(true);
		scope = scopeHere();
		derived = createMemo<int32>((p: int32 | null): int32 => { runs += 1; return x() * 10; });
		return 0;
	});
	setX(5);
	flush();
	setX(7);
	flush();
	assert derived() === 10 && runs === 1, "held: " + derived().toString() + " after " + runs.toString() + " runs";
	releaseSnapshotScope(scope as Computation);
	flush();
	assert derived() === 70 && runs === 2, "released: " + derived().toString() + " after " + runs.toString() + " runs";
	done();
}

test "a reader outside the scope sees a write during capture live" {
	let outside = unset;
	let inside = unset;
	let scope: Computation | null = null;
	const [x, setX] = createSignal<int32>(1);
	createRoot((d) => {
		outside = createMemo<int32>((p: int32 | null): int32 => x() + 100);
		setSnapshotCapture(true);
		createRoot((d2) => {
			scope = scopeHere();
			inside = createMemo<int32>((p: int32 | null): int32 => x() + 200);
			return 0;
		});
		return 0;
	});
	setX(5);
	flush();
	assert outside() === 105, "outside: " + outside().toString();
	assert inside() === 201, "inside: " + inside().toString();
	releaseSnapshotScope(scope as Computation);
	flush();
	assert inside() === 205, "released: " + inside().toString();
	done();
}

test "a node created under no owner during capture is outside every scope" {
	let orphan = unset;
	const [x, setX] = createSignal<int32>(1);
	createRoot((d) => {
		setSnapshotCapture(true);
		scopeHere();
		runWithOwner(null, (): int32 => {
			orphan = createMemo<int32>((p: int32 | null): int32 => x() * 3);
			return 0;
		});
		return 0;
	});
	setX(2);
	flush();
	assert orphan() === 6, "live: " + orphan().toString();
	done();
}

test "a memo created outside the scope during capture is held for scoped readers by its first value" {
	let shown = unset;
	let scope: Computation | null = null;
	const [x, setX] = createSignal<int32>(1);
	createRoot((d) => {
		setSnapshotCapture(true);
		scope = scopeHere();
		const orphan = runWithOwner(null, (): Accessor<int32> => createMemo<int32>((p: int32 | null): int32 => x() * 3));
		shown = createMemo<int32>((p: int32 | null): int32 => orphan());
		return 0;
	});
	setX(2);
	flush();
	assert shown() === 3, "held: " + shown().toString();
	releaseSnapshotScope(scope as Computation);
	flush();
	assert shown() === 6, "released: " + shown().toString();
	done();
}

test "a held reader checked through another source during capture still reruns at release" {
	let held = unset;
	let scope: Computation | null = null;
	const [x, setX] = createSignal<int32>(1);
	const [z, setZ] = createSignal<int32>(1);
	createRoot((d) => {
		setSnapshotCapture(true);
		scope = scopeHere();
		const zero = runWithOwner(null, (): Accessor<int32> => createMemo<int32>((p: int32 | null): int32 => z() * 0));
		held = createMemo<int32>((p: int32 | null): int32 => x() + zero());
		return 0;
	});
	setX(5);
	setZ(2);
	runWithOwner(scope, (): int32 => {
		createMemo<int32>((p: int32 | null): int32 => held());
		return 0;
	});
	flush();
	assert held() === 1, "held: " + held().toString();
	releaseSnapshotScope(scope as Computation);
	flush();
	assert held() === 5, "released: " + held().toString();
	done();
}

test "nested snapshot scopes release independently" {
	let outer = unset;
	let inner = unset;
	let rootScope: Computation | null = null;
	let innerScope: Computation | null = null;
	const [x, setX] = createSignal<int32>(1);
	createRoot((d) => {
		setSnapshotCapture(true);
		rootScope = scopeHere();
		outer = createMemo<int32>((p: int32 | null): int32 => x() + 100);
		createRoot((d2) => {
			innerScope = scopeHere();
			inner = createMemo<int32>((p: int32 | null): int32 => x() + 200);
			return 0;
		});
		return 0;
	});
	setX(5);
	flush();
	assert outer() === 101 && inner() === 201, "both held";
	releaseSnapshotScope(rootScope as Computation);
	flush();
	assert outer() === 105, "the root released: " + outer().toString();
	assert inner() === 201, "the inner scope still holds: " + inner().toString();
	releaseSnapshotScope(innerScope as Computation);
	flush();
	assert inner() === 205, "the inner released: " + inner().toString();
	done();
}

test "an unflushed write does not reach a scoped reader" {
	let upper: Accessor<string> = accessor((): string => "");
	let scope: Computation | null = null;
	const [x, setX] = createSignal("hello");
	createRoot((d) => {
		setSnapshotCapture(true);
		scope = scopeHere();
		upper = createMemo<string>((p: string | null): string => x().toUpperCase());
		return 0;
	});
	setX("world");
	assert upper() === "HELLO", "held: " + upper();
	releaseSnapshotScope(scope as Computation);
	flush();
	assert upper() === "WORLD", "released: " + upper();
	done();
}

test "a release schedules the stale readers and does not run them itself" {
	let derived = unset;
	let runs = 0;
	let scope: Computation | null = null;
	const [x, setX] = createSignal<int32>(1);
	createRoot((d) => {
		setSnapshotCapture(true);
		scope = scopeHere();
		derived = createMemo<int32>((p: int32 | null): int32 => { runs += 1; return x() * 2; });
		return 0;
	});
	setX(10);
	releaseSnapshotScope(scope as Computation);
	assert runs === 1, "not run by the release: " + runs.toString();
	flush();
	assert derived() === 20 && runs === 2, "run by the flush: " + derived().toString() + " after " + runs.toString();
	done();
}

test "releasing a released scope again does nothing" {
	let derived = unset;
	const [x, setX] = createSignal<int32>(1);
	createRoot((d) => {
		setSnapshotCapture(true);
		const scope = scopeHere();
		derived = createMemo<int32>((p: int32 | null): int32 => x());
		releaseSnapshotScope(scope);
		releaseSnapshotScope(scope);
		return 0;
	});
	flush();
	assert derived() === 1, "got " + derived().toString();
	done();
}

test "a memo created under a released scope while capture is still on reads live" {
	let late = unset;
	let scope: Computation | null = null;
	const [x, setX] = createSignal<int32>(1);
	createRoot((d) => {
		setSnapshotCapture(true);
		scope = scopeHere();
		return 0;
	});
	releaseSnapshotScope(scope as Computation);
	runWithOwner(scope, (): int32 => {
		late = createMemo<int32>((p: int32 | null): int32 => x() * 10);
		return 0;
	});
	setX(4);
	flush();
	assert late() === 40, "not in a scope: " + late().toString();
	done();
}

test "clearing the snapshots lets every reader see the written value" {
	let derived = unset;
	let scope: Computation | null = null;
	const [x, setX] = createSignal<int32>(1);
	createRoot((d) => {
		setSnapshotCapture(true);
		scope = scopeHere();
		derived = createMemo<int32>((p: int32 | null): int32 => x() * 3);
		return 0;
	});
	setX(10);
	releaseSnapshotScope(scope as Computation);
	clearSnapshots();
	flush();
	assert derived() === 30, "got " + derived().toString();
}

test "clearing the snapshots turns capture off, so a later scoped reader is live" {
	setSnapshotCapture(true);
	clearSnapshots();
	let derived = unset;
	const [x, setX] = createSignal<int32>(1);
	createRoot((d) => {
		scopeHere();
		derived = createMemo<int32>((p: int32 | null): int32 => x());
		return 0;
	});
	setX(2);
	flush();
	assert derived() === 2, "got " + derived().toString();
}

test "a write during capture does not rerun a scoped subscriber until release" {
	let derived = unset;
	let runs = 0;
	let scope: Computation | null = null;
	const [x, setX] = createSignal<int32>(1);
	createRoot((d) => {
		setSnapshotCapture(true);
		scope = scopeHere();
		derived = createMemo<int32>((p: int32 | null): int32 => { runs += 1; return x() + 1; });
		return 0;
	});
	setX(100);
	flush();
	assert runs === 1 && derived() === 2, "held: " + derived().toString() + " after " + runs.toString();
	releaseSnapshotScope(scope as Computation);
	flush();
	assert runs === 2 && derived() === 101, "released: " + derived().toString() + " after " + runs.toString();
	done();
}

test "a write and a write back during capture rerun an existing reader once at release and nothing below it" {
	let derived = unset;
	let below = unset;
	let runs = 0;
	let belowRuns = 0;
	let scope: Computation | null = null;
	const [x, setX] = createSignal<int32>(1);
	createRoot((d) => {
		setSnapshotCapture(true);
		scope = scopeHere();
		derived = createMemo<int32>((p: int32 | null): int32 => { runs += 1; return x() * 10; });
		below = createMemo<int32>((p: int32 | null): int32 => { belowRuns += 1; return derived() + 1; });
		return 0;
	});
	setX(5);
	flush();
	setX(1);
	flush();
	assert derived() === 10 && runs === 1, "held";
	releaseSnapshotScope(scope as Computation);
	flush();
	assert derived() === 10 && runs === 2, "the reader reruns once on the same value: " + runs.toString();
	assert below() === 11 && belowRuns === 1, "its reader does not: " + belowRuns.toString();
	done();
}

test "a reader created after a write and a write back is not stale and does not rerun at release" {
	let late = unset;
	let runs = 0;
	let scope: Computation | null = null;
	const [x, setX] = createSignal<int32>(1);
	createRoot((d) => {
		setSnapshotCapture(true);
		scope = scopeHere();
		return 0;
	});
	setX(5);
	setX(1);
	flush();
	runWithOwner(scope, (): int32 => {
		late = createMemo<int32>((p: int32 | null): int32 => { runs += 1; return x() * 10; });
		return 0;
	});
	releaseSnapshotScope(scope as Computation);
	flush();
	assert late() === 10 && runs === 1, "ran " + runs.toString() + " times";
	done();
}

test "an error boundary catches under capture" {
	let result: Accessor<string> = accessor((): string => "");
	let scope: Computation | null = null;
	createRoot((d) => {
		setSnapshotCapture(true);
		scope = scopeHere();
		result = createErrorBoundary<string>(
			(): string => { throw new Error("test error"); },
			(err: Accessor<Error>, reset: () => void): string => "fallback: " + err().message,
		);
		return 0;
	});
	flush();
	assert result() === "fallback: test error", "got " + result();
	releaseSnapshotScope(scope as Computation);
	done();
}

test "an error boundary whose content succeeds under capture shows it" {
	let result: Accessor<string> = accessor((): string => "");
	let scope: Computation | null = null;
	createRoot((d) => {
		setSnapshotCapture(true);
		scope = scopeHere();
		result = createErrorBoundary<string>(
			(): string => "success",
			(err: Accessor<Error>, reset: () => void): string => "fallback: " + err().message,
		);
		return 0;
	});
	flush();
	assert result() === "success", "got " + result();
	releaseSnapshotScope(scope as Computation);
	done();
}

test "a loading boundary whose content lands during capture shows it to scoped readers" {
	const gate = new Gate();
	let shown: Accessor<string> = accessor((): string => "");
	let scope: Computation | null = null;
	createRoot((d) => {
		setSnapshotCapture(true);
		scope = scopeHere();
		const answer = createAsyncMemo<string>((p: string | null): Promise<string> => gated(gate, "content"));
		const result = createLoadingBoundary<string>((): string => answer(), (): string => "fallback");
		shown = createMemo<string>((p: string | null): string => result());
		return 0;
	});
	flush();
	assert shown() === "fallback", "first: " + shown();
	await release(gate);
	assert shown() === "content", "the boundary is structure, not a held source: " + shown();
	releaseSnapshotScope(scope as Computation);
	done();
}

test "a store field written during capture keeps its value for a scoped reader" {
	let name: Accessor<string> = accessor((): string => "");
	let scope: Computation | null = null;
	const [store, setStore] = createStore({ name: "Alice", age: 30 });
	createRoot((d) => {
		setSnapshotCapture(true);
		scope = scopeHere();
		name = createMemo<string>((p: string | null): string => store.name);
		return 0;
	});
	assert name() === "Alice", "first: " + name();
	setStore((s) => { s.name = "Bob"; });
	flush();
	assert name() === "Alice", "held: " + name();
	releaseSnapshotScope(scope as Computation);
	flush();
	assert name() === "Bob", "released: " + name();
	done();
}

test "an unwritten store field reads its value through a scope" {
	let age = unset;
	let scope: Computation | null = null;
	const [store, setStore] = createStore({ name: "Alice", age: 30 as int32 });
	createRoot((d) => {
		setSnapshotCapture(true);
		scope = scopeHere();
		age = createMemo<int32>((p: int32 | null): int32 => store.age);
		return 0;
	});
	releaseSnapshotScope(scope as Computation);
	flush();
	assert age() === 30, "got " + age().toString();
	done();
}

interface Row { label: string; }

test "a structural write to a store array during capture is held for scoped readers" {
	let labels: Accessor<string> = accessor((): string => "");
	let scope: Computation | null = null;
	let runs = 0;
	createRoot((d) => {
		setSnapshotCapture(true);
		scope = scopeHere();
		const [state, setState] = createStore<{ items: Row[] }>({ items: [{ label: "remove" }, { label: "keep" }] });
		labels = createMemo<string>((p: string | null): string => {
			runs += 1;
			const out: string[] = [];
			for (let i = 0; i < state.items.length; i += 1) { out.push(state.items[i].label); }
			return out.join(",");
		});
		onSettled((): Cleanup | null => {
			setState((s) => { s.items.splice(0, 1); });
			return null;
		});
		return 0;
	});
	assert labels() === "remove,keep", "first: " + labels();
	flush();
	assert labels() === "remove,keep" && runs === 1, "held: " + labels() + " after " + runs.toString();
	releaseSnapshotScope(scope as Computation);
	flush();
	assert labels() === "keep" && runs === 2, "released: " + labels() + " after " + runs.toString();
	done();
}

test "an async memo is not snapshotted: its answer landing during capture reaches scoped readers and stays after release" {
	const gate = new Gate();
	let value = unset;
	let scope: Computation | null = null;
	createRoot((d) => {
		setSnapshotCapture(true);
		scope = scopeHere();
		const answer = createAsyncMemo<int32>((p: int32 | null): Promise<int32> => gated(gate, 42 as int32));
		value = createMemo<int32>((p: int32 | null): int32 => answer());
		return 0;
	});
	flush();
	await release(gate);
	assert value() === 42, "revealed under capture: " + value().toString();
	releaseSnapshotScope(scope as Computation);
	flush();
	assert value() === 42, "released: " + value().toString();
	done();
}

test "an untracked isPending in a scoped memo during capture does not rerun it when its source reloads" {
	const gate = new Gate();
	let runs = 0;
	let scope: Computation | null = null;
	let answer = unset;
	createRoot((d) => {
		answer = createAsyncMemo<int32>((p: int32 | null): Promise<int32> => gated(gate, 7 as int32));
		return 0;
	});
	flush();
	await release(gate);
	createRoot((d) => {
		setSnapshotCapture(true);
		scope = scopeHere();
		createMemo<boolean>((p: boolean | null): boolean => {
			runs += 1;
			return untrack((): boolean => isPending((): int32 => answer()));
		});
		return 0;
	});
	gate.open = false;
	refresh(answer);
	flush();
	assert runs === 1, "a probe made untracked is a snapshot: ran " + runs.toString() + " times";
	releaseSnapshotScope(scope as Computation);
	gate.open = true;
	done();
}

test "a labelled untracked read served from the snapshot still fails in a debug build" {
	const [count, setCount] = createSignal<int32>(1);
	setSnapshotCapture(true);
	setCount(2);
	let served: int32 = -1;
	let message = "";
	createRoot((d) => {
		scopeHere();
		const read = createMemo<int32>((p: int32 | null): int32 => {
			served = untrack((): int32 => count(), "<Child>");
			return served;
		});
		try {
			read();
		} catch (e) {
			message = e.message;
		}
		return 0;
	});
	when (debug) {
		assert message.indexOf("[STRICT_READ_UNTRACKED]") === 0 && message.indexOf("<Child>") > 0, "got [" + message + "]";
	} else {
		assert message === "" && served === 1, "the snapshot is served: " + served.toString() + " [" + message + "]";
	}
	done();
}

test "control: the same labelled read outside capture fails in a debug build" {
	const [count, setCount] = createSignal<int32>(1);
	let message = "";
	createRoot((d) => {
		const read = createMemo<int32>((p: int32 | null): int32 => untrack((): int32 => count(), "<Child>"));
		try {
			read();
		} catch (e) {
			message = e.message;
		}
		return 0;
	});
	when (debug) {
		assert message.indexOf("[STRICT_READ_UNTRACKED]") === 0, "got [" + message + "]";
	} else {
		assert message === "", "got [" + message + "]";
	}
}
