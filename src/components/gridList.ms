// Flutter SliverGridDelegateWithMaxCrossAxisExtent over FlatList's numColumns, and a
// shortest-column masonry layout over a ScrollView.

import { Accessor, accessor, createSignal, untrack } from "../core/signal";
import { createMemo } from "../core/memo";
import { Host, HostNode } from "../render/hostTypes";
import { element } from "../macros/ui/element";
import { For } from "../macros/ui/flow";
import { NeonNode } from "../render/node";
import { NeonEvent } from "../render/event";
import { Style, mergeStyle } from "../render/style";
import { ScrollView, View } from "./primitives";
import { EndReachedInfo, FlatList, FlatListHandle, ListRenderItemInfo } from "./flatList";

export interface GridMetrics {
	columns: int32;
	itemWidth: number;
}

// rendering/sliver_grid.dart:502-521.
export function maxExtentColumns(width: number, maxItemWidth: number, spacing: number): GridMetrics {
	if (width <= 0 || maxItemWidth <= 0) { return { columns: 1, itemWidth: Math.max(0, width) }; }
	const columns = Math.max(1, Math.ceil(width / (maxItemWidth + spacing)) as int32);
	const usable = Math.max(0, width - spacing * ((columns - 1) as number));
	return { columns, itemWidth: usable / (columns as number) };
}

export interface GridRenderItemInfo<T> {
	item: T;
	index: Accessor<number>;
	itemWidth: Accessor<number>;
}

function spacingOf(prop: Accessor<number> | null): number {
	return prop === null ? 0 : (prop as Accessor<number>)();
}

export function GridList<T>(props: {
	data: Accessor<T[]>;
	renderItem: (info: GridRenderItemInfo<T>) => NeonNode;
	maxItemWidth?: Accessor<number> | null;
	numColumns?: Accessor<number> | null;
	itemSpacing?: Accessor<number> | null;
	rowSpacing?: Accessor<number> | null;
	childAspectRatio?: Accessor<number> | null;
	itemHeight?: Accessor<number> | null;
	ListHeaderComponent?: NeonNode | null;
	ListFooterComponent?: NeonNode | null;
	ListEmptyComponent?: NeonNode | null;
	onEndReached?: ((info: EndReachedInfo) => void) | null;
	onScroll?: ((e: NeonEvent) => void) | null;
	style?: Accessor<Style> | null;
	contentContainerStyle?: Accessor<Style> | null;
	ref?: ((handle: FlatListHandle) => void) | null;
}): NeonNode {
	const maxProp = props.maxItemWidth;
	const columnsProp = props.numColumns;
	if (maxProp === null && columnsProp === null) { throw "GridList: maxItemWidth or numColumns is required"; }
	const spacingProp = props.itemSpacing;
	const rowSpacingProp = props.rowSpacing;
	const ratioProp = props.childAspectRatio;
	const heightProp = props.itemHeight;
	const userRender = props.renderItem;
	const [width, setWidth] = createSignal<number>(0);
	const metrics = createMemo<GridMetrics>((): GridMetrics => {
		const spacing = spacingOf(spacingProp);
		const w = width();
		if (columnsProp !== null) {
			const columns = Math.max(1, (columnsProp as Accessor<number>)() as int32);
			const usable = Math.max(0, w - spacing * ((columns - 1) as number));
			return { columns, itemWidth: usable / (columns as number) };
		}
		return maxExtentColumns(w, (maxProp as Accessor<number>)(), spacing);
	});
	const columns = createMemo<number[]>((): number[] => width() <= 0 ? [] : [metrics().columns as number], (a: number[], b: number[]): boolean => a.length === b.length && (a.length === 0 || a[0] === b[0]));
	const itemWidth = accessor((): number => metrics().itemWidth);
	const cellStyle = (index: Accessor<number>): Accessor<Style> => accessor((): Style => {
		const m = metrics();
		const spacing = spacingOf(spacingProp);
		const column = (index() as int32) % m.columns;
		let height: number | null = null;
		if (heightProp !== null) { height = (heightProp as Accessor<number>)(); }
		else if (ratioProp !== null) { height = m.itemWidth / (ratioProp as Accessor<number>)(); }
		return { width: m.itemWidth, height, marginLeft: column === 0 ? 0 : spacing, flexShrink: 0 };
	});
	const renderCell = (info: ListRenderItemInfo<T>): NeonNode => {
		const body = userRender({ item: info.item, index: info.index, itemWidth });
		return View({ style: cellStyle(info.index), children: body });
	};
	const separator: NeonNode | null = rowSpacingProp === null ? null : element(<View style={{ height: spacingOf(rowSpacingProp) }} />);
	const data = props.data;
	const grid = For<number>({
		each: columns,
		children: (count: number, i: Accessor<number>): NeonNode => FlatList<T>({
			data,
			renderItem: renderCell,
			numColumns: accessor((): number => count),
			ItemSeparatorComponent: separator,
			ListHeaderComponent: props.ListHeaderComponent,
			ListFooterComponent: props.ListFooterComponent,
			ListEmptyComponent: props.ListEmptyComponent,
			onEndReached: props.onEndReached,
			onScroll: props.onScroll,
			style: accessor((): Style => ({ flex: 1 })),
			contentContainerStyle: props.contentContainerStyle,
			ref: props.ref,
		}),
	});
	const userStyle = props.style;
	return View({
		style: accessor((): Style => mergeStyle({ flex: 1 }, userStyle === null ? {} : (userStyle as Accessor<Style>)())),
		onLayout: (e: NeonEvent): void => { if (e.width !== untrack<number>(width)) { setWidth(e.width); } },
		children: grid,
	});
}

export interface MasonryRenderItemInfo<T> {
	item: T;
	index: Accessor<number>;
	column: number;
	columnWidth: Accessor<number>;
}

class MasonryPlacement {
	column: int32;
	height: number;

	constructor(column: int32, height: number) {
		this.column = column;
		this.height = height;
	}
}

export function shortestColumn(heights: number[]): int32 {
	let best: int32 = 0;
	for (let i = 1; i < heights.length; i += 1) {
		if (heights[i] < heights[best]) { best = i; }
	}
	return best;
}

export function MasonryList<T>(props: {
	data: Accessor<T[]>;
	renderItem: (info: MasonryRenderItemInfo<T>) => NeonNode;
	maxItemWidth?: Accessor<number> | null;
	numColumns?: Accessor<number> | null;
	getItemHeight?: ((item: T, index: number, columnWidth: number) => number) | null;
	itemSpacing?: Accessor<number> | null;
	ListHeaderComponent?: NeonNode | null;
	ListFooterComponent?: NeonNode | null;
	onScroll?: ((e: NeonEvent) => void) | null;
	style?: Accessor<Style> | null;
	contentContainerStyle?: Accessor<Style> | null;
}): NeonNode {
	const maxProp = props.maxItemWidth;
	const columnsProp = props.numColumns;
	if (maxProp === null && columnsProp === null) { throw "MasonryList: maxItemWidth or numColumns is required"; }
	const spacingProp = props.itemSpacing;
	const estimate = props.getItemHeight;
	const userRender = props.renderItem;
	const data = props.data;
	const [width, setWidth] = createSignal<number>(0);
	const metrics = createMemo<GridMetrics>((): GridMetrics => {
		const spacing = spacingOf(spacingProp);
		const w = width();
		if (columnsProp !== null) {
			const columns = Math.max(1, (columnsProp as Accessor<number>)() as int32);
			return { columns, itemWidth: Math.max(0, w - spacing * ((columns - 1) as number)) / (columns as number) };
		}
		return maxExtentColumns(w, (maxProp as Accessor<number>)(), spacing);
	});
	let placements = new Map<T, MasonryPlacement>();
	let placedColumns: int32 = 0;
	const columnItems = createMemo<T[][]>((): T[][] => {
		const items = data();
		const m = metrics();
		return untrack<T[][]>((): T[][] => {
			if (m.columns !== placedColumns) {
				placements = new Map<T, MasonryPlacement>();
				placedColumns = m.columns;
			}
			const out: T[][] = [];
			const totals: number[] = [];
			for (let c = 0; c < m.columns; c += 1) {
				out.push([]);
				totals.push(0);
			}
			const next = new Map<T, MasonryPlacement>();
			for (let i = 0; i < items.length; i += 1) {
				const item = items[i];
				let placed: MasonryPlacement | null = placements.has(item) ? placements.get(item) as MasonryPlacement : null;
				if (placed === null) {
					const guess = estimate === null ? 1 : (estimate as (item: T, index: number, columnWidth: number) => number)(item, i as number, m.itemWidth);
					placed = new MasonryPlacement(shortestColumn(totals), guess);
				}
				const p = placed as MasonryPlacement;
				next.set(item, p);
				out[p.column].push(item);
				totals[p.column] += p.height;
			}
			placements = next;
			return out;
		});
	});
	const spacing = (): number => spacingOf(spacingProp);
	const column = (c: number, i: Accessor<number>): NeonNode => {
		const items = accessor((): T[] => {
			const all = columnItems();
			return (c as int32) < all.length ? all[c as int32] : [];
		});
		const columnWidth = accessor((): number => metrics().itemWidth);
		return View({
			style: accessor((): Style => ({ width: metrics().itemWidth, marginLeft: c === 0 ? 0 : spacing(), flexDirection: "column", flexShrink: 0 })),
			children: For<T>({
				each: items,
				children: (item: T, at: Accessor<number>): NeonNode => View({
					style: accessor((): Style => ({ marginBottom: spacing() })),
					onLayout: (e: NeonEvent): void => {
						if (!placements.has(item)) { return; }
						const p = placements.get(item) as MasonryPlacement;
						if (Math.abs(p.height - e.height) < 0.5) { return; }
						p.height = e.height;
					},
					children: userRender({ item, index: at, column: c, columnWidth }),
				}),
			}),
		});
	};
	const columnIndices = createMemo<number[]>((): number[] => {
		const out: number[] = [];
		if (width() <= 0) { return out; }
		for (let c = 0; c < metrics().columns; c += 1) { out.push(c as number); }
		return out;
	}, (a: number[], b: number[]): boolean => a.length === b.length);
	const header = props.ListHeaderComponent;
	const footer = props.ListFooterComponent;
	const userStyle = props.style;
	const columnsRow: NeonNode = View({
		style: accessor((): Style => ({ flexDirection: "row", alignItems: "flex-start" })),
		children: For<number>({ each: columnIndices, children: column }),
	});
	return ScrollView({
		style: accessor((): Style => mergeStyle({ flex: 1 }, userStyle === null ? {} : (userStyle as Accessor<Style>)())),
		contentContainerStyle: props.contentContainerStyle,
		onScroll: props.onScroll,
		onLayout: (e: NeonEvent): void => { if (e.width !== untrack<number>(width)) { setWidth(e.width); } },
		children: (host: Host, parent: HostNode, before: HostNode | null): void => {
			if (header !== null) { (header as NeonNode)(host, parent, before); }
			columnsRow(host, parent, before);
			if (footer !== null) { (footer as NeonNode)(host, parent, before); }
		},
	});
}
