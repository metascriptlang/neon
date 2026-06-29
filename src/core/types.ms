// Reactive graph shapes — shared by signal/effect/memo/cleanup/owner to avoid cyclic imports.

export enum CompState { Clean, Stale }

export type EffectFn = () => void;
export type Dispose = () => void;

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
}
