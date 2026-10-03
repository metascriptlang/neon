import { Accessor, createSignal } from "../core/signal";
import { createMemo } from "../core/memo";
import { createEffect } from "../core/effect";
import { mapArrayKeyedText } from "../core/array";
import { element } from "../macros/ui/element";
import { NeonNode, regionNode } from "../render/node";
import { Row, makeRow } from "../render/reconcile";
import { NeonEvent } from "../render/event";
import { Host } from "../render/hostTypes";
import { Style } from "../render/style";
import { ScrollView, ScrollViewHandle, View } from "./primitives";

export interface ListRenderItemInfo<T> {
	item: T;
	index: number;
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

interface Slot<T> {
	item: T;
	index: number;
}

export class FlatListHandle {
	private scroll: ScrollViewHandle;
	private layoutOf: (index: number) => ItemLayout;
	private count: () => number;
	private viewport: () => number;

	constructor(scroll: ScrollViewHandle, layoutOf: (index: number) => ItemLayout, count: () => number, viewport: () => number) {
		this.scroll = scroll;
		this.layoutOf = layoutOf;
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
		if (index < 0 || index >= n) {
			throw `FlatList.scrollToIndex: index ${index} is outside the ${n} items`;
		}
		const at = this.layoutOf(index);
		this.scroll.scrollTo({ y: at.offset - viewPosition * (this.viewport() - at.length) - viewOffset, animated });
	}

	scrollToEnd(options: ScrollToEndOptions): void {
		const { animated = true } = options;
		const n = this.count();
		if (n === 0) { return; }
		const last = this.layoutOf(n - 1);
		this.scroll.scrollTo({ y: Math.max(0, last.offset + last.length - this.viewport()), animated });
	}
}

export function FlatList<T>(props: {
	data: () => T[];
	renderItem: (info: ListRenderItemInfo<T>) => NeonNode;
	keyExtractor: (item: T, index: number) => string;
	getItemLayout?: ((data: T[], index: number) => ItemLayout) | null;
	initialNumToRender?: Accessor<number> | null;
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
	const keyExtractor = props.keyExtractor;
	const initialProp = props.initialNumToRender;
	const windowProp = props.windowSize;
	const thresholdProp = props.onEndReachedThreshold;
	const userScroll = props.onScroll;
	const userLayout = props.onLayout;
	const endReached = props.onEndReached;
	const userRef = props.ref;

	const [offset, setOffset] = createSignal<number>(0);
	const [viewport, setViewport] = createSignal<number>(0);

	const layoutOf = (index: number): ItemLayout => getItemLayout(data(), index);
	const count = (): number => data().length;
	const total = (): number => {
		const n = count();
		if (n === 0) { return 0; }
		const last = layoutOf(n - 1);
		return last.offset + last.length;
	};
	const indexAt = (y: number): number => {
		let lo: number = 0;
		let hi: number = count() - 1;
		while (lo < hi) {
			const mid = Math.floor((lo + hi + 1) / 2);
			if (layoutOf(mid).offset <= y) { lo = mid; } else { hi = mid - 1; }
		}
		return lo;
	};

	const first = createMemo((): number => {
		if (count() === 0 || viewport() <= 0) { return 0; }
		const ws = windowProp === null ? 21 : (windowProp as () => number)();
		return indexAt(Math.max(0, offset() - (ws - 1) / 2 * viewport()));
	});
	const last = createMemo((): number => {
		const n = count();
		if (n === 0) { return -1; }
		if (viewport() <= 0) {
			const initial = initialProp === null ? 10 : (initialProp as () => number)();
			return Math.min(n, initial) - 1;
		}
		const ws = windowProp === null ? 21 : (windowProp as () => number)();
		return indexAt(offset() + viewport() + (ws - 1) / 2 * viewport());
	});
	const slots = createMemo((): Slot<T>[] => {
		const items = data();
		const out: Slot<T>[] = [];
		for (let i = first(); i <= last(); i += 1) { out.push({ item: items[i], index: i }); }
		return out;
	});
	const topSpace = (): number => last() < 0 ? 0 : layoutOf(first()).offset;
	const bottomSpace = (): number => {
		if (last() < 0) { return 0; }
		const end = layoutOf(last());
		return total() - end.offset - end.length;
	};

	if (endReached !== null) {
		const fire = endReached as (info: EndReachedInfo) => void;
		let firedAt = -1.0;
		createEffect((): void => {
			const v = viewport();
			const n = count();
			if (v <= 0 || n === 0) { return; }
			const distance = total() - v - offset();
			const threshold = (thresholdProp === null ? 2 : (thresholdProp as () => number)()) * v;
			if (distance >= threshold) {
				firedAt = -1.0;
				return;
			}
			if (last() === n - 1 && firedAt !== total()) {
				firedAt = total();
				fire({ distanceFromEnd: distance });
			}
		});
	}

	const rows = regionNode((host: Host) => mapArrayKeyedText<Slot<T>, Row>(
		slots,
		(slot: Slot<T>): string => keyExtractor(slot.item, slot.index),
		(slot: Slot<T>): Row => makeRow(renderItem({ item: slot.item, index: slot.index })),
		false,
		"FlatList",
	));

	const onScroll = (e: NeonEvent): void => {
		setOffset(e.y);
		setViewport(e.height);
		if (userScroll !== null) { (userScroll as (e: NeonEvent) => void)(e); }
	};
	const onLayout = (e: NeonEvent): void => {
		setViewport(e.height);
		if (userLayout !== null) { (userLayout as (e: NeonEvent) => void)(e); }
	};
	const scrollRef = (h: ScrollViewHandle): void => {
		if (userRef !== null) { (userRef as (handle: FlatListHandle) => void)(new FlatListHandle(h, layoutOf, count, viewport)); }
	};

	const content: NeonNode = element(<>
		<View style={{ height: topSpace() }} />
		{rows}
		<View style={{ height: bottomSpace() }} />
	</>);
	// Parked: <ScrollView style={props.style}> wraps a nullable Accessor again (BUGS.md §3, isAccessorTyped) —
	// ~/metascript/.inbox/compiler/2026-09-19-design-typed-slots-value-read-and-text-coercion.md
	return ScrollView({
		style: props.style, contentContainerStyle: props.contentContainerStyle, class: null,
		scrollEventThrottle: props.scrollEventThrottle, onScroll, onLayout, ref: scrollRef, children: content,
	});
}
