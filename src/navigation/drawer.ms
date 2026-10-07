import { Accessor, accessor } from "../core/signal";
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
	createCore,
	currentScope,
	optionsAccessor,
} from "./core";
import { screenView } from "./header";
import { ScreenCollector, collectScreens, readName, readOptions, screenOf } from "./stack";
import { BackBehavior, labelOf, mountedEntries, readBehavior } from "./tabs";

export const DRAWER_WIDTH = 280;

export type DrawerPosition = "left" | "right";

const BACKDROP: Style = {
	position: "absolute",
	top: 0,
	left: 0,
	right: 0,
	bottom: 0,
	backgroundColor: "#000000",
	opacity: 0.4,
};

export function drawerItem<P>(core: NavigatorCore<P>, entry: Navigation<P>): NeonNode {
	const key = entry.route.key;
	const focused = accessor((): boolean => core.currentKey() === key);
	const options = accessor((): ScreenOptions => entry.options());
	const label = accessor((): string => labelOf<P>(entry, options().drawerLabel));
	const tint = accessor((): string => {
		const own = options().drawerActiveTintColor;
		return own === null ? core.container.theme().colors.primary : own as string;
	});
	const row = accessor((): Style => ({
		flexDirection: "row",
		alignItems: "center",
		height: 48,
		paddingLeft: 16,
		paddingRight: 16,
		marginLeft: 8,
		marginRight: 8,
		borderRadius: 8,
		backgroundColor: focused()
			? (core.container.theme().dark ? "#1c2b40" : "#e5f0ff")
			: core.container.theme().colors.card,
	}));
	const press = (e: NeonEvent): void => { core.navigateLocal(entry.route.name, null); };
	const text = accessor((): Style => ({
		color: focused() ? tint() : core.container.theme().colors.text,
		fontSize: 15,
		fontWeight: focused() ? "bold" : "normal",
	}));
	return <Pressable style={row} accessibilityRole="button" accessibilityLabel={label()}
		onPress={press}>
		<Text style={text}>{label()}</Text>
	</Pressable>;
}

export interface DrawerNavigator<P> {
	Navigator: (props: {
		children: NeonNode;
		initialRouteName?: Accessor<string> | null;
		screenOptions?: Accessor<ScreenOptionsOf<P>> | null;
		backBehavior?: Accessor<BackBehavior> | null;
		drawerStyle?: Accessor<Style> | null;
		drawerPosition?: Accessor<DrawerPosition> | null;
	}) => NeonNode;
	Screen: (props: {
		name: string;
		component: (props: ScreenProps<P>) => NeonNode;
		options?: Accessor<ScreenOptionsOf<P>> | null;
		initialParams?: P | null;
		parseParams?: ((values: Map<string, string>) => P) | null;
	}) => NeonNode;
}

export function createDrawerNavigator<P>(): DrawerNavigator<P> {
	const collector: ScreenCollector<P> = { screens: null };
	return {
		Navigator: (props: {
			children: NeonNode;
			initialRouteName?: Accessor<string> | null;
			screenOptions?: Accessor<ScreenOptionsOf<P>> | null;
			backBehavior?: Accessor<BackBehavior> | null;
			drawerStyle?: Accessor<Style> | null;
			drawerPosition?: Accessor<DrawerPosition> | null;
		}): NeonNode => {
			const screens = collectScreens<P>(collector, props.children);
			const core = createCore<P>({
				kind: NavigatorKind.Drawer,
				screens,
				initialRouteName: readName(props.initialRouteName),
				initialParams: null,
				screenOptions: readOptions<P>(props.screenOptions),
				backBehavior: readBehavior(props.backBehavior, "firstRoute"),
				scope: currentScope("Drawer.Navigator"),
			});
			const own = props.drawerStyle;
			const side = props.drawerPosition;
			const right = accessor((): boolean => {
				if (side === null) { return false; }
				const value: DrawerPosition = (side as Accessor<DrawerPosition>)();
				return value === "right";
			});
			const panel = accessor((): Style => {
				const base: Style = {
					position: "absolute",
					top: 0,
					left: right() ? null : 0,
					right: right() ? 0 : null,
					bottom: 0,
					width: DRAWER_WIDTH,
					flexDirection: "column",
					gap: 4,
					paddingTop: 56,
					backgroundColor: core.container.theme().colors.card,
				};
				if (own === null) { return base; }
				const extra = (own as Accessor<Style>)();
				return {
					...base,
					width: extra.width !== null ? extra.width : base.width,
					backgroundColor: extra.backgroundColor !== null
						? extra.backgroundColor
						: base.backgroundColor,
				};
			});
			const close = (e: NeonEvent): void => { core.writeDrawerOpen(false); };
			const mounted = mountedEntries<P>(core);
			const screen = (entry: Navigation<P>, at: Accessor<number>): NeonNode => {
				return screenView<P>(core, entry);
			};
			const item = (entry: Navigation<P>, at: Accessor<number>): NeonNode => {
				return drawerItem<P>(core, entry);
			};
			return <View style={{ flex: 1, flexDirection: "column", position: "relative" }}>
				<View style={{ flex: 1, flexDirection: "column", position: "relative" }}>
					<For each={mounted}>{screen}</For>
				</View>
				<Show when={core.drawerOpen()}>
					<Pressable style={BACKDROP} accessibilityRole="button"
						accessibilityLabel="Close navigation menu" onPress={close} />
					<View style={panel}>
						<For each={core.entries}>{item}</For>
					</View>
				</Show>
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
