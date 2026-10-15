import { Accessor, untrack } from "../core/signal";
import { ChildNavigation, ChildState, NavigationChild, createChildren } from "./children";

function slotState<C>(configuration: C | null, key: (configuration: C) => string): ChildState<C>[] {
	if (configuration === null) { return []; }
	const shown = configuration as C;
	return [{ key: key(shown), configuration: shown, active: true }];
}

export class ChildSlot<C, T> {
	private children: ChildNavigation<C, T>;
	private key: (configuration: C) => string;
	items: Accessor<NavigationChild<C, T>[]>;
	instances: Accessor<T[]>;

	constructor(children: ChildNavigation<C, T>, key: (configuration: C) => string) {
		this.children = children;
		this.key = key;
		this.items = children.children;
		this.instances = children.instances;
	}

	child(): NavigationChild<C, T> | null {
		const items = this.items();
		return items.length === 0 ? null : items[0];
	}

	configuration(): C | null {
		const state = untrack((): ChildState<C>[] => this.children.state());
		if (state.length === 0) { return null; }
		return state[0].configuration;
	}

	navigate(transformer: (configuration: C | null) => C | null): void {
		this.children.navigate(slotState<C>(transformer(this.configuration()), this.key));
	}

	activate(configuration: C): void {
		this.navigate((current: C | null): C | null => configuration);
	}

	dismiss(): boolean {
		if (this.configuration() === null) { return false; }
		this.navigate((current: C | null): C | null => null);
		return true;
	}

	dispose(): void {
		this.children.dispose();
	}
}

export function createChildSlot<C, T>(
	initial: C | null,
	key: (configuration: C) => string,
	factory: (configuration: Accessor<C>, active: Accessor<boolean>) => T,
): ChildSlot<C, T> {
	const children = createChildren<C, T>(slotState<C>(initial, key), factory);
	return new ChildSlot<C, T>(children, key);
}
