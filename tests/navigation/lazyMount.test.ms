import { flush } from "../../src/core/runtime";
import { onCleanup } from "../../src/core/cleanup";
import { NeonNode } from "../../src/render/hostTypes";
import { HostNode, mockHost, mockNode, render } from "../../src/render/host";
import { Text } from "../../src/components/primitives";
import {
	NavigationContainer,
	ScreenProps,
	createBottomTabNavigator,
	createDrawerNavigator,
	createNavigationContainerRef,
} from "../../src/navigation/index";

const Tab = createBottomTabNavigator<string>();
const Drawer = createDrawerNavigator<string>();

let bodies: int32 = 0;

let cleanups: int32 = 0;

function Plain(props: ScreenProps<string>): NeonNode {
	return <Text>plain</Text>;
}

function Counted(props: ScreenProps<string>): NeonNode {
	bodies += 1;
	onCleanup((): void => { cleanups += 1; });
	return <Text>counted</Text>;
}

test "a lazy tab is built the first time it is focused, once, and stays mounted" {
	bodies = 0;
	const ref = createNavigationContainerRef();
	const root = mockNode("root");
	const dispose = render(<NavigationContainer ref={ref}>
		<Tab.Navigator>
			<Tab.Screen name="First" component={Plain} />
			<Tab.Screen name="Second" component={Counted} />
			<Tab.Screen name="Third" component={Plain} />
		</Tab.Navigator>
	</NavigationContainer>, mockHost(), root as unknown as HostNode);
	assert bodies === 0, "an unvisited tab is not built";
	ref.navigate("Second");
	flush();
	assert ref.currentPath() === "Second", ref.currentPath();
	assert bodies === 1, "the focused tab is built: " + bodies.toString();
	ref.navigate("Third");
	flush();
	ref.navigate("Second");
	flush();
	assert bodies === 1, "a tab is built once: " + bodies.toString();
	dispose();
}

test "a lazy drawer screen is built the first time it is focused, once, and stays mounted" {
	bodies = 0;
	const ref = createNavigationContainerRef();
	const root = mockNode("root");
	const dispose = render(<NavigationContainer ref={ref}>
		<Drawer.Navigator>
			<Drawer.Screen name="First" component={Plain} />
			<Drawer.Screen name="Second" component={Counted} />
		</Drawer.Navigator>
	</NavigationContainer>, mockHost(), root as unknown as HostNode);
	assert bodies === 0, "an unvisited screen is not built";
	ref.navigate("Second");
	flush();
	assert bodies === 1, "the focused screen is built: " + bodies.toString();
	ref.navigate("First");
	flush();
	ref.navigate("Second");
	flush();
	assert bodies === 1, "a screen is built once: " + bodies.toString();
	dispose();
}
