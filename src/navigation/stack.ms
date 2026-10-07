import { Accessor, accessor, untrack } from "../core/signal";
import { Host, HostNode, NeonNode } from "../render/hostTypes";
import { mockHost, mockNode } from "../render/host";
import { View } from "../components/primitives";
import { For } from "../macros/ui/flow";
import {
	Navigation,
	NavigatorKind,
	ScreenConfig,
	ScreenOptions,
	ScreenOptionsOf,
	ScreenProps,
	createCore,
	optionsAccessor,
	currentScope,
} from "./core";
import { screenView } from "./header";

export interface ScreenCollector<P> {
	screens: ScreenConfig<P>[] | null;
}

export function collectScreens<P>(collector: ScreenCollector<P>, children: NeonNode): ScreenConfig<P>[] {
	const found: ScreenConfig<P>[] = [];
	collector.screens = found;
	const parent = mockNode("screens");
	children(mockHost(), parent, null);
	collector.screens = null;
	if (parent.children.length > 0) {
		throw new Error("a navigator's children must be Screen elements");
	}
	return found;
}

export function screenOf<P>(
	collector: ScreenCollector<P>,
	name: string,
	component: (props: ScreenProps<P>) => NeonNode,
	options: Accessor<ScreenOptions> | null,
	initialParams: P | null,
	parseParams: ((values: Map<string, string>) => P) | null,
): NeonNode {
	const config = new ScreenConfig<P>(name, component, options, initialParams, parseParams);
	return (host: Host, parent: HostNode, before: HostNode | null): void => {
		const list = collector.screens;
		if (list === null) { throw new Error("Screen '" + name + "' must be a child of its Navigator"); }
		for (const screen of list as ScreenConfig<P>[]) {
			if (screen.name === name) { throw new Error("two screens are named '" + name + "'"); }
		}
		(list as ScreenConfig<P>[]).push(config);
	};
}

export function readName(name: Accessor<string> | null): string | null {
	if (name === null) { return null; }
	const read = name as Accessor<string>;
	return untrack((): string => read());
}

export function readOptions<P>(options: Accessor<ScreenOptionsOf<P>> | null): Accessor<ScreenOptions> {
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
	Screen: (props: {
		name: string;
		component: (props: ScreenProps<P>) => NeonNode;
		options?: Accessor<ScreenOptionsOf<P>> | null;
		initialParams?: P | null;
		parseParams?: ((values: Map<string, string>) => P) | null;
	}) => NeonNode;
}

export function createStackNavigator<P>(): StackNavigator<P> {
	const collector: ScreenCollector<P> = { screens: null };
	return {
		Navigator: (props: {
			children: NeonNode;
			initialRouteName?: Accessor<string> | null;
			screenOptions?: Accessor<ScreenOptionsOf<P>> | null;
		}): NeonNode => {
			const screens = collectScreens<P>(collector, props.children);
			const core = createCore<P>({
				kind: NavigatorKind.Stack,
				screens,
				initialRouteName: readName(props.initialRouteName),
				initialParams: null,
				screenOptions: readOptions<P>(props.screenOptions),
				backBehavior: "history",
				scope: currentScope("Stack.Navigator"),
			});
			return <View style={{ flex: 1, flexDirection: "column" }}>
				<For each={core.entries}>{(entry: Navigation<P>, at: Accessor<number>): NeonNode => screenView<P>(core, entry)}</For>
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

export function createNativeStackNavigator<P>(): StackNavigator<P> {
	return createStackNavigator<P>();
}
