import { Source, CONFIG_OWNED_WRITE } from "./types";
import { newSource, readSource, isStaged, writeSource, assertWritable, isTracking, setTracking } from "./runtime";

export class Cell<T> {
	value: T;
	pending: T;

	constructor(initialValue: T) {
		this.value = initialValue;
		this.pending = initialValue;
	}
}

export interface SignalOptions<T> {
	equals?: ((a: T, b: T) => boolean) | false;
	ownedWrite?: boolean;
}

export function isEqual<T>(equals: ((a: T, b: T) => boolean) | null, a: T, b: T): boolean {
	return equals === null ? a === b : equals(a, b);
}

export class Signal<T> {
	private cell: Cell<T>;
	private node: Source;
	private equals: ((a: T, b: T) => boolean) | null;

	constructor(initialValue: T, equals: ((a: T, b: T) => boolean) | null = null, ownedWrite: boolean = false) {
		this.cell = new Cell<T>(initialValue);
		this.node = newSource(ownedWrite ? CONFIG_OWNED_WRITE : 0);
		this.equals = equals;
	}

	get(): T {
		return readSource(this.node) ? this.cell.pending : this.cell.value;
	}

	peek(): T {
		return isStaged(this.node) ? this.cell.pending : this.cell.value;
	}

	set(newValue: T): void {
		assertWritable(this.node);
		if (isEqual(this.equals, this.peek(), newValue)) { return; }
		const wasStaged = isStaged(this.node);
		this.cell.pending = newValue;
		if (this.node.commit === null) {
			const cell = this.cell;
			this.node.commit = (): void => { cell.value = cell.pending; };
		}
		writeSource(this.node, wasStaged);
	}

	update(fn: (current: T) => T): void {
		this.set(fn(this.peek()));
	}
}

export type Accessor<T> = distinct (() => T);
export type Setter<T> = (v: T | ((prev: T) => T)) => void;

export function accessor<T>(f: () => T): Accessor<T> {
	return f as Accessor<T>;
}

export function valueOf<T>(this a: Accessor<T>): T {
	return a();
}

export function createSignal<T>(initialValue: T, options?: SignalOptions<T>): [Accessor<T>, Setter<T>] {
	let equals: ((a: T, b: T) => boolean) | null = null;
	let ownedWrite = false;
	if (options !== undefined) {
		const given = options.equals;
		if (typeof given === "function") {
			equals = given;
		} else if (given === false) {
			equals = (a: T, b: T): boolean => false;
		}
		ownedWrite = options.ownedWrite === true;
	}
	const signal = new Signal<T>(initialValue, equals, ownedWrite);
	return [
		accessor(() => signal.get()),
		(v: T | ((prev: T) => T)) => {
			if (typeof v === "function") {
				signal.set(v(signal.peek()));
			} else {
				signal.set(v);
			}
		},
	];
}

export function untrack<T>(fn: () => T): T {
	const prev = isTracking();
	setTracking(false);
	try {
		return fn();
	} finally {
		setTracking(prev);
	}
}
