import { sleepAsync } from "std/core/promise";
import { el, dynText, NeonNode } from "../../src/render/node";
import { Host, HostNode } from "../../src/render/hostTypes";
import { place } from "../../src/render/reconcile";
import { createAsyncMemo, createMemo } from "../../src/core/memo";
import { NotReadyError } from "../../src/core/types";
import { Hole, ServerContext, ServerMarks, serverContext, pendingWaits } from "../../src/core/serverContext";
import { HOLES_DONE, HOLES_WAIT, HOLES_FAILED, runHoles } from "../../src/render/bind";
import { renderToString, renderToStream } from "../../src/render/ssr";

async function after(ms: int32, value: string): Promise<string> {
	await sleepAsync(ms);
	return value;
}

class Seen {
	ctx: ServerContext | null = null;
	holes: Hole[] = [];
	taken: string = "";
	thrown: string = "none";
	early: int32 = -1;
	state: int32 = -1;
	filled: string = "";
}

async function settled(seen: Seen, ctx: ServerContext, taken: string): Promise<void> {
	for (const h of seen.holes) {
		for (const w of pendingWaits(ctx, [h.source])) { await w; }
	}
	seen.state = runHoles(ctx, seen.holes);
	seen.filled = (ctx.marks as ServerMarks).fill(taken, seen.holes);
}

function mounted(seen: Seen, windowOpen: boolean, spot: () => NeonNode): NeonNode {
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		const ctx = serverContext() as ServerContext;
		seen.ctx = ctx;
		if (windowOpen) { ctx.holes = []; }
		const marks = ctx.marks as ServerMarks;
		const holder = marks.holder(parent) as HostNode;
		const first = host.createText("");
		place(host, holder, first, null);
		try {
			spot()(host, holder, null);
		} catch (e) {
			seen.thrown = e instanceof NotReadyError ? "not ready" : e.message;
		}
		if (ctx.holes !== null) { seen.holes = ctx.holes as Hole[]; }
		seen.taken = marks.take(first);
		ctx.holes = null;
		seen.early = runHoles(ctx, seen.holes);
		ctx.loops.push(settled(seen, ctx, seen.taken));
	};
}

function pendingSpot(): NeonNode {
	const data = createAsyncMemo((p: string | null): Promise<string> => after(4, "late"));
	return el("p", [], [], dynText((): string => "v=" + data()));
}

function readySpot(): NeonNode {
	const data = createMemo((p: string | null): string => "now");
	return el("p", [], [], dynText((): string => "v=" + data()));
}

function failingSpot(): NeonNode {
	return el("p", [], [], dynText((): string => { throw new Error("boom"); }));
}

test "a pending text spot under an open window leaves a hole and a marker, and the mount goes on" {
	const seen = new Seen();
	await renderToStream(mounted(seen, true, pendingSpot));
	assert seen.thrown === "none", seen.thrown;
	assert seen.holes.length === 1, "one hole: " + seen.holes.length.toString();
	assert seen.taken === "<!----><p><!--pl-#" + seen.holes[0].id + "--></p>", seen.taken;
}

test "the hole's thunk gives the text once its source has settled, and the marker fills to the bytes of a text written at once" {
	const seen = new Seen();
	await renderToStream(mounted(seen, true, pendingSpot));
	assert seen.early === HOLES_WAIT, "read before its source settled: " + seen.early.toString();
	assert seen.state === HOLES_DONE && seen.holes[0].value === "v=late", "after: " + seen.state.toString();
	const once = renderToString(el("p", [], [], dynText((): string => "v=late")));
	assert seen.filled === "<!---->" + once && once === "<p>v=late</p>", seen.filled + " | " + once;
}

test "a pending text spot with no window open throws, and a ready one under an open window leaves no hole" {
	const closed = new Seen();
	await renderToStream(mounted(closed, false, pendingSpot));
	assert closed.thrown === "not ready" && closed.holes.length === 0, closed.thrown + " " + closed.holes.length.toString();
	const ready = new Seen();
	await renderToStream(mounted(ready, true, readySpot));
	assert ready.thrown === "none" && ready.holes.length === 0, ready.thrown + " " + ready.holes.length.toString();
	assert ready.taken === "<!----><p>v=now</p>", ready.taken;
}

test "a spot that throws anything but a pending read rethrows under an open window and leaves no hole" {
	const seen = new Seen();
	await renderToStream(mounted(seen, true, failingSpot));
	assert seen.thrown === "boom" && seen.holes.length === 0, seen.thrown + " " + seen.holes.length.toString();
}

test "a hole whose thunk throws anything but a pending read leaves the hole channel" {
	const seen = new Seen();
	await renderToStream(mounted(seen, true, pendingSpot));
	const failing = new Hole("9", (): string => { throw new Error("boom"); }, null, seen.holes[0].source);
	assert runHoles(seen.ctx as ServerContext, [failing]) === HOLES_FAILED, "failed";
}
