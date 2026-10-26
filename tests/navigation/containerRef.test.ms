import { flush } from "../../src/core/runtime";
import { NeonNode } from "../../src/render/node";
import { HostNode, MockNode, mockNode, mockHost, render } from "../../src/render/host";
import { Text } from "../../src/components/primitives";
import {
	NavigationContainer,
	NavigationContainerRef,
	NavigationEventArg,
	NavigationState,
	ScreenProps,
	createNavigationContainerRef,
	createStackNavigator,
} from "../../src/navigation/index";

interface NavParams {
	First: null;
	Second: null;
}

const Stack = createStackNavigator<NavParams>();

function Plain(props: ScreenProps<NavParams>): NeonNode {
	return <Text>{props.route.name}</Text>;
}

function mount(ref: NavigationContainerRef): MockNode {
	const root: MockNode = mockNode("root");
	render(<NavigationContainer ref={ref}>
		<Stack.Navigator screenOptions={{ animation: "none" }}>
			<Stack.Screen name="First" component={Plain} options={{ title: "First title" }} />
			<Stack.Screen name="Second" component={Plain} options={{ title: "Second title" }} />
		</Stack.Navigator>
	</NavigationContainer>, mockHost(), root as unknown as HostNode);
	return root;
}

test "the container ref reports the focused screen's options" {
	const ref = createNavigationContainerRef();
	mount(ref);
	assert ref.getCurrentOptions().title === "First title";
	ref.navigate("Second");
	assert ref.getCurrentOptions().title === "Second title";
}

test "resetRoot replaces the whole navigation state" {
	const ref = createNavigationContainerRef();
	mount(ref);
	const initial = ref.getRootState();
	ref.navigate("Second");
	assert ref.currentPath() === "Second", ref.currentPath();
	ref.resetRoot(initial);
	flush();
	assert ref.currentPath() === "First", ref.currentPath();
}

test "resetRoot without a state returns to the initial state" {
	const ref = createNavigationContainerRef();
	mount(ref);
	ref.navigate("Second");
	ref.resetRoot();
	flush();
	assert ref.currentPath() === "First", ref.currentPath();
}

test "a state listener hears each state change until it unsubscribes" {
	const ref = createNavigationContainerRef();
	mount(ref);
	const seen: string[] = [];
	const stop = ref.addListener("state", (e: NavigationEventArg): void => {
		const state = e.data.state as NavigationState;
		seen.push(state.routes[state.index].name);
	});
	ref.navigate("Second");
	flush();
	assert seen.length > 0 && seen[seen.length - 1] === "Second", seen.join(",");
	const heard = seen.length;
	stop();
	ref.resetRoot();
	flush();
	assert seen.length === heard, seen.join(",");
}
