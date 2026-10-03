import { Accessor, createSignal, batch, untrack } from "../core/signal";
import { createEffect } from "../core/effect";
import { mapArray } from "../core/array";
import { element } from "../macros/ui/element";
import { NeonNode, regionNode } from "../render/node";
import { Row, makeRow } from "../render/reconcile";
import { NeonEvent } from "../render/event";
import { Host } from "../render/hostTypes";
import { Style } from "../render/style";
import { ScrollView, ScrollViewHandle, View } from "./primitives";
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

const VERTICAL: ListOrientation = { horizontal: false, rtl: false };

class ListCell {
	index: number = -1;
	setIndex: (index: number) => void;
	setSize: (size: number) => void;
	make: () => NeonNode;

	constructor(setIndex: (index: number) => void, setSize: (size: number) => void, make: () => NeonNode) {
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

	constructor(scroll: ScrollViewHandle, frameOf: (index: number) => CellMetrics, offsetOf: (index: number) => number, count: () => number, viewport: () => number) {
		this.scroll = scroll;
		this.frameOf = frameOf;
		this.offsetOf = offsetOf;
		this.count = count;
		this.viewport = viewport;
	}

	scrollToOffset(options: ScrollToOffsetOptions): void {
		const { offset, animated = true } = options;
		this.scroll.scrollTo({ y: offset, animated });
	}

	scrollToIndex(options: ScrollToIndexOptions): void {
		const { index, animated = true, viewPosition = 0, viewOffset = 0 } = options;
		const n = this.count();
		if (index < 0) { throw `scrollToIndex out of range: requested index ${index} but minimum is 0`; }
		if (n < 1) { throw `scrollToIndex out of range: item length ${n} but minimum is 1`; }
		if (index >= n) { throw `scrollToIndex out of range: requested index ${index} is out of 0 to ${n - 1}`; }
		const frame = this.frameOf(Math.floor(index));
		const offset = Math.max(0, this.offsetOf(index) - viewPosition * (this.viewport() - frame.length)) - viewOffset;
		this.scroll.scrollTo({ y: offset, animated });
	}

	scrollToEnd(options: ScrollToEndOptions): void {
		const { animated = true } = options;
		const n = this.count();
		if (n === 0) { return; }
		const frame = this.frameOf(n - 1);
		this.scroll.scrollTo({ y: Math.max(0, frame.offset + frame.length - this.viewport()), animated });
	}
}

export function FlatList<T>(props: {
	data: () => T[];
	renderItem: (info: ListRenderItemInfo<T>) => NeonNode;
	getItemLayout?: ((data: T[], index: number) => ItemLayout) | null;
	initialNumToRender?: Accessor<number> | null;
	maxToRenderPerBatch?: Accessor<number> | null;
	windowSize?: Accessor<number> | null;
	onEndReached?: ((info: EndReachedInfo) => void) | null;
	onEndReachedThreshold?: Accessor<number> | null;
	onScroll?: ((e: NeonEvent) => void) | null;
	onLayout?: ((e: NeonEvent) => void) | null;
	scrollEventThrottle?: Accessor<number> | null;
	style?: Accessor<Style> | null;
	contentContainerStyle?: Accessor<Style> | null;
	ref?: ((handle: FlatListHandle) => void) | null;
}): NeonNode {
	if (props.getItemLayout === null) {
		throw "FlatList: getItemLayout is required; rows of measured height are not supported yet";
	}
	const getItemLayout = props.getItemLayout as (data: T[], index: number) => ItemLayout;
	const data = props.data;
	const renderItem = props.renderItem;
	const initialProp = props.initialNumToRender;
	const batchProp = props.maxToRenderPerBatch;
	const windowProp = props.windowSize;
	const thresholdProp = props.onEndReachedThreshold;
	const endReached = props.onEndReached;
	const userScroll = props.onScroll;
	const userLayout = props.onLayout;
	const userRef = props.ref;

	let items: T[] = [];
	const metrics = new ListMetricsAggregator<T>();
	const source: CellSource<T> = {
		count: (): int32 => items.length as int32,
		keyAt: (index: int32): T => items[index],
		layoutAt: (index: int32): CellMetrics => {
			const layout = getItemLayout(items, index as number);
			return { index, length: layout.length, offset: layout.offset, isMounted: true };
		},
	};
	const metricsAt = (index: int32): CellMetrics => metrics.getCellMetricsApprox(index, source);

	const initialNumToRender = (): int32 => initialProp === null ? 10 : (initialProp as () => number)() as int32;
	const maxToRenderPerBatch = (): int32 => batchProp === null ? 10 : (batchProp as () => number)() as int32;
	const windowSize = (): int32 => windowProp === null ? 21 : (windowProp as () => number)() as int32;
	const initialRegion = (n: int32): CellRange => ({ first: 0, last: Math.min(n, initialNumToRender()) - 1 });

	let offset = 0.0;
	let visibleLength = 0.0;
	let sentEndForContentLength = 0.0;
	let cellsAroundViewport: CellRange = { first: 0, last: -1 };
	let itemCells = new Map<T, ListCell>();
	let spacerCells = new Map<int32, ListCell>();
	const [cells, setCells] = createSignal<ListCell[]>([]);

	// RN VirtualizedList._constrainToItemCount.
	const constrainToItemCount = (range: CellRange, n: int32): CellRange => {
		const maxFirst = Math.max(0, n - 1 - maxToRenderPerBatch());
		return { first: Math.min(Math.max(0, range.first), maxFirst), last: Math.min(n - 1, range.last) };
	};

	// RN VirtualizedList._adjustCellsAroundViewport, with every batch RN's timer would run taken
	// here: native hosts have no timer, so the window lands where RN's lands once its batches drain.
	const adjustCellsAroundViewport = (n: int32): CellRange => {
		if (visibleLength <= 0.0 || metrics.getContentLength() <= 0.0) {
			return cellsAroundViewport.last >= n ? constrainToItemCount(cellsAroundViewport, n) : cellsAroundViewport;
		}
		const scroll: WindowScroll = { offset, velocity: 0.0, visibleLength, zoomScale: 1.0 };
		let current = cellsAroundViewport;
		for (let pass: int32 = 0; pass <= n + 1; pass += 1) {
			const next = computeWindowedRenderLimits(n, maxToRenderPerBatch(), windowSize(), current, metricsAt, scroll);
			if (next.first === current.first && next.last === current.last) { return next; }
			current = next;
		}
		throw `FlatList: the render window did not settle within ${n + 1} batches`;
	};

	const spacerCell = (): ListCell => {
		const [size, setSize] = createSignal<number>(0);
		return new ListCell((index: number): void => {}, (next: number): void => { setSize(next); }, (): NeonNode => element(<View style={{ height: size() }} />));
	};

	const itemCell = (item: T, index: number): ListCell => {
		const [at, setAt] = createSignal<number>(index);
		return new ListCell((next: number): void => { setAt(next); }, (size: number): void => {}, (): NeonNode => renderItem({ item, index: at }));
	};

	const buildCells = (mask: CellRenderMask): ListCell[] => {
		const out: ListCell[] = [];
		const nextItems = new Map<T, ListCell>();
		const nextSpacers = new Map<int32, ListCell>();
		for (const region of mask.enumerateRegions()) {
			if (region.isSpacer) {
				const first = metricsAt(region.first);
				const last = metricsAt(region.last);
				const cell = spacerCells.has(region.first) ? spacerCells.get(region.first) as ListCell : spacerCell();
				cell.setSize(last.offset + last.length - first.offset);
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

	const refresh = (): void => {
		const n = items.length as int32;
		cellsAroundViewport = adjustCellsAroundViewport(n);
		const mask = new CellRenderMask(n);
		if (n > 0) {
			mask.addCells(cellsAroundViewport);
			mask.addCells(initialRegion(n));
		}
		batch((): void => { setCells(buildCells(mask)); });
		maybeCallOnEndReached(n);
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
			seenCount = n;
			refresh();
		});
	});

	const rows = regionNode((host: Host) => mapArray<ListCell, Row>(cells, (cell: ListCell, i: Accessor<number>): Row => makeRow(cell.make()), false));

	const onScroll = (e: NeonEvent): void => {
		if (userScroll !== null) { (userScroll as (e: NeonEvent) => void)(e); }
		offset = e.y;
		visibleLength = e.height;
		refresh();
	};
	const onLayout = (e: NeonEvent): void => {
		visibleLength = e.height;
		if (userLayout !== null) { (userLayout as (e: NeonEvent) => void)(e); }
		refresh();
	};
	const onContentSizeChange = (width: number, height: number): void => {
		metrics.notifyListContentLayout(VERTICAL, width, height);
		refresh();
	};
	const scrollRef = (h: ScrollViewHandle): void => {
		if (userRef === null) { return; }
		(userRef as (handle: FlatListHandle) => void)(new FlatListHandle(
			h,
			(index: number): CellMetrics => metricsAt(index as int32),
			(index: number): number => metrics.getCellOffsetApprox(index, source),
			(): number => items.length,
			(): number => visibleLength,
		));
	};

	// Parked: <ScrollView style={props.style}> wraps a nullable Accessor again (BUGS.md §3, isAccessorTyped) —
	// ~/metascript/.inbox/compiler/2026-09-19-design-typed-slots-value-read-and-text-coercion.md
	return ScrollView({
		style: props.style, contentContainerStyle: props.contentContainerStyle, class: null,
		scrollEventThrottle: props.scrollEventThrottle, onScroll, onLayout, onContentSizeChange, ref: scrollRef, children: rows,
	});
}
