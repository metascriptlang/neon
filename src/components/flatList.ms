import { Accessor, Signal, accessor, createSignal, batch, untrack } from "../core/signal";
import { createEffect } from "../core/effect";
import { onCleanup } from "../core/cleanup";
import { mapArray } from "../core/array";
import { element } from "../macros/ui/element";
import { Show } from "../macros/ui/flow";
import { NeonNode, regionNode } from "../render/node";
import { Row, makeRow } from "../render/reconcile";
import { NeonEvent } from "../render/event";
import { Host } from "../render/hostTypes";
import { Style, mergeStyle } from "../render/style";
import { ScrollView, ScrollViewHandle, View, KeyboardDismissMode, KeyboardShouldPersistTaps } from "./primitives";
import { CellMetrics, CellRange, WindowScroll, computeWindowedRenderLimits, shouldRenderWithPriority } from "./list/virtualizeUtils";
import { CellRenderMask } from "./list/cellRenderMask";
import { CellSource, LayoutBox, ListMetricsAggregator, ListOrientation } from "./list/listMetrics";
import { stickyTranslation } from "./list/sticky";

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

export interface StartReachedInfo {
	distanceFromStart: number;
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
class StickyState {
	offset: Signal<number> = new Signal<number>(0);
	viewport: Signal<number> = new Signal<number>(0);
	layoutVersion: Signal<int32> = new Signal<int32>(0);
	indicesVersion: Signal<int32> = new Signal<int32>(0);
	header: CellMetrics | null = null;
}


export class FlatListHandle {
	private scroll: ScrollViewHandle;
	private frameOf: (index: number) => CellMetrics;
	private offsetOf: (index: number) => number;
	private count: () => number;
	private viewport: () => number;
	private horizontal: () => boolean;
	private unmeasured: (index: number) => boolean;
	private footerLength: () => number;

	constructor(scroll: ScrollViewHandle, frameOf: (index: number) => CellMetrics, offsetOf: (index: number) => number, count: () => number, viewport: () => number, horizontal: () => boolean, unmeasured: (index: number) => boolean, footerLength: () => number) {
		this.scroll = scroll;
		this.frameOf = frameOf;
		this.offsetOf = offsetOf;
		this.count = count;
		this.viewport = viewport;
		this.horizontal = horizontal;
		this.unmeasured = unmeasured;
		this.footerLength = footerLength;
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
		this.moveTo(Math.max(0, frame.offset + frame.length + this.footerLength() - this.viewport()), animated);
	}
}

export function FlatList<T>(props: {
	data: Accessor<T[]>;
	renderItem: (info: ListRenderItemInfo<T>) => NeonNode;
	getItemLayout?: ((data: T[], index: number) => ItemLayout) | null;
	ListHeaderComponent?: NeonNode | null;
	ListFooterComponent?: NeonNode | null;
	ListEmptyComponent?: NeonNode | null;
	ItemSeparatorComponent?: NeonNode | null;
	ListHeaderComponentStyle?: Accessor<Style> | null;
	ListFooterComponentStyle?: Accessor<Style> | null;
	initialNumToRender?: Accessor<number> | null;
	initialScrollIndex?: Accessor<number> | null;
	onScrollToIndexFailed?: ((info: ScrollToIndexFailedInfo) => void) | null;
	maxToRenderPerBatch?: Accessor<number> | null;
	updateCellsBatchingPeriod?: Accessor<number> | null;
	windowSize?: Accessor<number> | null;
	onEndReached?: ((info: EndReachedInfo) => void) | null;
	onEndReachedThreshold?: Accessor<number> | null;
	onStartReached?: ((info: StartReachedInfo) => void) | null;
	onStartReachedThreshold?: Accessor<number> | null;
	onScroll?: ((e: NeonEvent) => void) | null;
	onLayout?: ((e: NeonEvent) => void) | null;
	scrollEventThrottle?: Accessor<number> | null;
	horizontal?: Accessor<boolean> | null;
	inverted?: Accessor<boolean> | null;
	numColumns?: Accessor<number> | null;
	columnWrapperStyle?: Accessor<Style> | null;
	stickyHeaderIndices?: Accessor<int32[]> | null;
	invertStickyHeaders?: Accessor<boolean> | null;
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
	const initialIndexProp = props.initialScrollIndex;
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
	const isInverted = (): boolean => props.inverted !== null && (props.inverted as Accessor<boolean>)();
	const inversionStyle = (): Style => ({ transform: isInverted() ? (isHorizontal() ? "scaleX(-1)" : "scaleY(-1)") : null });
	const slotStyle = (user: Accessor<Style> | null): Accessor<Style> => accessor((): Style => mergeStyle(inversionStyle(), user === null ? {} : (user as Accessor<Style>)()));

	let items: T[] = [];
	const columnsProp = props.numColumns;
	const columnsNow = (): int32 => columnsProp === null ? 1 : (columnsProp as Accessor<number>)() as int32;
	const columns: int32 = untrack(columnsNow);
	const cellCount = (): int32 => columns > 1 ? ((items.length as int32) + columns - 1) / columns : items.length as int32;
	if (columnsProp !== null || props.columnWrapperStyle !== null) {
		createEffect((): void => {
			const next = columnsNow();
			const horizontalNow = isHorizontal();
			untrack((): void => {
				if (next !== columns) {
					throw "FlatList: Changing numColumns on the fly is not supported. Mount a new FlatList when changing the number of columns.";
				}
				if (columns > 1 && horizontalNow) { throw "FlatList: numColumns does not support horizontal."; }
				if (columns <= 1 && props.columnWrapperStyle !== null) {
					throw "FlatList: columnWrapperStyle not supported for single column lists";
				}
			});
		});
	}
	const metrics = new ListMetricsAggregator<T>();
	const source: CellSource<T> = {
		count: (): int32 => cellCount(),
		keyAt: (index: int32): T => items[index * columns],
		layoutAt: getItemLayout === null ? null : (index: int32): CellMetrics => {
			const layout = (getItemLayout as (data: T[], index: number) => ItemLayout)(items, index as number);
			return { index, length: layout.length, offset: layout.offset, isMounted: true };
		},
	};
	const metricsAt = (index: int32): CellMetrics => metrics.getCellMetricsApprox(index, source);
	const sticky = props.stickyHeaderIndices === null ? null : new StickyState();
	let stickyIndices: int32[] = [];
	const headerOffset: int32 = props.ListHeaderComponent === null ? 0 : 1;
	const stickyFrame = (childIndex: int32): CellMetrics | null => {
		if (childIndex === 0 && headerOffset === 1) { return (sticky as StickyState).header; }
		const index = childIndex - headerOffset;
		return index < 0 || index >= cellCount() ? null : metrics.getCellMetrics(index, source);
	};
	const stickyStyle = (index: () => int32): Accessor<Style> => accessor((): Style => {
		const state = sticky as StickyState;
		state.indicesVersion.get();
		const childIndex = index();
		let found = false;
		let nextIndex: int32 = -1;
		for (const at of stickyIndices) {
			if (at === childIndex) { found = true; }
			if (at > childIndex && (nextIndex < 0 || at < nextIndex)) { nextIndex = at; }
		}
		if (!found) { return { flexShrink: 0 }; }
		if (isHorizontal()) { throw "FlatList: stickyHeaderIndices does not support horizontal lists"; }
		state.layoutVersion.get();
		const frame = stickyFrame(childIndex);
		if (frame === null) { return { flexShrink: 0, zIndex: 10 }; }
		const next = nextIndex < 0 ? null : stickyFrame(nextIndex);
		const invert = props.invertStickyHeaders;
		const translation = stickyTranslation(frame.offset, frame.length, next === null ? null : next.offset, state.offset.get(), state.viewport.get(), invert === null ? isInverted() : (invert as Accessor<boolean>)());
		return { flexShrink: 0, zIndex: 10, transform: "translateY(" + translation.toString() + "px)" };
	});

	const initialNumToRender = (): int32 => initialProp === null ? 10 : (initialProp as () => number)() as int32;
	const maxToRenderPerBatch = (): int32 => batchProp === null ? 10 : (batchProp as () => number)() as int32;
	const windowSize = (): int32 => windowProp === null ? 21 : (windowProp as () => number)() as int32;
	const batchingPeriod = (): number => periodProp === null ? 50 : (periodProp as () => number)();
	const initialScrollIndex = (): number => initialIndexProp === null ? 0 : (initialIndexProp as () => number)();
	const initialRegion = (n: int32): CellRange => {
		const first = Math.max(0, Math.min(n - 1, Math.floor(initialScrollIndex()) as int32));
		return { first, last: Math.min(n, first + initialNumToRender()) - 1 };
	};

	let offset = 0.0;
	let velocity = 0.0;
	let timeStamp = 0.0;
	let sentStartForContentLength = 0.0;
	let visibleLength = 0.0;
	let sentEndForContentLength = 0.0;
	let pendingScrollUpdateCount = initialScrollIndex() > 0 ? 1 : 0;
	let triggeredInitialScrollToIndex = false;
	let handle: FlatListHandle | null = null;
	let cellsAroundViewport: CellRange = { first: 0, last: -1 };
	let renderedMask: CellRenderMask | null = null;
	let itemCells = new Map<T, ListCell>();
	let spacerCells = new Map<int32, ListCell>();
	let gridRows = new Map<int32, ListCell>();
	let updateTimeout: number = -1;
	let hiPriInProgress = false;
	const [cells, setCells] = createSignal<ListCell[]>([]);
	const [cellTotal, setCellTotal] = createSignal<number>(0);
	let footerLength = 0.0;
	let footerMeasured = props.ListFooterComponent === null;
	let initialContentReady = false;
	const maybeScrollToInitialIndex = (): void => {
		const index = initialScrollIndex();
		if (!initialContentReady || !footerMeasured || index <= 0 || triggeredInitialScrollToIndex || handle === null) { return; }
		triggeredInitialScrollToIndex = true;
		if (index < cellCount()) {
			(handle as FlatListHandle).scrollToIndex({ animated: false, index });
		} else {
			(handle as FlatListHandle).scrollToEnd({ animated: false });
		}
	};
	let warnedInitialScrollIndex = false;
	const checkInitialScrollIndex = (n: int32): void => {
		if (initialIndexProp === null || warnedInitialScrollIndex || triggeredInitialScrollToIndex) { return; }
		const index = initialScrollIndex();
		if (index >= 0 && (n === 0 || index < n)) { return; }
		warnedInitialScrollIndex = true;
		console.warn(`initialScrollIndex "${index}" is not valid (list has ${n} items)`);
	};
	const fixedCell = (node: NeonNode): ListCell => new ListCell((index: number): void => {}, (size: number): void => {}, (scheduleUpdate: () => void): NeonNode => node);
	const header = props.ListHeaderComponent;
	const footer = props.ListFooterComponent;
	const empty = props.ListEmptyComponent;
	const separator = props.ItemSeparatorComponent;
	const headerNode = header === null ? null : View({ children: header, style: slotStyle(props.ListHeaderComponentStyle) });
	const headerCell = headerNode === null ? null : fixedCell(sticky === null ? headerNode : View({
		children: headerNode, style: stickyStyle((): int32 => 0),
		onLayout: (e: NeonEvent): void => {
			const state = sticky as StickyState;
			state.header = { index: -1, offset: e.y, length: e.height, isMounted: true };
			state.layoutVersion.set(state.layoutVersion.peek() + 1);
		},
	}));
	const footerCell = footer === null ? null : fixedCell(View({
		children: footer, style: slotStyle(props.ListFooterComponentStyle),
		onLayout: (e: NeonEvent): void => {
			footerLength = isHorizontal() ? e.width : e.height;
			footerMeasured = true;
			maybeScrollToInitialIndex();
		},
	}));
	const emptyCell = empty === null ? null : fixedCell(View({ children: empty, style: slotStyle(null) }));
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
		if (pendingScrollUpdateCount > 0) {
			return cellsAroundViewport.last >= n ? constrainToItemCount(cellsAroundViewport, n) : cellsAroundViewport;
		}
		const scroll: WindowScroll = { offset, velocity, visibleLength, zoomScale: 1.0 };
		return computeWindowedRenderLimits(n, maxToRenderPerBatch(), windowSize(), cellsAroundViewport, metricsAt, scroll);
	};

	const spacerCell = (): ListCell => {
		const [size, setSize] = createSignal<number>(0);
		return new ListCell((index: number): void => {}, (next: number): void => { setSize(next); }, (scheduleUpdate: () => void): NeonNode => element(<View style={{ width: isHorizontal() ? size() : null, height: isHorizontal() ? null : size(), flexShrink: 0 }} />));
	};

	const cellNode = (at: Accessor<number>, keyOf: () => T, row: NeonNode, scheduleUpdate: () => void, measured: (box: LayoutBox) => void): NeonNode => {
		if (separator === null && getItemLayout !== null && props.inverted === null && sticky === null) { return row; }
		const tail = separator === null ? null : Show({
			when: accessor((): boolean => at() < cellTotal() - 1),
			children: separator, fallback: null,
		});
		onCleanup((): void => { metrics.notifyCellUnmounted(keyOf()); });
		const onCellLayout = getItemLayout !== null && sticky === null ? null : (e: NeonEvent): void => {
			const box: LayoutBox = { x: e.x, y: e.y, width: e.width, height: e.height };
			measured(box);
			if (getItemLayout === null && metrics.notifyCellLayout(at() as int32, keyOf(), orientation(), box)) { scheduleUpdate(); }
			if (sticky !== null) {
				const state = sticky as StickyState;
				state.layoutVersion.set(state.layoutVersion.peek() + 1);
			}
		};
		const style = accessor((): Style => ({
			...inversionStyle(),
			display: "flex", flexShrink: 0,
			flexDirection: isHorizontal() ? (isInverted() ? "row-reverse" : "row") : (isInverted() ? "column-reverse" : "column"),
		}));
		const inner = View({ style, onLayout: sticky === null ? onCellLayout : null, children: element(<>{row}{tail}</>) });
		return sticky === null ? inner : View({ style: stickyStyle((): int32 => (at() as int32) + headerOffset), onLayout: onCellLayout, children: inner });
	};

	const itemCell = (item: T, index: number): ListCell => {
		const [at, setAt] = createSignal<number>(index);
		return new ListCell((next: number): void => { setAt(next); }, (size: number): void => {}, (scheduleUpdate: () => void): NeonNode =>
			cellNode(at, (): T => item, renderItem({ item, index: at }), scheduleUpdate, (box: LayoutBox): void => {}));
	};

	const rowItems = (row: int32): T[] => {
		const out: T[] = [];
		const end = Math.min(items.length as int32, (row + 1) * columns);
		for (let i = row * columns; i < end; i += 1) { out.push(items[i]); }
		return out;
	};

	const gridRowCell = (row: int32): ListCell => {
		const [at, setAt] = createSignal<number>(row as number);
		const [members, setMembers] = createSignal<T[]>(rowItems(row));
		let key: T = items[row * columns];
		let measuredBox: LayoutBox | null = null;
		const moveTo = (next: number): void => {
			setAt(next);
			const nextMembers = rowItems(next as int32);
			const current: T[] = untrack<T[]>(members);
			let same = current.length === nextMembers.length;
			for (let i = 0; same && i < current.length; i += 1) { same = current[i] === nextMembers[i]; }
			if (!same) { setMembers(nextMembers); }
			if (nextMembers[0] === key) { return; }
			key = nextMembers[0];
			if (measuredBox !== null && getItemLayout === null) {
				metrics.notifyCellLayout(next as int32, key, orientation(), measuredBox as LayoutBox);
			}
		};
		return new ListCell(moveTo, (size: number): void => {}, (scheduleUpdate: () => void): NeonNode => {
			const wrapper = props.columnWrapperStyle;
			const rowStyle = accessor((): Style => mergeStyle({ display: "flex", flexDirection: "row" }, wrapper === null ? {} : (wrapper as Accessor<Style>)()));
			const cells = regionNode((host: Host) => mapArray<T, Row>(members, (item: T, column: Accessor<number>): Row =>
				makeRow(renderItem({ item, index: accessor((): number => at() * (columns as number) + column()) })), true));
			return cellNode(at, (): T => key, View({ style: rowStyle, children: cells }), scheduleUpdate, (box: LayoutBox): void => { measuredBox = box; });
		});
	};

	const checkGridItems = (row: int32, seen: Map<T, int32>): void => {
		const end = Math.min(items.length as int32, (row + 1) * columns);
		for (let i = row * columns; i < end; i += 1) {
			if (seen.has(items[i])) {
				throw `FlatList: the same item is at indices ${seen.get(items[i]) as int32} and ${i}; items are told apart by their identity`;
			}
			seen.set(items[i], i);
		}
	};

	const buildCells = (mask: CellRenderMask): ListCell[] => {
		const out: ListCell[] = [];
		const nextItems = new Map<T, ListCell>();
		const nextRows = new Map<int32, ListCell>();
		const nextSpacers = new Map<int32, ListCell>();
		const gridSeen = new Map<T, int32>();
		if (headerCell !== null) { out.push(headerCell as ListCell); }
		if (items.length === 0 && emptyCell !== null) { out.push(emptyCell as ListCell); }
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
				if (columns > 1) {
					checkGridItems(i, gridSeen);
					const rowCell = gridRows.has(i) ? gridRows.get(i) as ListCell : gridRowCell(i);
					rowCell.index = i as number;
					rowCell.setIndex(i as number);
					nextRows.set(i, rowCell);
					out.push(rowCell);
					continue;
				}
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
		gridRows = nextRows;
		spacerCells = nextSpacers;
		if (footerCell !== null) { out.push(footerCell as ListCell); }
		return out;
	};

	const maybeCallOnEdgeReached = (n: int32): void => {
		const startReached = props.onStartReached;
		if ((endReached === null && startReached === null) || !metrics.hasContentLength() || visibleLength === 0.0 || pendingScrollUpdateCount > 0) { return; }
		const contentLength = metrics.getContentLength();
		let distanceFromEnd = contentLength - visibleLength - offset;
		if (distanceFromEnd < ON_EDGE_REACHED_EPSILON) { distanceFromEnd = 0; }
		const endThreshold = thresholdProp === null ? DEFAULT_THRESHOLD_PX : (thresholdProp as () => number)() * visibleLength;
		const withinEnd = distanceFromEnd <= endThreshold;
		if (endReached !== null && withinEnd && cellsAroundViewport.last === n - 1 && contentLength !== sentEndForContentLength) {
			sentEndForContentLength = contentLength;
			(endReached as (info: EndReachedInfo) => void)({ distanceFromEnd });
		}
		if (!withinEnd) { sentEndForContentLength = 0.0; }
		let distanceFromStart = offset;
		if (distanceFromStart < ON_EDGE_REACHED_EPSILON) { distanceFromStart = 0; }
		const startThresholdProp = props.onStartReachedThreshold;
		const startThreshold = startThresholdProp === null ? DEFAULT_THRESHOLD_PX : (startThresholdProp as Accessor<number>)() * visibleLength;
		const withinStart = distanceFromStart <= startThreshold;
		if (startReached !== null && withinStart && cellsAroundViewport.first === 0 && contentLength !== sentStartForContentLength) {
			sentStartForContentLength = contentLength;
			(startReached as (info: StartReachedInfo) => void)({ distanceFromStart });
		}
		if (!withinStart) { sentStartForContentLength = 0.0; }
	};

	const renderMask = (n: int32): CellRenderMask => {
		const mask = new CellRenderMask(n);
		if (n > 0) {
			mask.addCells(cellsAroundViewport);
			if (initialScrollIndex() <= 0) { mask.addCells(initialRegion(n)); }
			let closest: int32 = -1;
			for (const childIndex of stickyIndices) {
				const index = childIndex - headerOffset;
				if (index >= 0 && index < cellsAroundViewport.first && index > closest) { closest = index; }
			}
			if (closest >= 0) { mask.addCells({ first: closest, last: closest }); }
		}
		return mask;
	};

	const hasRenderPriority = (n: int32): boolean => {
		const start = props.onStartReachedThreshold;
		const scroll: WindowScroll = { offset, velocity, visibleLength, zoomScale: 1.0 };
		return shouldRenderWithPriority(n, cellsAroundViewport, metricsAt, scroll, start === null ? 2 : (start as Accessor<number>)(), thresholdProp === null ? 2 : (thresholdProp as Accessor<number>)());
	};

	const updateCellsToRender = (): boolean => {
		const n = cellCount();
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
		if ((metrics.getAverageCellLength() > 0.0 || props.getItemLayout !== null) && hasRenderPriority(cellCount()) && !hiPriInProgress) {
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
		if (props.getItemLayout !== null) { maybeCallOnEdgeReached(cellCount()); }
	};

	let seenCount: int32 = -1;
	if (sticky !== null) {
		createEffect((): void => {
			const next = (props.stickyHeaderIndices as Accessor<int32[]>)();
			untrack((): void => {
				for (const index of next) { if (index < 0) { throw "FlatList: stickyHeaderIndices must be non-negative"; } }
				if (next.length > 0 && isHorizontal()) { throw "FlatList: stickyHeaderIndices does not support horizontal lists"; }
				stickyIndices = next;
				const state = sticky as StickyState;
				state.indicesVersion.set(state.indicesVersion.peek() + 1);
				if (seenCount >= 0) { updateCellsToRender(); }
			});
		});
	}
	createEffect((): void => {
		const next = data();
		untrack((): void => {
			items = next;
			const n = cellCount();
			checkInitialScrollIndex(n);
			setCellTotal(n as number);
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
		const nextOffset = isHorizontal() ? e.x : e.y;
		velocity = e.timeStamp > 0 ? (nextOffset - offset) / (timeStamp > 0 ? Math.max(1, e.timeStamp - timeStamp) : 1) : 0;
		timeStamp = e.timeStamp;
		offset = nextOffset;
		visibleLength = isHorizontal() ? e.width : e.height;
		if (sticky !== null) {
			const state = sticky as StickyState;
			batch((): void => { state.offset.set(offset); state.viewport.set(visibleLength); });
		}
		metrics.notifyListContentLayout(orientation(), e.contentWidth, e.contentHeight);
		maybeCallOnEdgeReached(cellCount());
		if (pendingScrollUpdateCount > 0) { pendingScrollUpdateCount -= 1; }
		scheduleCellsToRenderUpdate(false);
	};
	const onLayout = (e: NeonEvent): void => {
		visibleLength = isHorizontal() ? e.width : e.height;
		if (sticky !== null) { (sticky as StickyState).viewport.set(visibleLength); }
		if (userLayout !== null) { (userLayout as (e: NeonEvent) => void)(e); }
		scheduleCellsToRenderUpdate(false);
		maybeCallOnEdgeReached(cellCount());
	};
	const onContentSizeChange = (width: number, height: number): void => {
		metrics.notifyListContentLayout(orientation(), width, height);
		initialContentReady = width > 0 && height > 0;
		maybeScrollToInitialIndex();
		const changed = props.onContentSizeChange;
		if (changed !== null) { (changed as (width: number, height: number) => void)(width, height); }
		scheduleCellsToRenderUpdate(false);
		maybeCallOnEdgeReached(cellCount());
	};
	const scrollRef = (h: ScrollViewHandle): void => {
		handle = new FlatListHandle(
			h,
			(index: number): CellMetrics => metricsAt(index as int32),
			(index: number): number => metrics.getCellOffsetApprox(index, source),
			(): number => cellCount() as number,
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
			(): number => footerLength,
		);
		if (userRef !== null) { (userRef as (handle: FlatListHandle) => void)(handle as FlatListHandle); }
	};

	// Parked: <ScrollView style={props.style}> wraps a nullable Accessor again (BUGS.md §3, isAccessorTyped) —
	// ~/metascript/.inbox/compiler/2026-09-19-design-typed-slots-value-read-and-text-coercion.md
	return ScrollView({
		style: props.inverted === null ? props.style : slotStyle(props.style), contentContainerStyle: props.contentContainerStyle, class: null,
		scrollEventThrottle: props.scrollEventThrottle, onScroll, onLayout, onContentSizeChange, ref: scrollRef, children: rows,
		horizontal: props.horizontal, scrollEnabled: props.scrollEnabled,
		showsHorizontalScrollIndicator: props.showsHorizontalScrollIndicator, showsVerticalScrollIndicator: props.showsVerticalScrollIndicator,
		pagingEnabled: props.pagingEnabled, keyboardDismissMode: props.keyboardDismissMode, keyboardShouldPersistTaps: props.keyboardShouldPersistTaps,
		onScrollBeginDrag: props.onScrollBeginDrag, onScrollEndDrag: props.onScrollEndDrag,
		onMomentumScrollBegin: props.onMomentumScrollBegin, onMomentumScrollEnd: props.onMomentumScrollEnd,
		onRefresh: props.onRefresh, refreshing: props.refreshing,
	});
}
