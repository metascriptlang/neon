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
	let current: T = undefined as T;
	const computation = createComputation(() => {
		const value = source();
		subscribers.forEach((entry: Source, key: U): void => {
			if (equals(key, value) === equals(key, current)) { return; }
			for (const observer of entry.observers) {
				if (!observer.disposed && observer.state === CompState.Clean) {
					observer.state = CompState.Stale;
					enqueue(observer);
				}
			}
		});
		current = value;
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
		return equals(key, current);
	};
}
