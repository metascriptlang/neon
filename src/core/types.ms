// Reactive graph shapes — shared by signal/effect/memo/cleanup/owner to avoid cyclic imports.

export enum CompState { Clean, Stale }

export type EffectFn = () => void;
export type Dispose = () => void;
export type ErrorHandler = (err: Error) => void;

// A context entry an owner scope carries: `key` is the context object itself
// (identity by creation, not by name), `read` the value thunk so each consumer
// read re-evaluates it and signals inside the value track per consumer.
export interface ContextEntry {
	key: unknown;
	read: () => unknown;
}

// The observable half of the graph: a Signal's node, or a memo's own node.
export interface Source {
	observers: Computation[];
	observerSlots: number[];
}

// A reactive computation (effect/memo) — also an owner scope, and (for memos) a Source.
// A root created by createRoot is a Computation with isRoot=true and a no-op fn.
export interface Computation {
	observers: Computation[];
	observerSlots: number[];

	fn: EffectFn;
	isRoot: boolean;
	state: CompState;
	sources: Source[];
	sourceSlots: number[];
	pure: boolean;
	disposed: boolean;

	owned: Computation[];
	cleanups: EffectFn[];
	owner: Computation | null;
	contexts: ContextEntry[] | null;
	handler: ErrorHandler | null;
}
