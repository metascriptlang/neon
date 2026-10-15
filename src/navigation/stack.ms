import { Accessor, accessor, untrack } from "../core/signal";
import { NeonNode } from "../render/hostTypes";
import { NeonEvent } from "../render/event";
import { Style } from "../render/style";
import { StackLayout } from "./layout";
import { View } from "../components/primitives";
import { For } from "../macros/ui/flow";
import {
	Navigation,
	NavigatorKind,
	ScreenOptions,
	ScreenOptionsOf,
	ScreenProps,
	createCore,
	optionsAccessor,
	currentScope,
} from "./core";
import { screenView } from "./header";
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

export function readOptions<P>(
	options: Accessor<ScreenOptionsOf<P>> | null,
): Accessor<ScreenOptions> {
	const plain = optionsAccessor<P>(options);
	if (plain === null) { return accessor((): ScreenOptions => ({})); }
	return plain as Accessor<ScreenOptions>;
}

export interface StackNavigator<P> {
	Navigator: (props: {
		children: NeonNode;
		initialRouteName?: Accessor<string> | null;
		screenOptions?: Accessor<ScreenOptionsOf<P>> | null;
	}) => NeonNode;
	Group: (props: {
		children: NeonNode;
		screenOptions?: Accessor<ScreenOptionsOf<P>> | null;
		navigationKey?: Accessor<string> | null;
	}) => NeonNode;
	Screen: (props: {
		name: string;
		component: (props: ScreenProps<P>) => NeonNode;
		options?: Accessor<ScreenOptionsOf<P>> | null;
		initialParams?: P | null;
		parseParams?: ((values: Map<string, string>) => P) | null;
		navigationKey?: Accessor<string> | null;
	}) => NeonNode;
}

export function createStackNavigator<P>(): StackNavigator<P> {
	const collector = createScreenCollector();
	return {
		Navigator: (props: {
			children: NeonNode;
			initialRouteName?: Accessor<string> | null;
			screenOptions?: Accessor<ScreenOptionsOf<P>> | null;
		}): NeonNode => {
			const collection = collectScreens<P>(collector, props.children);
			const screens = untrack(() => collection.read());
			const core = createCore<P>({
				kind: NavigatorKind.Stack,
				screens,
				initialRouteName: readName(props.initialRouteName),
				initialParams: null,
				screenOptions: readOptions<P>(props.screenOptions),
				backBehavior: "history",
				scope: currentScope("Stack.Navigator"),
			});
			watchScreens<P>(collection, core);
			const screen = (entry: Navigation<P>, at: Accessor<number>): NeonNode => {
				return screenView<P>(core, entry);
			};
			const rendered = accessor((): Navigation<P>[] => core.rendered());
			const measure = (e: NeonEvent): void => { core.layout.measure(e); };
			return <View style={STACK_FRAME} onLayout={measure}>
				<For each={rendered}>{screen}</For>
			</View>;
		},
		Group: (props: {
			children: NeonNode;
			screenOptions?: Accessor<ScreenOptionsOf<P>> | null;
			navigationKey?: Accessor<string> | null;
		}): NeonNode => {
			return groupOf(
				collector, props.children, optionsAccessor<P>(props.screenOptions), props.navigationKey,
			);
		},
		Screen: (props: {
			name: string;
			component: (props: ScreenProps<P>) => NeonNode;
			options?: Accessor<ScreenOptionsOf<P>> | null;
			initialParams?: P | null;
			parseParams?: ((values: Map<string, string>) => P) | null;
			navigationKey?: Accessor<string> | null;
		}): NeonNode => screenOf<P>(
			collector,
			props.name,
			props.component,
			optionsAccessor<P>(props.options),
			props.initialParams,
			props.parseParams,
			props.navigationKey,
		),
	};
}

export function createNativeStackNavigator<P>(): StackNavigator<P> {
	return createStackNavigator<P>();
}
