import { Accessor, accessor, untrack } from "../core/signal";
import { NeonNode } from "../render/hostTypes";
import { NeonEvent } from "../render/event";
import { Style } from "../render/style";
import { StackLayout } from "./layout";
import { View } from "../components/primitives";
import { For } from "../macros/ui/flow";
import { NavigationChild } from "./children";
import { createChildStack } from "./childStack";
import {
	WebNavigationNode,
	WebNavigationOwner,
	childStackWebNavigation,
	webNavigationNode,
} from "./webNavigation";
import {
	Navigation,
	NavigatorCore,
	NavigatorKind,
	NavigatorModel,
	RouteSeed,
	RouteWebMap,
	ScreenOptions,
	ScreenProps,
	createCore,
	currentScope,
	DrawerAction,
	seedKey,
} from "./core";
import { screenView } from "./header";
import { createNavigatorMotion } from "./navigatorMotion";
import {
	createScreenCollector, collectScreens, groupOf, screenOf, watchScreens,
} from "./screenCollection";

const STACK_FRAME: Style = {
	flex: 1,
	flexDirection: "column",
	position: "relative",
	overflow: "hidden",
};

export function readName(name: Accessor<string> | null): string | null {
	if (name === null) { return null; }
	const read = name as Accessor<string>;
	return untrack((): string => read());
}

export function readOptions(
	options: Accessor<ScreenOptions> | null,
): Accessor<ScreenOptions> {
	if (options === null) { return accessor((): ScreenOptions => ({})); }
	return options as Accessor<ScreenOptions>;
}

function stackModel<P>(core: NavigatorCore<P>, restored: RouteSeed<P>[] | null): NavigatorModel<P> {
	const initial = restored === null ? [core.seed(core.initialName, null)] : restored as RouteSeed<P>[];
	const stack = createChildStack<RouteSeed<P>, Navigation<P>>(
		initial,
		seedKey,
		(seed: Accessor<RouteSeed<P>>, active: Accessor<boolean>): Navigation<P> => {
			return core.child(seed, active);
		},
	);
	const entries = stack.instances;
	const without = (key: string): void => {
		stack.navigate((current: RouteSeed<P>[]): RouteSeed<P>[] => {
			const kept: RouteSeed<P>[] = [];
			for (const seed of current) {
				if (seed.key !== key) { kept.push(seed); }
			}
			return kept;
		});
	};
	const back = (): boolean => {
		const list = core.snapshot();
		if (list.length <= 1) { return false; }
		core.guarded("GO_BACK", [list[list.length - 1]], (): void => {
			core.apply((): void => { stack.pop(); });
		});
		return true;
	};
	return {
		entries,
		index: accessor((): int32 => (entries().length - 1) as int32),
		arrange: (kept: Navigation<P>[], focused: Navigation<P> | null): void => {
			const list: RouteSeed<P>[] = [];
			for (const entry of kept) { list.push(core.seedOf(entry)); }
			if (list.length === 0) {
				const name = core.hasRoute(core.initialName)
					? core.initialName
					: core.screens[0].name;
				list.push(core.seed(name, null));
			}
			core.apply((): void => {
				stack.navigate((current: RouteSeed<P>[]): RouteSeed<P>[] => list);
			});
		},
		navigate: (name: string, params: P | null): void => {
			const list = core.snapshot();
			const at = core.indexOfName(list, name);
			if (at < 0) {
				const seed = core.seed(name, params);
				core.apply((): void => { stack.push(seed); });
				return;
			}
			core.guarded("NAVIGATE", list.slice(at + 1, list.length), (): void => {
				if (params !== null) { list[at].writeParams(params); }
				core.apply((): void => { stack.popTo(at); });
			});
		},
		push: (name: string, params: P | null): boolean => {
			const seed = core.seed(name, params);
			core.apply((): void => { stack.push(seed); });
			return true;
		},
		replace: (key: string, name: string, params: P | null): void => {
			for (const entry of core.snapshot()) {
				if (entry.route.key === key) {
					core.guarded("REPLACE", [entry], (): void => {
						const seed = core.seed(name, params);
						core.apply((): void => {
							stack.navigate((current: RouteSeed<P>[]): RouteSeed<P>[] => {
								for (let i = 0; i < current.length; i += 1) {
									if (current[i].key === key) { current[i] = seed; }
								}
								return current;
							});
						});
					});
					return;
				}
			}
		},
		popTo: (at: int32): void => {
			const list = core.snapshot();
			if (at >= list.length - 1) { return; }
			core.guarded("POP", list.slice(at + 1, list.length), (): void => {
				core.apply((): void => { stack.popTo(at); });
			});
		},
		reset: (list: RouteSeed<P>[], at: int32): void => {
			core.guarded("RESET", core.snapshot(), (): void => {
				core.apply((): void => {
					stack.navigate((current: RouteSeed<P>[]): RouteSeed<P>[] => list);
				});
			});
		},
		goBackFrom: (key: string): boolean => {
			const list = core.snapshot();
			if (list.length <= 1) { return false; }
			const removed: Navigation<P>[] = [];
			for (const entry of list) {
				if (entry.route.key === key) { removed.push(entry); }
			}
			if (removed.length === 0) { return false; }
			core.guarded("GO_BACK", removed, (): void => {
				core.apply((): void => { without(key); });
			});
			return true;
		},
		canBack: (): boolean => untrack((): Navigation<P>[] => entries()).length > 1,
		back,
		canPop: (): boolean => entries().length > 1,
		drawer: (action: DrawerAction): boolean => false,
		webNavigation: (map: RouteWebMap<P>): WebNavigationNode => {
			const web = childStackWebNavigation<RouteSeed<P>, Navigation<P>>(stack, map.serializer, {
				pathMapper: (child: NavigationChild<RouteSeed<P>, Navigation<P>>): string | null => {
					return map.path(child.instance);
				},
				parametersMapper: (
					child: NavigationChild<RouteSeed<P>, Navigation<P>>,
				): Map<string, string> | null => map.parameters(child.instance),
				onBeforeNavigate: (): boolean => {
					const list = core.snapshot();
					const top = list[list.length - 1];
					return core.allows("GO_BACK", [top], (): void => {
						core.apply((): void => { without(top.route.key); });
					});
				},
				childSelector: (
					child: NavigationChild<RouteSeed<P>, Navigation<P>>,
				): WebNavigationOwner | null => map.child(child.instance),
			});
			return webNavigationNode<RouteSeed<P>>({
				serializer: web.serializer,
				history: web.history,
				onBeforeNavigate: web.onBeforeNavigate,
				navigate: (history: RouteSeed<P>[]): void => {
					core.apply((): void => {
						web.navigate(history);
						core.restoreParams(history);
					});
				},
			});
		},
	};
}

export interface StackNavigator<P> {
	Navigator: (props: {
		children: NeonNode;
		initialRouteName?: Accessor<string> | null;
		screenOptions?: Accessor<ScreenOptions> | null;
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

export function createStackNavigator<P>(): StackNavigator<P> {
	const collector = createScreenCollector();
	return {
		Navigator: (props: {
			children: NeonNode;
			initialRouteName?: Accessor<string> | null;
			screenOptions?: Accessor<ScreenOptions> | null;
		}): NeonNode => {
			const collection = collectScreens<P>(collector, props.children);
			const screens = untrack(() => collection.read());
			const core = createCore<P>({
				kind: NavigatorKind.Stack,
				screens,
				initialRouteName: readName(props.initialRouteName),
				screenOptions: readOptions(props.screenOptions),
				scope: currentScope("Stack.Navigator"),
				model: (
					core: NavigatorCore<P>,
					restored: RouteSeed<P>[] | null,
					at: int32,
				): NavigatorModel<P> => stackModel<P>(core, restored),
			});
			watchScreens<P>(collection, core);
			const transitions = createNavigatorMotion<P>(core, true);
			const screen = (entry: Navigation<P>, at: Accessor<number>): NeonNode => {
				return screenView<P>(core, transitions, entry, false);
			};
			const rendered = accessor((): Navigation<P>[] => transitions.rendered());
			const measure = (e: NeonEvent): void => { core.layout.measure(e); };
			return <View style={STACK_FRAME} onLayout={measure}>
				<For each={rendered}>{screen}</For>
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

export function createNativeStackNavigator<P>(): StackNavigator<P> {
	return createStackNavigator<P>();
}
