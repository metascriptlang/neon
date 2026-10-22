import { Accessor, accessor } from "../core/signal";
import { NeonNode } from "../render/hostTypes";
import { NeonEvent } from "../render/event";
import { Style } from "../render/style";
import { createContext, useContext } from "../render/context";
import { View, Text, Pressable } from "../components/primitives";
import { For, Show } from "../macros/ui/flow";
import { Platform } from "../api/platform";
import { DefaultTheme, ScreenOptions, TabBarIconProps, Theme } from "./core";
import { Slot } from "./header";

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

export interface TabTrigger {
	key: string;
	label: Accessor<string>;
	options: Accessor<ScreenOptions>;
	focused: Accessor<boolean>;
	href: Accessor<string | null>;
	press: () => void;
}

export function tabAccessibilityLabel(label: string, at: int32, count: int32, os: string): string {
	if (os !== "ios") { return label; }
	return label + ", tab, " + (at + 1).toString() + " of " + count.toString();
}

function tabItem(
	trigger: TabTrigger,
	at: Accessor<number>,
	count: Accessor<int32>,
	theme: Accessor<Theme>,
	top: Accessor<boolean>,
): NeonNode {
	const options = trigger.options;
	const focused = trigger.focused;
	const label = trigger.label;
	const color = accessor((): string => {
		const own = focused() ? options().tabBarActiveTintColor : options().tabBarInactiveTintColor;
		if (own !== null) { return own as string; }
		return focused() ? theme().colors.primary : TAB_INACTIVE;
	});
	const a11y = accessor((): string => {
		const own = options().tabBarAccessibilityLabel;
		if (own !== null) { return own as string; }
		return tabAccessibilityLabel(label(), at() as int32, count(), Platform.OS);
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
		backgroundColor: focused() ? color() : theme().colors.card,
	}));
	const badgeBox = accessor((): Style => ({
		...BADGE,
		backgroundColor: theme().colors.notification,
	}));
	return <Pressable style={TAB_ITEM} accessibilityRole={Platform.OS === "ios" ? "button" : "tab"}
		accessibilityLabel={a11y()} accessibilityState={{ selected: focused() }}
		onPress={(e: NeonEvent): void => trigger.press()}>
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

export function tabRow(
	triggers: Accessor<TabTrigger[]>,
	theme: Accessor<Theme>,
	top: Accessor<boolean>,
	bar: Accessor<Style>,
): NeonNode {
	const count = accessor((): int32 => triggers().length as int32);
	const item = (trigger: TabTrigger, at: Accessor<number>): NeonNode => {
		return tabItem(trigger, at, count, theme, top);
	};
	return <View style={bar} accessibilityRole="tablist">
		<For each={triggers}>{item}</For>
	</View>;
}

export function tabHairline(theme: Accessor<Theme>): NeonNode {
	const line = accessor((): Style => ({ height: 1, backgroundColor: theme().colors.border }));
	return <View style={line} />;
}

export interface TabList {
	tabs: Accessor<TabTrigger[]>;
}

export const TabsContext = createContext<TabList | null>(null);

export function useTabs(): Accessor<TabTrigger[]> {
	const list = useContext(TabsContext);
	if (list === null) { throw new Error("navigation: useTabs is called outside the layout of a Tabs route"); }
	return (list as TabList).tabs;
}

export function TabBar(props: { theme?: Accessor<Theme> | null }): NeonNode {
	const tabs = useTabs();
	const own = props.theme;
	const theme = accessor((): Theme => own === null ? DefaultTheme : (own as Accessor<Theme>)());
	const bar = accessor((): Style => ({
		flexDirection: "row",
		height: 56,
		backgroundColor: theme().colors.card,
	}));
	return <View style={{ flexDirection: "column" }}>
		{tabHairline(theme)}
		{tabRow(tabs, theme, accessor((): boolean => false), bar)}
	</View>;
}
