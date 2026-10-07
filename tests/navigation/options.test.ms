import { createSignal } from "../../src/core/signal";
import { Dispose } from "../../src/core/types";
import { NeonNode } from "../../src/render/node";
import { NeonEvent } from "../../src/render/event";
import { Style } from "../../src/render/style";
import { HostNode, MockNode, mockNode, mockHost, render } from "../../src/render/host";
import { View, Text, Pressable } from "../../src/components/primitives";
import {
	NavigationContainer,
	NavigationState,
	ScreenProps,
	createBottomTabNavigator,
	createDrawerNavigator,
	createNavigationContainerRef,
	createStackNavigator,
	useNavigationState,
} from "../../src/navigation/index";
import { findLabel, press, visibleText } from "./navHarness";

const Tab = createBottomTabNavigator<string>();
const Stack = createStackNavigator<string>();
const Drawer = createDrawerNavigator<string>();

function Counted(props: ScreenProps<string>): NeonNode {
	const [count, setCount] = createSignal<int32>(0);
	const name = props.route.name;
	return <View>
		<Text>{name + " " + count().toString()}</Text>
		<Pressable accessibilityLabel={"bump " + name} onPress={(e: NeonEvent): void => { setCount(count() + 1); }}><Text>+</Text></Pressable>
	</View>;
}

test "unmountOnBlur drops a tab's state when it loses focus; other tabs keep theirs" {
	const root: MockNode = mockNode("root");
	const dispose: Dispose = render(<NavigationContainer>
		<Tab.Navigator screenOptions={{ headerShown: false }}>
			<Tab.Screen name="Kept" component={Counted} />
			<Tab.Screen name="Fresh" component={Counted} options={{ unmountOnBlur: true }} />
		</Tab.Navigator>
	</NavigationContainer>, mockHost(), root as unknown as HostNode);
	press(root, "bump Kept");
	press(root, "Fresh");
	press(root, "bump Fresh");
	assert visibleText(root).indexOf("Fresh 1") >= 0, visibleText(root);
	press(root, "Kept");
	assert visibleText(root).indexOf("Kept 1") >= 0, visibleText(root);
	press(root, "Fresh");
	assert visibleText(root).indexOf("Fresh 0") >= 0, "remounted: " + visibleText(root);
	dispose();
}

function Depth(props: ScreenProps<string>): NeonNode {
	const depth = useNavigationState<int32>((state: NavigationState): int32 => state.routes.length as int32);
	const navigation = props.navigation;
	return <View>
		<Text>{"depth " + depth().toString()}</Text>
		<Pressable accessibilityLabel="deeper" onPress={(e: NeonEvent): void => { navigation.push("Depth"); }}><Text>+</Text></Pressable>
	</View>;
}

test "useNavigationState follows the navigator's routes" {
	const root: MockNode = mockNode("root");
	const ref = createNavigationContainerRef();
	const dispose: Dispose = render(<NavigationContainer ref={ref}>
		<Stack.Navigator>
			<Stack.Screen name="Depth" component={Depth} />
		</Stack.Navigator>
	</NavigationContainer>, mockHost(), root as unknown as HostNode);
	assert visibleText(root) === "Depth|depth 1|+", visibleText(root);
	press(root, "deeper");
	assert visibleText(root) === "‹ Depth|Depth|depth 2|+", visibleText(root);
	ref.goBack();
	assert visibleText(root) === "Depth|depth 1|+", visibleText(root);
	dispose();
}

test "a right-hand drawer anchors its panel to the right edge" {
	const root: MockNode = mockNode("root");
	const ref = createNavigationContainerRef();
	const dispose: Dispose = render(<NavigationContainer ref={ref}>
		<Drawer.Navigator drawerPosition="right">
			<Drawer.Screen name="One" component={Counted} />
			<Drawer.Screen name="Two" component={Counted} />
		</Drawer.Navigator>
	</NavigationContainer>, mockHost(), root as unknown as HostNode);
	ref.openDrawer();
	const item = findLabel(root, "Two");
	assert item !== null, visibleText(root);
	const panel = (item as MockNode).parent as MockNode;
	const style = panel.style as Style;
	assert style.right === 0 && style.left === null, "anchored right";
	press(root, "Two");
	assert ref.currentPath() === "Two", ref.currentPath();
	dispose();
}
