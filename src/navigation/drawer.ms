import { Accessor, Setter, accessor, createSignal, untrack } from "../core/signal";
import { createEffect } from "../core/effect";
import { Animated, AnimatedValue, EndResult, Easing } from "../animation/index";
import {
	GestureResponderHandlers,
	PanResponder,
	PanResponderGestureState,
} from "../components/panResponder";
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
import { EDGE_WIDTH, screenView, shown } from "./header";
import { ScreenCollector, collectScreens, groupOf, readName, readOptions, screenOf } from "./stack";
import { BackBehavior, labelOf, mountedEntries, readBehavior } from "./tabs";

export const DRAWER_WIDTH = 280;

export const DRAWER_DURATION = 250;

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

class DrawerMotion {
	progress: AnimatedValue = new AnimatedValue(0);
	shown: Accessor<boolean>;
	writeShown: Setter<boolean>;
	open: Accessor<boolean>;
	setOpen: (open: boolean) => void;
	right: Accessor<boolean>;
	width: () => number;
	swipe: Accessor<boolean>;

	constructor(
		open: Accessor<boolean>,
		setOpen: (open: boolean) => void,
		right: Accessor<boolean>,
		width: () => number,
		swipe: Accessor<boolean>,
	) {
		const [shown, writeShown] = createSignal<boolean>(false);
		this.shown = shown;
		this.writeShown = writeShown;
		this.open = open;
		this.setOpen = setOpen;
		this.right = right;
		this.width = width;
		this.swipe = swipe;
	}

	run(toOpen: boolean): void {
		this.writeShown(true);
		Animated.timing(this.progress, {
			toValue: toOpen ? 1 : 0,
			duration: DRAWER_DURATION,
			easing: Easing.out(Easing.cubic),
		}).start((result: EndResult): void => {
			if (result.finished && !toOpen) { this.writeShown(false); }
		});
	}

	panelTransform(): string {
		const p = this.progress.get();
		if (p >= 1) { return "none"; }
		const offset = (1 - p) * this.width();
		return "translateX(" + (this.right() ? offset : -offset).toString() + "px)";
	}

	edgeShown(): boolean {
		return !this.open() && this.swipe();
	}

	edgeHandlers(): GestureResponderHandlers {
		const pan = PanResponder.create({
			onMoveShouldSetPanResponder: (e: NeonEvent, g: PanResponderGestureState): boolean => {
				const inward = this.right() ? -g.dx : g.dx;
				return inward > 10 && Math.abs(g.dx) > Math.abs(g.dy) * 2;
			},
			onPanResponderGrant: (e: NeonEvent, g: PanResponderGestureState): void => {
				this.progress.stopAnimation();
				this.writeShown(true);
			},
			onPanResponderMove: (e: NeonEvent, g: PanResponderGestureState): void => {
				const inward = this.right() ? -g.dx : g.dx;
				const width = this.width();
				this.progress.setValue(width > 0 ? Math.max(0, Math.min(1, inward / width)) : 0);
			},
			onPanResponderRelease: (e: NeonEvent, g: PanResponderGestureState): void => {
				const speed = this.right() ? -g.vx : g.vx;
				if (this.progress.get() > 0.5 || speed > 0.5) {
					this.setOpen(true);
				} else {
					this.run(false);
				}
			},
			onPanResponderTerminate: (e: NeonEvent, g: PanResponderGestureState): void => { this.run(false); },
		});
		return pan.panHandlers;
	}
}

function drawerMotion<P>(
	core: NavigatorCore<P>,
	right: Accessor<boolean>,
	own: Accessor<Style> | null,
): DrawerMotion {
	const width = (): number => {
		if (own !== null) {
			const extra = (own as Accessor<Style>)().width;
			if (extra !== null && typeof extra !== "string") { return extra as number; }
		}
		return DRAWER_WIDTH;
	};
	const swipe = accessor((): boolean => {
		const current = core.current();
		if (current === null) { return true; }
		return shown((current as Navigation<P>).options().swipeEnabled, true);
	});
	const setOpen = (open: boolean): void => { core.writeDrawerOpen(open); };
	const motion = new DrawerMotion(core.drawerOpen, setOpen, right, width, swipe);
	let first = true;
	createEffect((): void => {
		const open = core.drawerOpen();
		if (first) {
			first = false;
			return;
		}
		untrack((): void => { motion.run(open); });
	});
	return motion;
}

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
	Group: (props: {
		children: NeonNode;
		screenOptions?: Accessor<ScreenOptionsOf<P>> | null;
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
	const collector: ScreenCollector<P> = { screens: null, groups: [] };
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
			const motion = drawerMotion<P>(core, right, own);
			const panel = accessor((): Style => {
				const base: Style = {
					position: "absolute",
					top: 0,
					left: right() ? null : 0,
					right: right() ? 0 : null,
					bottom: 0,
					width: DRAWER_WIDTH,
					transform: motion.panelTransform(),
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
			const backdrop = accessor((): Style => ({ ...BACKDROP, opacity: 0.4 * motion.progress.get() }));
			const edge = accessor((): Style => ({
				position: "absolute",
				top: 56,
				bottom: 0,
				left: right() ? null : 0,
				right: right() ? 0 : null,
				width: EDGE_WIDTH,
			}));
			const edgeHandlers = motion.edgeHandlers();
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
				<Show when={motion.edgeShown()}>
					<View {...edgeHandlers} style={edge} />
				</Show>
				<Show when={motion.shown()}>
					<Pressable style={backdrop} accessibilityRole="button"
						accessibilityLabel="Close navigation menu" onPress={close} />
					<View style={panel}>
						<For each={core.entries}>{item}</For>
					</View>
				</Show>
			</View>;
		},
		Group: (props: {
			children: NeonNode;
			screenOptions?: Accessor<ScreenOptionsOf<P>> | null;
		}): NeonNode => {
			return groupOf<P>(collector, props.children, optionsAccessor<P>(props.screenOptions));
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
