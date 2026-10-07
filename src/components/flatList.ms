import { Accessor } from "../core/signal";
import { NeonNode } from "../render/node";
import { NeonEvent } from "../render/event";
import { Style } from "../render/style";
import { KeyboardDismissMode, KeyboardShouldPersistTaps } from "./primitives";
import {
	EndReachedInfo,
	FlatListHandle,
	ItemLayout,
	ListRenderItemInfo,
	ScrollToIndexFailedInfo,
	StartReachedInfo,
	ViewabilityConfig,
	ViewabilityConfigCallbackPair,
	ViewabilityInfo,
	listEngine,
} from "./virtualizedList";

export {
	EndReachedInfo,
	FlatListHandle,
	ItemLayout,
	ListRenderItemInfo,
	ScrollToEndOptions,
	ScrollToIndexFailedInfo,
	ScrollToIndexOptions,
	ScrollToOffsetOptions,
	StartReachedInfo,
	ViewabilityConfig,
	ViewabilityConfigCallbackPair,
	ViewabilityInfo,
	ViewToken,
} from "./virtualizedList";

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
	onViewableItemsChanged?: ((info: ViewabilityInfo<T>) => void) | null;
	viewabilityConfig?: Accessor<ViewabilityConfig> | null;
	viewabilityConfigCallbackPairs?: Accessor<ViewabilityConfigCallbackPair<T>[]> | null;
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
	return listEngine<T, T[]>({
		...props,
		getItem: (data: T[], index: number): T => data[index],
		getItemCount: (data: T[]): number => data.length,
	}, "FlatList", props.numColumns, props.columnWrapperStyle);
}
