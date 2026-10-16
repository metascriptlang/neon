// A reactive read that is not tracked, made under a labelled untrack (a component body), throws in a debug build and does nothing in a release build.
import { createSignal, untrack } from "../../src/core/signal";
import { createMemo, createAsyncMemo } from "../../src/core/memo";
import { createRenderEffect } from "../../src/core/effect";
import { createRoot } from "../../src/core/owner";
import { resetErrorHalt } from "../../src/core/runtime";
import { Cleanup } from "../../src/core/types";
import { createComponent } from "../../src/render/component";
import { NeonNode } from "../../src/render/hostTypes";
import { render, mockHost, mockNode, Host, HostNode } from "../../src/render/host";
import { Gate, gated, release } from "./asyncClock";

const STRICT = "[STRICT_READ_UNTRACKED]";
const PENDING = "[PENDING_ASYNC_UNTRACKED_READ]";

function nothing(host: Host, parent: HostNode, before: HostNode | null): void {}

function messageOfMount(body: () => void): string {
	let message = "";
	const root = mockNode("root");
	try {
		render(createComponent((p: int32): NeonNode => { body(); return nothing; }, 0), mockHost(), root as unknown as HostNode);
	} catch (e) { message = e.message; }
	resetErrorHalt();
	return message;
}

function readThrough(read: () => int32): int32 {
	return read();
}

test "a helper called from a component body that reads an accessor throws in debug only" {
	const [x, setX] = createSignal(1);
	let seen = 0;
	const message = messageOfMount(() => { seen = readThrough((): int32 => x()); });
	when (debug) {
		assert message.indexOf(STRICT) === 0, "got [" + message + "]";
		assert message.indexOf("a component body") > 0, "the message names the label: [" + message + "]";
	} else {
		assert message === "", "a release build reads without a check: [" + message + "]";
		assert seen === 1, "and the read returns the value: " + seen.toString();
	}
}

test "a memo accessor read through a helper in a component body throws in debug only" {
	const [x, setX] = createSignal(2);
	const message = messageOfMount(() => {
		const doubled = createMemo<int32>((p: int32 | null): int32 => x() * 2);
		readThrough((): int32 => doubled());
	});
	when (debug) {
		assert message.indexOf(STRICT) === 0, "got [" + message + "]";
	} else {
		assert message === "", "got [" + message + "]";
	}
}

test "the same read inside a memo, an effect compute or untrack in a component body is allowed" {
	const [x, setX] = createSignal(3);
	let inMemo = 0;
	let inEffect = 0;
	let inUntrack = 0;
	const message = messageOfMount(() => {
		const m = createMemo<int32>((p: int32 | null): int32 => readThrough((): int32 => x()));
		createRenderEffect<int32>(
			(p: int32 | null): int32 => readThrough((): int32 => x()),
			(v: int32, p: int32 | null): Cleanup | null => { inEffect = v; return null; },
		);
		inUntrack = untrack((): int32 => readThrough((): int32 => x()));
		inMemo = untrack((): int32 => m());
	});
	assert message === "", "got [" + message + "]";
	assert inMemo === 3 && inEffect === 3 && inUntrack === 3, "got " + inMemo.toString() + inEffect.toString() + inUntrack.toString();
}

test "an effect's apply phase run during a component body reads without the label" {
	const [x, setX] = createSignal(6);
	const [y, setY] = createSignal(7);
	let applied = 0;
	const message = messageOfMount(() => {
		createRenderEffect<int32>(
			(p: int32 | null): int32 => x(),
			(v: int32, p: int32 | null): Cleanup | null => { applied = v + y(); return null; },
		);
	});
	assert message === "", "got [" + message + "]";
	assert applied === 13, "the first apply ran and read the second signal: " + applied.toString();
}

test "a plain untrack nested in a labelled one clears the label and a nested label replaces it" {
	const [x, setX] = createSignal(4);
	let plain = 0;
	const plainMessage = messageOfMount(() => {
		untrack((): int32 => { plain = x(); return 0; });
	});
	assert plainMessage === "" && plain === 4, "got [" + plainMessage + "] " + plain.toString();
	let labelled = "";
	try {
		untrack((): int32 => untrack((): int32 => x(), "a probe"), null);
	} catch (e) { labelled = e.message; }
	resetErrorHalt();
	when (debug) {
		assert labelled.indexOf("a probe") > 0, "got [" + labelled + "]";
	} else {
		assert labelled === "", "got [" + labelled + "]";
	}
}

test "an unlabelled read outside any component body is allowed" {
	const [x, setX] = createSignal(5);
	assert untrack((): int32 => x()) === 5, "untrack without a label";
	assert x() === 5, "a bare read";
}

test "a pending async read through a helper in a component body is its own error in debug" {
	const gate = new Gate();
	const a = createRoot((d) => {
		const m = createAsyncMemo((p: int32 | null): Promise<int32> => gated(gate, 42));
		createRenderEffect<int32>((p: int32 | null): int32 => m(), (v: int32, p: int32 | null): Cleanup | null => null);
		return m;
	});
	const message = messageOfMount(() => { readThrough((): int32 => a()); });
	when (debug) {
		assert message.indexOf(PENDING) === 0, "got [" + message + "]";
	} else {
		assert message.indexOf(PENDING) < 0 && message.indexOf(STRICT) < 0, "got [" + message + "]";
	}
	await release(gate);
	assert a() === 42, "the memo still lands";
}

test "a re-pending async read keeps the pending message, not the strict one" {
	const gate = new Gate();
	const [s, set] = createSignal<int32>(1);
	const a = createRoot((d) => {
		const m = createAsyncMemo((p: int32 | null): Promise<int32> => gated(gate, s()));
		createRenderEffect<int32>((p: int32 | null): int32 => m(), (v: int32, p: int32 | null): Cleanup | null => null);
		return m;
	});
	await release(gate);
	gate.open = false;
	set(2);
	const message = messageOfMount(() => { readThrough((): int32 => a()); });
	when (debug) {
		assert message.indexOf(PENDING) === 0, "got [" + message + "]";
	} else {
		assert message === "", "a release build serves the last value: [" + message + "]";
	}
	await release(gate);
	assert a() === 2, "the second run lands";
}
