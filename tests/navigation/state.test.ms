import { NeonNode } from "../../src/render/node";
import { NeonEvent } from "../../src/render/event";
import { HostNode, MockNode, mockNode, mockHost, render } from "../../src/render/host";
import { View, Text, Pressable } from "../../src/components/primitives";
import {
	NavigationContainer,
	NavigationContainerRef,
	NavigationState,
	ScreenProps,
	createBottomTabNavigator,
	createNavigationContainerRef,
	createStackNavigator,
	useRoute,
} from "../../src/navigation/index";
import { press, visibleText } from "./navHarness";

interface ItemParams {
	id: int32;
}

interface TabParams {
	Home: null;
	Profile: null;
}

interface HomeParams {
	List: null;
	Detail: ItemParams;
}

const Tab = createBottomTabNavigator<TabParams>();
const HomeStack = createStackNavigator<HomeParams>();

function List(props: ScreenProps<HomeParams>): NeonNode {
	const navigation = props.navigation;
	return <View>
		<Text>list</Text>
		<Pressable accessibilityLabel="item 3" onPress={(e: NeonEvent): void => { navigation.navigate("Detail", { id: 3 }); }}><Text>3</Text></Pressable>
	</View>;
}

function Detail(props: ScreenProps<HomeParams>): NeonNode {
	const params = useRoute<HomeParams, "Detail">().params;
	return <Text>{"detail " + (params() === null ? "-" : (params() as ItemParams).id.toString())}</Text>;
}

function encodeItem(params: ItemParams): Map<string, string> {
	const values = new Map<string, string>();
	values.set("id", params.id.toString());
	return values;
}

function Home(props: ScreenProps<TabParams>): NeonNode {
	return <HomeStack.Navigator>
		<HomeStack.Screen name="List" component={List} options={{ title: "Items" }} />
		<HomeStack.Screen name="Detail" component={Detail}
			params={HomeStack.params.of("Detail", {
				parse: (values: Map<string, string>): ItemParams => ({ id: parseInt(values.get("id") ?? "0") as int32 }),
				stringify: encodeItem,
			})} />
	</HomeStack.Navigator>;
}

function Profile(props: ScreenProps<TabParams>): NeonNode {
	return <Text>profile</Text>;
}

function mountApp(ref: NavigationContainerRef, initial: NavigationState | null, seen: NavigationState[]): MockNode {
	const root = mockNode("root");
	render(<NavigationContainer ref={ref} initialState={initial}
		onStateChange={(state: NavigationState): void => { seen.push(state); }}>
		<Tab.Navigator>
			<Tab.Screen name="Home" component={Home} options={{ headerShown: false }} />
			<Tab.Screen name="Profile" component={Profile} />
		</Tab.Navigator>
	</NavigationContainer>, mockHost(), root as unknown as HostNode);
	return root;
}

test "the root state nests each child navigator's state with stringified params" {
	const ref = createNavigationContainerRef();
	const seen: NavigationState[] = [];
	const root = mountApp(ref, null, seen);
	press(root, "item 3");
	const state = ref.getRootState();
	assert state.index === 0 && state.routes.length === 2, "tabs";
	const home = state.routes[0].state;
	assert home !== null, "the Home tab holds its stack's state";
	const stack = home as NavigationState;
	assert stack.index === 1 && stack.routes[1].name === "Detail", "stack";
	const params = stack.routes[1].params;
	assert params !== null && (params as Map<string, string>).get("id") === "3", "params";
	assert stack.routes[0].params === null, "a route without params reports none";
	assert state.routes[1].state === null, "an unvisited tab has no child state";
	const last = seen[seen.length - 1];
	assert last.routes[0].state !== null, "onStateChange reports the nested state";
}

test "a saved state mounts again as the same screens with their params" {
	const ref = createNavigationContainerRef();
	const seen: NavigationState[] = [];
	const first = mountApp(ref, null, seen);
	press(first, "item 3");
	press(first, "Profile");
	const saved = seen[seen.length - 1];
	const again = createNavigationContainerRef();
	const root = mountApp(again, saved, []);
	assert again.currentPath() === "Profile", again.currentPath();
	press(root, "Home");
	assert again.currentPath() === "Home>Detail", again.currentPath();
	assert visibleText(root).indexOf("detail 3") >= 0, visibleText(root);
	assert again.canGoBack(), "the restored stack keeps the screen below";
}

test "an initial stack state whose index is below its last route focuses the last route" {
	const ids = new Map<string, string>();
	ids.set("id", "4");
	const stack: NavigationState = {
		index: 0,
		routeNames: [],
		routes: [
			{ key: "", name: "List", params: null, state: null },
			{ key: "", name: "Detail", params: ids, state: null },
		],
	};
	const state: NavigationState = {
		index: 0,
		routeNames: [],
		routes: [{ key: "", name: "Home", params: null, state: stack }],
	};
	const ref = createNavigationContainerRef();
	const root = mountApp(ref, state, []);
	assert ref.currentPath() === "Home>Detail", ref.currentPath();
	assert visibleText(root).indexOf("detail 4") >= 0, visibleText(root);
	assert ref.canGoBack(), "the route below the focused one is kept";
}

test "an initial state naming no screen fails at mount" {
	const state: NavigationState = {
		index: 0,
		routeNames: [],
		routes: [{ key: "x", name: "Missing", params: null, state: null }],
	};
	let message = "";
	try {
		mountApp(createNavigationContainerRef(), state, []);
	} catch (e) {
		message = (e as Error).message;
	}
	assert message === "initialState: no screen named 'Missing'", message;
}
