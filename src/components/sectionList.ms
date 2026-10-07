import { Accessor, accessor, createSignal, untrack } from "../core/signal";
import { element } from "../macros/ui/element";
import { Show } from "../macros/ui/flow";
import { NeonNode } from "../render/node";
import { NeonEvent } from "../render/event";
import { Host, HostNode } from "../render/hostTypes";
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
	ViewabilityInfo,
	ViewToken,
	listEngine,
} from "./virtualizedList";

export interface SectionBase<T> {
	data: T[];
	key?: string | null;
}

export interface SectionListRenderItemInfo<T, S> {
	item: T;
	index: Accessor<number>;
	section: Accessor<S>;
}

export interface SectionInfo<S> {
	section: S;
}

export interface SectionViewToken<T, S> {
	item: T | null;
	index: number | null;
	section: S;
	isViewable: boolean;
}

export interface SectionViewabilityInfo<T, S> {
	viewableItems: SectionViewToken<T, S>[];
	changed: SectionViewToken<T, S>[];
	viewabilityConfig: ViewabilityConfig;
}

export interface ScrollToLocationParams {
	sectionIndex: number;
	itemIndex: number;
	animated?: boolean | null;
	viewOffset?: number | null;
	viewPosition?: number | null;
}

enum SectionCellKind {
	Header,
	Item,
	Footer,
}

interface SectionCell<T, S> {
	kind: SectionCellKind;
	section: S | null;
	item: T | null;
}

export class SectionListHandle {
	private list: FlatListHandle;
	private sectionStart: (sectionIndex: int32) => int32;
	private stickyHeaders: boolean;

	constructor(list: FlatListHandle, sectionStart: (sectionIndex: int32) => int32, stickyHeaders: boolean) {
		this.list = list;
		this.sectionStart = sectionStart;
		this.stickyHeaders = stickyHeaders;
	}

	scrollToLocation(params: ScrollToLocationParams): void {
		const { sectionIndex, itemIndex, animated = true, viewOffset = 0, viewPosition = 0 } = params;
		const index = itemIndex + (this.sectionStart(sectionIndex as int32) as number);
		let offset = viewOffset;
		if (itemIndex > 0 && this.stickyHeaders) { offset += this.list.cellLength(index - itemIndex); }
		this.list.scrollToIndex({ index, animated, viewOffset: offset, viewPosition });
	}

	recordInteraction(): void {
		this.list.recordInteraction();
	}
}

when (ios) {
	function stickySectionHeadersByDefault(): boolean { return true; }
} else {
	function stickySectionHeadersByDefault(): boolean { return false; }
}

const emptyCell: NeonNode = (host: Host, parent: HostNode, before: HostNode | null): void => {};

export function VirtualizedSectionList<T, S>(props: {
	sections: Accessor<S[]>;
	getItem: (section: S, index: number) => T;
	getItemCount: (section: S) => number;
	renderItem: (info: SectionListRenderItemInfo<T, S>) => NeonNode;
	renderSectionHeader?: ((info: SectionInfo<S>) => NeonNode) | null;
	renderSectionFooter?: ((info: SectionInfo<S>) => NeonNode) | null;
	getItemLayout?: ((sections: S[], index: number) => ItemLayout) | null;
	ItemSeparatorComponent?: NeonNode | null;
	SectionSeparatorComponent?: NeonNode | null;
	stickySectionHeadersEnabled?: Accessor<boolean> | null;
	disableVirtualization?: Accessor<boolean> | null;
	onViewableItemsChanged?: ((info: SectionViewabilityInfo<T, S>) => void) | null;
	ListHeaderComponent?: NeonNode | null;
	ListFooterComponent?: NeonNode | null;
	ListEmptyComponent?: NeonNode | null;
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
	invertStickyHeaders?: Accessor<boolean> | null;
	scrollEnabled?: Accessor<boolean> | null;
	showsHorizontalScrollIndicator?: Accessor<boolean> | null;
	showsVerticalScrollIndicator?: Accessor<boolean> | null;
	pagingEnabled?: Accessor<boolean> | null;
	keyboardDismissMode?: Accessor<KeyboardDismissMode> | null;
	keyboardShouldPersistTaps?: Accessor<KeyboardShouldPersistTaps> | null;
	viewabilityConfig?: Accessor<ViewabilityConfig> | null;
	onScrollBeginDrag?: ((e: NeonEvent) => void) | null;
	onScrollEndDrag?: ((e: NeonEvent) => void) | null;
	onMomentumScrollBegin?: ((e: NeonEvent) => void) | null;
	onMomentumScrollEnd?: ((e: NeonEvent) => void) | null;
	onRefresh?: (() => void) | null;
	refreshing?: Accessor<boolean> | null;
	onContentSizeChange?: ((width: number, height: number) => void) | null;
	style?: Accessor<Style> | null;
	contentContainerStyle?: Accessor<Style> | null;
	ref?: ((handle: SectionListHandle) => void) | null;
}): NeonNode {
	const getItem = props.getItem;
	const getItemCount = props.getItemCount;
	const renderItem = props.renderItem;
	const renderHeader = props.renderSectionHeader;
	const renderFooter = props.renderSectionFooter;
	const sectionSeparator = props.SectionSeparatorComponent;
	const itemSeparator = props.ItemSeparatorComponent;
	const userRef = props.ref;
	const sectionChanged = props.onViewableItemsChanged;
	const stickyProp = props.stickySectionHeadersEnabled;
	const stickyHeaders = stickyProp !== null && untrack((): boolean => (stickyProp as Accessor<boolean>)());
	const listHeaderOffset: int32 = props.ListHeaderComponent === null ? 0 : 1;

	let laidOut: S[] | null = null;
	let snapshot: S[] = [];
	let starts: int32[] = [];
	let total: int32 = 0;
	let layoutCount: int32 = 0;
	const [version, setVersion] = createSignal<int32>(0);
	const layoutOf = (sections: S[]): void => {
		if (laidOut !== null && laidOut === sections) { return; }
		const next: int32[] = [];
		let at: int32 = 0;
		for (const section of sections) {
			next.push(at);
			at += (getItemCount(section) as int32) + 2;
		}
		laidOut = sections;
		snapshot = sections;
		starts = next;
		total = at;
		layoutCount += 1;
		setVersion(layoutCount);
	};
	const sectionAt = (flat: int32): int32 => {
		let low: int32 = 0;
		let high: int32 = (starts.length as int32) - 1;
		while (low < high) {
			const mid = (low + high + 1) / 2;
			if (starts[mid] <= flat) { low = mid; } else { high = mid - 1; }
		}
		return low;
	};

	const items = new Map<T, SectionCell<T, S>>();
	const headers = new Map<S, SectionCell<T, S>>();
	const footers = new Map<S, SectionCell<T, S>>();
	const cellAt = (sections: S[], index: number): SectionCell<T, S> => {
		layoutOf(sections);
		const flat = index as int32;
		const s = sectionAt(flat);
		const section = sections[s];
		const local = flat - starts[s] - 1;
		if (local === -1 || local === (getItemCount(section) as int32)) {
			const kind = local === -1 ? SectionCellKind.Header : SectionCellKind.Footer;
			const cache = local === -1 ? headers : footers;
			if (!cache.has(section)) { cache.set(section, { kind, section, item: null }); }
			return cache.get(section) as SectionCell<T, S>;
		}
		const item = getItem(section, local as number);
		if (!items.has(item)) { items.set(item, { kind: SectionCellKind.Item, section: null, item }); }
		return items.get(item) as SectionCell<T, S>;
	};

	const renderCell = (info: ListRenderItemInfo<SectionCell<T, S>>): NeonNode => {
		const cell = info.item;
		if (cell.kind === SectionCellKind.Header) {
			return renderHeader === null ? emptyCell : (renderHeader as (info: SectionInfo<S>) => NeonNode)({ section: cell.section as S });
		}
		if (cell.kind === SectionCellKind.Footer) {
			return renderFooter === null ? emptyCell : (renderFooter as (info: SectionInfo<S>) => NeonNode)({ section: cell.section as S });
		}
		const flat = info.index;
		const sectionIndex = (): int32 => {
			version();
			return sectionAt(flat() as int32);
		};
		const local = accessor((): number => {
			const s = sectionIndex();
			return flat() - (starts[s] as number) - 1;
		});
		const section = accessor((): S => snapshot[sectionIndex()]);
		const node = renderItem({ item: cell.item as T, index: local, section });
		if (sectionSeparator === null && itemSeparator === null) { return node; }
		const last = accessor((): boolean => local() >= getItemCount(section()) - 1);
		const leading = sectionSeparator === null ? null : Show({ when: accessor((): boolean => local() === 0), children: sectionSeparator, fallback: null });
		const between = itemSeparator === null ? null : Show({ when: accessor((): boolean => !last()), children: itemSeparator, fallback: null });
		const trailing = sectionSeparator === null ? between : Show({ when: last, children: sectionSeparator, fallback: between });
		return element(<>{leading}{node}{trailing}</>);
	};

	const tokens = (cells: ViewToken<SectionCell<T, S>>[]): SectionViewToken<T, S>[] => {
		const out: SectionViewToken<T, S>[] = [];
		for (const token of cells) {
			const flat = token.index as int32;
			if (flat >= total) { continue; }
			const s = sectionAt(flat);
			const cell = token.item;
			if (cell.kind === SectionCellKind.Item) {
				out.push({ item: cell.item, index: (flat - starts[s] - 1) as number, section: snapshot[s], isViewable: token.isViewable });
			} else {
				out.push({ item: null, index: null, section: cell.section as S, isViewable: token.isViewable });
			}
		}
		return out;
	};

	return listEngine<SectionCell<T, S>, S[]>({
		...props,
		data: props.sections,
		getItem: cellAt,
		getItemCount: (sections: S[]): number => {
			layoutOf(sections);
			return total as number;
		},
		renderItem: renderCell,
		ItemSeparatorComponent: null,
		stickyHeaderIndices: !stickyHeaders ? null : accessor((): int32[] => {
			version();
			const out: int32[] = [];
			for (const at of starts) { out.push(at + listHeaderOffset); }
			return out;
		}),
		onViewableItemsChanged: sectionChanged === null ? null : (info: ViewabilityInfo<SectionCell<T, S>>): void => {
			(sectionChanged as (info: SectionViewabilityInfo<T, S>) => void)({
				viewableItems: tokens(info.viewableItems),
				changed: tokens(info.changed),
				viewabilityConfig: info.viewabilityConfig,
			});
		},
		viewabilityConfigCallbackPairs: null,
		ref: (list: FlatListHandle): void => {
			if (userRef === null) { return; }
			(userRef as (handle: SectionListHandle) => void)(new SectionListHandle(list, (sectionIndex: int32): int32 => sectionIndex < starts.length ? starts[sectionIndex] : total, stickyHeaders));
		},
	}, "VirtualizedSectionList", null, null);
}

export function SectionList<T, S extends SectionBase<T>>(props: {
	sections: Accessor<S[]>;
	renderItem: (info: SectionListRenderItemInfo<T, S>) => NeonNode;
	renderSectionHeader?: ((info: SectionInfo<S>) => NeonNode) | null;
	renderSectionFooter?: ((info: SectionInfo<S>) => NeonNode) | null;
	getItemLayout?: ((sections: S[], index: number) => ItemLayout) | null;
	ItemSeparatorComponent?: NeonNode | null;
	SectionSeparatorComponent?: NeonNode | null;
	stickySectionHeadersEnabled?: Accessor<boolean> | null;
	disableVirtualization?: Accessor<boolean> | null;
	onViewableItemsChanged?: ((info: SectionViewabilityInfo<T, S>) => void) | null;
	ListHeaderComponent?: NeonNode | null;
	ListFooterComponent?: NeonNode | null;
	ListEmptyComponent?: NeonNode | null;
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
	invertStickyHeaders?: Accessor<boolean> | null;
	scrollEnabled?: Accessor<boolean> | null;
	showsHorizontalScrollIndicator?: Accessor<boolean> | null;
	showsVerticalScrollIndicator?: Accessor<boolean> | null;
	pagingEnabled?: Accessor<boolean> | null;
	keyboardDismissMode?: Accessor<KeyboardDismissMode> | null;
	keyboardShouldPersistTaps?: Accessor<KeyboardShouldPersistTaps> | null;
	viewabilityConfig?: Accessor<ViewabilityConfig> | null;
	onScrollBeginDrag?: ((e: NeonEvent) => void) | null;
	onScrollEndDrag?: ((e: NeonEvent) => void) | null;
	onMomentumScrollBegin?: ((e: NeonEvent) => void) | null;
	onMomentumScrollEnd?: ((e: NeonEvent) => void) | null;
	onRefresh?: (() => void) | null;
	refreshing?: Accessor<boolean> | null;
	onContentSizeChange?: ((width: number, height: number) => void) | null;
	style?: Accessor<Style> | null;
	contentContainerStyle?: Accessor<Style> | null;
	ref?: ((handle: SectionListHandle) => void) | null;
}): NeonNode {
	const sticky = props.stickySectionHeadersEnabled;
	return VirtualizedSectionList<T, S>({
		...props,
		getItem: (section: S, index: number): T => section.data[index],
		getItemCount: (section: S): number => section.data.length,
		stickySectionHeadersEnabled: sticky !== null ? sticky : accessor((): boolean => stickySectionHeadersByDefault()),
	});
}
