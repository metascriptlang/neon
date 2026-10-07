// Flutter widgets/reorderable_list.dart with react-native-draggable-flatlist's surface:
// renderItem receives drag(), the dragged row follows the touch, the others open a gap,
// and the drop reports onReorder(from, to) with `to` the index after removal.

import { Accessor, accessor, createSignal, untrack, batch } from "../core/signal";
import { onCleanup } from "../core/cleanup";
import { element } from "../macros/ui/element";
import { NeonNode } from "../render/node";
import { NeonEvent } from "../render/event";
import { Style, mergeStyle } from "../render/style";
import { View } from "./primitives";
import { FlatList, FlatListHandle, ListRenderItemInfo } from "./flatList";
import { PanResponder, PanResponderGestureState } from "./panResponder";
import { Tween, easeOut, tween } from "./tween";

export interface ReorderableRenderItemInfo<T> {
	item: T;
	index: Accessor<number>;
	drag: () => void;
	isActive: Accessor<boolean>;
}

// reorderable_list.dart:1312 (gap), :1565 (drop), scrollable_helpers.dart:256 (step cap).
const DROP_MS = 250;
const AUTOSCROLL_STEP = 20;
const AUTOSCROLL_MS = 20;

export function reorderTarget(heights: number[], from: int32, delta: number): int32 {
	if (from < 0 || from >= heights.length) { return from; }
	let edge = 0.0;
	const tops: number[] = [];
	for (const h of heights) {
		tops.push(edge);
		edge += h;
	}
	const top = tops[from] + delta;
	const bottom = top + heights[from];
	let target = from;
	if (delta > 0) {
		for (let i = from + 1; i < heights.length; i += 1) {
			if (bottom > tops[i] + heights[i] / 2) { target = i; } else { break; }
		}
	} else if (delta < 0) {
		for (let i = from - 1; i >= 0; i -= 1) {
			if (top < tops[i] + heights[i] / 2) { target = i; } else { break; }
		}
	}
	return target;
}

export function ReorderableFlatList<T>(props: {
	data: Accessor<T[]>;
	renderItem: (info: ReorderableRenderItemInfo<T>) => NeonNode;
	onReorder: (from: number, to: number) => void;
	onDragBegin?: ((index: number) => void) | null;
	ListHeaderComponent?: NeonNode | null;
	ListFooterComponent?: NeonNode | null;
	style?: Accessor<Style> | null;
	contentContainerStyle?: Accessor<Style> | null;
	activeItemStyle?: Accessor<Style> | null;
	dropDuration?: Accessor<number> | null;
	onScroll?: ((e: NeonEvent) => void) | null;
	ref?: ((handle: FlatListHandle) => void) | null;
}): NeonNode {
	const data = props.data;
	const userRender = props.renderItem;
	const onReorder = props.onReorder;
	const onDragBegin = props.onDragBegin;
	const activeStyleProp = props.activeItemStyle;
	const userScroll = props.onScroll;
	const userRef = props.ref;
	const dropProp = props.dropDuration;

	const [activeIndex, setActiveIndex] = createSignal<number>(-1);
	const [targetIndex, setTargetIndex] = createSignal<number>(-1);
	const [translation, setTranslation] = createSignal<number>(0);
	const heights = new Map<T, number>();
	let activeItem: T | null = null;
	let activeHeight = 0.0;
	let snapshot: number[] = [];
	let granted = false;
	let dragDelta = 0.0;
	let offset = 0.0;
	let viewport = 0.0;
	let grantOffset = 0.0;
	let headerLength = 0.0;
	let autoscroll: number = -1;
	let handle: FlatListHandle | null = null;
	let drop: Tween | null = null;

	const stopAutoscroll = (): void => {
		if (autoscroll >= 0) {
			clearTimeout(autoscroll);
			autoscroll = -1;
		}
	};
	const stopDrop = (): void => {
		if (drop !== null) {
			(drop as Tween).stop();
			drop = null;
		}
	};
	onCleanup((): void => {
		stopAutoscroll();
		stopDrop();
	});

	const averageHeight = (): number => {
		let total = 0.0;
		let count = 0;
		for (const item of heights) {
			total += heights.get(item) as number;
			count += 1;
		}
		return count === 0 ? 44 : total / count;
	};

	const reset = (): void => {
		stopAutoscroll();
		activeItem = null;
		granted = false;
		dragDelta = 0;
		batch((): void => {
			setActiveIndex(-1);
			setTargetIndex(-1);
			setTranslation(0);
		});
	};

	const slotTop = (index: int32): number => {
		let top = headerLength;
		for (let i = 0; i < index && i < snapshot.length; i += 1) { top += snapshot[i]; }
		return top;
	};

	const place = (): void => {
		const from = untrack<number>(activeIndex) as int32;
		const scrolled = offset - grantOffset;
		const moved = dragDelta + scrolled;
		batch((): void => {
			setTranslation(moved);
			setTargetIndex(reorderTarget(snapshot, from, moved) as number);
		});
	};

	const autoscrollTick = (): void => {
		autoscroll = -1;
		if (activeItem === null || !granted || handle === null || viewport <= 0) { return; }
		const from = untrack<number>(activeIndex) as int32;
		const top = slotTop(from) - grantOffset + dragDelta;
		const bottom = top + activeHeight;
		let step = 0.0;
		if (top < 0 && offset > 0) { step = -Math.min(AUTOSCROLL_STEP, -top); }
		else if (bottom > viewport) { step = Math.min(AUTOSCROLL_STEP, bottom - viewport); }
		if (step === 0) { return; }
		const next = Math.max(0, offset + step);
		(handle as FlatListHandle).scrollToOffset({ offset: next, animated: false });
		offset = next;
		place();
		autoscroll = setTimeout(autoscrollTick, AUTOSCROLL_MS) as number;
	};

	const startDrag = (item: T, index: number): void => {
		stopDrop();
		const items = untrack<T[]>(data);
		const average = averageHeight();
		snapshot = [];
		for (const each of items) { snapshot.push(heights.has(each) ? heights.get(each) as number : average); }
		activeItem = item;
		activeHeight = heights.has(item) ? heights.get(item) as number : average;
		granted = false;
		dragDelta = 0;
		grantOffset = offset;
		batch((): void => {
			setActiveIndex(index);
			setTargetIndex(index);
			setTranslation(0);
		});
		if (onDragBegin !== null) { (onDragBegin as (index: number) => void)(index); }
	};

	const finishDrag = (): void => {
		stopAutoscroll();
		const from = untrack<number>(activeIndex) as int32;
		const to = untrack<number>(targetIndex) as int32;
		if (from < 0) {
			reset();
			return;
		}
		const settle = slotTop(to) - slotTop(from) + (to > from ? snapshot[to] - activeHeight : 0);
		const commit = (): void => {
			drop = null;
			batch((): void => {
				reset();
				if (to !== from) { onReorder(from as number, to as number); }
			});
		};
		drop = tween(untrack<number>(translation), settle, dropProp === null ? DROP_MS : (dropProp as Accessor<number>)(), easeOut, (value: number): void => { setTranslation(value); }, commit);
	};

	const rowStyle = (item: T, index: Accessor<number>): Accessor<Style> => accessor((): Style => {
		const from = activeIndex();
		if (from < 0) { return { transform: "translateY(0px)" }; }
		const at = index();
		if (at === from && activeItem === item) {
			const lifted: Style = { transform: `translateY(${translation()}px)`, zIndex: 10 };
			return activeStyleProp === null ? lifted : mergeStyle((activeStyleProp as Accessor<Style>)(), lifted);
		}
		const to = targetIndex();
		let shift = 0.0;
		if (to > from && at > from && at <= to) { shift = -activeHeight; }
		if (to < from && at >= to && at < from) { shift = activeHeight; }
		return { transform: `translateY(${shift}px)` };
	});

	const renderRow = (info: ListRenderItemInfo<T>): NeonNode => {
		const item = info.item;
		const index = info.index;
		const isActive = accessor((): boolean => activeIndex() >= 0 && activeIndex() === index() && activeItem === item);
		const pan = PanResponder.create({
			onMoveShouldSetPanResponderCapture: (e: NeonEvent, g: PanResponderGestureState): boolean => activeItem === item && !granted,
			onPanResponderGrant: (e: NeonEvent, g: PanResponderGestureState): void => {
				granted = true;
				dragDelta = 0;
			},
			onPanResponderMove: (e: NeonEvent, g: PanResponderGestureState): void => {
				dragDelta = g.dy;
				place();
				if (autoscroll < 0) { autoscrollTick(); }
			},
			onPanResponderRelease: (e: NeonEvent, g: PanResponderGestureState): void => { finishDrag(); },
			onPanResponderTerminate: (e: NeonEvent, g: PanResponderGestureState): void => { finishDrag(); },
			onPanResponderTerminationRequest: (e: NeonEvent, g: PanResponderGestureState): boolean => false,
		});
		const handlers = pan.panHandlers;
		const body = userRender({
			item, index, isActive,
			drag: (): void => { startDrag(item, untrack<number>(index)); },
		});
		return element(<View {...handlers} style={rowStyle(item, index)}
			onTouchEnd={(e: NeonEvent): void => { if (activeItem === item && !granted) { reset(); } }}
			onLayout={(e: NeonEvent): void => { heights.set(item, e.height); }}>{body}</View>);
	};

	const header = props.ListHeaderComponent;
	const measuredHeader: NeonNode | null = header === null ? null : View({
		children: header,
		onLayout: (e: NeonEvent): void => { headerLength = e.height; },
	});
	return FlatList<T>({
		data,
		renderItem: renderRow,
		ListHeaderComponent: measuredHeader,
		ListFooterComponent: props.ListFooterComponent,
		style: props.style,
		contentContainerStyle: props.contentContainerStyle,
		onScroll: (e: NeonEvent): void => {
			offset = e.y;
			viewport = e.height;
			if (userScroll !== null) { (userScroll as (e: NeonEvent) => void)(e); }
		},
		onLayout: (e: NeonEvent): void => { viewport = e.height; },
		ref: (h: FlatListHandle): void => {
			handle = h;
			if (userRef !== null) { (userRef as (h: FlatListHandle) => void)(h); }
		},
	});
}
