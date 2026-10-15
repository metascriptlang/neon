import { Computation, EFFECT_PURE, RUN_UNCHANGED, RUN_PUBLISHED, RUN_STAGED } from "./types";
import { Cell, Accessor, accessor, isEqual } from "./signal";
import { createComputed, readSource, isStaged } from "./runtime";

export interface MemoOptions<T> {
	equals?: ((a: T, b: T) => boolean) | false;
	lazy?: boolean;
	unobserved?: () => void;
}

export function createMemo<T>(compute: (prev: T | null) => T, options?: MemoOptions<T>): Accessor<T> {
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

	const run = (self: Computation, create: boolean): int32 => {
		const held = cell;
		if (held === null) {
			const fresh = new Cell<T>(compute(null));
			cell = fresh;
			self.commit = (): void => { fresh.value = fresh.pending; };
			return RUN_PUBLISHED;
		}
		const prev = isStaged(self) ? held.pending : held.value;
		const next = compute(prev);
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
		const staged = readSource(node);
		const held = cell;
		if (held === null) {
			throw new Error("Memo accessed before initialization");
		}
		return staged ? held.pending : held.value;
	});
}
