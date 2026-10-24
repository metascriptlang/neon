import { Accessor, accessor, untrack } from "../core/signal";
import { createMemo } from "../core/memo";
import { NeonNode } from "../render/hostTypes";
import { Style } from "../render/style";
import { View } from "../components/primitives";
import { For } from "../macros/ui/flow";
import { mapArray } from "../core/array";
import { NavigationChild } from "./children";
import { BackBehavior, ChildPages, Pages, createChildPages } from "./childPages";
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
	ParamSlot,
	ScreenParams,
	ScreenParamsBuilder,
	ScreenProps,
	Theme,
	createCore,
	currentScope,
	mergeOptions,
	NavigationAction,
	noAction,
	seedKey,
} from "./core";
import { screenView, shown } from "./header";
import { TabTrigger, tabHairline, tabRow } from "./tabBar";
import { createNavigatorMotion } from "./navigatorMotion";
import { readName, readOptions } from "./stack";
import {
	createScreenCollector, collectScreens, groupOf, screenOf, watchScreens,
} from "./screenCollection";

export type TabBarPosition = "top" | "bottom";

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

export function mountedEntries<PL>(core: NavigatorCore<PL>): Accessor<Navigation<PL>[]> {
	const visited = createMemo<string[]>(
		(seen: string[] | null): string[] => withKey(seen, core.currentKey()),
	);
	return accessor((): Navigation<PL>[] => {
		const kept: Navigation<PL>[] = [];
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

export function labelOf<PL>(entry: Navigation<PL>, own: string | null): string {
	if (own !== null) { return own as string; }
	const title = entry.options().title;
	return title === null ? entry.route.name : title as string;
}

function triggerOf<PL>(core: NavigatorCore<PL>, entry: Navigation<PL>): TabTrigger {
	const key = entry.route.key;
	const options = accessor((): ScreenOptions => entry.options());
	const focused = accessor((): boolean => core.currentKey() === key);
	return {
		key,
		label: accessor((): string => labelOf<PL>(entry, options().tabBarLabel)),
		options,
		focused,
		href: accessor((): string | null => null),
		press: (): void => {
			if (entry.emit("tabPress", new NavigationAction("TAB_PRESS", noAction))) { return; }
			if (untrack((): boolean => focused())) {
				core.repressFocused();
				return;
			}
			core.navigateLocal(entry.route.name, null);
		},
	};
}

function startPages<PL>(core: NavigatorCore<PL>): Pages<RouteSeed<PL>> {
	const items: RouteSeed<PL>[] = [];
	let selectedIndex: int32 = 0;
	for (let i = 0; i < core.screens.length; i += 1) {
		const name = core.screens[i].name;
		if (name === core.initialName) { selectedIndex = i as int32; }
		items.push(core.seed(name, null));
	}
	return { items, selectedIndex };
}

function resetPages<PL>(
	core: NavigatorCore<PL>,
	list: RouteSeed<PL>[],
	at: int32,
): Pages<RouteSeed<PL>> {
	const items: RouteSeed<PL>[] = [];
	let selectedIndex: int32 = 0;
	for (let i = 0; i < core.screens.length; i += 1) {
		const name = core.screens[i].name;
		let entry: RouteSeed<PL> | null = null;
		for (const given of list) {
			if (given.name === name) { entry = given; }
		}
		if (entry === null) { entry = core.seed(name, null); }
		if (name === list[at].name) { selectedIndex = i as int32; }
		items.push(entry as RouteSeed<PL>);
	}
	return { items, selectedIndex };
}

export function pagesModel<PL>(
	core: NavigatorCore<PL>,
	behavior: string,
	restored: RouteSeed<PL>[] | null,
	at: int32,
): NavigatorModel<PL> {
	const initial = restored === null
		? startPages<PL>(core)
		: resetPages<PL>(core, restored as RouteSeed<PL>[], at);
	const pages = createChildPages<RouteSeed<PL>, Navigation<PL>>(
		initial,
		seedKey,
		(seed: Accessor<RouteSeed<PL>>, active: Accessor<boolean>): Navigation<PL> => {
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
		arrange: (kept: Navigation<PL>[], focused: Navigation<PL> | null): void => {
			const items: RouteSeed<PL>[] = [];
			for (const config of core.screens) {
				let found: Navigation<PL> | null = null;
				for (const entry of kept) {
					if (entry.route.name === config.name) { found = entry; }
				}
				items.push(found === null
					? core.seed(config.name, null)
					: core.seedOf(found as Navigation<PL>));
			}
			let selectedIndex: int32 = 0;
			if (focused !== null) {
				for (let i = 0; i < items.length; i += 1) {
					if (items[i].name === (focused as Navigation<PL>).route.name) {
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
				pages.navigate((current: Pages<RouteSeed<PL>>): Pages<RouteSeed<PL>> => {
					return { items, selectedIndex };
				});
			});
		},
		navigate: (name: string, params: ParamSlot | null, pop: boolean): void => {
			const list = core.snapshot();
			const at = core.indexOfName(list, name);
			if (params !== null) { list[at].writeParams(params); }
			focus(at);
		},
		push: (name: string, params: ParamSlot | null): boolean => false,
		replace: (key: string, name: string, params: ParamSlot | null): void => {
			core.navigate(name, params);
		},
		popTo: (at: int32): void => {},
		popToRoute: (name: string, params: ParamSlot | null, source: string | null): boolean => false,
		reset: (list: RouteSeed<PL>[], at: int32): void => {
			const next = resetPages<PL>(core, list, at);
			history = [next.items[next.selectedIndex].key];
			core.apply((): void => {
				pages.navigate((current: Pages<RouteSeed<PL>>): Pages<RouteSeed<PL>> => next);
			});
		},
		goBackFrom: (key: string): boolean => back(),
		canBack: (): boolean => backTarget() >= 0,
		back,
		canPop: (): boolean => false,
		drawer: (action: DrawerAction): boolean => false,
		webNavigation: (map: RouteWebMap<PL>): WebNavigationNode => {
			const web = childPagesWebNavigation<RouteSeed<PL>, Navigation<PL>>(pages, map.serializer, {
				pathMapper: (
					page: NavigationChild<RouteSeed<PL>, Navigation<PL>>,
				): string | null => map.path(page.instance),
				parametersMapper: (
					page: NavigationChild<RouteSeed<PL>, Navigation<PL>>,
				): Map<string, string> | null => map.parameters(page.instance),
				childSelector: (
					child: NavigationChild<RouteSeed<PL>, Navigation<PL>>,
				): WebNavigationOwner | null => map.child(child.instance),
				visited: (current: ChildPages<RouteSeed<PL>, Navigation<PL>>): int32[] => backPath(),
			});
			return webNavigationNode<Pages<RouteSeed<PL>>>({
				serializer: web.serializer,
				history: web.history,
				onBeforeNavigate: web.onBeforeNavigate,
				navigate: (keys: Pages<RouteSeed<PL>>[]): void => {
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
					if (current !== null) { visit((current as Navigation<PL>).route.key); }
				},
			});
		},
	};
}

export interface TabNavigator<PL> {
	params: ScreenParamsBuilder<PL>;
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
		name: keyof PL;
		component: (props: ScreenProps<PL>) => NeonNode;
		options?: Accessor<ScreenOptions> | null;
		params?: ScreenParams<PL> | null;
		navigationKey?: Accessor<string> | null;
	}) => NeonNode;
}

export function createBottomTabNavigator<PL>(): TabNavigator<PL> {
	return createTabs<PL>(false);
}

export function createMaterialTopTabNavigator<PL>(): TabNavigator<PL> {
	return createTabs<PL>(true);
}

function createTabs<PL>(material: boolean): TabNavigator<PL> {
	const collector = createScreenCollector();
	return {
		params: new ScreenParamsBuilder<PL>(),
		Navigator: (props: {
			children: NeonNode;
			initialRouteName?: Accessor<string> | null;
			screenOptions?: Accessor<ScreenOptions> | null;
			backBehavior?: Accessor<BackBehavior> | null;
			tabBarStyle?: Accessor<Style> | null;
			tabBarPosition?: Accessor<TabBarPosition> | null;
		}): NeonNode => {
			const collection = collectScreens<PL>(collector, props.children);
			const screens = untrack(() => collection.read());
			const declared = readOptions(props.screenOptions);
			const behavior = readBehavior(props.backBehavior, "firstRoute");
			const core = createCore<PL>({
				kind: NavigatorKind.Tabs,
				screens,
				initialRouteName: readName(props.initialRouteName),
				screenOptions: material ? withoutHeader(declared) : declared,
				scope: currentScope("Tab.Navigator"),
				model: (
					core: NavigatorCore<PL>,
					restored: RouteSeed<PL>[] | null,
					at: int32,
				): NavigatorModel<PL> => pagesModel<PL>(core, behavior, restored, at),
			});
			watchScreens<PL>(collection, core);
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
			const mounted = mountedEntries<PL>(core);
			const transitions = createNavigatorMotion<PL>(core, false);
			const screen = (entry: Navigation<PL>, at: Accessor<number>): NeonNode => {
				return screenView<PL>(core, transitions, entry, false, at);
			};
			const triggers = mapArray<Navigation<PL>, TabTrigger>(
				(): Navigation<PL>[] => core.entries(),
				(entry: Navigation<PL>, at: Accessor<number>): TabTrigger => triggerOf<PL>(core, entry),
			);
			const theme = accessor((): Theme => core.container.theme());
			const frame = accessor((): Style => ({
				flex: 1,
				flexDirection: top() ? "column-reverse" : "column",
			}));
			return <View style={frame}>
				<View style={{ flex: 1, flexDirection: "column", position: "relative" }}>
					<For each={mounted}>{screen}</For>
				</View>
				{tabHairline(theme)}
				{tabRow(triggers, theme, top, bar)}
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
			name: keyof PL;
			component: (props: ScreenProps<PL>) => NeonNode;
			options?: Accessor<ScreenOptions> | null;
			params?: ScreenParams<PL> | null;
			navigationKey?: Accessor<string> | null;
		}): NeonNode => screenOf<PL>(
			collector,
			props.name as string,
			props.component,
			props.options,
			props.params,
			props.navigationKey,
		),
	};
}
