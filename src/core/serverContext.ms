export class SafeError extends Error {}

export function sanitized(error: Error): Error {
	let wire = error;
	when (debug) {} else { if (!(error instanceof SafeError)) { wire = new Error("Internal Server Error"); } }
	return wire;
}

export class ServerSlot {
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

export class ServerContext {
	slots: Map<string, ServerSlot> = new Map<string, ServerSlot>();
	started: string[] = [];
	waits: Promise<void>[] = [];
	every: Promise<void>[] = [];
	loops: Promise<void>[] = [];
	fragments: Map<string, string> = new Map<string, string>();
	failure: Error | null = null;
	marks: ServerMarks | null = null;
}

export function takeWaits(ctx: ServerContext): Promise<void>[] {
	const taken = ctx.waits;
	ctx.waits = [];
	for (const w of taken) { ctx.every.push(w); }
	return taken;
}

export function awaitable(ctx: ServerContext, taken: Promise<void>[]): Promise<void>[] {
	if (taken.length > 0) { return taken; }
	if (ctx.every.length === 0) { throw new Error("SSR: a read was not ready and nothing is awaited; the render cannot settle"); }
	return ctx.every.slice(0, ctx.every.length);
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
