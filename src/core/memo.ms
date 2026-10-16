import { Computation, NotReadyError, EFFECT_PURE, RUN_UNCHANGED, RUN_PUBLISHED, RUN_STAGED } from "./types";
import { Cell, Accessor, accessor, isEqual, untrack } from "./signal";
import { createComputed, readSource, isStaged, writeSource, beginFlight, endFlight, landFlight, failFlight, markRefresh } from "./runtime";

export interface MemoOptions<T> {
	equals?: ((a: T, b: T) => boolean) | false;
	lazy?: boolean;
	unobserved?: () => void;
}

class Outcome<T> {
	isSync: boolean = true;
	value: Cell<T> | null = null;
	failure: Error | null = null;
}

class RefreshProbeStop extends Error {
	constructor() {
		super("[REFRESH_PROBE] a refresh target was read");
	}
}

let refreshProbing: boolean = false;
let refreshTarget: Computation | null = null;

async function watch<T>(promise: Promise<T>, done: (value: Cell<T> | null, failure: Error | null) => void): Promise<void> {
	let value: Cell<T> | null = null;
	let failure: Error | null = null;
	try {
		value = new Cell<T>(await promise);
	} catch (e) {
		failure = e;
	}
	done(value, failure);
}

function awaitResult<T>(self: Computation, result: Promise<T>, land: (self: Computation, value: T) => void): T {
	const id = beginFlight(self);
	const outcome = new Outcome<T>();
	watch<T>(result, (value: Cell<T> | null, failure: Error | null): void => {
		if (outcome.isSync) {
			outcome.value = value;
			outcome.failure = failure;
		} else if (failure !== null) {
			failFlight(self, id, failure);
		} else if (value !== null) {
			landFlight(self, id, (): void => land(self, value.value));
		}
	});
	outcome.isSync = false;
	const failure = outcome.failure;
	if (failure !== null) {
		endFlight(self);
		throw failure;
	}
	const settled = outcome.value;
	if (settled === null) { throw new NotReadyError(self); }
	endFlight(self);
	return settled.value;
}

function buildMemo<T, R>(compute: (prev: T | null) => R, answer: (self: Computation, result: R, land: (self: Computation, value: T) => void) => T, options?: MemoOptions<T>): Accessor<T> {
	let cell: Cell<T> | null = null;
	let equals: ((a: T, b: T) => boolean) | null = null;
	let lazy = false;
	let hook: (() => void) | null = null;
	if (options !== undefined) {
		const given = options.equals;
		if (typeof given === "function") {
			equals = given;
		} else if (given === false) {
			equals = (a: T, b: T): boolean => false;
		}
		lazy = options.lazy === true;
		hook = options.unobserved === undefined ? null : options.unobserved;
	}

	const publishFirst = (self: Computation, value: T): Cell<T> => {
		const fresh = new Cell<T>(value);
		cell = fresh;
		self.commit = (): void => { fresh.value = fresh.pending; };
		return fresh;
	};

	const land = (self: Computation, value: T): void => {
		const held = cell;
		if (held === null) {
			publishFirst(self, value);
			writeSource(self, false);
			return;
		}
		const wasStaged = isStaged(self);
		if (isEqual(equals, wasStaged ? held.pending : held.value, value)) { return; }
		held.pending = value;
		writeSource(self, wasStaged);
	};

	const run = (self: Computation, create: boolean): int32 => {
		const held = cell;
		if (held === null) {
			publishFirst(self, answer(self, compute(null), land));
			return RUN_PUBLISHED;
		}
		const prev = isStaged(self) ? held.pending : held.value;
		const next = answer(self, compute(prev), land);
		if (isEqual(equals, prev, next)) { return RUN_UNCHANGED; }
		if (create) {
			held.value = next;
			held.pending = next;
			return RUN_PUBLISHED;
		}
		held.pending = next;
		return RUN_STAGED;
	};
	const node = createComputed(run, EFFECT_PURE, lazy, false, hook);

	return accessor((): T => {
		if (refreshProbing) {
			refreshTarget = node;
			throw new RefreshProbeStop();
		}
		const staged = readSource(node);
		const held = cell;
		if (held === null) {
			throw new Error("Memo accessed before initialization");
		}
		return staged ? held.pending : held.value;
	});
}

export function createMemo<T>(compute: (prev: T | null) => T, options?: MemoOptions<T>): Accessor<T> {
	return buildMemo<T, T>(compute, (self: Computation, result: T, land: (self: Computation, value: T) => void): T => result, options);
}

// Parked on ~/metascript/.inbox/compiler/2026-10-16-function-returning-one-member-is-refused-where-a-function-returning-the-union-is-expected.md and its two siblings: Solid 2.0 has one `createMemo` whose compute returns `Promise<T> | T`; this engine entry is not exported and merges into it.
export function createAsyncMemo<T>(compute: (prev: T | null) => Promise<T>, options?: MemoOptions<T>): Accessor<T> {
	return buildMemo<T, Promise<T>>(compute, (self: Computation, result: Promise<T>, land: (self: Computation, value: T) => void): T => awaitResult<T>(self, result, land), options);
}

export function refresh<T>(target: Accessor<T>): void {
	refreshProbing = true;
	refreshTarget = null;
	try {
		untrack((): T => target());
	} catch (e) {
		if (!(e instanceof RefreshProbeStop)) { throw e; }
	} finally {
		refreshProbing = false;
	}
	const node = refreshTarget;
	refreshTarget = null;
	if (node !== null) { markRefresh(node); }
}
