// Flutter's scroll-driven headers and CustomScrollView in Neon's vocabulary. A collapsing
// header is an overlay whose extent follows the scroll offset (material/app_bar.dart
// SliverAppBar, rendering/sliver_persistent_header.dart). Several lists and grids in one
// scroll are one VirtualizedList over the slivers' rows laid end to end, which is what
// RenderViewport.layoutChildSequence does with one shared scroll offset.

import { Accessor, accessor, createSignal, untrack } from "../core/signal";
import { createMemo } from "../core/memo";
import { Host, HostNode } from "../render/hostTypes";
import { For } from "../macros/ui/flow";
import { NeonNode } from "../render/node";
import { NeonEvent } from "../render/event";
import { Style, mergeStyle } from "../render/style";
import { View } from "./primitives";
import { FlatListHandle, ListRenderItemInfo, VirtualizedList } from "./virtualizedList";

export interface ScrollOffset {
	offset: Accessor<number>;
	onScroll: (e: NeonEvent) => void;
}

// The scroll half of RN's Animated.event([{ nativeEvent: { contentOffset: { y } } }]).
export function createScrollOffset(horizontal: boolean): ScrollOffset {
	const [offset, setOffset] = createSignal<number>(0);
	return {
		offset,
		onScroll: (e: NeonEvent): void => { setOffset(horizontal ? e.x : e.y); },
	};
}

export interface HeaderMetrics {
	extent: number;
	translate: number;
	progress: number;
}

// sliver_persistent_header.dart:220-250 (child extent), :352-387 (scrolling) and :420-442 (pinned).
export function headerMetrics(offset: number, expanded: number, collapsed: number, pinned: boolean): HeaderMetrics {
	const scrolled = Math.max(0, offset);
	const shrink = Math.min(scrolled, expanded);
	const extent = Math.max(collapsed, expanded - shrink);
	const range = expanded - collapsed;
	const progress = range <= 0 ? 1 : Math.min(1, Math.max(0, (expanded - extent) / range));
	if (pinned) { return { extent, translate: 0, progress }; }
	const paint = Math.max(0, expanded - scrolled);
	return { extent, translate: Math.min(0, paint - extent), progress };
}

// sliver_persistent_header.dart:650-690: a floating header keeps its own offset that grows
// with forward scrolling and shrinks as soon as the user scrolls back.
export class FloatingOffset {
	effective: number = 0;
	last: number = 0;

	update(offset: number, expanded: number): number {
		const delta = offset - this.last;
		this.last = offset;
		this.effective = Math.min(Math.max(0, offset), Math.max(0, Math.min(expanded, this.effective + delta)));
		return this.effective;
	}
}

// material/flexible_space_bar.dart:212-252, :330-335.
const TOOLBAR_HEIGHT = 56;
const EXPANDED_TITLE_SCALE = 1.5;

export function backgroundOpacity(progress: number, expanded: number, collapsed: number): number {
	const range = expanded - collapsed;
	if (range <= 0) { return 1; }
	const fadeStart = Math.max(0, 1 - TOOLBAR_HEIGHT / range);
	if (progress <= fadeStart) { return 1; }
	return 1 - (progress - fadeStart) / (1 - fadeStart);
}

export function CollapsingHeader(props: {
	scrollOffset: Accessor<number>;
	expandedHeight: Accessor<number>;
	collapsedHeight?: Accessor<number> | null;
	pinned?: Accessor<boolean> | null;
	floating?: Accessor<boolean> | null;
	background?: NeonNode | null;
	title?: NeonNode | null;
	children?: NeonNode | null;
	style?: Accessor<Style> | null;
	onProgress?: ((progress: number) => void) | null;
}): NeonNode {
	const offsetProp = props.scrollOffset;
	const expandedProp = props.expandedHeight;
	const collapsedProp = props.collapsedHeight;
	const pinnedProp = props.pinned;
	const floatingProp = props.floating;
	const onProgress = props.onProgress;
	const floating = new FloatingOffset();
	const metrics = createMemo<HeaderMetrics>((): HeaderMetrics => {
		const expanded = expandedProp();
		const collapsed = collapsedProp === null ? TOOLBAR_HEIGHT : (collapsedProp as Accessor<number>)();
		const pinned = pinnedProp !== null && (pinnedProp as Accessor<boolean>)();
		const raw = offsetProp();
		const isFloating = floatingProp !== null && (floatingProp as Accessor<boolean>)();
		const offset = isFloating ? floating.update(raw, expanded) : raw;
		const m = headerMetrics(offset, expanded, collapsed, pinned);
		if (onProgress !== null) { untrack((): void => { (onProgress as (p: number) => void)(m.progress); }); }
		return m;
	});
	const userStyle = props.style;
	const frame = accessor((): Style => {
		const m = metrics();
		const base: Style = {
			position: "absolute", left: 0, right: 0, top: 0, height: m.extent, overflow: "hidden", zIndex: 10,
			transform: `translateY(${m.translate}px)`,
		};
		return userStyle === null ? base : mergeStyle((userStyle as Accessor<Style>)(), base);
	});
	const backgroundStyle = accessor((): Style => {
		const m = metrics();
		const expanded = expandedProp();
		const collapsed = collapsedProp === null ? TOOLBAR_HEIGHT : (collapsedProp as Accessor<number>)();
		const parallax = -(m.progress * (expanded - collapsed) / 4);
		return {
			position: "absolute", left: 0, right: 0, top: 0, height: expanded,
			opacity: backgroundOpacity(m.progress, expanded, collapsed),
			transform: `translateY(${parallax}px)`,
		};
	});
	const titleStyle = accessor((): Style => {
		const m = metrics();
		const scale = EXPANDED_TITLE_SCALE + (1 - EXPANDED_TITLE_SCALE) * m.progress;
		return { position: "absolute", left: 16, bottom: 16, transform: `scale(${scale})` };
	});
	const background = props.background;
	const title = props.title;
	const children = props.children;
	const backgroundLayer: NeonNode | null = background === null ? null : View({ style: backgroundStyle, children: background });
	const titleLayer: NeonNode | null = title === null ? null : View({ style: titleStyle, children: title });
	return View({
		style: frame,
		children: (host: Host, parent: HostNode, before: HostNode | null): void => {
			if (backgroundLayer !== null) { (backgroundLayer as NeonNode)(host, parent, before); }
			if (children !== null) { (children as NeonNode)(host, parent, before); }
			if (titleLayer !== null) { (titleLayer as NeonNode)(host, parent, before); }
		},
	});
}

export class SliverRow {
	render: (index: Accessor<number>) => NeonNode;
	sticky: boolean;

	constructor(render: (index: Accessor<number>) => NeonNode, sticky: boolean) {
		this.render = render;
		this.sticky = sticky;
	}
}

export interface Sliver {
	rows: Accessor<SliverRow[]>;
}

export function sliverToBox(child: NeonNode): Sliver {
	const row = new SliverRow((index: Accessor<number>): NeonNode => child, false);
	return { rows: accessor((): SliverRow[] => [row]) };
}

export function sliverPinnedHeader(child: NeonNode): Sliver {
	const row = new SliverRow((index: Accessor<number>): NeonNode => child, true);
	return { rows: accessor((): SliverRow[] => [row]) };
}

export function sliverList<T>(data: Accessor<T[]>, renderItem: (item: T, index: Accessor<number>) => NeonNode): Sliver {
	let cache = new Map<T, SliverRow>();
	const rows = createMemo<SliverRow[]>((): SliverRow[] => {
		const items = data();
		const next = new Map<T, SliverRow>();
		const out: SliverRow[] = [];
		for (const item of items) {
			const row = cache.has(item) ? cache.get(item) as SliverRow : new SliverRow((index: Accessor<number>): NeonNode => renderItem(item, index), false);
			next.set(item, row);
			out.push(row);
		}
		cache = next;
		return out;
	});
	return { rows };
}

export function sliverGrid<T>(data: Accessor<T[]>, columns: int32, renderItem: (item: T, index: Accessor<number>) => NeonNode, rowStyle: Style | null): Sliver {
	let cache = new Map<T, SliverRow>();
	const members = (first: T): T[] => {
		const items = data();
		const at = items.indexOf(first);
		const out: T[] = [];
		if (at < 0) { return out; }
		for (let i = at; i < items.length && i < at + columns; i += 1) { out.push(items[i]); }
		return out;
	};
	const rows = createMemo<SliverRow[]>((): SliverRow[] => {
		const items = data();
		const next = new Map<T, SliverRow>();
		const out: SliverRow[] = [];
		for (let i = 0; i < items.length; i += columns) {
			const first = items[i];
			const row = cache.has(first) ? cache.get(first) as SliverRow : new SliverRow((index: Accessor<number>): NeonNode => {
				const each = accessor((): T[] => members(first));
				return View({
					style: accessor((): Style => mergeStyle({ flexDirection: "row" }, rowStyle === null ? {} : rowStyle as Style)),
					children: For<T>({
						each,
						children: (item: T, column: Accessor<number>): NeonNode => {
							const position = accessor((): number => data().indexOf(item) as number);
							return View({ style: accessor((): Style => ({ flex: 1 })), children: renderItem(item, position) });
						},
					}),
				});
			}, false);
			next.set(first, row);
			out.push(row);
		}
		cache = next;
		return out;
	});
	return { rows };
}

export function CustomScrollView(props: {
	slivers: Sliver[];
	onScroll?: ((e: NeonEvent) => void) | null;
	scrollEventThrottle?: Accessor<number> | null;
	style?: Accessor<Style> | null;
	contentContainerStyle?: Accessor<Style> | null;
	ref?: ((handle: FlatListHandle) => void) | null;
}): NeonNode {
	const slivers = props.slivers;
	const rows = createMemo<SliverRow[]>((): SliverRow[] => {
		const out: SliverRow[] = [];
		for (const sliver of slivers) {
			for (const row of sliver.rows()) { out.push(row); }
		}
		return out;
	});
	const pinned = accessor((): int32[] => {
		const out: int32[] = [];
		const all = rows();
		for (let i = 0; i < all.length; i += 1) {
			if (all[i].sticky) { out.push(i as int32); }
		}
		return out;
	});
	return VirtualizedList<SliverRow, SliverRow[]>({
		data: rows,
		getItem: (data: SliverRow[], index: number): SliverRow => data[index],
		getItemCount: (data: SliverRow[]): number => data.length,
		renderItem: (info: ListRenderItemInfo<SliverRow>): NeonNode => info.item.render(info.index),
		stickyHeaderIndices: pinned,
		onScroll: props.onScroll,
		scrollEventThrottle: props.scrollEventThrottle,
		style: props.style,
		contentContainerStyle: props.contentContainerStyle,
		ref: props.ref,
	});
}
