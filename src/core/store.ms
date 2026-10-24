import { Signal, untrack } from "./signal";
import { isTracking } from "./runtime";
import { isArray, isObject } from "std/typetraits";
import { proxyHandler } from "std/core/proxy";
import { fieldsLiteral } from "./storeFields";

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

function copyOf<T>(value: T): T {
	when (isArray<T>()) {
		return value.slice(0, value.length);
	} else {
		const copy: T = { ...value };
		return copy;
	}
}

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
	private origin: T;
	private owned: boolean = false;
	private privatizeUp: () => void = (): void => {};
	private adoptUp: (old: T, copy: T) => void = (old: T, copy: T): void => {};
	private root: StoreRoot;
	private slots: Map<string, SlotBase> = new Map<string, SlotBase>();
	private children: Map<string, ChildBase> = new Map<string, ChildBase>();

	constructor(raw: T, root: StoreRoot) {
		this.raw = raw;
		this.origin = raw;
		this.root = root;
	}

	get<K extends keyof T>(target: T, key: K): StoreValue<T[K]> {
		when (isArray<T>()) {
			const index = keyOf(key);
			if (typeof index === "number") {
				const length = untrack<number>((): number => this.committed("length"));
				if (index >= length) { throw new Error(`index ${index} is past the end of a store array of length ${length}`); }
			}
		}
		const value = this.committed(key);
		when (isObject<T[K]>()) {
			return new Proxy(value, this.child(key, value));
		} else {
			return value;
		}
	}

	set<K extends keyof T>(target: T, key: K, value: WriteTheDraftInsideSetStore): boolean {
		return false;
	}

	has<K extends keyof T>(target: T, key: K): boolean {
		return Reflect.has(this.raw, key);
	}

	snapshot(): T {
		if (!this.owned) { return this.raw; }
		when (isArray<T>()) {
			return snapshotArray(this);
		} else {
			return fieldsLiteral(this.raw, "snapshotField", this);
		}
	}

	child<K extends keyof T>(key: K, value: T[K]): StoreTraps<T[K]> {
		const name = `${key}`;
		when (isArray<T[K]>()) {
			const found = this.children.get(name);
			if (found !== undefined) {
				const traps = (found as Child<T[K]>).traps;
				if (traps.raw === value || traps.origin === value) { return traps; }
			}
			const traps = this.born(key, value);
			this.children.set(name, new Child<T[K]>(traps));
			return traps;
		} else {
			const found = this.root.targets.get(value as unknown);
			if (found !== undefined) { return (found as Child<T[K]>).traps; }
			const traps = this.born(key, value);
			this.root.targets.set(value as unknown, new Child<T[K]>(traps));
			return traps;
		}
	}

	private born<K extends keyof T>(key: K, value: T[K]): StoreTraps<T[K]> {
		const traps = new StoreTraps<T[K]>(value, this.root);
		traps.privatizeUp = (): void => { this.privatize(); };
		traps.adoptUp = (old: T[K], copy: T[K]): void => { this.replaceChild(key, old, copy); };
		return traps;
	}

	private replaceChild<K extends keyof T>(key: K, old: T[K], copy: T[K]): void {
		const raw = this.raw;
		when (isArray<T>()) {
			for (let i = 0; i < raw.length; i += 1) {
				if (Reflect.get(raw, i) === old) {
					Reflect.set(raw, i, copy);
					return;
				}
			}
		} else {
			if (Reflect.get(raw, key) === old) { Reflect.set(raw, key, copy); }
		}
	}

	privatize(): void {
		if (this.owned) { return; }
		this.privatizeUp();
		const old = this.raw;
		const copy = copyOf<T>(old);
		when (!isArray<T>()) {
			const found = this.root.targets.get(this.raw as unknown);
			if (found !== undefined) { this.root.targets.set(copy as unknown, found); }
		}
		this.raw = copy;
		this.owned = true;
		this.adoptUp(old, copy);
	}

	private committed<K extends keyof T>(key: K): T[K] {
		const target = this.raw;
		const name = `${key}`;
		const found = this.slots.get(name);
		if (found !== undefined) { return (found as Slot<T[K]>).signal.get(); }
		if (!isTracking()) { return Reflect.get(target, key); }
		const slot = slotFor(Reflect.get(target, key));
		this.slots.set(name, slot);
		return slot.signal.get();
	}

	private slotOf<K extends keyof T>(target: T, key: K, old: T[K]): Slot<T[K]> {
		const name = `${key}`;
		const found = this.slots.get(name);
		if (found !== undefined) { return found as Slot<T[K]>; }
		const slot = slotFor(old);
		this.slots.set(name, slot);
		return slot;
	}

	private notify(name: string): void {
		const found = this.slots.get(name);
		if (found !== undefined) { found.touch(); }
	}

	write<K extends keyof T>(key: K, value: T[K]): void {
		this.privatize();
		const target = this.raw;
		when (isArray<T>()) {
			const index = keyOf(key);
			const length = Reflect.get(target, "length");
			if (index === "length" || index === length) {
				if (index === "length") { this.capture(0); }
				Reflect.set(target, key, value);
				this.restamp(length, index === length ? length : Reflect.get(target, "length"));
				return;
			}
		}
		const old = Reflect.get(target, key);
		if (old === value) { return; }
		const slot = this.slotOf(target, key, old);
		Reflect.set(target, key, value);
		slot.signal.set(value);
	}

	remove<K extends keyof T>(key: K): boolean {
		when (isArray<T>()) {
			this.privatize();
			const target = this.raw;
			const length = Reflect.get(target, "length");
			this.capture(length - 1);
			if (!Reflect.deleteProperty(target, key)) { return false; }
			this.restamp(length, length - 1);
			return true;
		} else {
			return false;
		}
	}

	capture(from: number): void {
		when (isArray<T>()) {
			this.privatize();
			const target = this.raw;
			this.slotOf(target, "length", target.length);
			for (let i = from; i < target.length; i += 1) {
				const name = `${i}`;
				if (this.slots.get(name) === undefined) { this.slots.set(name, slotFor(target[i])); }
			}
		}
	}

	restamp(before: number, from: number): void {
		when (isArray<T>()) {
			const target = this.raw;
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
		const value = Reflect.get(this.traps.raw, key);
		when (isObject<T[K]>()) {
			return new Proxy(value, new DraftTraps(this.traps.child(key, value)));
		} else {
			return value;
		}
	}

	set<K extends keyof T>(target: T, key: K, value: T[K]): boolean {
		when (debug) {
			if (writing === 0) { throw new Error("a store draft was written after its setStore call returned"); }
		}
		this.traps.write(key, value);
		return true;
	}

	has<K extends keyof T>(target: T, key: K): boolean {
		return Reflect.has(this.traps.raw, key);
	}

	deleteProperty<K extends keyof T>(target: T, key: K): boolean {
		return this.traps.remove(key);
	}

	shift(target: T): Element<T> {
		when (isArray<T>()) {
			this.traps.capture(0);
			const raw = this.traps.raw;
			const length = raw.length;
			const first = raw.shift();
			this.traps.restamp(length, 0);
			return first;
		} else {
			throw new Error("shift() of a store draft that is not an array");
		}
	}

	splice(target: T, start: number, count: number): Element<T>[] {
		when (isArray<T>()) {
			this.traps.capture(start);
			const raw = this.traps.raw;
			const length = raw.length;
			const removed = raw.splice(start, count);
			this.traps.restamp(length, start);
			return removed;
		} else {
			throw new Error("splice() of a store draft that is not an array");
		}
	}
}

function snapshotField<T, K extends keyof T>(traps: StoreTraps<T>, key: K): T[K] {
	const value = Reflect.get(traps.raw, key);
	when (isObject<T[K]>()) {
		return traps.child(key, value).snapshot();
	} else {
		return value;
	}
}

function snapshotArray<E>(traps: StoreTraps<E[]>): E[] {
	const out: E[] = [];
	for (let i = 0; i < traps.raw.length; i += 1) { out.push(snapshotField(traps, i)); }
	return out;
}

export function snapshot<T>(store: Store<T>): T {
	return proxyHandler(store).snapshot();
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
