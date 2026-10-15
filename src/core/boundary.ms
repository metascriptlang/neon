import { Computation, NotReadyError, STATUS_PENDING, STATUS_ERROR, CONFIG_REDERIVE } from "./types";
import { getOwner, createOwner, isDisposed, linkDependency, recomputeNode, wakeNode, requestFlush, requeueEffect, installBoundaryHooks } from "./runtime";
import { runWithOwner } from "./owner";
import { Accessor, Signal, accessor } from "./signal";
import { createMemo } from "./memo";

class BoundaryKey {}

const BOUNDARY_KEY = new BoundaryKey();

class Boundary {
	kind: int32;
	parent: Boundary | null;
	tree: Computation | null = null;
	output: Computation | null = null;
	readers: Computation[] = [];
	held: Computation[] = [];
	initialized: boolean = false;
	fallbackShown: boolean = false;
	failure: Signal<Error | null> | null;

	constructor(kind: int32, parent: Boundary | null) {
		this.kind = kind;
		this.parent = parent;
		this.failure = kind === STATUS_ERROR ? new Signal<Error | null>(null, null, true) : null;
	}
}

let collecting: Boundary[] = [];

function boundaryOf(node: Computation): Boundary | null {
	let entry = node.context;
	while (entry !== null) {
		if (entry.key === BOUNDARY_KEY) { return entry.value as Boundary; }
		entry = entry.next;
	}
	return null;
}

function isCollecting(b: Boundary): boolean {
	return b.kind === STATUS_ERROR || !b.initialized;
}

function unsettled(b: Boundary): int32 {
	return b.kind === STATUS_ERROR ? STATUS_ERROR | STATUS_PENDING : STATUS_PENDING;
}

function addReader(b: Boundary, node: Computation): void {
	for (const r of b.readers) {
		if (r === node) { return; }
	}
	b.readers.push(node);
}

function dropReader(b: Boundary, node: Computation): boolean {
	const rest: Computation[] = [];
	for (const r of b.readers) {
		if (r !== node) { rest.push(r); }
	}
	if (rest.length === b.readers.length) { return false; }
	b.readers = rest;
	return true;
}

function collect(b: Boundary): void {
	for (const c of collecting) {
		if (c === b) { return; }
	}
	collecting.push(b);
}

function uncollect(b: Boundary): void {
	const rest: Boundary[] = [];
	for (const c of collecting) {
		if (c !== b) { rest.push(c); }
	}
	collecting = rest;
}

function redraw(b: Boundary): void {
	const out = b.output;
	if (out !== null && !isDisposed(out)) { wakeNode(out); }
}

// The node an error came from: each reader of an errored node holds the same Error object, so the
// walk follows the dependency that still holds it (the reference wraps the error in a StatusError
// naming the source; the A2a runtime keeps the raw Error and tests pin its identity).
function errorSource(node: Computation, error: Error): Computation {
	let at = node;
	while (true) {
		let next: Computation | null = null;
		for (let d = at.deps; d !== null; d = d.nextDep) {
			const dep = d.dep;
			if (dep.computed) {
				const c = dep as Computation;
				if ((c.status & STATUS_ERROR) !== 0 && c.error === error) {
					next = c;
					break;
				}
			}
		}
		if (next === null) { return at; }
		at = next;
	}
}

function statusOf(node: Computation): Error {
	const error = node.error;
	if (error === null) { throw new Error("[BOUNDARY_STATUS_WITHOUT_ERROR] a boundary's content is pending or errored but holds no error to throw"); }
	return error;
}

// boundaries.ts:161 caught
function caught(b: Boundary, node: Computation, error: Error | null): void {
	let reader = node;
	if (b.kind === STATUS_ERROR) {
		const raised = error !== null ? error : statusOf(node);
		reader = errorSource(node, raised);
		(b.failure as Signal<Error | null>).set(raised);
	}
	addReader(b, reader);
	collect(b);
	if (!b.fallbackShown) { redraw(b); }
}

// boundaries.ts:206 catchStatus, installed through the runtime's hook (GlobalQueue._catch)
function catchStatus(node: Computation, flags: int32, error: Error | null): boolean {
	if (flags === 0) {
		if (collecting.length !== 0) {
			for (let b = boundaryOf(node); b !== null; b = b.parent) {
				if ((node.status & unsettled(b)) === 0 && dropReader(b, node) && b.readers.length === 0 && b.fallbackShown) {
					redraw(b);
				}
			}
		}
		return false;
	}
	for (let b = boundaryOf(node); b !== null; b = b.parent) {
		if ((b.kind & flags) === 0) { continue; }
		if (isCollecting(b)) {
			caught(b, node, error);
			return true;
		}
		addReader(b, node);
		collect(b);
	}
	return false;
}

// boundaries.ts:295 prune
function prune(b: Boundary): int32 {
	const mask = unsettled(b);
	const kept: Computation[] = [];
	for (const r of b.readers) {
		if (!isDisposed(r) && (r.status & mask) !== 0) { kept.push(r); }
	}
	b.readers = kept;
	return kept.length;
}

// boundaries.ts:335 boundarySeam, at the end of a flush's commit
function sweepBoundaries(): void {
	const batch = collecting;
	collecting = [];
	for (const b of batch) {
		const out = b.output;
		if (out === null || isDisposed(out)) { continue; }
		prune(b);
		if (b.readers.length === 0) {
			if (b.fallbackShown) { redraw(b); }
		} else {
			collecting.push(b);
		}
	}
}

// boundaries.ts:262 heldRun: a queued run behind a fallback waits for the reveal
function heldRun(node: Computation): boolean {
	for (let b = boundaryOf(node); b !== null; b = b.parent) {
		if (b.fallbackShown) {
			for (const n of b.held) {
				if (n === node) { return true; }
			}
			b.held.push(node);
			return true;
		}
	}
	return false;
}

// boundaries.ts:272 release
function release(b: Boundary): void {
	const runs = b.held;
	b.held = [];
	for (const n of runs) { requeueEffect(n); }
}

// boundaries.ts:464 reset
function reset(b: Boundary): void {
	const batch = b.readers.slice(0);
	for (const r of batch) {
		if (r.run !== null && !isDisposed(r)) { recomputeNode(r); }
	}
	requestFlush();
}

function showFallback<T>(b: Boundary, show: (b: Boundary) => T): T {
	b.fallbackShown = true;
	return show(b);
}

// boundaries.ts:554 the output pass of createBoundary
function derive<T>(b: Boundary, content: Accessor<T>, show: (b: Boundary) => T): T {
	const self = getOwner() as Computation;
	if (b.output === null) {
		b.output = self;
		self.config = self.config | CONFIG_REDERIVE;
	}
	const tree = b.tree as Computation;
	const status = tree.status & (STATUS_PENDING | STATUS_ERROR);
	if (status !== 0) {
		linkDependency(tree, self);
		if ((status & b.kind) !== 0) {
			if (isCollecting(b)) {
				caught(b, tree, null);
				return showFallback<T>(b, show);
			}
			addReader(b, tree);
			collect(b);
		}
		throw statusOf(tree);
	}
	if (isCollecting(b) && prune(b) !== 0) { return showFallback<T>(b, show); }
	let value: T;
	try {
		value = content();
	} catch (e) {
		if (e instanceof NotReadyError ? b.kind === STATUS_PENDING : b.kind === STATUS_ERROR) {
			if (isCollecting(b)) {
				caught(b, tree, e);
				return showFallback<T>(b, show);
			}
			addReader(b, tree);
			collect(b);
		}
		throw e;
	}
	if (isCollecting(b) && b.readers.length !== 0) { return showFallback<T>(b, show); }
	b.initialized = true;
	b.fallbackShown = false;
	release(b);
	return value;
}

// boundaries.ts:471 createBoundary
function createBoundary<T>(kind: int32, fn: () => T, show: (b: Boundary) => T): Accessor<T> {
	installBoundaryHooks(catchStatus, sweepBoundaries, heldRun);
	const owner = createOwner();
	const b = new Boundary(kind, boundaryOf(owner));
	owner.disposal = [(): void => {
		uncollect(b);
		b.tree = null;
		b.output = null;
		b.readers = [];
		b.held = [];
	}];
	owner.context = { key: BOUNDARY_KEY, value: b, next: owner.context };
	const content = runWithOwner(owner, (): Accessor<T> => createMemo<T>((prev: T | null): T => {
		b.tree = getOwner();
		return fn();
	}));
	return createMemo<T>((prev: T | null): T => derive<T>(b, content, show));
}

// boundaries.ts:739 createLoadingBoundary, without `on`: the dependency list re-arms a boundary through a held frame
export function createLoadingBoundary<T>(fn: () => T, fallback: () => T): Accessor<T> {
	return createBoundary<T>(STATUS_PENDING, fn, (b: Boundary): T => fallback());
}

function failureOf(b: Boundary): Accessor<Error> {
	const failure = b.failure as Signal<Error | null>;
	return accessor((): Error => {
		const error = failure.get();
		if (error === null) { throw new Error("[BOUNDARY_NO_ERROR] the error of a boundary was read before it caught one"); }
		return error;
	});
}

// boundaries.ts:770 createErrorBoundary
export function createErrorBoundary<T>(fn: () => T, fallback: (error: Accessor<Error>, reset: () => void) => T): Accessor<T> {
	return createBoundary<T>(STATUS_ERROR, fn, (b: Boundary): T => fallback(failureOf(b), (): void => { reset(b); }));
}
