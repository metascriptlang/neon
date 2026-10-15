import { Accessor, Signal, accessor } from "../core/signal";
import { Computation, Dispose } from "../core/types";
import { createRoot, runWithOwner } from "../core/owner";
import { getOwner } from "../core/runtime";
import { onCleanup } from "../core/cleanup";

export interface ChildState<C> {
	key: string;
	configuration: C;
	active: boolean;
}

export interface NavigationChild<C, T> {
	key: string;
	configuration: Accessor<C>;
	active: Accessor<boolean>;
	instance: T;
}

export interface ChildNavigation<C, T> {
	state: Accessor<ChildState<C>[]>;
	children: Accessor<NavigationChild<C, T>[]>;
	instances: Accessor<T[]>;
	navigate: (state: ChildState<C>[]) => void;
	dispose: Dispose;
}

interface OwnedChild<C, T> {
	child: NavigationChild<C, T>;
	configuration: Signal<C>;
	active: Signal<boolean>;
	dispose: Dispose;
}

function checkKeys<C>(state: ChildState<C>[]): void {
	const keys = new Set<string>();
	for (const child of state) {
		if (child.key === "") { throw new Error("navigation: empty child key"); }
		if (keys.has(child.key)) { throw new Error("duplicate child key: " + child.key); }
		keys.add(child.key);
	}
}

function ownChild<C, T>(
	configuration: ChildState<C>,
	factory: (configuration: Accessor<C>, active: Accessor<boolean>) => T,
	owner: Computation | null,
): OwnedChild<C, T> {
	const value = new Signal<C>(configuration.configuration, null, true);
	const active = new Signal<boolean>(configuration.active, null, true);
	const read = accessor((): C => value.get());
	const focused = accessor((): boolean => active.get());
	return runWithOwner(owner, (): OwnedChild<C, T> => {
		return createRoot((cleanup: Dispose): OwnedChild<C, T> => {
			try {
				return {
					child: {
						key: configuration.key,
						configuration: read,
						active: focused,
						instance: factory(read, focused),
					},
					configuration: value,
					active,
					dispose: cleanup,
				};
			} catch (error) { cleanup(); throw error; }
		});
	});
}

export function createChildren<C, T>(
	initial: ChildState<C>[],
	factory: (configuration: Accessor<C>, active: Accessor<boolean>) => T,
): ChildNavigation<C, T> {
	const owner = getOwner();
	const state = new Signal<ChildState<C>[]>([], null, true);
	const children = new Signal<NavigationChild<C, T>[]>([], null, true);
	let owned = new Map<string, OwnedChild<C, T>>();
	let disposed = false;
	let changing = false;
	const dispose: Dispose = (): void => {
		if (disposed) { return; }
		disposed = true;
		const previous = owned;
		owned = new Map<string, OwnedChild<C, T>>();
		for (const key of previous) { (previous.get(key) as OwnedChild<C, T>).dispose(); }
		state.set([]);
		children.set([]);
	};
	const navigate = (next: ChildState<C>[]): void => {
		if (disposed) { throw new Error("navigation: children are disposed"); }
		if (changing) { throw new Error("navigation: reentrant child change"); }
		checkKeys(next);
		changing = true;
		const desired = new Map<string, OwnedChild<C, T>>();
		const created: OwnedChild<C, T>[] = [];
		try {
			for (const configuration of next) {
				const existing = owned.get(configuration.key);
				if (existing !== null) {
					desired.set(configuration.key, existing as OwnedChild<C, T>);
				} else {
					const child = ownChild<C, T>(configuration, factory, owner);
					created.push(child);
					desired.set(configuration.key, child);
				}
			}
			if (disposed) { throw new Error("navigation: children disposed during creation"); }
		} catch (error) {
			for (const child of created) { child.dispose(); }
			changing = false;
			throw error;
		}
		try {
			for (const key of owned) {
				if (!desired.has(key)) { (owned.get(key) as OwnedChild<C, T>).dispose(); }
			}
			const snapshot: ChildState<C>[] = [];
			const visible: NavigationChild<C, T>[] = [];
			for (const config of next) {
				const child = desired.get(config.key) as OwnedChild<C, T>;
				child.configuration.set(config.configuration);
				child.active.set(config.active);
				snapshot.push({
					key: config.key,
					configuration: config.configuration,
					active: config.active,
				});
				visible.push(child.child);
			}
			owned = desired;
			state.set(snapshot);
			children.set(visible);
		} finally { changing = false; }
	};
	navigate(initial);
	if (owner !== null) { onCleanup(dispose); }
	return {
		state: accessor((): ChildState<C>[] => {
			const result: ChildState<C>[] = [];
			for (const child of state.get()) {
				result.push({
					key: child.key,
					configuration: child.configuration,
					active: child.active,
				});
			}
			return result;
		}),
		children: accessor((): NavigationChild<C, T>[] => {
			const result: NavigationChild<C, T>[] = [];
			for (const child of children.get()) {
				result.push({
					key: child.key,
					configuration: child.configuration,
					active: child.active,
					instance: child.instance,
				});
			}
			return result;
		}),
		instances: accessor((): T[] => {
			const result: T[] = [];
			for (const child of children.get()) { result.push(child.instance); }
			return result;
		}),
		navigate,
		dispose,
	};
}
