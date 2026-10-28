import { NeonNode } from "../../src/render/node";
import { HostNode, MockNode, mockNode, mockHost, render } from "../../src/render/host";
import { Text } from "../../src/components/primitives";
import {
	NavigationContainer,
	NavigationContainerRef,
	ScreenProps,
	createBottomTabNavigator,
	createNavigationContainerRef,
	createStackNavigator,
} from "../../src/navigation/index";

interface InnerParams {
	A: null;
	B: null;
}

interface TabParams {
	Home: null;
	Other: null;
}

const Inner = createStackNavigator<InnerParams>();
const Tab = createBottomTabNavigator<TabParams>();

function Plain(props: ScreenProps<InnerParams>): NeonNode {
	return <Text>{props.route.name}</Text>;
}

function Other(props: ScreenProps<TabParams>): NeonNode {
	return <Text>other</Text>;
}

function Home(props: ScreenProps<TabParams>): NeonNode {
	return <Inner.Navigator screenOptions={{ animation: "none" }}>
		<Inner.Screen name="A" component={Plain} />
		<Inner.Screen name="B" component={Plain} />
	</Inner.Navigator>;
}

function mount(ref: NavigationContainerRef, popToTopOnBlur: boolean): void {
	const root: MockNode = mockNode("root");
	render(<NavigationContainer ref={ref}>
		<Tab.Navigator>
			<Tab.Screen name="Home" component={Home} options={{ popToTopOnBlur, headerShown: false }} />
			<Tab.Screen name="Other" component={Other} />
		</Tab.Navigator>
	</NavigationContainer>, mockHost(), root as unknown as HostNode);
}

test "popToTopOnBlur pops the tab's stack to its first screen when another tab takes focus" {
	const ref = createNavigationContainerRef();
	mount(ref, true);
	ref.navigate("B");
	assert ref.currentPath() === "Home>B", ref.currentPath();
	ref.navigate("Other");
	ref.navigate("Home");
	assert ref.currentPath() === "Home>A", ref.currentPath();
}

test "a tab without popToTopOnBlur keeps its stack when it loses focus" {
	const ref = createNavigationContainerRef();
	mount(ref, false);
	ref.navigate("B");
	ref.navigate("Other");
	ref.navigate("Home");
	assert ref.currentPath() === "Home>B", ref.currentPath();
}
