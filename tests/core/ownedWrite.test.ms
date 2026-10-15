import { createSignal } from "../../src/core/signal";
import { createMemo } from "../../src/core/memo";
import { createEffect, createRenderEffect } from "../../src/core/effect";
import { createRoot, runWithOwner } from "../../src/core/owner";
import { getOwner, resetErrorHalt } from "../../src/core/runtime";
import { Cleanup } from "../../src/core/types";

const RULE = "[REACTIVE_WRITE_IN_OWNED_SCOPE]";

function messageOf(body: () => void): string {
	let message = "";
	try { body(); } catch (e) { message = e.message; }
	resetErrorHalt();
	return message;
}

test "a write with no owner is allowed" {
	const [x, setX] = createSignal(0);
	setX(1);
	assert x() === 1, "got " + x().toString();
}

test "a write in a createRoot body throws and names the rule" {
	const [x, setX] = createSignal(0);
	const message = messageOf(() => { createRoot((d) => { setX(1); return 0; }); });
	assert message.indexOf(RULE) === 0, "got [" + message + "]";
	assert message.indexOf("ownedWrite") > 0, "the message names the way out: [" + message + "]";
	assert x() === 0, "the failed write left the signal alone: " + x().toString();
}

test "a write under a root re-entered with runWithOwner throws" {
	const [x, setX] = createSignal(0);
	let owner = createRoot((d) => getOwner());
	const message = messageOf(() => { runWithOwner(owner, () => { setX(1); }); });
	assert message.indexOf(RULE) === 0, "got [" + message + "]";
}

test "a write in a memo body throws" {
	const [x, setX] = createSignal(0);
	const message = messageOf(() => {
		const m = createMemo<int32>((): int32 => { setX(1); return 1; });
		m();
	});
	assert message.indexOf(RULE) === 0, "got [" + message + "]";
}

test "a write in a root created inside a memo body throws" {
	const [x, setX] = createSignal(0);
	const message = messageOf(() => {
		const m = createMemo<int32>((): int32 => {
			createRoot((d) => { setX(1); return 0; });
			return 1;
		});
		m();
	});
	assert message.indexOf(RULE) === 0, "got [" + message + "]";
}

test "a write in an effect's compute phase throws" {
	const [x, setX] = createSignal(0);
	const message = messageOf(() => {
		createRoot((d) => {
			createRenderEffect<int32>(
				(p: int32 | null): int32 => { setX(1); return 0; },
				(v: int32, p: int32 | null): Cleanup | null => null,
			);
			return 0;
		});
	});
	assert message.indexOf(RULE) === 0, "got [" + message + "]";
}

test "a write in an effect's effect phase is allowed" {
	const [tick, setTick] = createSignal(0);
	const [x, setX] = createSignal(0);
	createRoot((d) => {
		createEffect<int32>(
			(p: int32 | null): int32 => tick(),
			(v: int32, p: int32 | null): Cleanup | null => { setX(v); return null; },
		);
		createRenderEffect<int32>(
			(p: int32 | null): int32 => tick(),
			(v: int32, p: int32 | null): Cleanup | null => { if (v > 0) { setX(v + 10); } return null; },
		);
		return 0;
	});
	setTick(1);
	assert x() === 1, "the user effect wrote last: " + x().toString();
}

test "ownedWrite lets a signal be written in a root body" {
	const [x, setX] = createSignal(0, { ownedWrite: true });
	createRoot((d) => { setX(1); return 0; });
	assert x() === 1, "got " + x().toString();
}

test "ownedWrite lets a signal be written in a memo body" {
	const [x, setX] = createSignal(0, { ownedWrite: true });
	const m = createMemo<int32>((): int32 => { setX(2); return 1; });
	m();
	assert x() === 2, "got " + x().toString();
}

test "ownedWrite on one signal does not open the others" {
	const [open, setOpen] = createSignal(0, { ownedWrite: true });
	const [shut, setShut] = createSignal(0);
	const message = messageOf(() => {
		createRoot((d) => { setOpen(1); setShut(1); return 0; });
	});
	assert message.indexOf(RULE) === 0, "got [" + message + "]";
	assert shut() === 0, "the failed write left the other signal alone: " + shut().toString();
}
