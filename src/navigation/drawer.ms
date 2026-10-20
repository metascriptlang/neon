import { Accessor, Setter, accessor, createSignal, untrack } from "../core/signal";
import { flush } from "../core/runtime";
import { createEffect, createRenderEffect } from "../core/effect";
import { Cleanup } from "../core/types";
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
	DRAWER_OPEN_KEY,
	DrawerAction,
	Navigation,
	NavigatorCore,
	NavigatorKind,
	NavigatorLink,
	NavigatorModel,
	RouteSeed,
	RouteWebMap,
	ScreenOptions,
	ScreenProps,
	createCore,
	currentScope,
} from "./core";
import {
	WebHistoryItem,
	WebNavigationError,
	WebNavigationNode,
	WebNavigationOwner,
} from "./webNavigation";
import { EDGE_WIDTH, screenView, shown } from "./header";
import { createNavigatorMotion } from "./navigatorMotion";
import { readName, readOptions } from "./stack";
import {
	createScreenCollector, collectScreens, groupOf, screenOf, watchScreens,
} from "./screenCollection";
import { BackBehavior } from "./childPages";
import { labelOf, mountedEntries, pagesModel, readBehavior } from "./tabs";

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
			onPanResponderTerminate: (e: NeonEvent, g: PanResponderGestureState): void => {
				this.run(false);
			},
		});
		return pan.panHandlers;
	}
}

function branchAddress(
	item: WebHistoryItem<string>,
	parts: string[],
	parameters: Map<string, string>,
): void {
	if (item.path !== "") { parts.push(item.path); }
	for (const [name, value] of item.parameters) { parameters.set(name, value); }
	const owner = item.child;
	if (owner === null) { return; }
	const items = (owner as WebNavigationOwner).webNavigation.history();
	if (items.length > 0) { branchAddress(items[items.length - 1], parts, parameters); }
}

function drawerModel<P>(
	pages: NavigatorModel<P>,
	open: Accessor<boolean>,
	writeOpen: Setter<boolean>,
): NavigatorModel<P> {
	const back = (): boolean => {
		if (untrack((): boolean => open())) {
			writeOpen(false);
			return true;
		}
		return pages.back();
	};
	return {
		entries: pages.entries,
		index: pages.index,
		arrange: pages.arrange,
		navigate: (name: string, params: P | null, pop: boolean): void => {
			flush((): void => {
				pages.navigate(name, params, pop);
				writeOpen(false);
			});
		},
		push: pages.push,
		replace: pages.replace,
		popTo: pages.popTo,
		popToRoute: pages.popToRoute,
		reset: pages.reset,
		goBackFrom: (key: string): boolean => back(),
		canBack: (): boolean => untrack((): boolean => open()) || pages.canBack(),
		back,
		canPop: pages.canPop,
		drawer: (action: DrawerAction): boolean => {
			writeOpen((current: boolean): boolean => {
				const next = match (action) {
					DrawerAction.Open => true,
					DrawerAction.Close => false,
					DrawerAction.Toggle => !current,
				};
				return next;
			});
			return true;
		},
		webNavigation: (map: RouteWebMap<P>): WebNavigationNode => {
			const web = pages.webNavigation(map);
			return {
				history: accessor((): WebHistoryItem<string>[] => {
					const items = web.history();
					if (!open()) { return items; }
					const parts: string[] = [];
					const parameters = new Map<string, string>();
					branchAddress(items[items.length - 1], parts, parameters);
					const opened = items.slice(0, items.length);
					opened.push({ key: DRAWER_OPEN_KEY, path: parts.join("/"), parameters, child: null });
					return opened;
				}),
				onBeforeNavigate: web.onBeforeNavigate,
				navigate: (keys: string[]): Result<void, WebNavigationError> => {
					const opened = keys.length > 1 && keys[keys.length - 1] === DRAWER_OPEN_KEY;
					const pageKeys = opened ? keys.slice(0, keys.length - 1) : keys;
					if (pageKeys.length === 0 || pageKeys.includes(DRAWER_OPEN_KEY)) {
						return Result.err(WebNavigationError.UndecodableKey);
					}
					const applied = web.navigate(pageKeys);
					if (applied.ok) { writeOpen(opened); }
					return applied;
				},
			};
		},
	};
}

function drawerMotion<P>(
	core: NavigatorCore<P>,
	open: Accessor<boolean>,
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
		core.currentKey();
		const current = core.current();
		if (current === null) { return true; }
		if (!shown((current as Navigation<P>).options().swipeEnabled, true)) { return false; }
		let child = (core.link as NavigatorLink).focusedChild();
		while (child !== null) {
			const here = child as NavigatorLink;
			if (here.canPop()) { return false; }
			child = here.focusedChild();
		}
		return true;
	});
	const setOpen = (next: boolean): void => {
		core.drawerLocal(next ? DrawerAction.Open : DrawerAction.Close);
	};
	const motion = new DrawerMotion(open, setOpen, right, width, swipe);
	createRenderEffect<boolean>(
		(prev: boolean | null): boolean => open(),
		(shown: boolean, prev: boolean | null): Cleanup | null => { motion.run(shown); return null; },
		{ defer: true },
	);
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
		screenOptions?: Accessor<ScreenOptions> | null;
		backBehavior?: Accessor<BackBehavior> | null;
		drawerStyle?: Accessor<Style> | null;
		drawerPosition?: Accessor<DrawerPosition> | null;
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

export function createDrawerNavigator<P>(): DrawerNavigator<P> {
	const collector = createScreenCollector();
	return {
		Navigator: (props: {
			children: NeonNode;
			initialRouteName?: Accessor<string> | null;
			screenOptions?: Accessor<ScreenOptions> | null;
			backBehavior?: Accessor<BackBehavior> | null;
			drawerStyle?: Accessor<Style> | null;
			drawerPosition?: Accessor<DrawerPosition> | null;
		}): NeonNode => {
			const collection = collectScreens<P>(collector, props.children);
			const screens = untrack(() => collection.read());
			const behavior = readBehavior(props.backBehavior, "firstRoute");
			const [open, writeOpen] = createSignal<boolean>(false, { ownedWrite: true });
			const core = createCore<P>({
				kind: NavigatorKind.Drawer,
				screens,
				initialRouteName: readName(props.initialRouteName),
				screenOptions: readOptions(props.screenOptions),
				scope: currentScope("Drawer.Navigator"),
				model: (
					core: NavigatorCore<P>,
					restored: RouteSeed<P>[] | null,
					at: int32,
				): NavigatorModel<P> => {
					const pages = pagesModel<P>(core, behavior, restored, at);
					return drawerModel<P>(pages, open, writeOpen);
				},
			});
			watchScreens<P>(collection, core);
			createEffect<boolean>(
				(prev: boolean | null): boolean => open(),
				(shown: boolean, prev: boolean | null): Cleanup | null => {
					core.container.changed();
					return null;
				},
				{ defer: true },
			);
			const own = props.drawerStyle;
			const side = props.drawerPosition;
			const right = accessor((): boolean => {
				if (side === null) { return false; }
				const value: DrawerPosition = (side as Accessor<DrawerPosition>)();
				return value === "right";
			});
			const motion = drawerMotion<P>(core, open, right, own);
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
			const close = (e: NeonEvent): void => { core.drawerLocal(DrawerAction.Close); };
			const mounted = mountedEntries<P>(core);
			const backdrop = accessor((): Style => ({
				...BACKDROP,
				opacity: 0.4 * motion.progress.get(),
			}));
			const edge = accessor((): Style => ({
				position: "absolute",
				top: 56,
				bottom: 0,
				left: right() ? null : 0,
				right: right() ? 0 : null,
				width: EDGE_WIDTH,
			}));
			const edgeHandlers = motion.edgeHandlers();
			const transitions = createNavigatorMotion<P>(core, false);
			const screen = (entry: Navigation<P>, at: Accessor<number>): NeonNode => {
				return screenView<P>(core, transitions, entry, true);
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
