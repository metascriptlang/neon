import { flush } from "../../src/core/runtime";
import { onCleanup } from "../../src/core/cleanup";
import { NeonNode } from "../../src/render/node";
import { HostNode, MockNode, mockNode, mockHost, render } from "../../src/render/host";
import { Text } from "../../src/components/primitives";
import {
	Navigation,
	NavigationContainer,
	NavigationEventArg,
	NavigationState,
	ScreenProps,
	createBottomTabNavigator,
	createDrawerNavigator,
	createNavigationContainerRef,
	createStackNavigator,
	useRoute,
} from "../../src/navigation/index";
import { findLabel, press, visibleText } from "./navHarness";

interface FeedParams {
	topic: string;
}

interface StackList {
	Home: null;
	Detail: null;
	Last: null;
}

interface TabList {
	Home: null;
	Feed: FeedParams | null;
}

interface DrawerList {
	Home: null;
	Other: null;
}

const Stack = createStackNavigator<StackList>();
const Tab = createBottomTabNavigator<TabList>();
const Drawer = createDrawerNavigator<DrawerList>();

let seenIndex = -1;
let seenRoutes = 0;
let removalTypes = "";
let stackNavigation: Navigation<StackList> | null = null;
let tabNavigation: Navigation<TabList> | null = null;
let drawerNavigation: Navigation<DrawerList> | null = null;

function StackHome(props: ScreenProps<StackList>): NeonNode {
	stackNavigation = props.navigation;
	const stop = props.navigation.addListener("state", (e: NavigationEventArg): void => {
		const state = e.data.state;
		if (state !== null) {
			seenIndex = (state as NavigationState).index;
			seenRoutes = (state as NavigationState).routes.length;
		}
	});
	onCleanup(stop);
	return <Text>home</Text>;
}

function StackLast(props: ScreenProps<StackList>): NeonNode {
	const stop = props.navigation.addListener("beforeRemove", (e: NavigationEventArg): void => {
		removalTypes += e.data.action.type + ";";
	});
	onCleanup(stop);
	return <Text>last</Text>;
}

function StackPlain(props: ScreenProps<StackList>): NeonNode {
	return <Text>detail</Text>;
}

function TabHome(props: ScreenProps<TabList>): NeonNode {
	tabNavigation = props.navigation;
	return <Text>home</Text>;
}

function TabFeed(props: ScreenProps<TabList>): NeonNode {
	const route = useRoute<TabList, "Feed">();
	const label = (): string => {
		const params = route.params();
		return params === null ? "feed all" : "feed " + params.topic;
	};
	return <Text>{label()}</Text>;
}

function DrawerHome(props: ScreenProps<DrawerList>): NeonNode {
	drawerNavigation = props.navigation;
	return <Text>drawer home</Text>;
}

function DrawerOther(props: ScreenProps<DrawerList>): NeonNode {
	return <Text>drawer other</Text>;
}

function mountStack(): void {
	const ref = createNavigationContainerRef();
	const root: MockNode = mockNode("root");
	render(<NavigationContainer ref={ref}>
		<Stack.Navigator>
			<Stack.Screen name="Home" component={StackHome} />
			<Stack.Screen name="Detail" component={StackPlain} />
			<Stack.Screen name="Last" component={StackLast} />
		</Stack.Navigator>
	</NavigationContainer>, mockHost(), root as unknown as HostNode);
	flush();
}

test "a state listener receives the navigation state in event data" {
	seenIndex = -1;
	seenRoutes = 0;
	mountStack();
	const navigation = stackNavigation as Navigation<StackList>;
	navigation.navigate("Detail");
	flush();
	assert seenIndex === 1 && seenRoutes === 2, seenIndex.toString() + "/" + seenRoutes.toString();
}

test "popToTop reports POP_TO_TOP to beforeRemove and pop reports POP" {
	removalTypes = "";
	mountStack();
	const navigation = stackNavigation as Navigation<StackList>;
	navigation.navigate("Last");
	flush();
	navigation.popToTop();
	flush();
	assert removalTypes === "POP_TO_TOP;", removalTypes;
	navigation.navigate("Last");
	flush();
	navigation.pop();
	flush();
	assert removalTypes === "POP_TO_TOP;POP;", removalTypes;
}

test "tab navigate without params resets the tab's params and pressing the tab keeps them" {
	const ref = createNavigationContainerRef();
	const root: MockNode = mockNode("root");
	render(<NavigationContainer ref={ref}>
		<Tab.Navigator>
			<Tab.Screen name="Home" component={TabHome} />
			<Tab.Screen name="Feed" component={TabFeed} />
		</Tab.Navigator>
	</NavigationContainer>, mockHost(), root as unknown as HostNode);
	flush();
	const navigation = tabNavigation as Navigation<TabList>;
	const topic: FeedParams = { topic: "neon" };
	navigation.navigate("Feed", topic);
	flush();
	assert visibleText(root).indexOf("feed neon") >= 0, visibleText(root);
	press(root, "Home");
	press(root, "Feed");
	assert visibleText(root).indexOf("feed neon") >= 0, "pressing the tab keeps params: " + visibleText(root);
	navigation.navigate("Home");
	flush();
	navigation.navigate("Feed");
	flush();
	assert visibleText(root).indexOf("feed all") >= 0, "navigate without params resets: " + visibleText(root);
}

test "drawer closes on navigate to another route and stays open on navigate to the focused one" {
	const ref = createNavigationContainerRef();
	const root: MockNode = mockNode("root");
	render(<NavigationContainer ref={ref}>
		<Drawer.Navigator>
			<Drawer.Screen name="Home" component={DrawerHome} />
			<Drawer.Screen name="Other" component={DrawerOther} />
		</Drawer.Navigator>
	</NavigationContainer>, mockHost(), root as unknown as HostNode);
	flush();
	const navigation = drawerNavigation as Navigation<DrawerList>;
	navigation.openDrawer();
	flush();
	assert findLabel(root, "Close navigation menu") !== null, "opened";
	navigation.navigate("Home");
	flush();
	assert findLabel(root, "Close navigation menu") !== null, "navigate to the focused route keeps it open";
	navigation.navigate("Other");
	flush();
	assert findLabel(root, "Close navigation menu") === null, "navigate to another route closes it";
	navigation.openDrawer();
	flush();
	press(root, "Other");
	assert findLabel(root, "Close navigation menu") === null, "pressing the focused item closes it";
}
