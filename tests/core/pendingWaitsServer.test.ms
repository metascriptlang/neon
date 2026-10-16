import { sleepAsync } from "std/core/promise";
import { createAsyncMemo } from "../../src/core/memo";
import { createRoot } from "../../src/core/owner";
import { Accessor } from "../../src/core/signal";
import { Computation, NotReadyError } from "../../src/core/types";
import { ServerContext, pendingWaits, withServerContext } from "../../src/core/serverContext";

async function after(ms: int32, value: int32): Promise<int32> {
	await sleepAsync(ms);
	return value;
}

function sourceOf(ctx: ServerContext | null, id: string): Computation {
	const make = (): Accessor<int32> => createRoot((d: () => void): Accessor<int32> => createAsyncMemo((p: int32 | null): Promise<int32> => after(4, 1)), id);
	const data = ctx === null ? make() : withServerContext(ctx, make);
	try {
		if (ctx === null) { data(); } else { withServerContext(ctx, (): int32 => data()); }
	} catch (e) {
		if (e instanceof NotReadyError) { return (e as NotReadyError).source; }
		throw e;
	}
	throw new Error("the read did not pend");
}

test "pendingWaits maps a pending source to the wait of its slot" {
	const ctx = new ServerContext();
	const a = sourceOf(ctx, "a");
	const waits = pendingWaits(ctx, [a]);
	assert waits.length === 1, "one wait";
	assert waits[0] === ctx.slots.get(ctx.started[0]).wait, "the slot's own wait";
	await waits[0];
	assert ctx.slots.get(ctx.started[0]).settled, "awaiting it settles the slot";
}

test "pendingWaits names an error for a source that has no slot" {
	const ctx = new ServerContext();
	const stray = sourceOf(new ServerContext(), "stray");
	let message = "none";
	try {
		pendingWaits(ctx, [stray]);
	} catch (e) {
		message = e.message;
	}
	assert message.includes("SERVER_WAIT_WITHOUT_SLOT"), "named error: " + message;
}
