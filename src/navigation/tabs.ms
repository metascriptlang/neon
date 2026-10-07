import { Accessor, accessor, untrack } from "../core/signal";
import { NeonNode } from "../render/hostTypes";
import { NeonEvent } from "../render/event";
import { Style } from "../render/style";
import { View, Text, Pressable } from "../components/primitives";
import { For, Show } from "../macros/ui/flow";
import {
	Navigation,
	NavigatorCore,
	NavigatorKind,
	ScreenOptions,
	ScreenOptionsOf,
	ScreenProps,
	TabBarIconProps,
	createCore,
	currentScope,
	optionsAccessor,
} from "./core";
import { Slot, screenView, shown } from "./header";
import { ScreenCollector, collectScreens, readName, readOptions, screenOf } from "./stack";

export type BackBehavior = "firstRoute" | "initialRoute" | "history" | "none";

export const TAB_ACTIVE = "#007aff";
export const TAB_INACTIVE = "#8e8e93";
export const BADGE_COLOR = "#ff3b30";

const TAB_ITEM: Style = {
	flex: 1,
	flexDirection: "column",
	alignItems: "center",
	justifyContent: "center",
	paddingTop: 6,
	paddingBottom: 6,
};

const BADGE: Style = {
	backgroundColor: BADGE_COLOR,
	borderRadius: 9,
	paddingLeft: 5,
	paddingRight: 5,
	height: 18,
	alignItems: "center",
	justifyContent: "center",
};

export function readBehavior(behavior: Accessor<BackBehavior> | null, fallback: string): string {
	if (behavior === null) { return fallback; }
	const read = behavior as Accessor<BackBehavior>;
	return untrack((): string => {
		const value: BackBehavior = read();
		return value;
	});
}

export function mountedEntries<P>(core: NavigatorCore<P>): Accessor<Navigation<P>[]> {
	return accessor((): Navigation<P>[] => {
		const kept: Navigation<P>[] = [];
		const focused = core.currentKey();
		for (const entry of core.entries()) {
			const options = entry.options();
			if (shown(options.unmountOnBlur, false) && entry.route.key !== focused) { continue; }
			if (entry.visited() || !shown(options.lazy, true)) { kept.push(entry); }
		}
		return kept;
	});
}

export function labelOf<P>(entry: Navigation<P>, own: string | null): string {
	if (own !== null) { return own as string; }
	const title = entry.options().title;
	return title === null ? entry.route.name : title as string;
}

export function tabItem<P>(core: NavigatorCore<P>, entry: Navigation<P>): NeonNode {
	const key = entry.route.key;
	const focused = accessor((): boolean => core.currentKey() === key);
	const options = accessor((): ScreenOptions => entry.options());
	const label = accessor((): string => labelOf<P>(entry, options().tabBarLabel));
	const color = accessor((): string => {
		const own = focused() ? options().tabBarActiveTintColor : options().tabBarInactiveTintColor;
		if (own !== null) { return own as string; }
		return focused() ? TAB_ACTIVE : TAB_INACTIVE;
	});
	const a11y = accessor((): string => {
		const own = options().tabBarAccessibilityLabel;
		return own === null ? label() : own as string;
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
	const press = (e: NeonEvent): void => {
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
				<View style={BADGE}>
					<Text style={{ color: "#ffffff", fontSize: 11 }}>{badge()}</Text>
				</View>
			</Show>
		</View>
	</Pressable>;
}

export interface TabNavigator<P> {
	Navigator: (props: {
		children: NeonNode;
		initialRouteName?: Accessor<string> | null;
		screenOptions?: Accessor<ScreenOptionsOf<P>> | null;
		backBehavior?: Accessor<BackBehavior> | null;
		tabBarStyle?: Accessor<Style> | null;
	}) => NeonNode;
	Screen: (props: {
		name: string;
		component: (props: ScreenProps<P>) => NeonNode;
		options?: Accessor<ScreenOptionsOf<P>> | null;
		initialParams?: P | null;
		parseParams?: ((values: Map<string, string>) => P) | null;
	}) => NeonNode;
}

export function createBottomTabNavigator<P>(): TabNavigator<P> {
	const collector: ScreenCollector<P> = { screens: null };
	return {
		Navigator: (props: {
			children: NeonNode;
			initialRouteName?: Accessor<string> | null;
			screenOptions?: Accessor<ScreenOptionsOf<P>> | null;
			backBehavior?: Accessor<BackBehavior> | null;
			tabBarStyle?: Accessor<Style> | null;
		}): NeonNode => {
			const screens = collectScreens<P>(collector, props.children);
			const core = createCore<P>({
				kind: NavigatorKind.Tabs,
				screens,
				initialRouteName: readName(props.initialRouteName),
				initialParams: null,
				screenOptions: readOptions<P>(props.screenOptions),
				backBehavior: readBehavior(props.backBehavior, "firstRoute"),
				scope: currentScope("Tab.Navigator"),
			});
			const own = props.tabBarStyle;
			const bar = accessor((): Style => {
				const base: Style = {
					flexDirection: "row",
					height: 56,
					backgroundColor: "#ffffff",
				};
				if (own === null) { return base; }
				const extra = (own as Accessor<Style>)();
				const background = extra.backgroundColor;
				if (background === null) { return base; }
				return { ...base, backgroundColor: background };
			});
			const mounted = mountedEntries<P>(core);
			const screen = (entry: Navigation<P>, at: Accessor<number>): NeonNode => {
				return screenView<P>(core, entry);
			};
			const item = (entry: Navigation<P>, at: Accessor<number>): NeonNode => {
				return tabItem<P>(core, entry);
			};
			return <View style={{ flex: 1, flexDirection: "column" }}>
				<View style={{ flex: 1, flexDirection: "column", position: "relative" }}>
					<For each={mounted}>{screen}</For>
				</View>
				<View style={{ height: 1, backgroundColor: "#d8d8d8" }} />
				<View style={bar}>
					<For each={core.entries}>{item}</For>
				</View>
			</View>;
		},
		Screen: (props: {
			name: string;
			component: (props: ScreenProps<P>) => NeonNode;
			options?: Accessor<ScreenOptionsOf<P>> | null;
			initialParams?: P | null;
			parseParams?: ((values: Map<string, string>) => P) | null;
		}): NeonNode => screenOf<P>(
			collector,
			props.name,
			props.component,
			optionsAccessor<P>(props.options),
			props.initialParams,
			props.parseParams,
		),
	};
}
