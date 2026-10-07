// react-native-tab-view's TabView and TabBar (Flutter material/tabs.dart TabBar with
// TabBarView): swipeable pages under a tab bar whose indicator follows the page position
// between the measured tabs, lazy scenes, and a scrollable bar that centres its tab.

import { Accessor, accessor, createSignal, untrack } from "../core/signal";
import { createEffect } from "../core/effect";
import { For, Show } from "../macros/ui/flow";
import { element } from "../macros/ui/element";
import { NeonNode, VAttr, dynAttr, evt, hostElement } from "../render/node";
import { NeonEvent } from "../render/event";
import { Style, mergeStyle } from "../render/style";
import { ScrollView, ScrollViewHandle, Text, View } from "./primitives";
import { MATERIAL_PRIMARY, MATERIAL_SURFACE, colorOr, stateAttr, stateTokens } from "./material";
import { PageController, PageRenderItemInfo, PageView } from "./pageView";

export interface TabRoute {
	key: string;
	title: string;
	accessibilityLabel?: string | null;
}

export interface TabSceneInfo {
	route: TabRoute;
	index: number;
	focused: Accessor<boolean>;
	jumpTo: (key: string) => void;
}

export type TabBarPosition = "top" | "bottom";

// RN tab-view TabBar: minHeight 48, indicator height 2; Flutter tabs.dart kTabLabelPadding
// is 16 pt each side.
const TAB_HEIGHT = 48;
const INDICATOR_HEIGHT = 2;
const LABEL_PADDING = 16;
const INACTIVE_COLOR = "#757575";

export interface TabLayout {
	x: number;
	width: number;
}

// Where the indicator sits at a fractional page position: between the two tabs it lies
// between, linearly (TabBar _IndicatorPainter over the TabController animation).
export function indicatorAt(layouts: TabLayout[], position: number): TabLayout {
	const n = layouts.length as int32;
	if (n === 0) { return { x: 0, width: 0 }; }
	const clamped = Math.max(0, Math.min((n - 1) as number, position));
	const from = Math.floor(clamped) as int32;
	const to = Math.min(n - 1, from + 1);
	const t = clamped - (from as number);
	const a = layouts[from];
	const b = layouts[to];
	return { x: a.x + (b.x - a.x) * t, width: a.width + (b.width - a.width) * t };
}

export function TabBar(props: {
	routes: Accessor<TabRoute[]>;
	position: Accessor<number>;
	index: Accessor<number>;
	onTabPress?: ((index: number) => void) | null;
	scrollEnabled?: Accessor<boolean> | null;
	activeColor?: Accessor<string> | null;
	inactiveColor?: Accessor<string> | null;
	indicatorColor?: Accessor<string> | null;
	style?: Accessor<Style> | null;
	tabStyle?: Accessor<Style> | null;
	labelStyle?: Accessor<Style> | null;
}): NeonNode {
	const { routes, position, index, onTabPress } = props;
	const scrollProp = props.scrollEnabled;
	const activeProp = props.activeColor;
	const inactiveProp = props.inactiveColor;
	const indicatorProp = props.indicatorColor;
	const tabStyleProp = props.tabStyle;
	const labelStyleProp = props.labelStyle;
	const scrolls = (): boolean => scrollProp !== null && (scrollProp as Accessor<boolean>)();
	const [layouts, setLayouts] = createSignal<TabLayout[]>([]);
	const [viewport, setViewport] = createSignal<number>(0);
	let scroller: ScrollViewHandle | null = null;

	const measured = (at: number, e: NeonEvent): void => {
		const next: TabLayout[] = [];
		const old = untrack<TabLayout[]>(layouts);
		const n = untrack<TabRoute[]>(routes).length as int32;
		for (let i = 0; i < n; i += 1) {
			next.push(i < old.length ? old[i] : { x: 0, width: 0 });
		}
		const slot = at as int32;
		if (slot >= n) { return; }
		if (next[slot].x === e.x && next[slot].width === e.width) { return; }
		next[slot] = { x: e.x, width: e.width };
		setLayouts(next);
	};

	// tabs.dart _TabBarState._scrollToCurrentIndex: a scrollable bar centres its tab.
	createEffect((): void => {
		if (!scrolls()) { return; }
		const at = index() as int32;
		const all = layouts();
		const width = viewport();
		if (scroller === null || at < 0 || at >= all.length || width <= 0) { return; }
		const tab = all[at];
		const target = Math.max(0, tab.x + tab.width / 2 - width / 2);
		(scroller as ScrollViewHandle).scrollTo({ x: target, y: 0, animated: true });
	});

	const tab = (route: TabRoute, at: Accessor<number>): NeonNode => {
		const focused = (): boolean => index() === at();
		const box = accessor((): Style => {
			const base: Style = scrolls()
				? { minHeight: TAB_HEIGHT, paddingLeft: LABEL_PADDING, paddingRight: LABEL_PADDING, alignItems: "center", justifyContent: "center" }
				: { flex: 1, minHeight: TAB_HEIGHT, paddingLeft: 4, paddingRight: 4, alignItems: "center", justifyContent: "center" };
			return tabStyleProp === null ? base : mergeStyle(base, (tabStyleProp as Accessor<Style>)());
		});
		const label = accessor((): Style => {
			const ink = focused() ? colorOr(activeProp, MATERIAL_PRIMARY) : colorOr(inactiveProp, INACTIVE_COLOR);
			const base: Style = { fontSize: 14, fontWeight: "bold", color: ink };
			return labelStyleProp === null ? base : mergeStyle(base, (labelStyleProp as Accessor<Style>)());
		});
		const attrs: VAttr[] = [];
		attrs.push(dynAttr("accessibilityRole", (): string | null => "tab"));
		const spoken = route.accessibilityLabel;
		attrs.push(dynAttr("accessibilityLabel", (): string | null => spoken === null ? route.title : spoken as string));
		stateAttr(attrs, (): string => stateTokens("", focused(), false));
		const press = (e: NeonEvent): void => {
			if (onTabPress !== null) { (onTabPress as (i: number) => void)(at()); }
		};
		const layout = (e: NeonEvent): void => { measured(at(), e); };
		const kids = element(<Text style={label}>{route.title}</Text>);
		return hostElement("pressable", attrs, [evt("onPress", press), evt("onLayout", layout)], kids, box as () => Style, null);
	};

	const indicator = accessor((): Style => {
		const spot = indicatorAt(layouts(), position());
		return {
			position: "absolute", bottom: 0, left: spot.x, width: spot.width, height: INDICATOR_HEIGHT,
			backgroundColor: colorOr(indicatorProp, colorOr(activeProp, MATERIAL_PRIMARY)),
		};
	});
	const tabs = For<TabRoute>({ each: routes, children: tab });
	const rowStyle = accessor((): Style => scrolls() ? { flexDirection: "row" } : { flexDirection: "row", flex: 1 });
	const row: NeonNode = element(<View style={rowStyle}>{tabs}<View style={indicator} /></View>);
	const attrs: VAttr[] = [];
	attrs.push(dynAttr("accessibilityRole", (): string | null => "tablist"));
	const userStyle = props.style;
	const barStyle = accessor((): Style => mergeStyle({ flexDirection: "row", backgroundColor: MATERIAL_SURFACE }, userStyle === null ? {} : (userStyle as Accessor<Style>)()));
	const scroll: NeonNode = ScrollView({
		horizontal: accessor((): boolean => true),
		showsHorizontalScrollIndicator: accessor((): boolean => false),
		style: accessor((): Style => ({ flexGrow: 1 })),
		ref: (h: ScrollViewHandle): void => { scroller = h; },
		onLayout: (e: NeonEvent): void => { setViewport(e.width); },
		children: row,
	});
	const body = element(<Show when={scrolls()} fallback={row}>{scroll}</Show>);
	return hostElement("view", attrs, [], body, barStyle as () => Style, null);
}

export function TabView(props: {
	routes: Accessor<TabRoute[]>;
	renderScene: (info: TabSceneInfo) => NeonNode;
	index?: Accessor<number> | null;
	onIndexChange?: ((index: number) => void) | null;
	lazy?: Accessor<boolean> | null;
	lazyPreloadDistance?: Accessor<number> | null;
	renderLazyPlaceholder?: ((route: TabRoute) => NeonNode) | null;
	swipeEnabled?: Accessor<boolean> | null;
	tabBarPosition?: Accessor<TabBarPosition> | null;
	scrollEnabled?: Accessor<boolean> | null;
	activeColor?: Accessor<string> | null;
	inactiveColor?: Accessor<string> | null;
	indicatorColor?: Accessor<string> | null;
	tabBarStyle?: Accessor<Style> | null;
	tabStyle?: Accessor<Style> | null;
	labelStyle?: Accessor<Style> | null;
	style?: Accessor<Style> | null;
}): NeonNode {
	const { routes, renderScene, onIndexChange } = props;
	const indexProp = props.index;
	const lazyProp = props.lazy;
	const preloadProp = props.lazyPreloadDistance;
	const placeholder = props.renderLazyPlaceholder;
	const positionProp = props.tabBarPosition;
	const controller = new PageController(indexProp === null ? 0 : (indexProp as Accessor<number>)());
	const selected = (): number => controller.selectedPage();

	const changed = (at: number): void => {
		if (onIndexChange !== null) { (onIndexChange as (i: number) => void)(at); }
	};
	const jumpTo = (key: string): void => {
		const all = untrack<TabRoute[]>(routes);
		for (let i = 0; i < all.length; i += 1) {
			if (all[i].key === key) { controller.setPage(i as number); }
		}
	};
	// A controlled index moves the pages; a swipe reports through onPageSelected first, so
	// the index it echoes back already matches.
	if (indexProp !== null) {
		createEffect((): void => {
			const wanted = (indexProp as Accessor<number>)();
			if (untrack<number>(selected) !== wanted) { controller.setPage(wanted); }
		});
	}

	const isLazy = (): boolean => lazyProp !== null && (lazyProp as Accessor<boolean>)();
	const preload = (): number => preloadProp === null ? 0 : (preloadProp as Accessor<number>)();
	const scene = (info: PageRenderItemInfo<TabRoute>): NeonNode => {
		const route = info.item;
		const at = info.index;
		const focused = accessor((): boolean => selected() === at());
		let visited = false;
		const ready = accessor((): boolean => {
			if (!isLazy() || visited) { return true; }
			visited = Math.abs(selected() - at()) <= preload();
			return visited;
		});
		const content = renderScene({ route, index: untrack<number>(at), focused, jumpTo });
		const fallback: NeonNode = placeholder === null ? View({}) : (placeholder as (r: TabRoute) => NeonNode)(route);
		return element(<View style={{ flex: 1 }}><Show when={ready()} fallback={fallback}>{content}</Show></View>);
	};

	const pages = PageView<TabRoute>({
		data: routes,
		renderItem: scene,
		controller,
		scrollEnabled: props.swipeEnabled,
		onPageSelected: (at: number): void => {
			if (indexProp !== null && untrack<number>(indexProp as Accessor<number>) === at) { return; }
			changed(at);
		},
		style: accessor((): Style => ({ flex: 1 })),
	});
	const bar = TabBar({
		routes,
		position: accessor((): number => controller.page()),
		index: accessor(selected),
		onTabPress: (at: number): void => {
			if (indexProp === null) { controller.setPage(at); } else { changed(at); }
		},
		scrollEnabled: props.scrollEnabled,
		activeColor: props.activeColor,
		inactiveColor: props.inactiveColor,
		indicatorColor: props.indicatorColor,
		style: props.tabBarStyle,
		tabStyle: props.tabStyle,
		labelStyle: props.labelStyle,
	});
	const bottom = (): boolean => positionProp !== null && (positionProp as Accessor<TabBarPosition>)() === "bottom";
	const userStyle = props.style;
	const outer = accessor((): Style => mergeStyle({ flex: 1, flexDirection: "column" }, userStyle === null ? {} : (userStyle as Accessor<Style>)()));
	return element(<View style={outer}>
		<Show when={!bottom()}>{bar}</Show>
		{pages}
		<Show when={bottom()}>{bar}</Show>
	</View>);
}
