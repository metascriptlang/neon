import { Accessor, accessor, untrack } from "../core/signal";
import { createMemo } from "../core/memo";
import { NeonNode } from "../render/hostTypes";
import { NeonEvent } from "../render/event";
import { Style } from "../render/style";
import { View, Text, Pressable } from "../components/primitives";
import { For, Show } from "../macros/ui/flow";
import { Platform } from "../api/platform";
import { NavigationChild } from "./children";
import { ChildPages, Pages, createChildPages } from "./childPages";
import {
	WebNavigationNode,
	WebNavigationOwner,
	childPagesWebNavigation,
	webNavigationNode,
} from "./webNavigation";
import {
	DrawerAction,
	Navigation,
	NavigatorCore,
	NavigatorKind,
	NavigatorModel,
	RouteSeed,
	RouteWebMap,
	ScreenOptions,
	ScreenProps,
	TabBarIconProps,
	createCore,
	currentScope,
	mergeOptions,
	NavigationAction,
	noAction,
	seedKey,
} from "./core";
import { Slot, screenView, shown } from "./header";
import { createNavigatorMotion } from "./navigatorMotion";
import { readName, readOptions } from "./stack";
import {
	createScreenCollector, collectScreens, groupOf, screenOf, watchScreens,
} from "./screenCollection";

export type BackBehavior = "firstRoute" | "initialRoute" | "history" | "none";

export type TabBarPosition = "top" | "bottom";

export const TAB_INACTIVE = "#8e8e93";

const TAB_ITEM: Style = {
	flex: 1,
	position: "relative",
	flexDirection: "column",
	alignItems: "center",
	justifyContent: "center",
	paddingTop: 6,
	paddingBottom: 6,
};

const BADGE: Style = {
	borderRadius: 9,
	paddingLeft: 5,
	paddingRight: 5,
	height: 18,
	alignItems: "center",
	justifyContent: "center",
};

function withoutHeader(options: Accessor<ScreenOptions>): Accessor<ScreenOptions> {
	return accessor((): ScreenOptions => mergeOptions({ headerShown: false }, options()));
}

export function readBehavior(behavior: Accessor<BackBehavior> | null, fallback: string): string {
	if (behavior === null) { return fallback; }
	const read = behavior as Accessor<BackBehavior>;
	return untrack((): string => {
		const value: BackBehavior = read();
		return value;
	});
}

function holds(keys: string[], key: string): boolean {
	for (const known of keys) {
		if (known === key) { return true; }
	}
	return false;
}

function withKey(seen: string[] | null, key: string): string[] {
	if (seen === null) { return [key]; }
	return holds(seen, key) ? seen : [...seen, key];
}

export function mountedEntries<P>(core: NavigatorCore<P>): Accessor<Navigation<P>[]> {
	const visited = createMemo<string[]>(
		(seen: string[] | null): string[] => withKey(seen, core.currentKey()),
	);
	return accessor((): Navigation<P>[] => {
		const kept: Navigation<P>[] = [];
		const focused = core.currentKey();
		const seen = visited();
		for (const entry of core.entries()) {
			const options = entry.options();
			if (shown(options.unmountOnBlur, false) && entry.route.key !== focused) { continue; }
			if (holds(seen, entry.route.key) || !shown(options.lazy, true)) { kept.push(entry); }
		}
		return kept;
	});
}

export function labelOf<P>(entry: Navigation<P>, own: string | null): string {
	if (own !== null) { return own as string; }
	const title = entry.options().title;
	return title === null ? entry.route.name : title as string;
}

export function tabAccessibilityLabel(label: string, at: int32, count: int32, os: string): string {
	if (os !== "ios") { return label; }
	return label + ", tab, " + (at + 1).toString() + " of " + count.toString();
}

export function tabItem<P>(
	core: NavigatorCore<P>,
	entry: Navigation<P>,
	top: Accessor<boolean>,
): NeonNode {
	const key = entry.route.key;
	const focused = accessor((): boolean => core.currentKey() === key);
	const options = accessor((): ScreenOptions => entry.options());
	const label = accessor((): string => labelOf<P>(entry, options().tabBarLabel));
	const color = accessor((): string => {
		const own = focused() ? options().tabBarActiveTintColor : options().tabBarInactiveTintColor;
		if (own !== null) { return own as string; }
		return focused() ? core.container.theme().colors.primary : TAB_INACTIVE;
	});
	const a11y = accessor((): string => {
		const own = options().tabBarAccessibilityLabel;
		if (own !== null) { return own as string; }
		const all = core.entries();
		let at: int32 = 0;
		for (let i = 0; i < all.length; i += 1) {
			if (all[i].route.key === key) { at = i as int32; }
		}
		return tabAccessibilityLabel(label(), at, all.length as int32, Platform.OS);
	});
	const badge = accessor((): string => {
		const value = options().tabBarBadge;
		return value === null ? "" : value as string;
	});
	const icon = accessor((): NeonNode | null => {
		const render = options().tabBarIcon;
		if (render === null) { return null; }
		const props: TabBarIconProps = { focused: focused(), color: color(), size: 24 };
		return (render as (props: TabBarIconProps) => NeonNode)(props);
	});
	const indicator = accessor((): Style => ({
		position: "absolute",
		left: 0,
		right: 0,
		bottom: 0,
		height: 2,
		backgroundColor: focused() ? color() : core.container.theme().colors.card,
	}));
	const badgeBox = accessor((): Style => ({
		...BADGE,
		backgroundColor: core.container.theme().colors.notification,
	}));
	const press = (e: NeonEvent): void => {
		if (entry.emit("tabPress", new NavigationAction("TAB_PRESS", noAction))) { return; }
		if (untrack((): boolean => focused())) {
			core.repressFocused();
			return;
		}
		core.navigateLocal(entry.route.name, null);
	};
	return <Pressable style={TAB_ITEM}
		accessibilityRole="button" accessibilityLabel={a11y()} onPress={press}>
		<Slot node={icon} />
		<View style={{ flexDirection: "row", alignItems: "center", gap: 4 }}>
			<Text style={{ color: color(), fontSize: 12 }}>{label()}</Text>
			<Show when={badge() !== ""}>
				<View style={badgeBox}>
					<Text style={{ color: "#ffffff", fontSize: 11 }}>{badge()}</Text>
				</View>
			</Show>
		</View>
		<Show when={top()}>
			<View style={indicator} />
		</Show>
	</Pressable>;
}

function startPages<P>(core: NavigatorCore<P>): Pages<RouteSeed<P>> {
	const items: RouteSeed<P>[] = [];
	let selectedIndex: int32 = 0;
	for (let i = 0; i < core.screens.length; i += 1) {
		const name = core.screens[i].name;
		if (name === core.initialName) { selectedIndex = i as int32; }
		items.push(core.seed(name, null));
	}
	return { items, selectedIndex };
}

function resetPages<P>(
	core: NavigatorCore<P>,
	list: RouteSeed<P>[],
	at: int32,
): Pages<RouteSeed<P>> {
	const items: RouteSeed<P>[] = [];
	let selectedIndex: int32 = 0;
	for (let i = 0; i < core.screens.length; i += 1) {
		const name = core.screens[i].name;
		let entry: RouteSeed<P> | null = null;
		for (const given of list) {
			if (given.name === name) { entry = given; }
		}
		if (entry === null) { entry = core.seed(name, null); }
		if (name === list[at].name) { selectedIndex = i as int32; }
		items.push(entry as RouteSeed<P>);
	}
	return { items, selectedIndex };
}

export function pagesModel<P>(
	core: NavigatorCore<P>,
	behavior: string,
	restored: RouteSeed<P>[] | null,
	at: int32,
): NavigatorModel<P> {
	const initial = restored === null
		? startPages<P>(core)
		: resetPages<P>(core, restored as RouteSeed<P>[], at);
	const pages = createChildPages<RouteSeed<P>, Navigation<P>>(
		initial,
		seedKey,
		(seed: Accessor<RouteSeed<P>>, active: Accessor<boolean>): Navigation<P> => {
			return core.child(seed, active);
		},
	);
	const entries = pages.instances;
	let history: string[] = [initial.items[initial.selectedIndex].key];
	const visit = (key: string): void => {
		const kept: string[] = [];
		for (const visited of history) {
			if (visited !== key) { kept.push(visited); }
		}
		kept.push(key);
		history = kept;
	};
	const focus = (at: int32): void => {
		visit(core.snapshot()[at].route.key);
		core.apply((): void => { pages.select(at); });
	};
	const backTarget = (): int32 => {
		const list = core.snapshot();
		const at = untrack((): int32 => pages.selectedIndex());
		if (behavior === "none") { return -1; }
		if (behavior === "history") {
			if (history.length < 2) { return -1; }
			const previous = history[history.length - 2];
			for (let i = 0; i < list.length; i += 1) {
				if (list[i].route.key === previous) { return i as int32; }
			}
			return -1;
		}
		let goal: int32 = 0;
		if (behavior === "initialRoute") { goal = core.indexOfName(list, core.initialName); }
		return goal === at || goal < 0 ? -1 : goal;
	};
	const backPath = (): int32[] => {
		const at = pages.selectedIndex();
		if (behavior !== "history") {
			const goal = untrack((): int32 => backTarget());
			return goal < 0 ? [at] : [goal, at];
		}
		const list = core.snapshot();
		const path: int32[] = [];
		for (const key of history) {
			for (let i = 0; i < list.length; i += 1) {
				if (i !== at && list[i].route.key === key) { path.push(i as int32); }
			}
		}
		path.push(at);
		return path;
	};
	const back = (): boolean => {
		const goal = backTarget();
		if (goal < 0) { return false; }
		if (behavior === "history") {
			history.pop();
			core.apply((): void => { pages.select(goal); });
			return true;
		}
		focus(goal);
		return true;
	};
	return {
		entries,
		index: accessor((): int32 => pages.selectedIndex()),
		arrange: (kept: Navigation<P>[], focused: Navigation<P> | null): void => {
			const items: RouteSeed<P>[] = [];
			for (const config of core.screens) {
				let found: Navigation<P> | null = null;
				for (const entry of kept) {
					if (entry.route.name === config.name) { found = entry; }
				}
				items.push(found === null
					? core.seed(config.name, null)
					: core.seedOf(found as Navigation<P>));
			}
			let selectedIndex: int32 = 0;
			if (focused !== null) {
				for (let i = 0; i < items.length; i += 1) {
					if (items[i].name === (focused as Navigation<P>).route.name) {
						selectedIndex = i as int32;
					}
				}
			}
			const visited: string[] = [];
			for (const key of history) {
				for (const seed of items) {
					if (seed.key === key) { visited.push(key); }
				}
			}
			if (visited.length === 0) { visited.push(items[selectedIndex].key); }
			history = visited;
			core.apply((): void => {
				pages.navigate((current: Pages<RouteSeed<P>>): Pages<RouteSeed<P>> => {
					return { items, selectedIndex };
				});
			});
		},
		navigate: (name: string, params: P | null): void => {
			const list = core.snapshot();
			const at = core.indexOfName(list, name);
			if (params !== null) { list[at].writeParams(params); }
			focus(at);
		},
		push: (name: string, params: P | null): boolean => false,
		replace: (key: string, name: string, params: P | null): void => {
			core.navigate(name, params);
		},
		popTo: (at: int32): void => {},
		reset: (list: RouteSeed<P>[], at: int32): void => {
			const next = resetPages<P>(core, list, at);
			history = [next.items[next.selectedIndex].key];
			core.apply((): void => {
				pages.navigate((current: Pages<RouteSeed<P>>): Pages<RouteSeed<P>> => next);
			});
		},
		goBackFrom: (key: string): boolean => back(),
		canBack: (): boolean => backTarget() >= 0,
		back,
		canPop: (): boolean => false,
		drawer: (action: DrawerAction): boolean => false,
		webNavigation: (map: RouteWebMap<P>): WebNavigationNode => {
			const web = childPagesWebNavigation<RouteSeed<P>, Navigation<P>>(pages, map.serializer, {
				pathMapper: (
					page: NavigationChild<RouteSeed<P>, Navigation<P>>,
				): string | null => map.path(page.instance),
				parametersMapper: (
					page: NavigationChild<RouteSeed<P>, Navigation<P>>,
				): Map<string, string> | null => map.parameters(page.instance),
				childSelector: (
					child: NavigationChild<RouteSeed<P>, Navigation<P>>,
				): WebNavigationOwner | null => map.child(child.instance),
				visited: (current: ChildPages<RouteSeed<P>, Navigation<P>>): int32[] => backPath(),
			});
			return webNavigationNode<Pages<RouteSeed<P>>>({
				serializer: web.serializer,
				history: web.history,
				onBeforeNavigate: web.onBeforeNavigate,
				navigate: (keys: Pages<RouteSeed<P>>[]): void => {
					const restored: string[] = [];
					for (const key of keys) {
						if (key.selectedIndex >= 0) { restored.push(key.items[key.selectedIndex].key); }
					}
					history = restored;
					core.apply((): void => {
						web.navigate(keys);
						core.restoreParams(keys[keys.length - 1].items);
					});
					const current = core.current();
					if (current !== null) { visit((current as Navigation<P>).route.key); }
				},
			});
		},
	};
}

export interface TabNavigator<P> {
	Navigator: (props: {
		children: NeonNode;
		initialRouteName?: Accessor<string> | null;
		screenOptions?: Accessor<ScreenOptions> | null;
		backBehavior?: Accessor<BackBehavior> | null;
		tabBarStyle?: Accessor<Style> | null;
		tabBarPosition?: Accessor<TabBarPosition> | null;
	}) => NeonNode;
	Group: (props: {
		children: NeonNode;
		screenOptions?: Accessor<ScreenOptions> | null;
		navigationKey?: Accessor<string> | null;
	}) => NeonNode;
	Screen: (props: {
		name: string;
		component: (props: ScreenProps<P>) => NeonNode;
		options?: Accessor<ScreenOptions> | null;
		initialParams?: P | null;
		parseParams?: ((values: Map<string, string>) => P) | null;
		stringifyParams?: ((params: P) => Map<string, string>) | null;
		navigationKey?: Accessor<string> | null;
	}) => NeonNode;
}

export function createBottomTabNavigator<P>(): TabNavigator<P> {
	return createTabs<P>(false);
}

export function createMaterialTopTabNavigator<P>(): TabNavigator<P> {
	return createTabs<P>(true);
}

function createTabs<P>(material: boolean): TabNavigator<P> {
	const collector = createScreenCollector();
	return {
		Navigator: (props: {
			children: NeonNode;
			initialRouteName?: Accessor<string> | null;
			screenOptions?: Accessor<ScreenOptions> | null;
			backBehavior?: Accessor<BackBehavior> | null;
			tabBarStyle?: Accessor<Style> | null;
			tabBarPosition?: Accessor<TabBarPosition> | null;
		}): NeonNode => {
			const collection = collectScreens<P>(collector, props.children);
			const screens = untrack(() => collection.read());
			const declared = readOptions(props.screenOptions);
			const behavior = readBehavior(props.backBehavior, "firstRoute");
			const core = createCore<P>({
				kind: NavigatorKind.Tabs,
				screens,
				initialRouteName: readName(props.initialRouteName),
				screenOptions: material ? withoutHeader(declared) : declared,
				scope: currentScope("Tab.Navigator"),
				model: (
					core: NavigatorCore<P>,
					restored: RouteSeed<P>[] | null,
					at: int32,
				): NavigatorModel<P> => pagesModel<P>(core, behavior, restored, at),
			});
			watchScreens<P>(collection, core);
			const position = props.tabBarPosition;
			const top = accessor((): boolean => {
				if (position === null) { return material; }
				const value: TabBarPosition = (position as Accessor<TabBarPosition>)();
				return value === "top";
			});
			const own = props.tabBarStyle;
			const bar = accessor((): Style => {
				const base: Style = {
					flexDirection: "row",
					height: material ? 48 : 56,
					backgroundColor: core.container.theme().colors.card,
				};
				if (own === null) { return base; }
				const extra = (own as Accessor<Style>)();
				const background = extra.backgroundColor;
				if (background === null) { return base; }
				return { ...base, backgroundColor: background };
			});
			const mounted = mountedEntries<P>(core);
			const transitions = createNavigatorMotion<P>(core, false);
			const screen = (entry: Navigation<P>, at: Accessor<number>): NeonNode => {
				return screenView<P>(core, transitions, entry, false);
			};
			const item = (entry: Navigation<P>, at: Accessor<number>): NeonNode => {
				return tabItem<P>(core, entry, top);
			};
			const frame = accessor((): Style => ({
				flex: 1,
				flexDirection: top() ? "column-reverse" : "column",
			}));
			const hairline = accessor((): Style => ({
				height: 1,
				backgroundColor: core.container.theme().colors.border,
			}));
			return <View style={frame}>
				<View style={{ flex: 1, flexDirection: "column", position: "relative" }}>
					<For each={mounted}>{screen}</For>
				</View>
				<View style={hairline} />
				<View style={bar}>
					<For each={core.entries}>{item}</For>
				</View>
			</View>;
		},
		Group: (props: {
			children: NeonNode;
			screenOptions?: Accessor<ScreenOptions> | null;
			navigationKey?: Accessor<string> | null;
		}): NeonNode => {
			return groupOf(
				collector, props.children, props.screenOptions, props.navigationKey,
			);
		},
		Screen: (props: {
			name: string;
			component: (props: ScreenProps<P>) => NeonNode;
			options?: Accessor<ScreenOptions> | null;
			initialParams?: P | null;
			parseParams?: ((values: Map<string, string>) => P) | null;
			stringifyParams?: ((params: P) => Map<string, string>) | null;
			navigationKey?: Accessor<string> | null;
		}): NeonNode => screenOf<P>(
			collector,
			props.name,
			props.component,
			props.options,
			props.initialParams,
			props.parseParams,
			props.stringifyParams,
			props.navigationKey,
		),
	};
}
