import { Accessor } from "./signal";
import { CompState, Source } from "./types";
import {
	createComputation,
	runComputation,
	getListener,
	registerDependency,
	enqueue,
} from "./runtime";
import { onCleanup } from "./cleanup";

export function createSelector<T>(source: Accessor<T>): (key: T) => boolean {
	return createSelector<T, T>(source, (key: T, value: T): boolean => key === value);
}

export function createSelector<T, U>(
	source: Accessor<T>,
	equals: (key: U, value: T) => boolean,
): (key: U) => boolean {
	const subscribers = new Map<U, Source>();
	let held: { value: T } | null = null;
	const computation = createComputation(() => {
		const value = source();
		const prior = held;
		if (prior === null) {
			held = { value };
			return;
		}
		const current = prior.value;
		subscribers.forEach((entry: Source, key: U): void => {
			if (equals(key, value) === equals(key, current)) { return; }
			for (const observer of entry.observers) {
				if (!observer.disposed && observer.state === CompState.Clean) {
					observer.state = CompState.Stale;
					enqueue(observer);
				}
			}
		});
		prior.value = value;
	}, true);
	runComputation(computation);

	return (key: U): boolean => {
		const listener = getListener();
		if (listener !== null) {
			const existing = subscribers.get(key);
			const entry: Source = existing !== null
				? existing
				: { observers: [], observerSlots: [] };
			if (existing === null) { subscribers.set(key, entry); }
			const count = entry.observers.length;
			registerDependency(entry, listener);
			if (entry.observers.length !== count) {
				onCleanup(() => {
					if (entry.observers.length === 0) { subscribers.delete(key); }
				});
			}
		}
		const now = held;
		if (now === null) {
			throw new Error("Selector read before initialization");
		}
		return equals(key, now.value);
	};
}
