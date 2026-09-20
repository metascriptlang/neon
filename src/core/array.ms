// Reactive list reconcilers — the engines behind <For> (mapArray, value-keyed) and
// <Index> (indexArray, index-keyed). Ported from the S-array algorithm. Host-agnostic:
// they reconcile mapped results U + per-row reactive scopes, never touching the host.
//
// Divergences from the reference: index/value signals are always allocated (the language
// can't read a callback's arity to skip them), and the empty-list fallback lives in the
// caller (region), not here (no Symbol sentinel to mark a fallback row inside items[]).

import { onCleanup } from "./cleanup";
import { createRoot } from "./owner";
import { untrack, createSignal, accessor, Accessor, Setter } from "./signal";

// Per-row index state, shared between the index accessor and the move controller. The
// signal is created lazily on first read, so a row whose callback never reads the index
// pays nothing (matches the reference when the index is used, allocates nothing when not).
interface IndexCell {
	pos: number;
	getter: (() => number) | null;
	setter: Setter<number> | null;
}

export function mapArray<T, U>(list: () => T[], mapFn: (v: T, index: Accessor<number>) => U, usesIndex: boolean = true): () => U[] {
	return mapArrayBy<T, T, U>(list, null, mapFn, usesIndex);
}

export function mapArrayKeyed<T, U>(list: () => T[], keyOf: (v: T) => number, mapFn: (v: T, index: Accessor<number>) => U, usesIndex: boolean = true): () => U[] {
	return mapArrayBy<T, number, U>(list, keyOf, mapFn, usesIndex);
}

const unreadIndex: Accessor<number> = accessor((): number => {
	throw new Error("the row of this <For> was emitted as not reading its index, but it read it");
});

function mapArrayBy<T, K, U>(list: () => T[], keyOf: ((v: T) => K) | null, mapFn: (v: T, index: Accessor<number>) => U, usesIndex: boolean): () => U[] {
	let items: T[] = [];
	let keys: K[] = [];
	let mapped: U[] = [];
	let disposers: (() => void)[] = [];
	let indexSetters: ((v: number) => void)[] = [];
	let len = 0;

	function makeRowInto(item: T, pos: number, mapStore: U[], dispStore: (() => void)[], idxStore: ((v: number) => void)[]): void {
		if (!usesIndex) {
			mapStore[pos] = createRoot((d) => {
				dispStore[pos] = d;
				return mapFn(item, unreadIndex);
			});
			return;
		}
		mapStore[pos] = createRoot((d) => {
			dispStore[pos] = d;
			const cell: IndexCell = { pos, getter: null, setter: null };
			const index = accessor((): number => {
				if (cell.getter === null) {
					const [g, s] = createSignal(cell.pos);
					cell.getter = g;
					cell.setter = s;
				}
				return (cell.getter as () => number)();
			});
			idxStore[pos] = (newPos: number): void => {
				cell.pos = newPos;
				if (cell.setter !== null) { cell.setter(newPos); }
			};
			return mapFn(item, index);
		});
	}

	onCleanup(() => { for (const d of disposers) { d(); } });

	return () => {
		const newItems = list();
		const newLen = newItems.length;
		return untrack(() => {
			let newKeys: K[] = newItems as unknown as K[];
			let keyIndex: Map<K, number> | null = null;
			if (keyOf !== null) {
				const of = keyOf as (v: T) => K;
				const ks: K[] = new Array(newLen);
				const seen = new Map<K, number>();
				for (let j = 0; j < newLen; j += 1) {
					const k = of(newItems[j]);
					if (seen.has(k)) {
						throw new Error("For: the key " + k.toString() + " is used by rows " + (seen.get(k) as number).toString() + " and " + j.toString());
					}
					seen.set(k, j);
					ks[j] = k;
				}
				newKeys = ks;
				keyIndex = seen;
			}

			if (newLen === 0) {
				if (len !== 0) {
					for (const d of disposers) { d(); }
					disposers = [];
					items = [];
					keys = [];
					mapped = [];
					indexSetters = [];
					len = 0;
				}
				return mapped;
			}

			if (len === 0) {
				const firstMapped: U[] = new Array(newLen);
				const firstDisposers: (() => void)[] = new Array(newLen);
				const firstIndexSetters: ((v: number) => void)[] = new Array(usesIndex ? newLen : 0);
				const firstItems: T[] = new Array(newLen);
				for (let j = 0; j < newLen; j += 1) {
					firstItems[j] = newItems[j];
					makeRowInto(newItems[j], j, firstMapped, firstDisposers, firstIndexSetters);
				}
				mapped = firstMapped;
				disposers = firstDisposers;
				indexSetters = firstIndexSetters;
				items = firstItems;
				keys = keyOf === null ? (items as unknown as K[]) : newKeys;
				len = newLen;
				return mapped;
			}

			const temp: U[] = new Array(newLen);
			const tempFilled: boolean[] = new Array(newLen);
			const tempDisposers: (() => void)[] = new Array(newLen);
			const tempIndexSetters: ((v: number) => void)[] = new Array(usesIndex ? newLen : 0);
			for (let k = 0; k < newLen; k += 1) { tempFilled[k] = false; }

			let start = 0;
			const minLen = len < newLen ? len : newLen;
			while (start < minLen && keys[start] === newKeys[start]) { start += 1; }

			let end = len - 1;
			let newEnd = newLen - 1;
			while (end >= start && newEnd >= start && keys[end] === newKeys[newEnd]) {
				temp[newEnd] = mapped[end];
				tempFilled[newEnd] = true;
				tempDisposers[newEnd] = disposers[end];
				if (usesIndex) { tempIndexSetters[newEnd] = indexSetters[end]; }
				end -= 1;
				newEnd -= 1;
			}

			const newIndices = keyIndex !== null ? (keyIndex as Map<K, number>) : new Map<K, number>();
			const newIndicesNext: number[] = new Array(newLen);
			if (keyIndex === null) {
				for (let j = newEnd; j >= start; j -= 1) {
					const k = newKeys[j];
					const prev = newIndices.has(k) ? (newIndices.get(k) as number) : -1;
					newIndicesNext[j] = prev;
					newIndices.set(k, j);
				}
			} else {
				for (let j = 0; j < newLen; j += 1) { newIndicesNext[j] = -1; }
			}

			for (let i = start; i <= end; i += 1) {
				const k = keys[i];
				if (newIndices.has(k)) {
					const j = newIndices.get(k) as number;
					if (j !== -1) {
						temp[j] = mapped[i];
						tempFilled[j] = true;
						tempDisposers[j] = disposers[i];
						if (usesIndex) { tempIndexSetters[j] = indexSetters[i]; }
						newIndices.set(k, newIndicesNext[j]);
					} else {
						disposers[i]();
					}
				} else {
					disposers[i]();
				}
			}

			const nextMapped: U[] = new Array(newLen);
			const nextDisposers: (() => void)[] = new Array(newLen);
			const nextIndexSetters: ((v: number) => void)[] = new Array(usesIndex ? newLen : 0);
			for (let p = 0; p < start; p += 1) {
				nextMapped[p] = mapped[p];
				nextDisposers[p] = disposers[p];
				if (usesIndex) { nextIndexSetters[p] = indexSetters[p]; }
			}
			for (let j = start; j < newLen; j += 1) {
				if (tempFilled[j]) {
					nextMapped[j] = temp[j];
					nextDisposers[j] = tempDisposers[j];
					if (usesIndex) {
						nextIndexSetters[j] = tempIndexSetters[j];
						nextIndexSetters[j](j);
					}
				} else {
					makeRowInto(newItems[j], j, nextMapped, nextDisposers, nextIndexSetters);
				}
			}

			mapped = nextMapped;
			disposers = nextDisposers;
			indexSetters = nextIndexSetters;
			items = newItems.slice(0, newItems.length);
			keys = keyOf === null ? (items as unknown as K[]) : newKeys;
			len = newLen;
			return mapped;
		});
	};
}

export function indexArray<T, U>(list: () => T[], mapFn: (v: Accessor<T>, index: number) => U): () => U[] {
	let items: T[] = [];
	let mapped: U[] = [];
	let disposers: (() => void)[] = [];
	let valueSetters: Setter<T>[] = [];
	let len = 0;

	// Rows are only ever created at the tail (the caller walks i upward and stops at
	// items.length), so each store grows by one. They are appended, not index-assigned:
	// storing past the end raises here, it does not grow the array as it would in JS.
	// Stores are parameters rather than captures, mirroring mapArray's makeRowInto.
	function makeRowInto(item: T, pos: number, mapStore: U[], dispStore: (() => void)[], setStore: Setter<T>[]): void {
		const row = createRoot((d) => {
			dispStore.push(d);
			const [val, setVal] = createSignal(item);
			setStore.push(setVal);
			return mapFn(val, pos);
		});
		mapStore.push(row);
	}

	onCleanup(() => { for (const d of disposers) { d(); } });

	return () => {
		const newItems = list();
		const newLen = newItems.length;
		return untrack(() => {
			if (newLen === 0) {
				if (len !== 0) {
					for (const d of disposers) { d(); }
					disposers = [];
					items = [];
					mapped = [];
					valueSetters = [];
					len = 0;
				}
				return mapped;
			}

			let i = 0;
			while (i < newLen) {
				if (i < items.length && items[i] !== newItems[i]) {
					valueSetters[i](newItems[i]);
				} else if (i >= items.length) {
					makeRowInto(newItems[i], i, mapped, disposers, valueSetters);
				}
				i += 1;
			}
			while (i < items.length) {
				disposers[i]();
				i += 1;
			}

			disposers = disposers.slice(0, newLen);
			valueSetters = valueSetters.slice(0, newLen);
			mapped = mapped.slice(0, newLen);
			items = newItems.slice(0, newItems.length);
			len = newLen;
			return mapped;
		});
	};
}
