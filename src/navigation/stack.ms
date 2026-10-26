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
	ScreenParams,
	ScreenParamsBuilder,
	ParamSlot,
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

function reuseWith<PL>(entry: Navigation<PL>, params: ParamSlot | null): void {
	if (untrack((): ParamSlot | null => entry.route.slot()) !== params) { entry.writeParams(params); }
}

function stackModel<PL>(core: NavigatorCore<PL>, restored: RouteSeed<PL>[] | null): NavigatorModel<PL> {
	const initial = restored === null ? [core.seed(core.initialName, null)] : restored as RouteSeed<PL>[];
	const stack = createChildStack<RouteSeed<PL>, Navigation<PL>>(
		initial,
		seedKey,
		(seed: Accessor<RouteSeed<PL>>, active: Accessor<boolean>): Navigation<PL> => {
			return core.child(seed, active);
		},
	);
	const entries = stack.instances;
	const without = (key: string): void => {
		stack.navigate((current: RouteSeed<PL>[]): RouteSeed<PL>[] => {
			const kept: RouteSeed<PL>[] = [];
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
		arrange: (kept: Navigation<PL>[], focused: Navigation<PL> | null): void => {
			const list: RouteSeed<PL>[] = [];
			for (const entry of kept) { list.push(core.seedOf(entry)); }
			if (list.length === 0) {
				const name = core.hasRoute(core.initialName)
					? core.initialName
					: core.screens[0].name;
				list.push(core.seed(name, null));
			}
			core.apply((): void => {
				stack.navigate((current: RouteSeed<PL>[]): RouteSeed<PL>[] => list);
			});
		},
		navigate: (name: string, params: ParamSlot | null, pop: boolean): void => {
			const list = core.snapshot();
			const top = list.length - 1;
			const at = list[top].route.name === name ? top : pop ? core.indexOfName(list, name) : -1;
			if (at < 0) {
				const seed = core.seed(name, params);
				core.apply((): void => { stack.push(seed); });
				return;
			}
			core.guarded("NAVIGATE", list.slice(at + 1, list.length), (): void => {
				reuseWith<PL>(list[at], params);
				core.apply((): void => { stack.popTo(at); });
			});
		},
		push: (name: string, params: ParamSlot | null): boolean => {
			const seed = core.seed(name, params);
			core.apply((): void => { stack.push(seed); });
			return true;
		},
		replace: (key: string, name: string, params: ParamSlot | null): void => {
			for (const entry of core.snapshot()) {
				if (entry.route.key === key) {
					core.guarded("REPLACE", [entry], (): void => {
						const seed = core.seed(name, params);
						core.apply((): void => {
							stack.navigate((current: RouteSeed<PL>[]): RouteSeed<PL>[] => {
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
		popToRoute: (name: string, params: ParamSlot | null, source: string | null): boolean => {
			const list = core.snapshot();
			let from = list.length - 1;
			if (source !== null) {
				while (from >= 0 && list[from].route.key !== source) { from -= 1; }
				if (from < 0) { return false; }
			}
			let at = from;
			while (at >= 0 && list[at].route.name !== name) { at -= 1; }
			if (at < 0) {
				const seed = core.seed(name, params);
				const keep = from;
				core.guarded("POP_TO", list.slice(keep, list.length), (): void => {
					core.apply((): void => {
						stack.navigate((current: RouteSeed<PL>[]): RouteSeed<PL>[] => {
							const kept = current.slice(0, keep);
							kept.push(seed);
							return kept;
						});
					});
				});
				return true;
			}
			core.guarded("POP_TO", list.slice(at + 1, list.length), (): void => {
				reuseWith<PL>(list[at], params);
				core.apply((): void => { stack.popTo(at); });
			});
			return true;
		},
		popTo: (at: int32, type: string): void => {
			const list = core.snapshot();
			if (at >= list.length - 1) { return; }
			core.guarded(type, list.slice(at + 1, list.length), (): void => {
				core.apply((): void => { stack.popTo(at); });
			});
		},
		reset: (list: RouteSeed<PL>[], at: int32): void => {
			core.guarded("RESET", core.snapshot(), (): void => {
				core.apply((): void => {
					stack.navigate((current: RouteSeed<PL>[]): RouteSeed<PL>[] => list);
				});
			});
		},
		goBackFrom: (key: string): boolean => {
			const list = core.snapshot();
			if (list.length <= 1) { return false; }
			const removed: Navigation<PL>[] = [];
			for (const entry of list) {
				if (entry.route.key === key) { removed.push(entry); }
			}
			if (removed.length === 0) { return false; }
			core.guarded("GO_BACK", removed, (): void => {
				core.apply((): void => { without(key); });
			});
			return true;
		},
		canBack: (): boolean => untrack((): Navigation<PL>[] => entries()).length > 1,
		back,
		canPop: (): boolean => entries().length > 1,
		drawer: (action: DrawerAction): boolean => false,
		webNavigation: (map: RouteWebMap<PL>): WebNavigationNode => {
			const web = childStackWebNavigation<RouteSeed<PL>, Navigation<PL>>(stack, map.serializer, {
				pathMapper: (child: NavigationChild<RouteSeed<PL>, Navigation<PL>>): string | null => {
					return map.path(child.instance);
				},
				parametersMapper: (
					child: NavigationChild<RouteSeed<PL>, Navigation<PL>>,
				): Map<string, string> | null => map.parameters(child.instance),
				onBeforeNavigate: (): boolean => {
					const list = core.snapshot();
					const top = list[list.length - 1];
					return core.allows("GO_BACK", [top], (): void => {
						core.apply((): void => { without(top.route.key); });
					});
				},
				childSelector: (
					child: NavigationChild<RouteSeed<PL>, Navigation<PL>>,
				): WebNavigationOwner | null => map.child(child.instance),
			});
			return webNavigationNode<RouteSeed<PL>>({
				serializer: web.serializer,
				history: web.history,
				onBeforeNavigate: web.onBeforeNavigate,
				navigate: (history: RouteSeed<PL>[]): void => {
					core.apply((): void => {
						web.navigate(history);
						core.restoreParams(history);
					});
				},
			});
		},
	};
}

export interface StackNavigator<PL> {
	params: ScreenParamsBuilder<PL>;
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
		name: keyof PL;
		component: (props: ScreenProps<PL>) => NeonNode;
		options?: Accessor<ScreenOptions> | null;
		params?: ScreenParams<PL> | null;
		navigationKey?: Accessor<string> | null;
	}) => NeonNode;
}

export function createStackNavigator<PL>(): StackNavigator<PL> {
	const collector = createScreenCollector();
	return {
		params: new ScreenParamsBuilder<PL>(),
		Navigator: (props: {
			children: NeonNode;
			initialRouteName?: Accessor<string> | null;
			screenOptions?: Accessor<ScreenOptions> | null;
		}): NeonNode => {
			const collection = collectScreens<PL>(collector, props.children);
			const screens = untrack(() => collection.read());
			const core = createCore<PL>({
				kind: NavigatorKind.Stack,
				screens,
				initialRouteName: readName(props.initialRouteName),
				screenOptions: readOptions(props.screenOptions),
				scope: currentScope("Stack.Navigator"),
				model: (
					core: NavigatorCore<PL>,
					restored: RouteSeed<PL>[] | null,
					at: int32,
				): NavigatorModel<PL> => stackModel<PL>(core, restored),
			});
			watchScreens<PL>(collection, core);
			const transitions = createNavigatorMotion<PL>(core, true);
			const screen = (entry: Navigation<PL>, at: Accessor<number>): NeonNode => {
				return screenView<PL>(core, transitions, entry, false, at);
			};
			const rendered = accessor((): Navigation<PL>[] => transitions.rendered());
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

export function createNativeStackNavigator<PL>(): StackNavigator<PL> {
	return createStackNavigator<PL>();
}
