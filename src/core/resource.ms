import { Accessor, Signal, accessor, createSignal, untrack } from "./signal";
import { createEffect } from "./effect";
import { onCleanup } from "./cleanup";

export enum ResourceState {
	Unresolved,
	Pending,
	Ready,
	Refreshing,
	Errored,
}

export interface ResourceActions<T, E> {
	state: Accessor<ResourceState>;
	loading: Accessor<boolean>;
	error: Accessor<E | null>;
	latest: Accessor<T | null>;
	refetch: () => void;
	mutate: (value: T | null) => void;
}

async function settleResource<T, E>(request: Promise<Result<T, E>>, done: (result: Result<T, E>) => void): Promise<void> {
	const result = await request;
	done(result);
}

export function createResource<S, T, E>(source: () => S, fetcher: (source: S) => Promise<Result<T, E>>): [Accessor<T | null>, ResourceActions<T, E>] {
	const valueCell = new Signal<T[]>([]);
	const [failure, setFailure] = createSignal<E | null>(null);
	const stateCell = new Signal<ResourceState>(ResourceState.Unresolved);
	const value = accessor((): T | null => {
		const held = valueCell.get();
		return held.length === 0 ? null : held[0];
	});
	const state = accessor((): ResourceState => stateCell.get());
	let generation = 0;
	let alive = true;
	onCleanup((): void => { alive = false; });

	function load(input: S): void {
		generation += 1;
		const run = generation;
		const had = untrack((): boolean => value() !== null);
		stateCell.set(had ? ResourceState.Refreshing : ResourceState.Pending);
		settleResource(fetcher(input), (result: Result<T, E>): void => {
			if (!alive || run !== generation) { return; }
			if (result.ok) {
				setFailure(null);
				valueCell.set([result.value]);
				stateCell.set(ResourceState.Ready);
			} else {
				setFailure(result.error);
				stateCell.set(ResourceState.Errored);
			}
		});
	}

	createEffect((): void => {
		const input = source();
		untrack((): void => { load(input); });
	});

	const loading = accessor((): boolean => {
		const s = state();
		return s === ResourceState.Pending || s === ResourceState.Refreshing;
	});
	return [value, {
		state,
		loading,
		error: failure,
		latest: value,
		refetch: (): void => { load(untrack(source)); },
		mutate: (next: T | null): void => { valueCell.set(next === null ? [] : [next as T]); },
	}];
}
