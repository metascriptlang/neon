import { flush } from "../../src/core/runtime";
import { onCleanup } from "../../src/core/cleanup";
import { Dispose } from "../../src/core/types";
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
import { settle } from "./navHarness";

interface StackParams {
	Home: null;
	Detail: null;
}

interface TabParams {
	First: null;
	Second: null;
}

const Stack = createStackNavigator<StackParams>();
const Tab = createBottomTabNavigator<TabParams>();

let log = "";

function listening(name: string, props: ScreenProps<StackParams>): NeonNode {
	const stopFocus = props.navigation.addListener("focus", (): void => { log += name + "+;"; });
	const stopBlur = props.navigation.addListener("blur", (): void => { log += name + "-;"; });
	onCleanup((): void => {
		stopFocus();
		stopBlur();
	});
	return <Text>{name}</Text>;
}

function Home(props: ScreenProps<StackParams>): NeonNode {
	return listening("home", props);
}

function Detail(props: ScreenProps<StackParams>): NeonNode {
	return listening("detail", props);
}

function Inner(props: ScreenProps<TabParams>): NeonNode {
	const stopFocus = props.navigation.addListener("focus", (): void => { log += "inner+;"; });
	onCleanup(stopFocus);
	return <Text>inner</Text>;
}

function First(props: ScreenProps<TabParams>): NeonNode {
	return <Stack.Navigator>
		<Stack.Screen name="Home" component={Home} />
		<Stack.Screen name="Detail" component={Detail} />
	</Stack.Navigator>;
}

function Second(props: ScreenProps<TabParams>): NeonNode {
	return <Inner navigation={props.navigation} route={props.route} />;
}

let unmount: Dispose | null = null;

function mountStack(ref: NavigationContainerRef): void {
	if (unmount !== null) { (unmount as Dispose)(); }
	const root: MockNode = mockNode("root");
	unmount = render(<NavigationContainer ref={ref}>
		<Stack.Navigator>
			<Stack.Screen name="Home" component={Home} />
			<Stack.Screen name="Detail" component={Detail} />
		</Stack.Navigator>
	</NavigationContainer>, mockHost(), root as unknown as HostNode);
	flush();
}

function mountTabs(ref: NavigationContainerRef): void {
	if (unmount !== null) { (unmount as Dispose)(); }
	const root: MockNode = mockNode("root");
	unmount = render(<NavigationContainer ref={ref}>
		<Tab.Navigator>
			<Tab.Screen name="First" component={First} />
			<Tab.Screen name="Second" component={Second} />
		</Tab.Navigator>
	</NavigationContainer>, mockHost(), root as unknown as HostNode);
	flush();
}

test "a screen mounted focused receives focus once, and a pushed screen receives it on mount" {
	log = "";
	const ref = createNavigationContainerRef();
	mountStack(ref);
	assert log === "home+;", log;
	ref.navigate("Detail");
	flush();
	assert log === "home+;home-;detail+;", log;
}

test "a screen in a nested navigator receives its initial focus, and a lazy tab only when it is first shown" {
	log = "";
	const ref = createNavigationContainerRef();
	mountTabs(ref);
	assert log === "home+;", log;
	ref.navigate("Second");
	flush();
	assert log === "home+;home-;inner+;", log;
}
