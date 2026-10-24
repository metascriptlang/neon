import { flush } from "../../src/core/runtime";
import { createSignal } from "../../src/core/signal";
import { createEffect } from "../../src/core/effect";
import { Cleanup } from "../../src/core/types";
import { NeonNode } from "../../src/render/hostTypes";
import { HostNode, mockHost, mockNode, render } from "../../src/render/host";
import { Text } from "../../src/components/primitives";
import { Show } from "../../src/macros/ui/flow";
import {
	NavigationContainer,
	NavigationState,
	ScreenProps,
	createBottomTabNavigator,
	createNavigationContainerRef,
	createStackNavigator,
} from "../../src/navigation/index";

interface NavParams {
	First: null;
	Second: null;
	Help: null;
	Start: null;
	Target: null;
}

const Tab = createBottomTabNavigator<NavParams>();
const Stack = createStackNavigator<NavParams>();

function Plain(props: ScreenProps<NavParams>): NeonNode {
	return <Text>plain</Text>;
}

const [redirect, setRedirect] = createSignal<boolean>(false);

function Redirecting(props: ScreenProps<NavParams>): NeonNode {
	const navigation = props.navigation;
	createEffect<boolean>(
		(prev: boolean | null): boolean => redirect(),
		(now: boolean, prev: boolean | null): Cleanup | null => {
			if (now) { navigation.navigate("Target"); }
			return null;
		},
	);
	return <Text>redirecting</Text>;
}

test "onStateChange after a screen swap reports the new focus on a stack" {
	const [first, setFirst] = createSignal(true);
	const ref = createNavigationContainerRef();
	const seen: string[] = [];
	const root = mockNode("root");
	const dispose = render(<NavigationContainer ref={ref}
		onStateChange={(state: NavigationState): void => { seen.push(state.routes[state.index].name); }}>
		<Stack.Navigator screenOptions={{ animation: "none" }}>
			<Show when={first}>
				<Stack.Screen name="First" component={Plain} />
			</Show>
			<Show when={!first()}>
				<Stack.Screen name="Second" component={Plain} />
			</Show>
			<Stack.Screen name="Help" component={Plain} />
		</Stack.Navigator>
	</NavigationContainer>, mockHost(), root as unknown as HostNode);
	setFirst(false);
	flush();
	assert ref.currentPath() === "Second", ref.currentPath();
	assert seen.length > 0 && seen[seen.length - 1] === "Second", seen.join(",");
	dispose();
}

test "onStateChange after a screen swap reports the new focus on tabs" {
	const [first, setFirst] = createSignal(true);
	const ref = createNavigationContainerRef();
	const seen: string[] = [];
	const root = mockNode("root");
	const dispose = render(<NavigationContainer ref={ref}
		onStateChange={(state: NavigationState): void => { seen.push(state.routes[state.index].name); }}>
		<Tab.Navigator>
			<Show when={first}>
				<Tab.Screen name="First" component={Plain} />
			</Show>
			<Show when={!first()}>
				<Tab.Screen name="Second" component={Plain} />
			</Show>
			<Tab.Screen name="Help" component={Plain} />
		</Tab.Navigator>
	</NavigationContainer>, mockHost(), root as unknown as HostNode);
	setFirst(false);
	flush();
	assert ref.currentPath() === "Second", ref.currentPath();
	assert seen.length > 0 && seen[seen.length - 1] === "Second", seen.join(",");
	dispose();
}

test "a navigation made in an effect is reported with its final route" {
	setRedirect(false);
	const ref = createNavigationContainerRef();
	const seen: string[] = [];
	const root = mockNode("root");
	const dispose = render(<NavigationContainer ref={ref}
		onStateChange={(state: NavigationState): void => { seen.push(state.routes[state.index].name); }}>
		<Stack.Navigator screenOptions={{ animation: "none" }}>
			<Stack.Screen name="Start" component={Redirecting} />
			<Stack.Screen name="Target" component={Plain} />
		</Stack.Navigator>
	</NavigationContainer>, mockHost(), root as unknown as HostNode);
	assert ref.currentPath() === "Start", ref.currentPath();
	setRedirect(true);
	flush();
	assert ref.currentPath() === "Target", ref.currentPath();
	assert seen.length > 0 && seen[seen.length - 1] === "Target", seen.join(",");
	dispose();
}
