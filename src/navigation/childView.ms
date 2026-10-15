import { Accessor, accessor } from "../core/signal";
import { createMemo } from "../core/memo";
import { NeonNode } from "../render/hostTypes";
import { Style } from "../render/style";
import { View } from "../components/primitives";
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

function activeFrame<C, T>(
	render: (child: NavigationChild<C, T>) => NeonNode,
): (child: NavigationChild<C, T>) => NeonNode {
	return (child: NavigationChild<C, T>): NeonNode => {
		const frame = accessor((): Style => ({
			flex: 1,
			flexDirection: "column",
			display: child.active() ? "flex" : "none",
		}));
		return <View style={frame}>{render(child)}</View>;
	};
}

export function renderStack<C, T>(
	stack: ChildStack<C, T>,
	render: (child: NavigationChild<C, T>) => NeonNode,
): NeonNode {
	return renderChildren<C, T>((): NavigationChild<C, T>[] => stack.items(), activeFrame<C, T>(render));
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
	let visited = new Set<string>();
	return renderChildren<C, T>((): NavigationChild<C, T>[] => {
		const next = new Set<string>();
		const kept: NavigationChild<C, T>[] = [];
		for (const child of pages.items()) {
			if (child.active() || visited.has(child.key)) {
				next.add(child.key);
				kept.push(child);
			}
		}
		visited = next;
		return kept;
	}, activeFrame<C, T>(render));
}
