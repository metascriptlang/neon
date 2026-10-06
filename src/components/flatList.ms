import { Accessor, createSignal, batch, untrack } from "../core/signal";
import { createEffect } from "../core/effect";
import { onCleanup } from "../core/cleanup";
import { mapArray } from "../core/array";
import { element } from "../macros/ui/element";
import { NeonNode, regionNode } from "../render/node";
import { Row, makeRow } from "../render/reconcile";
import { NeonEvent } from "../render/event";
import { Host } from "../render/hostTypes";
import { Style } from "../render/style";
import { ScrollView, ScrollViewHandle, View, KeyboardDismissMode, KeyboardShouldPersistTaps } from "./primitives";
import { CellMetrics, CellRange, WindowScroll, computeWindowedRenderLimits } from "./list/virtualizeUtils";
import { CellRenderMask } from "./list/cellRenderMask";
import { CellSource, ListMetricsAggregator, ListOrientation } from "./list/listMetrics";

export interface ListRenderItemInfo<T> {
	item: T;
	index: Accessor<number>;
}

export interface ItemLayout {
	length: number;
	offset: number;
	index: number;
}

export interface EndReachedInfo {
	distanceFromEnd: number;
}

export interface ScrollToIndexFailedInfo {
	index: number;
	highestMeasuredFrameIndex: number;
	averageItemLength: number;
}

export interface ScrollToIndexOptions {
	index: number;
	animated?: boolean | null;
	viewPosition?: number | null;
	viewOffset?: number | null;
}

export interface ScrollToOffsetOptions {
	offset: number;
	animated?: boolean | null;
}

export interface ScrollToEndOptions {
	animated?: boolean | null;
}

// RN VirtualizedList._maybeCallOnEdgeReached: 2 px without onEndReachedThreshold, distances under 0.001 read 0.
const DEFAULT_THRESHOLD_PX = 2;
const ON_EDGE_REACHED_EPSILON = 0.001;


class ListCell {
	index: number = -1;
	setIndex: (index: number) => void;
	setSize: (size: number) => void;
	make: (scheduleUpdate: () => void) => NeonNode;

	constructor(setIndex: (index: number) => void, setSize: (size: number) => void, make: (scheduleUpdate: () => void) => NeonNode) {
		this.setIndex = setIndex;
		this.setSize = setSize;
		this.make = make;
	}
}

export class FlatListHandle {
	private scroll: ScrollViewHandle;
	private frameOf: (index: number) => CellMetrics;
	private offsetOf: (index: number) => number;
	private count: () => number;
	private viewport: () => number;
	private horizontal: () => boolean;
	private unmeasured: (index: number) => boolean;

	constructor(scroll: ScrollViewHandle, frameOf: (index: number) => CellMetrics, offsetOf: (index: number) => number, count: () => number, viewport: () => number, horizontal: () => boolean, unmeasured: (index: number) => boolean) {
		this.scroll = scroll;
		this.frameOf = frameOf;
		this.offsetOf = offsetOf;
		this.count = count;
		this.viewport = viewport;
		this.horizontal = horizontal;
		this.unmeasured = unmeasured;
	}

	private moveTo(offset: number, animated: boolean): void {
		const horizontal = this.horizontal();
		this.scroll.scrollTo({ x: horizontal ? offset : 0, y: horizontal ? 0 : offset, animated });
	}

	scrollToOffset(options: ScrollToOffsetOptions): void {
		const { offset, animated = true } = options;
		this.moveTo(offset, animated);
	}

	scrollToIndex(options: ScrollToIndexOptions): void {
		const { index, animated = true, viewPosition = 0, viewOffset = 0 } = options;
		const n = this.count();
		if (index < 0) { throw `scrollToIndex out of range: requested index ${index} but minimum is 0`; }
		if (n < 1) { throw `scrollToIndex out of range: item length ${n} but minimum is 1`; }
		if (index >= n) { throw `scrollToIndex out of range: requested index ${index} is out of 0 to ${n - 1}`; }
		if (this.unmeasured(index)) { return; }
		const frame = this.frameOf(Math.floor(index));
		const offset = Math.max(0, this.offsetOf(index) - viewPosition * (this.viewport() - frame.length)) - viewOffset;
		this.moveTo(offset, animated);
	}

	scrollToEnd(options: ScrollToEndOptions): void {
		const { animated = true } = options;
		const n = this.count();
		if (n === 0) { return; }
		const frame = this.frameOf(n - 1);
		this.moveTo(Math.max(0, frame.offset + frame.length - this.viewport()), animated);
	}
}

export function FlatList<T>(props: {
	data: Accessor<T[]>;
	renderItem: (info: ListRenderItemInfo<T>) => NeonNode;
	getItemLayout?: ((data: T[], index: number) => ItemLayout) | null;
	initialNumToRender?: Accessor<number> | null;
	onScrollToIndexFailed?: ((info: ScrollToIndexFailedInfo) => void) | null;
	maxToRenderPerBatch?: Accessor<number> | null;
	updateCellsBatchingPeriod?: Accessor<number> | null;
	windowSize?: Accessor<number> | null;
	onEndReached?: ((info: EndReachedInfo) => void) | null;
	onEndReachedThreshold?: Accessor<number> | null;
	onScroll?: ((e: NeonEvent) => void) | null;
	onLayout?: ((e: NeonEvent) => void) | null;
	scrollEventThrottle?: Accessor<number> | null;
	horizontal?: Accessor<boolean> | null;
	scrollEnabled?: Accessor<boolean> | null;
	showsHorizontalScrollIndicator?: Accessor<boolean> | null;
	showsVerticalScrollIndicator?: Accessor<boolean> | null;
	pagingEnabled?: Accessor<boolean> | null;
	keyboardDismissMode?: Accessor<KeyboardDismissMode> | null;
	keyboardShouldPersistTaps?: Accessor<KeyboardShouldPersistTaps> | null;
	onScrollBeginDrag?: ((e: NeonEvent) => void) | null;
	onScrollEndDrag?: ((e: NeonEvent) => void) | null;
	onMomentumScrollBegin?: ((e: NeonEvent) => void) | null;
	onMomentumScrollEnd?: ((e: NeonEvent) => void) | null;
	onRefresh?: (() => void) | null;
	refreshing?: Accessor<boolean> | null;
	onContentSizeChange?: ((width: number, height: number) => void) | null;
	style?: Accessor<Style> | null;
	contentContainerStyle?: Accessor<Style> | null;
	ref?: ((handle: FlatListHandle) => void) | null;
}): NeonNode {
	const getItemLayout = props.getItemLayout;
	const data = props.data;
	const renderItem = props.renderItem;
	const initialProp = props.initialNumToRender;
	const batchProp = props.maxToRenderPerBatch;
	const periodProp = props.updateCellsBatchingPeriod;
	const windowProp = props.windowSize;
	const thresholdProp = props.onEndReachedThreshold;
	const endReached = props.onEndReached;
	const userScroll = props.onScroll;
	const userLayout = props.onLayout;
	const userRef = props.ref;
	const horizontal = props.horizontal;
	const isHorizontal = (): boolean => horizontal !== null && (horizontal as () => boolean)();
	const orientation = (): ListOrientation => ({ horizontal: isHorizontal(), rtl: false });

	let items: T[] = [];
	const metrics = new ListMetricsAggregator<T>();
	const source: CellSource<T> = {
		count: (): int32 => items.length as int32,
		keyAt: (index: int32): T => items[index],
		layoutAt: getItemLayout === null ? null : (index: int32): CellMetrics => {
			const layout = (getItemLayout as (data: T[], index: number) => ItemLayout)(items, index as number);
			return { index, length: layout.length, offset: layout.offset, isMounted: true };
		},
	};
	const metricsAt = (index: int32): CellMetrics => metrics.getCellMetricsApprox(index, source);

	const initialNumToRender = (): int32 => initialProp === null ? 10 : (initialProp as () => number)() as int32;
	const maxToRenderPerBatch = (): int32 => batchProp === null ? 10 : (batchProp as () => number)() as int32;
	const windowSize = (): int32 => windowProp === null ? 21 : (windowProp as () => number)() as int32;
	const batchingPeriod = (): number => periodProp === null ? 50 : (periodProp as () => number)();
	const initialRegion = (n: int32): CellRange => ({ first: 0, last: Math.min(n, initialNumToRender()) - 1 });

	let offset = 0.0;
	let visibleLength = 0.0;
	let sentEndForContentLength = 0.0;
	let cellsAroundViewport: CellRange = { first: 0, last: -1 };
	let renderedMask: CellRenderMask | null = null;
	let itemCells = new Map<T, ListCell>();
	let spacerCells = new Map<int32, ListCell>();
	let updateTimeout: number = -1;
	let hiPriInProgress = false;
	const [cells, setCells] = createSignal<ListCell[]>([]);
	onCleanup((): void => {
		if (updateTimeout >= 0) { clearTimeout(updateTimeout); }
	});

	// RN VirtualizedList._constrainToItemCount.
	const constrainToItemCount = (range: CellRange, n: int32): CellRange => {
		const maxFirst = Math.max(0, n - 1 - maxToRenderPerBatch());
		return { first: Math.min(Math.max(0, range.first), maxFirst), last: Math.min(n - 1, range.last) };
	};

	// RN VirtualizedList._adjustCellsAroundViewport.
	const adjustCellsAroundViewport = (n: int32): CellRange => {
		if (visibleLength <= 0.0 || metrics.getContentLength() <= 0.0) {
			return cellsAroundViewport.last >= n ? constrainToItemCount(cellsAroundViewport, n) : cellsAroundViewport;
		}
		const scroll: WindowScroll = { offset, velocity: 0.0, visibleLength, zoomScale: 1.0 };
		return computeWindowedRenderLimits(n, maxToRenderPerBatch(), windowSize(), cellsAroundViewport, metricsAt, scroll);
	};

	const spacerCell = (): ListCell => {
		const [size, setSize] = createSignal<number>(0);
		return new ListCell((index: number): void => {}, (next: number): void => { setSize(next); }, (scheduleUpdate: () => void): NeonNode => element(<View style={{ width: isHorizontal() ? size() : null, height: isHorizontal() ? null : size(), flexShrink: 0 }} />));
	};

	const itemCell = (item: T, index: number): ListCell => {
		const [at, setAt] = createSignal<number>(index);
		return new ListCell((next: number): void => { setAt(next); }, (size: number): void => {}, (scheduleUpdate: () => void): NeonNode => {
			if (getItemLayout !== null) { return renderItem({ item, index: at }); }
			onCleanup((): void => { metrics.notifyCellUnmounted(item); });
			const onCellLayout = (e: NeonEvent): void => {
				if (metrics.notifyCellLayout(at() as int32, item, orientation(), { x: e.x, y: e.y, width: e.width, height: e.height })) { scheduleUpdate(); }
			};
			return element(<View onLayout={onCellLayout}>{renderItem({ item, index: at })}</View>);
		});
	};

	const buildCells = (mask: CellRenderMask): ListCell[] => {
		const out: ListCell[] = [];
		const nextItems = new Map<T, ListCell>();
		const nextSpacers = new Map<int32, ListCell>();
		const regions = mask.enumerateRegions();
		for (let r = 0; r < regions.length; r += 1) {
			const region = regions[r];
			if (region.isSpacer) {
				const highest = metrics.getHighestMeasuredCellIndex();
				const lastIndex = r === regions.length - 1 && getItemLayout === null ? (region.last > highest ? highest : region.last) : region.last;
				const first = metricsAt(region.first);
				const cell = spacerCells.has(region.first) ? spacerCells.get(region.first) as ListCell : spacerCell();
				if (lastIndex < region.first) {
					cell.setSize(0);
				} else {
					const last = metricsAt(lastIndex);
					cell.setSize(last.offset + last.length - first.offset);
				}
				nextSpacers.set(region.first, cell);
				out.push(cell);
				continue;
			}
			for (let i = region.first; i <= region.last; i += 1) {
				const item = items[i];
				if (nextItems.has(item)) {
					throw `FlatList: the same item is at rows ${(nextItems.get(item) as ListCell).index} and ${i}; rows are told apart by their item`;
				}
				const cell = itemCells.has(item) ? itemCells.get(item) as ListCell : itemCell(item, i as number);
				cell.index = i as number;
				cell.setIndex(i as number);
				nextItems.set(item, cell);
				out.push(cell);
			}
		}
		itemCells = nextItems;
		spacerCells = nextSpacers;
		return out;
	};

	// RN VirtualizedList._maybeCallOnEdgeReached, the onEndReached half.
	const maybeCallOnEndReached = (n: int32): void => {
		if (endReached === null || !metrics.hasContentLength() || visibleLength === 0.0) { return; }
		const contentLength = metrics.getContentLength();
		let distanceFromEnd = contentLength - visibleLength - offset;
		if (distanceFromEnd < ON_EDGE_REACHED_EPSILON) { distanceFromEnd = 0; }
		const endThreshold = thresholdProp === null ? DEFAULT_THRESHOLD_PX : (thresholdProp as () => number)() * visibleLength;
		const within = distanceFromEnd <= endThreshold;
		if (within && cellsAroundViewport.last === n - 1 && contentLength !== sentEndForContentLength) {
			sentEndForContentLength = contentLength;
			(endReached as (info: EndReachedInfo) => void)({ distanceFromEnd });
		}
		if (!within) { sentEndForContentLength = 0.0; }
	};

	const renderMask = (n: int32): CellRenderMask => {
		const mask = new CellRenderMask(n);
		if (n > 0) {
			mask.addCells(cellsAroundViewport);
			mask.addCells(initialRegion(n));
		}
		return mask;
	};

	const shouldRenderWithPriority = (n: int32): boolean => {
		const first = cellsAroundViewport.first;
		const last = cellsAroundViewport.last;
		if (first > 0 && offset - metricsAt(first).offset < 0) { return true; }
		return last >= 0 && last < n - 1 && metricsAt(last).offset - (offset + visibleLength) < 0;
	};

	const updateCellsToRender = (): boolean => {
		const n = items.length as int32;
		const previous = cellsAroundViewport;
		cellsAroundViewport = adjustCellsAroundViewport(n);
		const mask = renderMask(n);
		if (cellsAroundViewport.first === previous.first && cellsAroundViewport.last === previous.last && renderedMask !== null && mask.equals(renderedMask as CellRenderMask)) { return false; }
		renderedMask = mask;
		batch((): void => { setCells(buildCells(mask)); });
		return true;
	};

	const scheduleCellsToRenderUpdate = (rendered: boolean): void => {
		const hiPri = hiPriInProgress;
		const update = (): void => {
			if (updateCellsToRender()) { scheduleCellsToRenderUpdate(true); }
		};
		if ((metrics.getAverageCellLength() > 0.0 || props.getItemLayout !== null) && shouldRenderWithPriority(items.length as int32) && !hiPriInProgress) {
			hiPriInProgress = true;
			if (updateTimeout >= 0) {
				clearTimeout(updateTimeout);
				updateTimeout = -1;
			}
			update();
		} else if (updateTimeout < 0) {
			updateTimeout = setTimeout((): void => {
				updateTimeout = -1;
				update();
			}, batchingPeriod());
		}
		if (!rendered) { return; }
		if (hiPri) { hiPriInProgress = false; }
		if (props.getItemLayout !== null) { maybeCallOnEndReached(items.length as int32); }
	};

	let seenCount: int32 = -1;
	createEffect((): void => {
		const next = data();
		untrack((): void => {
			items = next;
			const n = items.length as int32;
			if (seenCount < 0) {
				cellsAroundViewport = initialRegion(n);
			} else if (n !== seenCount) {
				cellsAroundViewport = constrainToItemCount(cellsAroundViewport, n);
			}
			const first = seenCount < 0;
			seenCount = n;
			renderedMask = renderMask(n);
			batch((): void => { setCells(buildCells(renderedMask as CellRenderMask)); });
			if (!first) { scheduleCellsToRenderUpdate(true); }
		});
	});

	const scheduleUpdate = (): void => { scheduleCellsToRenderUpdate(false); };
	const rows = regionNode((host: Host) => mapArray<ListCell, Row>(cells, (cell: ListCell, i: Accessor<number>): Row => makeRow(cell.make(scheduleUpdate)), false));

	const onScroll = (e: NeonEvent): void => {
		if (userScroll !== null) { (userScroll as (e: NeonEvent) => void)(e); }
		offset = isHorizontal() ? e.x : e.y;
		visibleLength = isHorizontal() ? e.width : e.height;
		maybeCallOnEndReached(items.length as int32);
		scheduleCellsToRenderUpdate(false);
	};
	const onLayout = (e: NeonEvent): void => {
		visibleLength = isHorizontal() ? e.width : e.height;
		if (userLayout !== null) { (userLayout as (e: NeonEvent) => void)(e); }
		scheduleCellsToRenderUpdate(false);
		maybeCallOnEndReached(items.length as int32);
	};
	const onContentSizeChange = (width: number, height: number): void => {
		metrics.notifyListContentLayout(orientation(), width, height);
		const changed = props.onContentSizeChange;
		if (changed !== null) { (changed as (width: number, height: number) => void)(width, height); }
		scheduleCellsToRenderUpdate(false);
		maybeCallOnEndReached(items.length as int32);
	};
	const scrollRef = (h: ScrollViewHandle): void => {
		if (userRef === null) { return; }
		(userRef as (handle: FlatListHandle) => void)(new FlatListHandle(
			h,
			(index: number): CellMetrics => metricsAt(index as int32),
			(index: number): number => metrics.getCellOffsetApprox(index, source),
			(): number => items.length,
			(): number => visibleLength,
			isHorizontal,
			(index: number): boolean => {
				if (getItemLayout !== null || index <= metrics.getHighestMeasuredCellIndex()) { return false; }
				const failed = props.onScrollToIndexFailed;
				if (failed === null) {
					throw "scrollToIndex should be used in conjunction with getItemLayout or onScrollToIndexFailed, otherwise there is no way to know the location of offscreen indices or handle failures.";
				}
				(failed as (info: ScrollToIndexFailedInfo) => void)({
					averageItemLength: metrics.getAverageCellLength(),
					highestMeasuredFrameIndex: metrics.getHighestMeasuredCellIndex(),
					index,
				});
				return true;
			},
		));
	};

	// Parked: <ScrollView style={props.style}> wraps a nullable Accessor again (BUGS.md §3, isAccessorTyped) —
	// ~/metascript/.inbox/compiler/2026-09-19-design-typed-slots-value-read-and-text-coercion.md
	return ScrollView({
		style: props.style, contentContainerStyle: props.contentContainerStyle, class: null,
		scrollEventThrottle: props.scrollEventThrottle, onScroll, onLayout, onContentSizeChange, ref: scrollRef, children: rows,
		horizontal: props.horizontal, scrollEnabled: props.scrollEnabled,
		showsHorizontalScrollIndicator: props.showsHorizontalScrollIndicator, showsVerticalScrollIndicator: props.showsVerticalScrollIndicator,
		pagingEnabled: props.pagingEnabled, keyboardDismissMode: props.keyboardDismissMode, keyboardShouldPersistTaps: props.keyboardShouldPersistTaps,
		onScrollBeginDrag: props.onScrollBeginDrag, onScrollEndDrag: props.onScrollEndDrag,
		onMomentumScrollBegin: props.onMomentumScrollBegin, onMomentumScrollEnd: props.onMomentumScrollEnd,
		onRefresh: props.onRefresh, refreshing: props.refreshing,
	});
}
