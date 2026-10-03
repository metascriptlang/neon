// Reactive graph shapes — shared by signal/effect/memo/cleanup/owner to avoid cyclic imports.

export enum CompState { Clean, Stale }

export type EffectFn = () => void;
export type Dispose = () => void;
export type ErrorHandler = (err: Error) => void;

// The context a provider scope carries: `key` is the context object itself
// (identity by creation, not by name), `value` the provider's typed holder.
export interface ContextEntry {
	key: unknown;
	value: unknown;
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
	context: ContextEntry | null;
	handler: ErrorHandler | null;
}
