import { sleepAsync } from "std/core/promise";
import { createAsyncMemo } from "../../src/core/memo";
import { createRoot } from "../../src/core/owner";
import { Accessor } from "../../src/core/signal";
import { NotReadyError } from "../../src/core/types";
import { ServerContext, SafeError, withServerContext } from "../../src/core/serverContext";

const calls: string[] = [];

async function after(ms: int32, value: int32): Promise<int32> {
	await sleepAsync(ms);
	return value;
}

async function afterFail(ms: int32, failure: Error): Promise<int32> {
	await sleepAsync(ms);
	throw failure;
}

function mounted(ctx: ServerContext, name: string, ms: int32, value: int32): Accessor<int32> {
	return withServerContext(ctx, (): Accessor<int32> => createRoot((d: () => void): Accessor<int32> => createAsyncMemo((p: int32 | null): Promise<int32> => {
		calls.push(name);
		return after(ms, value);
	}), ""));
}

function mountedFailing(ctx: ServerContext, failure: Error): Accessor<int32> {
	return withServerContext(ctx, (): Accessor<int32> => createRoot((d: () => void): Accessor<int32> => createAsyncMemo((p: int32 | null): Promise<int32> => afterFail(2, failure)), ""));
}

function thrownBy(read: () => int32): Error | null {
	try {
		read();
	} catch (e) {
		return e;
	}
	return null;
}

async function settle(ctx: ServerContext): Promise<void> {
	for (const id of ctx.started) { await ctx.slots.get(id).wait; }
}

function startedOf(c: ServerContext): int32 { return c.started.length; }

function called(name: string): int32 {
	let n = 0;
	for (const c of calls) { if (c === name) { n += 1; } }
	return n;
}

test "a pending async memo throws NotReadyError, then a memo at the same owner id runs its compute again, then adopts the settled value" {
	const ctx = new ServerContext();
	const first = mounted(ctx, "adopt", 4, 42);
	assert thrownBy(first) instanceof NotReadyError, "pending read";
	assert ctx.started.length === 1, "one flight";
	await settle(ctx);
	const again = mounted(ctx, "adopt", 4, 42);
	assert again() === 42, "adopted";
	assert called("adopt") === 2, "compute ran again, its promise dropped: " + called("adopt").toString();
	assert ctx.started.length === 1, "the adopted memo started nothing";
	assert ctx.slots.get(ctx.started[0]).json === "42", "the record is the value's JSON";
}

test "a pending slot read again before it settles joins the flight and starts no second one" {
	const ctx = new ServerContext();
	mounted(ctx, "join", 4, 1);
	const second = mounted(ctx, "join", 4, 1);
	assert thrownBy(second) instanceof NotReadyError, "still pending";
	assert called("join") === 2 && ctx.started.length === 1, "the compute ran again, one flight";
	await settle(ctx);
}

test "a memo made again at a slot still in flight reads the settled value once the flight lands" {
	const ctx = new ServerContext();
	thrownBy(mounted(ctx, "land", 4, 7));
	const second = mounted(ctx, "land", 4, 7);
	assert thrownBy(second) instanceof NotReadyError, "pending while the flight is out";
	await settle(ctx);
	await sleepAsync(2);
	assert second() === 7, "the node made again holds the answer";
	assert called("land") === 2 && ctx.started.length === 1, "one flight, the compute ran again";
}

test "a memo made again at a slot whose flight failed throws the failure once it lands" {
	const ctx = new ServerContext();
	thrownBy(mountedFailing(ctx, new SafeError("late failure")));
	const second = mountedFailing(ctx, new SafeError("late failure"));
	assert thrownBy(second) instanceof NotReadyError, "pending while the flight is out";
	await settle(ctx);
	await sleepAsync(2);
	const thrown = thrownBy(second);
	assert thrown !== null && !(thrown instanceof NotReadyError) && thrown.message === "late failure", "the failure, not a pending read";
}

test "a rejection is recorded sanitized, and the memo created again at that id throws it" {
	const ctx = new ServerContext();
	mountedFailing(ctx, new Error("db password=hunter2"));
	await settle(ctx);
	const again = mountedFailing(ctx, new Error("db password=hunter2"));
	const failure = thrownBy(again);
	assert failure !== null, "rejected";
	when (debug) {
		assert (failure as Error).message === "db password=hunter2", "a dev build keeps the message";
	} else {
		assert (failure as Error).message === "Internal Server Error", "a build without debug hides it: " + (failure as Error).message;
	}
}

test "a SafeError rejection keeps its message" {
	const ctx = new ServerContext();
	mountedFailing(ctx, new SafeError("try again later"));
	await settle(ctx);
	const failure = thrownBy(mountedFailing(ctx, new SafeError("try again later")));
	assert failure !== null && (failure as Error).message === "try again later", "kept";
}

test "two contexts keep their own slots for the same owner id" {
	const a = new ServerContext();
	const b = new ServerContext();
	mounted(a, "ctx-a", 8, 1);
	mounted(b, "ctx-b", 2, 2);
	await settle(b);
	await settle(a);
	assert mounted(a, "ctx-a", 8, 1)() === 1 && mounted(b, "ctx-b", 2, 2)() === 2, "each adopts its own";
	assert called("ctx-a") === 2 && called("ctx-b") === 2 && startedOf(a) + startedOf(b) === 2, "compute again, no second flight";
}
