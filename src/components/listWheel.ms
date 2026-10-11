// Flutter widgets/list_wheel_scroll_view.dart over a ScrollView: items of one extent on a
// cylinder (rendering/list_wheel_viewport.dart), snapping to an item when the scroll
// settles (FixedExtentScrollPhysics), and onSelectedItemChanged at the half-item boundary.

import { Accessor, accessor, createSignal, untrack } from "../core/signal";
import { onCleanup } from "../core/cleanup";
import { For } from "../macros/ui/flow";
import { NeonNode } from "../render/node";
import { NeonEvent } from "../render/event";
import { Style, mergeStyle } from "../render/style";
import { ScrollView, ScrollViewHandle, View } from "./primitives";

export interface WheelRenderItemInfo<T> {
	item: T;
	index: Accessor<number>;
	selected: Accessor<boolean>;
}

// list_wheel_scroll_view.dart:586-601.
const DIAMETER_RATIO = 2.0;
const SETTLE_MS = 120;

export interface WheelItemPaint {
	visible: boolean;
	scaleY: number;
	translateY: number;
	opacity: number;
}

// list_wheel_viewport.dart:563-568 and :869-879: an item's angle on the cylinder from its
// distance to the centre; its projection shrinks by cos(angle) and moves towards the centre.
export function wheelPaint(itemCenter: number, viewportCenter: number, viewport: number, diameterRatio: number, magnification: number, itemExtent: number): WheelItemPaint {
	const radius = viewport * diameterRatio / 2;
	const offset = itemCenter - viewportCenter;
	const maxAngle = diameterRatio < 1 ? Math.PI / 2 : Math.asin(1 / diameterRatio);
	const angle = radius > 0 ? offset / radius : 0;
	if (Math.abs(angle) > Math.PI / 2) { return { visible: false, scaleY: 0, translateY: 0, opacity: 0 }; }
	const projected = radius * Math.sin(angle);
	const centred = Math.abs(offset) < itemExtent / 2;
	const scale = Math.cos(angle) * (centred ? magnification : 1);
	const fade = maxAngle > 0 ? Math.max(0.15, 1 - Math.abs(angle) / (Math.PI / 2)) : 1;
	return { visible: true, scaleY: scale, translateY: projected - offset, opacity: fade };
}

export function selectedIndex(offset: number, itemExtent: number, count: int32): int32 {
	if (count <= 0 || itemExtent <= 0) { return 0; }
	const index = Math.round(offset / itemExtent) as int32;
	return Math.max(0, Math.min(count - 1, index));
}

export function ListWheelScrollView<T>(props: {
	data: Accessor<T[]>;
	itemExtent: Accessor<number>;
	renderItem: (info: WheelRenderItemInfo<T>) => NeonNode;
	onSelectedItemChanged?: ((index: number) => void) | null;
	initialItem?: Accessor<number> | null;
	diameterRatio?: Accessor<number> | null;
	magnification?: Accessor<number> | null;
	style?: Accessor<Style> | null;
}): NeonNode {
	const data = props.data;
	const extentProp = props.itemExtent;
	const userRender = props.renderItem;
	const changed = props.onSelectedItemChanged;
	const initialProp = props.initialItem;
	const ratioProp = props.diameterRatio;
	const magnifyProp = props.magnification;
	const [offset, setOffset] = createSignal<number>(0);
	const [viewport, setViewport] = createSignal<number>(0);
	const initial = initialProp === null ? 0 : (initialProp as Accessor<number>)();
	let reported: int32 = initial as int32;
	let handle: ScrollViewHandle | null = null;
	let settle: number = -1;
	let positioned = false;
	const [selected, setSelected] = createSignal<number>(initial);

	const cancelSettle = (): void => {
		if (settle >= 0) {
			clearTimeout(settle);
			settle = -1;
		}
	};
	onCleanup(cancelSettle);

	const extent = (): number => extentProp();
	const snap = (): void => {
		cancelSettle();
		if (handle === null) { return; }
		const count = untrack<T[]>(data).length as int32;
		const target = (selectedIndex(untrack<number>(offset), extent(), count) as number) * extent();
		if (Math.abs(target - untrack<number>(offset)) < 0.5) { return; }
		(handle as ScrollViewHandle).scrollTo({ x: 0, y: target, animated: true });
	};
	const scheduleSnap = (): void => {
		cancelSettle();
		settle = setTimeout(snap, SETTLE_MS) as number;
	};

	const onScroll = (e: NeonEvent): void => {
		setOffset(e.y);
		if (e.height > 0 && e.height !== untrack<number>(viewport)) { setViewport(e.height); }
		const index = selectedIndex(e.y, extent(), untrack<T[]>(data).length as int32);
		if (index !== reported) {
			reported = index;
			setSelected(index as number);
			if (changed !== null) { (changed as (index: number) => void)(index as number); }
		}
	};

	const itemStyle = (index: Accessor<number>): Accessor<Style> => accessor((): Style => {
		const height = extent();
		const view = viewport();
		if (view <= 0) { return { height, flexShrink: 0 }; }
		const ratio = ratioProp === null ? DIAMETER_RATIO : (ratioProp as Accessor<number>)();
		const magnification = magnifyProp === null ? 1 : (magnifyProp as Accessor<number>)();
		const centre = (index() as number) * height + height / 2;
		const paint = wheelPaint(centre - offset(), view / 2 - (view - height) / 2, view, ratio, magnification, height);
		if (!paint.visible) { return { height, flexShrink: 0, opacity: 0 }; }
		return {
			height, flexShrink: 0, opacity: paint.opacity,
			transform: `translateY(${paint.translateY}px) scale(1, ${paint.scaleY})`,
		};
	});

	const userStyle = props.style;
	const padding = accessor((): Style => {
		const pad = Math.max(0, (viewport() - extent()) / 2);
		return { paddingTop: pad, paddingBottom: pad };
	});
	return ScrollView({
		style: accessor((): Style => mergeStyle({ flexGrow: 0 }, userStyle === null ? {} : (userStyle as Accessor<Style>)())),
		contentContainerStyle: padding,
		showsVerticalScrollIndicator: accessor((): boolean => false),
		scrollEventThrottle: accessor((): number => 16),
		onScroll,
		onLayout: (e: NeonEvent): void => {
			if (e.height !== untrack<number>(viewport)) { setViewport(e.height); }
			if (!positioned && handle !== null && e.height > 0 && initial > 0) {
				positioned = true;
				(handle as ScrollViewHandle).scrollTo({ x: 0, y: initial * extent(), animated: false });
			}
		},
		onScrollEndDrag: (e: NeonEvent): void => { scheduleSnap(); },
		onMomentumScrollBegin: (e: NeonEvent): void => { cancelSettle(); },
		onMomentumScrollEnd: (e: NeonEvent): void => { snap(); },
		ref: (h: ScrollViewHandle): void => { handle = h; },
		children: For<T>({
			each: data,
			children: (item: T, index: Accessor<number>): NeonNode => View({
				style: itemStyle(index),
				children: userRender({ item, index, selected: accessor((): boolean => selected() === index()) }),
			}),
		}),
	});
}
