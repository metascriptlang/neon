import { onCleanup } from "./cleanup";
import { createRoot } from "./owner";
import { untrack, accessor, Accessor, Signal } from "./signal";

enum MapMode { Identity, Keyed, Position }

class IndexCell {
	pos: number;
	sig: Signal<number> | null;

	constructor(pos: number) {
		this.pos = pos;
		this.sig = null;
	}

	read(): number {
		if (this.sig === null) { this.sig = new Signal<number>(this.pos); }
		return (this.sig as Signal<number>).get();
	}

	write(next: number): void {
		this.pos = next;
		if (this.sig !== null) { (this.sig as Signal<number>).set(next); }
	}
}

const noIndex: Accessor<number> = accessor((): number => {
	throw new Error("mapArray: this row has no index accessor: a position-keyed row receives its index as a number, and a row emitted as not reading its index never gets one");
});

function disposeAll(ds: (() => void)[]): void {
	for (const d of ds) { d(); }
}

export function mapArray<T, U>(
	list: () => T[],
	mapFn: (item: T, index: Accessor<number>) => U,
	fallback: (() => U) | null = null,
	usesIndex: boolean = true,
): () => U[] {
	return mapRows<T, T, U>(
		list,
		MapMode.Identity,
		usesIndex,
		(items: T[]): T[] => items.slice(0, items.length),
		(item: T, pos: number, cell: Signal<T> | null, index: Accessor<number>): U => mapFn(item, index),
		fallback,
	);
}

export function mapArrayKeyedBy<T, K, U>(
	list: () => T[],
	keyOf: (item: T) => K,
	mapFn: (item: Accessor<T>, index: Accessor<number>) => U,
	fallback: (() => U) | null = null,
	usesIndex: boolean = true,
): () => U[] {
	return mapRows<T, K, U>(
		list,
		MapMode.Keyed,
		usesIndex,
		(items: T[]): K[] => {
			const ks: K[] = new Array(items.length);
			for (let j = 0; j < items.length; j += 1) { ks[j] = keyOf(items[j]); }
			return ks;
		},
		(item: T, pos: number, cell: Signal<T> | null, index: Accessor<number>): U => {
			const c = cell as Signal<T>;
			return mapFn(accessor((): T => c.get()), index);
		},
		fallback,
	);
}

export function mapArrayByPosition<T, U>(
	list: () => T[],
	mapFn: (item: Accessor<T>, index: number) => U,
	fallback: (() => U) | null = null,
): () => U[] {
	return mapRows<T, number, U>(
		list,
		MapMode.Position,
		false,
		(items: T[]): number[] => [],
		(item: T, pos: number, cell: Signal<T> | null, index: Accessor<number>): U => {
			const c = cell as Signal<T>;
			return mapFn(accessor((): T => c.get()), pos);
		},
		fallback,
	);
}

function mapRows<T, K, U>(
	list: () => T[],
	mode: MapMode,
	usesIndex: boolean,
	keysOf: (items: T[]) => K[],
	make: (item: T, pos: number, cell: Signal<T> | null, index: Accessor<number>) => U,
	fallback: (() => U) | null,
): () => U[] {
	const hasKeys = mode !== MapMode.Position;
	const hasCells = mode !== MapMode.Identity;
	const hasIdx = mode !== MapMode.Position && usesIndex;
	let keys: K[] = [];
	let mapped: U[] = [];
	let disposers: (() => void)[] = [];
	let cells: Signal<T>[] = [];
	let idxs: IndexCell[] = [];
	let len = 0;
	let fbLive = false;
	let fbDispose: (() => void) | null = null;

	function makeRowInto(
		item: T,
		pos: number,
		mapStore: U[],
		dispStore: (() => void)[],
		cellStore: Signal<T>[],
		idxStore: IndexCell[],
		fresh: (() => void)[],
	): void {
		mapStore[pos] = createRoot((d) => {
			dispStore[pos] = d;
			fresh.push(d);
			let cell: Signal<T> | null = null;
			if (hasCells) {
				const c = new Signal<T>(item);
				cellStore[pos] = c;
				cell = c;
			}
			let index: Accessor<number> = noIndex;
			if (hasIdx) {
				const ic = new IndexCell(pos);
				idxStore[pos] = ic;
				index = accessor((): number => ic.read());
			}
			return make(item, pos, cell, index);
		});
	}

	function dropFallback(): void {
		if (fbLive && fbDispose !== null) { (fbDispose as () => void)(); }
		fbDispose = null;
		fbLive = false;
	}

	onCleanup(() => {
		disposeAll(disposers);
		dropFallback();
	});

	return () => {
		const newItems = list();
		const newLen = newItems.length;
		return untrack((): U[] => {
			if (newLen === 0) {
				if (len !== 0) {
					const gone = disposers;
					keys = [];
					mapped = [];
					disposers = [];
					cells = [];
					idxs = [];
					len = 0;
					disposeAll(gone);
				}
				if (fallback !== null && !fbLive) {
					const fb = fallback as () => U;
					let row: U;
					try {
						row = createRoot((d) => { fbDispose = d; return fb(); });
					} catch (e) {
						if (fbDispose !== null) { (fbDispose as () => void)(); }
						fbDispose = null;
						throw e;
					}
					fbLive = true;
					const shown: U[] = [];
					shown.push(row);
					mapped = shown;
				}
				return mapped;
			}

			const newKeys = keysOf(newItems);

			if (len === 0) {
				const firstMapped: U[] = new Array(newLen);
				const firstDisposers: (() => void)[] = new Array(newLen);
				const firstCells: Signal<T>[] = new Array(hasCells ? newLen : 0);
				const firstIdxs: IndexCell[] = new Array(hasIdx ? newLen : 0);
				const fresh: (() => void)[] = [];
				try {
					for (let j = 0; j < newLen; j += 1) {
						makeRowInto(newItems[j], j, firstMapped, firstDisposers, firstCells, firstIdxs, fresh);
					}
				} catch (e) {
					disposeAll(fresh);
					throw e;
				}
				dropFallback();
				mapped = firstMapped;
				disposers = firstDisposers;
				cells = firstCells;
				idxs = firstIdxs;
				keys = newKeys;
				len = newLen;
				return mapped;
			}

			let start = 0;
			const minLen = len < newLen ? len : newLen;
			while (start < minLen && (!hasKeys || keys[start] === newKeys[start])) {
				if (hasCells) { cells[start].set(newItems[start]); }
				start += 1;
			}

			let end = len - 1;
			let newEnd = newLen - 1;
			while (hasKeys && end >= start && newEnd >= start && keys[end] === newKeys[newEnd]) {
				end -= 1;
				newEnd -= 1;
			}

			if (start === newLen && len === newLen) {
				keys = newKeys;
				return mapped;
			}

			const dif = newLen - len;
			const temp: U[] = new Array(newLen);
			const tempFilled: boolean[] = new Array(newLen);
			const tempDisposers: (() => void)[] = new Array(newLen);
			const tempCells: Signal<T>[] = new Array(hasCells ? newLen : 0);
			const tempIdxs: IndexCell[] = new Array(hasIdx ? newLen : 0);
			for (let k = 0; k < newLen; k += 1) { tempFilled[k] = false; }

			const newIndices = new Map<K, number>();
			const newIndicesNext: number[] = new Array(newEnd + 1);
			if (hasKeys) {
				for (let j = newEnd; j >= start; j -= 1) {
					const k = newKeys[j];
					newIndicesNext[j] = newIndices.has(k) ? (newIndices.get(k) as number) : -1;
					newIndices.set(k, j);
				}
			}

			const removed: (() => void)[] = [];
			for (let i = start; i <= end; i += 1) {
				if (hasKeys) {
					const k = keys[i];
					if (newIndices.has(k)) {
						const j = newIndices.get(k) as number;
						if (j !== -1) {
							temp[j] = mapped[i];
							tempFilled[j] = true;
							tempDisposers[j] = disposers[i];
							if (hasCells) { tempCells[j] = cells[i]; }
							if (hasIdx) { tempIdxs[j] = idxs[i]; }
							newIndices.set(k, newIndicesNext[j]);
							continue;
						}
					}
				}
				removed.push(disposers[i]);
			}

			const fresh: (() => void)[] = [];
			try {
				for (let j = start; j <= newEnd; j += 1) {
					if (tempFilled[j]) { continue; }
					makeRowInto(newItems[j], j, temp, tempDisposers, tempCells, tempIdxs, fresh);
				}
			} catch (e) {
				disposeAll(fresh);
				throw e;
			}

			for (let i = 0; i < start; i += 1) {
				temp[i] = mapped[i];
				tempDisposers[i] = disposers[i];
				if (hasCells) { tempCells[i] = cells[i]; }
				if (hasIdx) { tempIdxs[i] = idxs[i]; }
			}
			for (let j = start; j <= newEnd; j += 1) {
				if (hasCells) { tempCells[j].set(newItems[j]); }
				if (hasIdx) { tempIdxs[j].write(j); }
			}
			for (let j = newEnd + 1; j < newLen; j += 1) {
				temp[j] = mapped[j - dif];
				tempDisposers[j] = disposers[j - dif];
				if (hasCells) {
					tempCells[j] = cells[j - dif];
					tempCells[j].set(newItems[j]);
				}
				if (hasIdx) {
					tempIdxs[j] = idxs[j - dif];
					if (dif !== 0) { tempIdxs[j].write(j); }
				}
			}

			mapped = temp;
			disposers = tempDisposers;
			cells = tempCells;
			idxs = tempIdxs;
			keys = newKeys;
			len = newLen;
			disposeAll(removed);
			return mapped;
		});
	};
}

export function repeat<U>(
	count: () => number,
	mapFn: (index: number) => U,
	from: (() => number) | null = null,
	fallback: (() => U) | null = null,
): () => U[] {
	let mapped: U[] = [];
	let disposers: (() => void)[] = [];
	let offset: int32 = 0;
	let len: int32 = 0;
	let fbLive = false;
	let fbDispose: (() => void) | null = null;

	function dropFallback(): void {
		if (fbLive && fbDispose !== null) { (fbDispose as () => void)(); }
		fbDispose = null;
		fbLive = false;
	}

	onCleanup(() => {
		disposeAll(disposers);
		dropFallback();
	});

	return () => {
		const wanted = count();
		const origin = from === null ? 0 : (from as () => number)();
		if (wanted < 0 || Math.floor(wanted) !== wanted) {
			throw new Error("Repeat: count must be a non-negative integer, got " + wanted.toString());
		}
		if (Math.floor(origin) !== origin) {
			throw new Error("Repeat: from must be an integer, got " + origin.toString());
		}
		const newLen = wanted as int32;
		const start = origin as int32;
		return untrack((): U[] => {
			if (newLen === 0) {
				if (len !== 0) {
					const gone = disposers;
					mapped = [];
					disposers = [];
					len = 0;
					offset = 0;
					disposeAll(gone);
				}
				if (fallback !== null && !fbLive) {
					const fb = fallback as () => U;
					let row: U;
					try {
						row = createRoot((d) => { fbDispose = d; return fb(); });
					} catch (e) {
						if (fbDispose !== null) { (fbDispose as () => void)(); }
						fbDispose = null;
						throw e;
					}
					fbLive = true;
					const shown: U[] = [];
					shown.push(row);
					mapped = shown;
				}
				return mapped;
			}

			const to = start + newLen;
			const prevTo = offset + len;
			const keepStart = start > offset ? start : offset;
			const keepEnd = to < prevTo ? to : prevTo;

			const next: U[] = new Array(newLen);
			const nextDisposers: (() => void)[] = new Array(newLen);
			for (let i = keepStart; i < keepEnd; i += 1) {
				next[i - start] = mapped[i - offset];
				nextDisposers[i - start] = disposers[i - offset];
			}
			const fresh: (() => void)[] = [];
			try {
				for (let i = start; i < to; i += 1) {
					if (i >= keepStart && i < keepEnd) { continue; }
					next[i - start] = createRoot((d) => {
						nextDisposers[i - start] = d;
						fresh.push(d);
						return mapFn(i);
					});
				}
			} catch (e) {
				disposeAll(fresh);
				throw e;
			}

			if (len === 0) {
				dropFallback();
			} else {
				for (let i = offset; i < prevTo; i += 1) {
					if (i < start || i >= to) { disposers[i - offset](); }
				}
			}
			mapped = next;
			disposers = nextDisposers;
			offset = start;
			len = newLen;
			return mapped;
		});
	};
}
