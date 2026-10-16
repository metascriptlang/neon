import { Computation } from "./types";

export class SafeError extends Error {}

export function sanitized(error: Error): Error {
	let wire = error;
	when (debug) {} else { if (!(error instanceof SafeError)) { wire = new Error("Internal Server Error"); } }
	return wire;
}

async function noWait(): Promise<void> {}

export class ServerSlot {
	wait: Promise<void> = noWait();
	settled: boolean = false;
	json: string = "";
	cell: unknown;
	failure: Error | null = null;
}

export interface ServerMarks {
	open: (id: string) => unknown;
	close: (id: string) => unknown;
	holder: (beside: unknown) => unknown;
	html: (holder: unknown) => string;
	within: (id: string, run: () => boolean) => boolean;
}

export class Fragments {
	markup: Map<string, string> = new Map<string, string>();
	settled: ((id: string) => void) | null = null;

	set(id: string, html: string): void {
		this.markup.set(id, html);
		if (this.settled !== null) { (this.settled as (id: string) => void)(id); }
	}

	get(id: string): string | null {
		return this.markup.get(id);
	}
}

export class ServerContext {
	slots: Map<string, ServerSlot> = new Map<string, ServerSlot>();
	started: string[] = [];
	loops: Promise<void>[] = [];
	fragments: Fragments = new Fragments();
	failure: Error | null = null;
	marks: ServerMarks | null = null;
}

export function pendingWaits(ctx: ServerContext, sources: Computation[]): Promise<void>[] {
	const waits: Promise<void>[] = [];
	for (const source of sources) {
		const id = source.id;
		const slot = id === null ? null : ctx.slots.get(id);
		if (slot === null) { throw new Error("[SERVER_WAIT_WITHOUT_SLOT] a pending read names an async memo that has no server slot: create the memo inside the render that reads it, not before renderToStream or streamRender starts"); }
		waits.push(slot.wait);
	}
	return waits;
}

let current: ServerContext | null = null;

export function serverContext(): ServerContext | null {
	return current;
}

export function withServerContext<T>(ctx: ServerContext, run: () => T): T {
	const prev = current;
	current = ctx;
	try {
		return run();
	} finally {
		current = prev;
	}
}

export const MAX_PASSES = 10000;

export function unconverged(where: string): Error {
	return new Error("SSR: " + where + " did not converge after " + MAX_PASSES.toString() + " passes; an async memo is created under a new owner id on every pass, so no settled answer is ever found again");
}
