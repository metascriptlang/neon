export type EffectFn = () => void;
export type Dispose = () => void;
export type ErrorHandler = (err: Error) => void;

export interface ContextEntry {
	key: unknown;
	value: unknown;
	next: ContextEntry | null;
}

export const REACTIVE_CHECK: int32 = 1 << 0;
export const REACTIVE_DIRTY: int32 = 1 << 1;
export const REACTIVE_RECOMPUTING_DEPS: int32 = 1 << 2;
export const REACTIVE_IN_HEAP: int32 = 1 << 3;
export const REACTIVE_IN_HEAP_HEIGHT: int32 = 1 << 4;
export const REACTIVE_DISPOSED: int32 = 1 << 6;
export const REACTIVE_LAZY: int32 = 1 << 9;
export const REACTIVE_MISSED_WAKE: int32 = 1 << 12;

export const CONFIG_OWNED_WRITE: int32 = 1 << 0;
export const CONFIG_TRANSPARENT: int32 = 1 << 2;
export const CONFIG_AUTO_DISPOSE: int32 = 1 << 5;
export const CONFIG_STAGED: int32 = 1 << 7;
export const CONFIG_PROMOTED: int32 = 1 << 22;
export const CONFIG_ROOT: int32 = 1 << 23;
export const CONFIG_MODIFIED: int32 = 1 << 24;
export const CONFIG_DORMANT_QUEUED: int32 = 1 << 25;

export const EFFECT_PURE: int32 = 0;
export const EFFECT_RENDER: int32 = 1;
export const EFFECT_USER: int32 = 2;

export const RUN_UNCHANGED: int32 = 0;
export const RUN_PUBLISHED: int32 = 1;
export const RUN_STAGED: int32 = 2;

export interface Link {
	dep: Source;
	sub: Computation;
	nextDep: Link | null;
	prevSub: Link | null;
	nextSub: Link | null;
	gen: int32;
}

// `commit` and `run` close over the typed Cell only, never their own node: --gc=drc has
// no cycle collector, so a node that reaches itself through its closure leaks.
export interface Source {
	subs: Link | null;
	subsTail: Link | null;
	config: int32;
	computed: boolean;
	commit: (() => void) | null;
}

export interface Computation extends Source {
	deps: Link | null;
	depsTail: Link | null;
	depGen: int32;
	flags: int32;
	height: int32;
	nextHeap: Computation | null;
	prevHeap: Computation | null;
	run: ((self: Computation, create: boolean) => int32) | null;
	type: int32;
	unobserved: (() => void) | null;

	parent: Computation | null;
	parentComputed: Computation | null;
	firstChild: Computation | null;
	nextSibling: Computation | null;
	prevSibling: Computation | null;
	disposal: EffectFn[] | null;
	context: ContextEntry | null;
	handler: ErrorHandler | null;
	id: string | null;
	childCount: int32;
}
