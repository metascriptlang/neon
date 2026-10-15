import { Accessor } from "../core/signal";
import { createMemo } from "../core/memo";
import { NeonNode } from "../render/hostTypes";
import { For } from "../macros/ui/flow";
import { NavigationChild } from "./children";
import { ChildStack } from "./childStack";
import { ChildPages } from "./childPages";

function keptChildren<C, T>(
	read: () => NavigationChild<C, T>[],
): Accessor<NavigationChild<C, T>[]> {
	let held = new Map<string, NavigationChild<C, T>>();
	return createMemo<NavigationChild<C, T>[]>((): NavigationChild<C, T>[] => {
		const next = new Map<string, NavigationChild<C, T>>();
		const shown: NavigationChild<C, T>[] = [];
		for (const child of read()) {
			const known = held.get(child.key);
			const kept = known === null ? child : known as NavigationChild<C, T>;
			next.set(child.key, kept);
			shown.push(kept);
		}
		held = next;
		return shown;
	});
}

function renderChildren<C, T>(
	read: () => NavigationChild<C, T>[],
	render: (child: NavigationChild<C, T>) => NeonNode,
): NeonNode {
	const shown = keptChildren<C, T>(read);
	return <For each={shown}>{(child: NavigationChild<C, T>): NeonNode => render(child)}</For>;
}

export function renderStack<C, T>(
	stack: ChildStack<C, T>,
	render: (child: NavigationChild<C, T>) => NeonNode,
): NeonNode {
	return renderChildren<C, T>((): NavigationChild<C, T>[] => stack.items(), render);
}

export function renderStackTop<C, T>(
	stack: ChildStack<C, T>,
	render: (child: NavigationChild<C, T>) => NeonNode,
): NeonNode {
	return renderChildren<C, T>((): NavigationChild<C, T>[] => [stack.active()], render);
}

export function renderPages<C, T>(
	pages: ChildPages<C, T>,
	render: (child: NavigationChild<C, T>) => NeonNode,
): NeonNode {
	return renderChildren<C, T>((): NavigationChild<C, T>[] => {
		const selected = pages.selected();
		return selected === null ? [] : [selected as NavigationChild<C, T>];
	}, render);
}
