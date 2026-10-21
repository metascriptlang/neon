import { Accessor, accessor } from "../core/signal";
import { createMemo } from "../core/memo";
import { Host, HostNode, NeonNode } from "../render/hostTypes";
import { Style } from "../render/style";
import { View } from "../components/primitives";
import { For } from "../macros/ui/flow";
import { NavigationChild } from "./children";
import { ChildStack } from "./childStack";
import { ChildPages } from "./childPages";
import { ChildPanels, ChildPanelsMode } from "./childPanels";

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
	return renderChildren<C, T>(
		(): NavigationChild<C, T>[] => stack.items(),
		activeFrame<C, T>(render),
	);
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

const emptyPanel: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {};

export interface PanelsLayout {
	dualWeights?: number[] | null;
	tripleWeights?: number[] | null;
	secondPanelPlaceholder?: (() => NeonNode) | null;
	thirdPanelPlaceholder?: (() => NeonNode) | null;
}

function weightsOf(given: number[] | null, count: int32): number[] {
	if (given === null) { return count === 2 ? [1, 1] : [1, 1, 1]; }
	const weights = given as number[];
	if (weights.length !== count) {
		throw new Error("navigation: panels take " + count.toString() + " weights, got " +
			weights.length.toString());
	}
	return weights;
}

function panelFrame<C, T>(
	render: (child: NavigationChild<C, T>) => NeonNode,
	weight: () => number,
): (child: NavigationChild<C, T>) => NeonNode {
	return (child: NavigationChild<C, T>): NeonNode => {
		const frame = accessor((): Style => ({
			flex: weight(),
			flexDirection: "column",
			display: child.active() ? "flex" : "none",
		}));
		return <View style={frame}>{render(child)}</View>;
	};
}

function placeholderFrame(shown: () => boolean, weight: () => number, content: (() => NeonNode) | null): NeonNode {
	const frame = accessor((): Style => ({
		flex: weight(),
		flexDirection: "column",
		display: shown() ? "flex" : "none",
	}));
	return <View style={frame}>{content === null ? emptyPanel : (content as () => NeonNode)()}</View>;
}

function byMode(mode: () => ChildPanelsMode, single: number, inDual: number, inTriple: number): () => number {
	return (): number => {
		const current = mode();
		return current === ChildPanelsMode.Single ? single : current === ChildPanelsMode.Dual ? inDual : inTriple;
	};
}

function optional<C, T>(child: NavigationChild<C, T> | null): NavigationChild<C, T>[] {
	return child === null ? [] : [child as NavigationChild<C, T>];
}

export function renderPanels<MC, MT, DC, DT, EC, ET>(
	panels: ChildPanels<MC, MT, DC, DT, EC, ET>,
	main: (child: NavigationChild<MC, MT>) => NeonNode,
	details: (child: NavigationChild<DC, DT>) => NeonNode,
	extra: ((child: NavigationChild<EC, ET>) => NeonNode) | null = null,
	layout: PanelsLayout = {},
): NeonNode {
	const dual = weightsOf(layout.dualWeights ?? null, 2);
	const triple = weightsOf(layout.tripleWeights ?? null, 3);
	const mode = (): ChildPanelsMode => panels.mode();
	const second = byMode(mode, 1, dual[1], triple[1]);
	const third = byMode(mode, 1, dual[1], triple[2]);
	const secondEmpty = (): boolean => {
		const mode = panels.mode();
		return mode !== ChildPanelsMode.Single && panels.details() === null &&
			(mode === ChildPanelsMode.Triple || panels.extra() === null);
	};
	const thirdEmpty = (): boolean => panels.mode() === ChildPanelsMode.Triple && panels.extra() === null;
	const renderExtra = extra === null
		? (child: NavigationChild<EC, ET>): NeonNode => emptyPanel
		: extra as (child: NavigationChild<EC, ET>) => NeonNode;
	const mainPanel = renderChildren<MC, MT>((): NavigationChild<MC, MT>[] => [panels.main()], panelFrame<MC, MT>(main, byMode(mode, 1, dual[0], triple[0])));
	const detailsPanel = renderChildren<DC, DT>((): NavigationChild<DC, DT>[] => optional<DC, DT>(panels.details()), panelFrame<DC, DT>(details, second));
	const secondPlaceholder = placeholderFrame(secondEmpty, second, layout.secondPanelPlaceholder ?? null);
	const extraPanel = renderChildren<EC, ET>((): NavigationChild<EC, ET>[] => optional<EC, ET>(panels.extra()), panelFrame<EC, ET>(renderExtra, third));
	const thirdPlaceholder = placeholderFrame(thirdEmpty, third, layout.thirdPanelPlaceholder ?? null);
	const row = accessor((): Style => ({ flex: 1, flexDirection: "row" }));
	return <View style={row}>{mainPanel}{detailsPanel}{secondPlaceholder}{extraPanel}{thirdPlaceholder}</View>;
}
