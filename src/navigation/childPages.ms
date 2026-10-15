import { Accessor, untrack } from "../core/signal";
import { ChildNavigation, ChildState, NavigationChild, createChildren } from "./children";

export interface Pages<C> {
	items: C[];
	selectedIndex: int32;
}

function pagesState<C>(pages: Pages<C>, key: (configuration: C) => string): ChildState<C>[] {
	const items = pages.items;
	const at = pages.selectedIndex;
	if (items.length > 0 && (at < 0 || at >= items.length)) {
		throw new Error(
			"child pages: selectedIndex " + at.toString() +
			" is outside " + items.length.toString() + " pages",
		);
	}
	const state: ChildState<C>[] = [];
	for (let i = 0; i < items.length; i += 1) {
		state.push({ key: key(items[i]), configuration: items[i], active: i === at });
	}
	return state;
}

function coerceSelected<C>(pages: Pages<C>, wanted: int32, circular: boolean): Pages<C> {
	const count = pages.items.length as int32;
	if (count === 0) { return pages; }
	let at = wanted;
	if (circular && at < 0) { at += count; }
	if (circular && at >= count) { at -= count; }
	return { items: pages.items, selectedIndex: Math.max(0, Math.min(at, count - 1)) };
}

export class ChildPages<C, T> {
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

	selectedIndex(): int32 {
		const state = this.children.state();
		for (let i = 0; i < state.length; i += 1) {
			if (state[i].active) { return i as int32; }
		}
		return -1;
	}

	selected(): NavigationChild<C, T> | null {
		const at = this.selectedIndex();
		return at < 0 ? null : this.items()[at];
	}

	pages(): Pages<C> {
		const items: C[] = [];
		let selectedIndex: int32 = -1;
		const state = untrack((): ChildState<C>[] => this.children.state());
		for (let i = 0; i < state.length; i += 1) {
			items.push(state[i].configuration);
			if (state[i].active) { selectedIndex = i as int32; }
		}
		return { items, selectedIndex };
	}

	navigate(transformer: (pages: Pages<C>) => Pages<C>): void {
		this.children.navigate(pagesState<C>(transformer(this.pages()), this.key));
	}

	select(index: int32): void {
		this.navigate((pages: Pages<C>): Pages<C> => ({ items: pages.items, selectedIndex: index }));
	}

	selectNext(circular: boolean): void {
		this.navigate((pages: Pages<C>): Pages<C> => {
			return coerceSelected<C>(pages, pages.selectedIndex + 1, circular);
		});
	}

	selectPrev(circular: boolean): void {
		this.navigate((pages: Pages<C>): Pages<C> => {
			return coerceSelected<C>(pages, pages.selectedIndex - 1, circular);
		});
	}

	dispose(): void {
		this.children.dispose();
	}
}

export function createChildPages<C, T>(
	initial: Pages<C>,
	key: (configuration: C) => string,
	factory: (configuration: Accessor<C>, active: Accessor<boolean>) => T,
): ChildPages<C, T> {
	const children = createChildren<C, T>(pagesState<C>(initial, key), factory);
	return new ChildPages<C, T>(children, key);
}
