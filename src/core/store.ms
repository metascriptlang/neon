import { Signal, untrack } from "./signal";
import { isTracking, createComputed, readSource } from "./runtime";
import { Computation, EFFECT_PURE, RUN_UNCHANGED, CONFIG_AUTO_DISPOSE } from "./types";
import { isArray, isObject } from "std/typetraits";
import { proxyHandler } from "std/core/proxy";
import { fieldsLiteral, fieldsDo, keyedBy } from "./storeFields";

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
let direct: int32 = 0;

function keyOf<K>(key: K): number | string {
	return key;
}

class SlotBase {
	touch: () => void = (): void => {};
}

class Slot<V> extends SlotBase {
	signal: Signal<V>;

	constructor(value: V, ownedWrite: boolean) {
		super();
		const signal = new Signal<V>(value, (a: V, b: V): boolean => false, ownedWrite);
		this.signal = signal;
		this.touch = (): void => { signal.set(signal.peek()); };
	}
}

function slotFor<V>(value: V, ownedWrite: boolean): Slot<V> {
	return new Slot<V>(value, ownedWrite);
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
	derived: boolean = false;
	deriving: boolean = false;
	pull: () => void = (): void => {};
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
		this.fresh();
		return Reflect.has(this.raw, key);
	}

	mergeIn(next: T, key: string | null): void {
		this.privatize();
		when (isArray<T>()) {
			mergeRows(this, next, key);
		} else {
			fieldsDo(this.raw, "mergeField", new MergePlan<T>(this, next, key));
		}
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
		this.fresh();
		const target = this.raw;
		const name = `${key}`;
		const found = this.slots.get(name);
		if (found !== undefined) { return (found as Slot<T[K]>).signal.get(); }
		if (!isTracking()) { return Reflect.get(target, key); }
		const slot = slotFor(Reflect.get(target, key), this.root.derived);
		this.slots.set(name, slot);
		return slot.signal.get();
	}

	private slotOf<K extends keyof T>(target: T, key: K, old: T[K]): Slot<T[K]> {
		const name = `${key}`;
		const found = this.slots.get(name);
		if (found !== undefined) { return found as Slot<T[K]>; }
		const slot = slotFor(old, this.root.derived);
		this.slots.set(name, slot);
		return slot;
	}

	fresh(): void {
		if (this.root.derived && !this.root.deriving && isTracking()) { this.root.pull(); }
	}

	private notify(name: string): void {
		const found = this.slots.get(name);
		if (found !== undefined) { found.touch(); }
	}

	write<K extends keyof T>(key: K, value: T[K]): void {
		this.privatize();
		const target = this.raw;
		if (direct > 0) {
			Reflect.set(target, key, value);
			return;
		}
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
			if (direct > 0) { return; }
			const target = this.raw;
			this.slotOf(target, "length", target.length);
			for (let i = from; i < target.length; i += 1) {
				const name = `${i}`;
				if (this.slots.get(name) === undefined) { this.slots.set(name, slotFor(target[i], this.root.derived)); }
			}
		}
	}

	restamp(before: number, from: number): void {
		when (isArray<T>()) {
			if (direct > 0) { return; }
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

	storeTraps(): StoreTraps<T> {
		return this.traps;
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

	splice(target: T, start: number, count: number): void {
		when (isArray<T>()) {
			this.traps.capture(start);
			const raw = this.traps.raw;
			const length = raw.length;
			raw.splice(start, count);
			this.traps.restamp(length, start);
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

class MergePlan<T> {
	traps: StoreTraps<T>;
	next: T;
	key: string | null;

	constructor(traps: StoreTraps<T>, next: T, key: string | null) {
		this.traps = traps;
		this.next = next;
		this.key = key;
	}
}

function keyText<V>(value: V): string {
	return `${value}`;
}

function keyNotAtomic(name: string): string {
	throw new Error(`reconcile key '${name}' is not a number, string or boolean field`);
}

function sameEntity<V>(old: V, next: V, key: string | null): boolean {
	if (key === null) { return true; }
	const was: string | null = keyedBy(old, key);
	const now: string | null = keyedBy(next, key);
	return was === null || now === null || was === now;
}

function mergeField<T, K extends keyof T>(plan: MergePlan<T>, name: K): boolean {
	const traps = plan.traps;
	const next = Reflect.get(plan.next, name);
	when (isObject<T[K]>()) {
		const old = Reflect.get(traps.raw, name);
		if (old === next) { return true; }
		if (sameEntity(old, next, plan.key)) {
			traps.child(name, old).mergeIn(next, plan.key);
		} else {
			traps.write(name, next);
		}
	} else {
		traps.write(name, next);
	}
	return true;
}

function mergedRow<E>(traps: StoreTraps<E[]>, index: number, old: E, next: E, key: string | null): E {
	if (old === next || !sameEntity(old, next, key)) { return next; }
	const row = traps.child(index, old);
	row.mergeIn(next, key);
	return row.raw;
}

function mergeRows<E>(traps: StoreTraps<E[]>, next: E[], key: string | null): void {
	const before = traps.raw.length;
	const arranged: E[] = [];
	when (isObject<E>()) {
		const old = traps.raw;
		let i: number = 0;
		if (key !== null) {
			const end = before < next.length ? before : next.length;
			while (i < end) {
				if (old[i] !== next[i] && !sameKeyed(old[i], next[i], key)) { break; }
				arranged.push(mergedRow(traps, i, old[i], next[i], key));
				i += 1;
			}
			const byKey = new Map<string, number[]>();
			for (let j = i; j < before; j += 1) {
				const name: string | null = keyedBy(old[j], key);
				if (name === null) { continue; }
				const found = byKey.get(name);
				if (found === undefined) { byKey.set(name, [j]); } else { found.push(j); }
			}
			while (i < next.length) {
				const name: string | null = keyedBy(next[i], key);
				let at: number = -1;
				if (name === null) {
					if (i < before) { at = i; }
				} else {
					const found = byKey.get(name);
					if (found !== undefined && found.length > 0) { at = found.shift() as number; }
				}
				arranged.push(at < 0 ? next[i] : mergedRow(traps, at, old[at], next[i], key));
				i += 1;
			}
		} else {
			while (i < next.length) {
				arranged.push(i < before ? mergedRow(traps, i, old[i], next[i], key) : next[i]);
				i += 1;
			}
		}
	} else {
		for (let i = 0; i < next.length; i += 1) { arranged.push(next[i]); }
	}
	for (let i = 0; i < arranged.length; i += 1) {
		if (i >= before || traps.raw[i] !== arranged[i]) { traps.write(i, arranged[i]); }
	}
	if (arranged.length < before) { traps.write("length", arranged.length); }
}

function sameKeyed<V>(a: V, b: V, key: string): boolean {
	const x: string | null = keyedBy(a, key);
	return x !== null && x === keyedBy(b, key);
}

export function reconcile<T>(value: T, key: string | null = "id"): (draft: Draft<T>) => void {
	return (draft: Draft<T>): void => {
		when (debug) {
			if (writing === 0) { throw new Error("reconcile was applied outside a setStore call"); }
		}
		const traps = proxyHandler(draft).storeTraps();
		if (key !== null) {
			const was: string | null = keyedBy(traps.raw, key);
			if (was !== null && was !== keyedBy(value, key)) {
				throw new Error("Cannot reconcile states with different identity");
			}
		}
		traps.mergeIn(value, key);
	};
}

export function snapshot<T>(store: Store<T>): T {
	const traps = proxyHandler(store);
	traps.fresh();
	return traps.snapshot();
}

function setterOf<T>(traps: StoreTraps<T>): SetStoreFunction<T> {
	return (fn: (draft: Draft<T>) => void): void => {
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
}

function deriveStore<T extends object>(seed: T, derive: (draft: Draft<T>) => void): StoreTraps<T> {
	const root = new StoreRoot();
	root.derived = true;
	const traps = new StoreTraps<T>(seed, root);
	const draft = new Proxy(seed, new DraftTraps<T>(traps));
	let first = true;
	const node = createComputed((self: Computation, create: boolean): int32 => {
		root.deriving = true;
		writing += 1;
		if (first) { direct += 1; }
		try {
			derive(draft);
		} finally {
			if (first) {
				direct -= 1;
				first = false;
			}
			writing -= 1;
			root.deriving = false;
		}
		return RUN_UNCHANGED;
	}, EFFECT_PURE, false, false, null);
	node.config = node.config & ~CONFIG_AUTO_DISPOSE;
	root.pull = (): void => { readSource(node); };
	return traps;
}

export function createStore<T extends object>(first: T | ((draft: Draft<T>) => void), seed: T | null = null): [Store<T>, SetStoreFunction<T>] {
	if (typeof first === "function") {
		if (seed === null) { throw new Error("createStore(fn) needs the seed the derive starts from: createStore(fn, seed)"); }
		const fn = first;
		const traps = deriveStore<T>(seed, (draft: Draft<T>): void => { fn(draft); });
		return [new Proxy(seed, traps), setterOf<T>(traps)];
	}
	const value = first as T;
	const traps = new StoreTraps<T>(value, new StoreRoot());
	return [new Proxy(value, traps), setterOf<T>(traps)];
}

export function createProjection<T extends object>(fn: (draft: Draft<T>) => void, seed: T): Store<T> {
	return new Proxy(seed, deriveStore<T>(seed, fn));
}
