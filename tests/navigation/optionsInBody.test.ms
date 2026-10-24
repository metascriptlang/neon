import { NeonNode } from "../../src/render/hostTypes";
import { HostNode, mockHost, mockNode, render } from "../../src/render/host";
import { Text } from "../../src/components/primitives";
import {
	NavigationContainer,
	ScreenProps,
	createBottomTabNavigator,
	createNavigationContainerRef,
	createStackNavigator,
} from "../../src/navigation/index";
import { visibleText } from "./navHarness";

interface NavParams {
	Only: null;
}

const Tab = createBottomTabNavigator<NavParams>();
const Stack = createStackNavigator<NavParams>();

function Titled(props: ScreenProps<NavParams>): NeonNode {
	props.navigation.setOptions({ title: "From the body" });
	return <Text>titled</Text>;
}

test "setOptions called in a screen body sets the header title of a stack screen" {
	const ref = createNavigationContainerRef();
	const root = mockNode("root");
	const dispose = render(<NavigationContainer ref={ref}>
		<Stack.Navigator>
			<Stack.Screen name="Only" component={Titled} />
		</Stack.Navigator>
	</NavigationContainer>, mockHost(), root as unknown as HostNode);
	assert visibleText(root).indexOf("From the body") >= 0, visibleText(root);
	dispose();
}

test "setOptions called in a screen body sets the header title of a tab screen" {
	const ref = createNavigationContainerRef();
	const root = mockNode("root");
	const dispose = render(<NavigationContainer ref={ref}>
		<Tab.Navigator>
			<Tab.Screen name="Only" component={Titled} />
		</Tab.Navigator>
	</NavigationContainer>, mockHost(), root as unknown as HostNode);
	assert visibleText(root).indexOf("From the body") >= 0, visibleText(root);
	dispose();
}
