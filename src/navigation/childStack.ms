import { Accessor, untrack } from "../core/signal";
import { ChildNavigation, ChildState, NavigationChild, createChildren } from "./children";

function stackState<C>(stack: C[], key: (configuration: C) => string): ChildState<C>[] {
	if (stack.length === 0) { throw new Error("child stack: a stack must not be empty"); }
	const state: ChildState<C>[] = [];
	for (let i = 0; i < stack.length; i += 1) {
		state.push({ key: key(stack[i]), configuration: stack[i], active: i === stack.length - 1 });
	}
	return state;
}

export class ChildStack<C, T> {
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

	active(): NavigationChild<C, T> {
		const items = this.items();
		return items[items.length - 1];
	}

	backStack(): NavigationChild<C, T>[] {
		const items = this.items();
		return items.slice(0, items.length - 1);
	}

	configurations(): C[] {
		const stack: C[] = [];
		for (const child of untrack((): ChildState<C>[] => this.children.state())) {
			stack.push(child.configuration);
		}
		return stack;
	}

	navigate(transformer: (stack: C[]) => C[]): void {
		this.children.navigate(stackState<C>(transformer(this.configurations()), this.key));
	}

	push(configuration: C): void {
		this.navigate((stack: C[]): C[] => {
			stack.push(configuration);
			return stack;
		});
	}

	pop(): void {
		this.navigate((stack: C[]): C[] => {
			if (stack.length < 2) {
				throw new Error("child stack: pop needs a back stack, the stack has one item");
			}
			return stack.slice(0, stack.length - 1);
		});
	}

	popTo(index: int32): void {
		this.navigate((stack: C[]): C[] => {
			if (index < 0 || index >= stack.length) {
				throw new Error(
					"child stack: popTo index " + index.toString() +
					" is outside a stack of " + stack.length.toString(),
				);
			}
			return stack.slice(0, index + 1);
		});
	}

	replaceCurrent(configuration: C): void {
		this.navigate((stack: C[]): C[] => {
			stack[stack.length - 1] = configuration;
			return stack;
		});
	}

	bringToFront(configuration: C): void {
		const front = this.key(configuration);
		this.navigate((stack: C[]): C[] => {
			const kept: C[] = [];
			for (const item of stack) {
				if (this.key(item) !== front) { kept.push(item); }
			}
			kept.push(configuration);
			return kept;
		});
	}

	dispose(): void {
		this.children.dispose();
	}
}

export function createChildStack<C, T>(
	initial: C[],
	key: (configuration: C) => string,
	factory: (configuration: Accessor<C>, active: Accessor<boolean>) => T,
): ChildStack<C, T> {
	const children = createChildren<C, T>(stackState<C>(initial, key), factory);
	return new ChildStack<C, T>(children, key);
}
