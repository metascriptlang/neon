import { Signal, untrack } from "./signal";
import { isTracking } from "./runtime";
import { isArray, isObject } from "std/typetraits";

type At<T, K extends keyof T> = T[K];
type SlotAt<T, K extends keyof T> = Slot<T[K]>;
type Element<T> = T extends Array<infer E> ? E : never;

export type Store<T> = Proxy<T, StoreTraps<T>>;
export type Draft<T> = Proxy<T, DraftTraps<T>>;
export type StoreValue<V> = V extends object ? Store<V> : V;
export type DraftValue<V> = V extends object ? Draft<V> : V;
export type SetStoreFunction<T> = (fn: (draft: Draft<T>) => void) => void;

export class WriteTheDraftInsideSetStore {
	private constructor() {}
}

let writing: int32 = 0;

function keyOf<K>(key: K): number | string {
	return key;
}

class SlotBase {
	touch: () => void = (): void => {};
}

class Slot<V> extends SlotBase {
	signal: Signal<V>;

	constructor(value: V) {
		super();
		const signal = new Signal<V>(value, (a: V, b: V): boolean => false);
		this.signal = signal;
		this.touch = (): void => { signal.set(signal.peek()); };
	}
}

function slotFor<V>(value: V): Slot<V> {
	return new Slot<V>(value);
}

class ChildBase {}

class StoreRoot {
	targets: Map<unknown, ChildBase> = new Map<unknown, ChildBase>();
}

class Child<V> extends ChildBase {
	traps: StoreTraps<V>;

	constructor(traps: StoreTraps<V>) {
		super();
		this.traps = traps;
	}
}

export class StoreTraps<T> {
	raw: T;
	private root: StoreRoot;
	private slots: Map<string, SlotBase> = new Map<string, SlotBase>();
	private children: Map<string, ChildBase> = new Map<string, ChildBase>();

	constructor(raw: T, root: StoreRoot) {
		this.raw = raw;
		this.root = root;
	}

	get<K extends keyof T>(target: T, key: K): StoreValue<T[K]> {
		when (isArray<T>()) {
			const index = keyOf(key);
			if (typeof index === "number") {
				const length = untrack<number>((): number => this.committed(target, "length"));
				if (index >= length) { throw new Error(`index ${index} is past the end of a store array of length ${length}`); }
			}
		}
		const value = this.committed(target, key);
		when (isObject<At<T, K>>()) {
			return new Proxy(value, this.child(`${key}`, value));
		} else {
			return value;
		}
	}

	set<K extends keyof T>(target: T, key: K, value: WriteTheDraftInsideSetStore): boolean {
		return false;
	}

	child<V>(name: string, value: V): StoreTraps<V> {
		when (isArray<V>()) {
			const found = this.children.get(name);
			if (found !== undefined) {
				const traps = (found as Child<V>).traps;
				if (traps.raw === value) { return traps; }
			}
			const traps = new StoreTraps<V>(value, this.root);
			this.children.set(name, new Child<V>(traps));
			return traps;
		} else {
			const found = this.root.targets.get(value as unknown);
			if (found !== undefined) { return (found as Child<V>).traps; }
			const traps = new StoreTraps<V>(value, this.root);
			this.root.targets.set(value as unknown, new Child<V>(traps));
			return traps;
		}
	}

	private committed<K extends keyof T>(target: T, key: K): T[K] {
		const name = `${key}`;
		const found = this.slots.get(name);
		if (found !== undefined) { return (found as SlotAt<T, K>).signal.get(); }
		if (!isTracking()) { return Reflect.get(target, key); }
		const slot = slotFor(Reflect.get(target, key));
		this.slots.set(name, slot);
		return slot.signal.get();
	}

	private slotOf<K extends keyof T>(target: T, key: K, old: T[K]): Slot<T[K]> {
		const name = `${key}`;
		const found = this.slots.get(name);
		if (found !== undefined) { return found as SlotAt<T, K>; }
		const slot = slotFor(old);
		this.slots.set(name, slot);
		return slot;
	}

	private notify(name: string): void {
		const found = this.slots.get(name);
		if (found !== undefined) { found.touch(); }
	}

	write<K extends keyof T>(target: T, key: K, value: T[K]): void {
		when (isArray<T>()) {
			const index = keyOf(key);
			const length = Reflect.get(target, "length");
			if (index === "length" || index === length) {
				if (index === "length") { this.capture(target, 0); }
				Reflect.set(target, key, value);
				this.restamp(target, length, index === length ? length : Reflect.get(target, "length"));
				return;
			}
		}
		const old = Reflect.get(target, key);
		if (old === value) { return; }
		const slot = this.slotOf(target, key, old);
		Reflect.set(target, key, value);
		slot.signal.set(value);
	}

	remove<K extends keyof T>(target: T, key: K): boolean {
		when (isArray<T>()) {
			const length = Reflect.get(target, "length");
			this.capture(target, length - 1);
			if (!Reflect.deleteProperty(target, key)) { return false; }
			this.restamp(target, length, length - 1);
			return true;
		} else {
			return false;
		}
	}

	capture(target: T, from: number): void {
		when (isArray<T>()) {
			this.slotOf(target, "length", target.length);
			for (let i = from; i < target.length; i += 1) {
				const name = `${i}`;
				if (this.slots.get(name) === undefined) { this.slots.set(name, slotFor(target[i])); }
			}
		}
	}

	restamp(target: T, before: number, from: number): void {
		when (isArray<T>()) {
			const after = target.length;
			const end = before > after ? before : after;
			for (let i = from; i < end; i += 1) {
				const found = this.slots.get(`${i}`);
				if (found === undefined) { continue; }
				if (i >= after) {
					found.touch();
					continue;
				}
				const slot = found as Slot<Element<T>>;
				if (slot.signal.peek() !== target[i]) { slot.signal.set(target[i]); }
			}
			if (after !== before) { this.slotOf(target, "length", before).signal.set(after); }
		}
	}
}

export class DraftTraps<T> {
	private traps: StoreTraps<T>;

	constructor(traps: StoreTraps<T>) {
		this.traps = traps;
	}

	get<K extends keyof T>(target: T, key: K): DraftValue<T[K]> {
		const value = Reflect.get(target, key);
		when (isObject<At<T, K>>()) {
			return new Proxy(value, new DraftTraps(this.traps.child(`${key}`, value)));
		} else {
			return value;
		}
	}

	set<K extends keyof T>(target: T, key: K, value: T[K]): boolean {
		when (debug) {
			if (writing === 0) { throw new Error("a store draft was written after its setStore call returned"); }
		}
		this.traps.write(target, key, value);
		return true;
	}

	deleteProperty<K extends keyof T>(target: T, key: K): boolean {
		return this.traps.remove(target, key);
	}

	shift(target: T): Element<T> {
		when (isArray<T>()) {
			const length = target.length;
			this.traps.capture(target, 0);
			const first = target.shift();
			this.traps.restamp(target, length, 0);
			return first;
		} else {
			throw new Error("shift() of a store draft that is not an array");
		}
	}

	splice(target: T, start: number, count: number): Element<T>[] {
		when (isArray<T>()) {
			const length = target.length;
			this.traps.capture(target, start);
			const removed = target.splice(start, count);
			this.traps.restamp(target, length, start);
			return removed;
		} else {
			throw new Error("splice() of a store draft that is not an array");
		}
	}
}

export function createStore<T extends object>(value: T): [Store<T>, SetStoreFunction<T>] {
	const traps = new StoreTraps<T>(value, new StoreRoot());
	const setStore = (fn: (draft: Draft<T>) => void): void => {
		untrack<int32>((): int32 => {
			writing += 1;
			try {
				fn(new Proxy(traps.raw, new DraftTraps<T>(traps)));
			} finally {
				writing -= 1;
			}
			return 0;
		});
	};
	return [new Proxy(value, traps), setStore];
}
