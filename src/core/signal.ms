// Signal — reactive state cell. Solid.js-style fine-grained reactivity over the graph
// engine in runtime.ms: reading inside a running computation links both ways; setting
// marks observers Stale and drains the effect queue.

import { Source, Computation, CompState } from "./types";
import { getListener, registerDependency, enqueue, runQueue, getBatchDepth, setBatchDepth, setListener } from "./runtime";

export class Signal<T> {
	private value: T;
	private node: Source;

	constructor(initialValue: T) {
		this.value = initialValue;
		this.node = { observers: [], observerSlots: [] };
	}

	get(): T {
		const l = getListener();
		if (l !== null) { registerDependency(this.node, l); }
		return this.value;
	}

	peek(): T {
		return this.value;
	}

	set(newValue: T): void {
		if (this.value === newValue) return;
		this.value = newValue;
		const observers = this.node.observers;
		for (let i = 0; i < observers.length; i += 1) {
			const o = observers[i];
			if (!o.disposed && o.state === CompState.Clean) {
				o.state = CompState.Stale;
				enqueue(o);
			}
		}
		if (getBatchDepth() === 0) { runQueue(); }
	}

	update(fn: (current: T) => T): void {
		this.set(fn(this.value));
	}
}

export function createSignal<T>(initialValue: T): [() => T, (v: T) => void] {
	const signal = new Signal<T>(initialValue);
	return [
		() => signal.get(),
		(v: T) => signal.set(v),
	];
}

// Read without subscribing.
export function untrack<T>(fn: () => T): T {
	const prev = getListener();
	setListener(null);
	const result = fn();
	setListener(prev);
	return result;
}

// Defer effect drain until the outermost batch completes.
export function batch(fn: () => void): void {
	setBatchDepth(getBatchDepth() + 1);
	fn();
	setBatchDepth(getBatchDepth() - 1);
	if (getBatchDepth() === 0) { runQueue(); }
}
