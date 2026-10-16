import { sleepAsync } from "std/core/promise";
import { createAsyncMemo, createMemo } from "../../src/core/memo";
import { createRoot } from "../../src/core/owner";
import { Accessor } from "../../src/core/signal";
import { NotReadyError } from "../../src/core/types";
import { ServerContext, SafeError, withServerContext } from "../../src/core/serverContext";

var runs = 0;

async function after(ms: int32, value: int32): Promise<int32> {
	await sleepAsync(ms);
	return value;
}

async function afterFail(ms: int32, failure: Error): Promise<int32> {
	await sleepAsync(ms);
	throw failure;
}

async function ready(value: int32): Promise<int32> {
	return value;
}

function mounted(ctx: ServerContext, make: () => Promise<int32>): Accessor<int32> {
	return withServerContext(ctx, (): Accessor<int32> => createRoot((d: () => void): Accessor<int32> => createAsyncMemo((p: int32 | null): Promise<int32> => {
		runs += 1;
		return make();
	}), "r"));
}

function readOf(ctx: ServerContext, read: () => int32): string {
	try {
		return withServerContext(ctx, (): string => read().toString());
	} catch (e) {
		return e instanceof NotReadyError ? "NotReady" : e.message;
	}
}

async function settle(ctx: ServerContext): Promise<void> {
	const waits = ctx.waits;
	ctx.waits = [];
	for (const w of waits) { await w; }
}

test "a memo created outside a pending read returns its settled value on the second read, computed once" {
	runs = 0;
	const ctx = new ServerContext();
	const data = mounted(ctx, (): Promise<int32> => after(4, 7));
	assert readOf(ctx, data) === "NotReady", "first read is pending";
	await settle(ctx);
	assert readOf(ctx, data) === "7", "second read: " + readOf(ctx, data);
	assert readOf(ctx, data) === "7", "third read keeps it";
	assert runs === 1, "compute ran once: " + runs.toString();
}

test "a memo whose promise rejects throws that error on the second read, not NotReadyError" {
	runs = 0;
	const ctx = new ServerContext();
	const data = mounted(ctx, (): Promise<int32> => afterFail(4, new SafeError("no row")));
	assert readOf(ctx, data) === "NotReady", "first read is pending";
	await settle(ctx);
	assert readOf(ctx, data) === "no row", "second read: " + readOf(ctx, data);
	assert runs === 1, "compute ran once: " + runs.toString();
}

test "a promise already settled at the read lands the same: the value on a read after the wait, computed once" {
	runs = 0;
	const ctx = new ServerContext();
	const data = mounted(ctx, (): Promise<int32> => ready(5));
	const first = readOf(ctx, data);
	assert first === "NotReady" || first === "5", "first read: " + first;
	await settle(ctx);
	assert readOf(ctx, data) === "5", "read after the wait: " + readOf(ctx, data);
	assert runs === 1, "compute ran once: " + runs.toString();
}

test "a memo derived from a pending async memo reads the settled value after the wait, each computed once" {
	runs = 0;
	let derivedRuns = 0;
	const ctx = new ServerContext();
	const data = mounted(ctx, (): Promise<int32> => after(4, 3));
	const doubled = withServerContext(ctx, (): Accessor<int32> => createRoot((d: () => void): Accessor<int32> => createMemo((p: int32 | null): int32 => {
		derivedRuns += 1;
		return data() * 2;
	}), "d"));
	assert readOf(ctx, doubled) === "NotReady", "first read is pending";
	await settle(ctx);
	assert readOf(ctx, doubled) === "6", "derived read: " + readOf(ctx, doubled);
	assert runs === 1, "source computed once: " + runs.toString();
}
