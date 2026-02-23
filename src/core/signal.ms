// Signal - Reactive State Primitive
// Solid.js-inspired fine-grained reactivity

// Global effect tracking context
let currentEffect: (() => void) | null = null;

export class Signal<T> {
	private value: T;
	private subscribers: Set<() => void>;

	constructor(initialValue: T) {
		this.value = initialValue;
		this.subscribers = new Set();
	}

	// Get current value (auto-subscribes if in effect)
	get(): T {
		if (currentEffect !== null) {
			this.subscribers.add(currentEffect);
		}
		return this.value;
	}

	// Set new value (triggers subscribers)
	set(newValue: T): void {
		if (this.value !== newValue) {
			this.value = newValue;
			this.notify();
		}
	}

	// Update with function
	update(fn: (current: T) => T): void {
		this.set(fn(this.value));
	}

	private notify(): void {
		this.subscribers.forEach(effect => effect());
	}
}

// Factory function for convenience
export function createSignal<T>(initialValue: T): [() => T, (v: T) => void] {
	const signal = new Signal(initialValue);
	return [
		() => signal.get(),
		(v: T) => signal.set(v)
	];
}

// Export effect context for other modules
export function setEffectContext(effect: (() => void) | null): void {
	currentEffect = effect;
}

export function getEffectContext(): (() => void) | null {
	return currentEffect;
}
