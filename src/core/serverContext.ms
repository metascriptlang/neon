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

export class ServerContext {
	slots: Map<string, ServerSlot> = new Map<string, ServerSlot>();
	started: string[] = [];
	waits: Promise<void>[] = [];
	waiting: string[] = [];
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
