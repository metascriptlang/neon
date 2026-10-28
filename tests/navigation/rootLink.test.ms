import { createRoot } from "../../src/core/owner";
import { Dispose } from "../../src/core/types";
import { NeonNode } from "../../src/render/hostTypes";
import { HostNode, mockHost, mockNode } from "../../src/render/host";
import { Text } from "../../src/components/primitives";
import {
	LinkingOptions,
	NavigationContainer,
	NavigationContainerRef,
	NavigationState,
	ScreenProps,
	createBottomTabNavigator,
	createDrawerNavigator,
	createNavigationContainerRef,
	createStackNavigator,
} from "../../src/navigation/index";

interface NavParams {
	Home: null;
	Settings: null;
}

const Tab = createBottomTabNavigator<NavParams>();
const Drawer = createDrawerNavigator<NavParams>();
const Stack = createStackNavigator<NavParams>();

function Plain(props: ScreenProps<NavParams>): NeonNode {
	return <Text>plain</Text>;
}

const DEEP: LinkingOptions = {
	prefixes: [],
	enabled: false,
	config: { screens: [{ name: "Home", path: "" }, { name: "Settings", path: "settings" }] },
};

function mountWithLinkBeforeMount(children: NeonNode, ref: NavigationContainerRef, path: string): Dispose {
	const root = mockNode("root");
	return createRoot((stop: Dispose): Dispose => {
		const container = NavigationContainer({ children, linking: DEEP, ref });
		if (!ref.linkTo(path)) { throw new Error("no screen matches " + path); }
		container(mockHost(), root as unknown as HostNode, null);
		return stop;
	});
}

test "a link opened before a drawer root mounts reaches its screen" {
	const ref = createNavigationContainerRef();
	const stop = mountWithLinkBeforeMount(<Drawer.Navigator>
		<Drawer.Screen name="Home" component={Plain} />
		<Drawer.Screen name="Settings" component={Plain} />
	</Drawer.Navigator>, ref, "/settings");
	assert ref.currentPath() === "Settings", ref.currentPath();
	stop();
}

test "a link opened before a tab root mounts reaches its screen" {
	const ref = createNavigationContainerRef();
	const stop = mountWithLinkBeforeMount(<Tab.Navigator>
		<Tab.Screen name="Home" component={Plain} />
		<Tab.Screen name="Settings" component={Plain} />
	</Tab.Navigator>, ref, "/settings");
	assert ref.currentPath() === "Settings", ref.currentPath();
	stop();
}

test "a link opened before a stack root mounts keeps the initial route below it" {
	const ref = createNavigationContainerRef();
	const stop = mountWithLinkBeforeMount(<Stack.Navigator>
		<Stack.Screen name="Home" component={Plain} />
		<Stack.Screen name="Settings" component={Plain} />
	</Stack.Navigator>, ref, "/settings");
	assert ref.currentPath() === "Settings", ref.currentPath();
	const state: NavigationState = ref.getRootState();
	assert state.routes.length === 2, "the initial route stays below the link target: " + state.routes.length.toString();
	assert state.routes[0].name === "Home", state.routes[0].name;
	stop();
}
