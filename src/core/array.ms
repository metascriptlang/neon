// Reactive list reconcilers — the engines behind <For> (mapArray, value-keyed) and
// <Index> (indexArray, index-keyed). Ported from the S-array algorithm. Host-agnostic:
// they reconcile mapped results U + per-row reactive scopes, never touching the host.
//
// Divergences from the reference: index/value signals are always allocated (the language
// can't read a callback's arity to skip them), and the empty-list fallback lives in the
// caller (region), not here (no Symbol sentinel to mark a fallback row inside items[]).

import { onCleanup } from "./cleanup";
import { createRoot } from "./owner";
import { untrack, createSignal } from "./signal";

// Per-row index state, shared between the index accessor and the move controller. The
// signal is created lazily on first read, so a row whose callback never reads the index
// pays nothing (matches the reference when the index is used, allocates nothing when not).
interface IndexCell {
	pos: number;
	getter: (() => number) | null;
	setter: ((v: number) => void) | null;
}

export function mapArray<T, U>(list: () => T[], mapFn: (v: T, index: () => number) => U): () => U[] {
	let items: T[] = [];
	let mapped: U[] = [];
	let disposers: (() => void)[] = [];
	let indexSetters: ((v: number) => void)[] = [];
	let len = 0;

	function makeRowInto(item: T, pos: number, mapStore: U[], dispStore: (() => void)[], idxStore: ((v: number) => void)[]): void {
		mapStore[pos] = createRoot((d) => {
			dispStore[pos] = d;
			const cell: IndexCell = { pos, getter: null, setter: null };
			const index = (): number => {
				if (cell.getter === null) {
					const [g, s] = createSignal(cell.pos);
					cell.getter = g;
					cell.setter = s;
				}
				return (cell.getter as () => number)();
			};
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
			if (newLen === 0) {
				if (len !== 0) {
					for (const d of disposers) { d(); }
					disposers = [];
					items = [];
					mapped = [];
					indexSetters = [];
					len = 0;
				}
				return mapped;
			}

			if (len === 0) {
				mapped = new Array(newLen);
				disposers = new Array(newLen);
				indexSetters = new Array(newLen);
				items = new Array(newLen);
				for (let j = 0; j < newLen; j += 1) {
					items[j] = newItems[j];
					makeRowInto(newItems[j], j, mapped, disposers, indexSetters);
				}
				len = newLen;
				return mapped;
			}

			const temp: U[] = new Array(newLen);
			const tempFilled: boolean[] = new Array(newLen);
			const tempDisposers: (() => void)[] = new Array(newLen);
			const tempIndexSetters: ((v: number) => void)[] = new Array(newLen);
			for (let k = 0; k < newLen; k += 1) { tempFilled[k] = false; }

			let start = 0;
			const minLen = len < newLen ? len : newLen;
			while (start < minLen && items[start] === newItems[start]) { start += 1; }

			let end = len - 1;
			let newEnd = newLen - 1;
			while (end >= start && newEnd >= start && items[end] === newItems[newEnd]) {
				temp[newEnd] = mapped[end];
				tempFilled[newEnd] = true;
				tempDisposers[newEnd] = disposers[end];
				tempIndexSetters[newEnd] = indexSetters[end];
				end -= 1;
				newEnd -= 1;
			}

			const newIndices = new Map<T, number>();
			const newIndicesNext: number[] = new Array(newEnd + 1);
			for (let j = newEnd; j >= start; j -= 1) {
				const item = newItems[j];
				const prev = newIndices.has(item) ? (newIndices.get(item) as number) : -1;
				newIndicesNext[j] = prev;
				newIndices.set(item, j);
			}

			for (let i = start; i <= end; i += 1) {
				const item = items[i];
				if (newIndices.has(item)) {
					const j = newIndices.get(item) as number;
					if (j !== -1) {
						temp[j] = mapped[i];
						tempFilled[j] = true;
						tempDisposers[j] = disposers[i];
						tempIndexSetters[j] = indexSetters[i];
						newIndices.set(item, newIndicesNext[j]);
					} else {
						disposers[i]();
					}
				} else {
					disposers[i]();
				}
			}

			const nextMapped: U[] = new Array(newLen);
			const nextDisposers: (() => void)[] = new Array(newLen);
			const nextIndexSetters: ((v: number) => void)[] = new Array(newLen);
			for (let p = 0; p < start; p += 1) {
				nextMapped[p] = mapped[p];
				nextDisposers[p] = disposers[p];
				nextIndexSetters[p] = indexSetters[p];
			}
			for (let j = start; j < newLen; j += 1) {
				if (tempFilled[j]) {
					nextMapped[j] = temp[j];
					nextDisposers[j] = tempDisposers[j];
					nextIndexSetters[j] = tempIndexSetters[j];
					nextIndexSetters[j](j);
				} else {
					makeRowInto(newItems[j], j, nextMapped, nextDisposers, nextIndexSetters);
				}
			}

			mapped = nextMapped;
			disposers = nextDisposers;
			indexSetters = nextIndexSetters;
			items = newItems.slice(0, newItems.length);
			len = newLen;
			return mapped;
		});
	};
}

export function indexArray<T, U>(list: () => T[], mapFn: (v: () => T, index: number) => U): () => U[] {
	let items: T[] = [];
	let mapped: U[] = [];
	let disposers: (() => void)[] = [];
	let valueSetters: ((v: T) => void)[] = [];
	let len = 0;

	function makeRowInto(item: T, pos: number): void {
		mapped[pos] = createRoot((d) => {
			disposers[pos] = d;
			const [val, setVal] = createSignal(item);
			valueSetters[pos] = setVal;
			return mapFn(val, pos);
		});
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
					makeRowInto(newItems[i], i);
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
