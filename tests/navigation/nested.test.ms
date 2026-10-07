import { Accessor, createSignal } from "../../src/core/signal";
import { onCleanup } from "../../src/core/cleanup";
import { Dispose } from "../../src/core/types";
import { NeonNode } from "../../src/render/node";
import { NeonEvent } from "../../src/render/event";
import { HostNode, MockNode, mockNode, mockHost, render } from "../../src/render/host";
import { View, Text, Pressable } from "../../src/components/primitives";
import { dispatchHardwareBackPress } from "../../src/api/backHandler";
import { publishUrl } from "../../src/api/linking";
import {
	LinkingOptions,
	NavigationContainer,
	NavigationContainerRef,
	ScreenProps,
	createBottomTabNavigator,
	createDrawerNavigator,
	createNavigationContainerRef,
	createStackNavigator,
	useIsFocused,
	useNavigation,
} from "../../src/navigation/index";
import { press, visibleText, findLabel } from "./navHarness";

interface ItemParams {
	id: int32;
}

const Drawer = createDrawerNavigator<string>();
const Tab = createBottomTabNavigator<string>();
const HomeStack = createStackNavigator<ItemParams>();

let searchBodies = 0;
let focusLog = "";

function counterScreen(name: string): NeonNode {
	const [count, setCount] = createSignal<int32>(0);
	return <View>
		<Text>{name + " " + count().toString()}</Text>
		<Pressable accessibilityLabel={"bump " + name} onPress={(e: NeonEvent): void => { setCount(count() + 1); }}><Text>+</Text></Pressable>
	</View>;
}

function List(props: ScreenProps<ItemParams>): NeonNode {
	const navigation = props.navigation;
	const focused = useIsFocused();
	const stopFocus = navigation.addListener("focus", (): void => { focusLog += "list+;"; });
	const stopBlur = navigation.addListener("blur", (): void => { focusLog += "list-;"; });
	onCleanup((): void => {
		stopFocus();
		stopBlur();
	});
	return <View>
		<Text>{"list " + (focused() ? "focused" : "blurred")}</Text>
		<Pressable accessibilityLabel="item 3" onPress={(e: NeonEvent): void => { navigation.navigate("Detail", { id: 3 }); }}><Text>3</Text></Pressable>
	</View>;
}

function Detail(props: ScreenProps<ItemParams>): NeonNode {
	const navigation = props.navigation;
	const params = props.route.params;
	return <View>
		<Text>{"detail " + (params() === null ? "-" : (params() as ItemParams).id.toString())}</Text>
		<Pressable accessibilityLabel="to settings" onPress={(e: NeonEvent): void => { navigation.navigate("Settings"); }}><Text>s</Text></Pressable>
		<Pressable accessibilityLabel="to search" onPress={(e: NeonEvent): void => { navigation.navigate("Search"); }}><Text>q</Text></Pressable>
	</View>;
}

function Home(props: ScreenProps<string>): NeonNode {
	return <HomeStack.Navigator>
		<HomeStack.Screen name="List" component={List} options={{ title: "Items" }} />
		<HomeStack.Screen name="Detail" component={Detail}
			parseParams={(values: Map<string, string>): ItemParams => ({ id: parseInt(values.get("id") ?? "0") as int32 })} />
	</HomeStack.Navigator>;
}

function Search(props: ScreenProps<string>): NeonNode {
	searchBodies += 1;
	const navigation = useNavigation<string>();
	return <View>
		{counterScreen("search")}
		<Pressable accessibilityLabel="badge" onPress={(e: NeonEvent): void => { navigation.setOptions({ tabBarBadge: "5" }); }}><Text>b</Text></Pressable>
		<Pressable accessibilityLabel="query" onPress={(e: NeonEvent): void => { navigation.setParams("neon"); }}><Text>q</Text></Pressable>
		<Text>{"query " + (props.route.params() ?? "none")}</Text>
	</View>;
}

function Profile(props: ScreenProps<string>): NeonNode {
	return counterScreen("profile");
}

function Main(props: ScreenProps<string>): NeonNode {
	return <Tab.Navigator>
		<Tab.Screen name="Home" component={Home} options={{ headerShown: false }} />
		<Tab.Screen name="Search" component={Search} />
		<Tab.Screen name="Profile" component={Profile} options={{ tabBarLabel: "Me" }} />
	</Tab.Navigator>;
}

function Settings(props: ScreenProps<string>): NeonNode {
	return counterScreen("settings");
}

function About(props: ScreenProps<string>): NeonNode {
	return <Text>about</Text>;
}

const linking: LinkingOptions = {
	prefixes: ["neonnav://", "https://neon.invalid/nav"],
	config: {
		screens: [
			{
				name: "Main",
				screens: [
					{
						name: "Home",
						screens: [
							{ name: "List", path: "items" },
							{ name: "Detail", path: "items/:id" },
						],
					},
					{ name: "Search", path: "search" },
					{ name: "Profile", path: "me" },
				],
			},
			{ name: "Settings", path: "settings" },
			{ name: "About", path: "about" },
		],
	},
};

let unmount: Dispose | null = null;

function mountApp(ref: NavigationContainerRef): MockNode {
	if (unmount !== null) { (unmount as Dispose)(); }
	const root: MockNode = mockNode("root");
	unmount = render(<NavigationContainer navigationRef={ref} linking={linking}>
		<Drawer.Navigator>
			<Drawer.Screen name="Main" component={Main} options={{ headerShown: false, drawerLabel: "Home" }} />
			<Drawer.Screen name="Settings" component={Settings} />
			<Drawer.Screen name="About" component={About} />
		</Drawer.Navigator>
	</NavigationContainer>, mockHost(), root as unknown as HostNode);
	return root;
}

test "tabs mount lazily, keep each tab's state and show the badge set by a screen" {
	searchBodies = 0;
	const ref = createNavigationContainerRef();
	const root = mountApp(ref);
	assert ref.currentPath() === "Main>Home>List", ref.currentPath();
	assert searchBodies === 0, "Search is lazy";
	press(root, "Search");
	assert ref.currentPath() === "Main>Search", ref.currentPath();
	assert searchBodies === 1, "Search mounted on first focus";
	press(root, "bump search");
	press(root, "bump search");
	press(root, "Me");
	press(root, "bump profile");
	press(root, "Search");
	assert visibleText(root).indexOf("search 2") >= 0, visibleText(root);
	press(root, "Me");
	assert visibleText(root).indexOf("profile 1") >= 0, visibleText(root);
	assert searchBodies === 1, "Search mounted once: " + searchBodies.toString();
	press(root, "Search");
	press(root, "badge");
	press(root, "query");
	assert visibleText(root).indexOf("Search|5") >= 0, "badge: " + visibleText(root);
	assert visibleText(root).indexOf("query neon") >= 0, "params: " + visibleText(root);
}

test "the home stack keeps its depth across tab switches; pressing its tab again pops to the top" {
	const ref = createNavigationContainerRef();
	const root = mountApp(ref);
	press(root, "item 3");
	assert ref.currentPath() === "Main>Home>Detail", ref.currentPath();
	press(root, "Me");
	press(root, "Home");
	assert ref.currentPath() === "Main>Home>Detail", "depth kept: " + ref.currentPath();
	assert visibleText(root).indexOf("detail 3") >= 0, visibleText(root);
	press(root, "Home");
	assert ref.currentPath() === "Main>Home>List", "re-press pops: " + ref.currentPath();
}

test "hardware back pops the nested stack, then goes to the first tab, then leaves" {
	const ref = createNavigationContainerRef();
	const root = mountApp(ref);
	press(root, "item 3");
	press(root, "to search");
	assert ref.currentPath() === "Main>Search", ref.currentPath();
	assert dispatchHardwareBackPress();
	assert ref.currentPath() === "Main>Home>Detail", "back to the first tab: " + ref.currentPath();
	assert dispatchHardwareBackPress();
	assert ref.currentPath() === "Main>Home>List", ref.currentPath();
	assert !dispatchHardwareBackPress(), "nothing left to go back to";
}

test "the drawer opens from the header button, navigates, and back closes it first" {
	const ref = createNavigationContainerRef();
	const root = mountApp(ref);
	ref.navigate("Settings");
	assert ref.currentPath() === "Settings", ref.currentPath();
	press(root, "bump settings");
	press(root, "Show navigation menu");
	assert findLabel(root, "Close navigation menu") !== null, "drawer open";
	assert dispatchHardwareBackPress(), "back closes the drawer";
	assert findLabel(root, "Close navigation menu") === null, "drawer closed";
	assert ref.currentPath() === "Settings", ref.currentPath();
	press(root, "Show navigation menu");
	press(root, "About");
	assert ref.currentPath() === "About" && findLabel(root, "Close navigation menu") === null, ref.currentPath();
	press(root, "Show navigation menu");
	press(root, "Settings");
	assert visibleText(root).indexOf("settings 1") >= 0, "settings state kept: " + visibleText(root);
	assert dispatchHardwareBackPress();
	assert ref.currentPath() === "Main>Home>List", "back goes to the first drawer route: " + ref.currentPath();
}

test "navigate bubbles from a nested stack screen to the drawer" {
	const ref = createNavigationContainerRef();
	const root = mountApp(ref);
	press(root, "item 3");
	press(root, "to settings");
	assert ref.currentPath() === "Settings", ref.currentPath();
	ref.navigate("Main");
	assert ref.currentPath() === "Main>Home>Detail", ref.currentPath();
}

test "focus and blur reach a screen when its route, tab or drawer item changes" {
	focusLog = "";
	const ref = createNavigationContainerRef();
	const root = mountApp(ref);
	assert visibleText(root).indexOf("list focused") >= 0, visibleText(root);
	press(root, "item 3");
	press(root, "Back");
	press(root, "Search");
	ref.navigate("Home");
	ref.navigate("Settings");
	assert focusLog === "list-;list+;list-;list+;list-;", focusLog;
}

test "a deep link reaches a nested screen with parsed params" {
	const ref = createNavigationContainerRef();
	mountApp(ref);
	publishUrl("neonnav://items/42");
	assert ref.currentPath() === "Main>Home>Detail", ref.currentPath();
	const route = ref.getCurrentRoute();
	assert route !== null && route.name === "Detail";
	publishUrl("https://neon.invalid/nav/settings");
	assert ref.currentPath() === "Settings", ref.currentPath();
	publishUrl("neonnav://me");
	assert ref.currentPath() === "Main>Profile", ref.currentPath();
	publishUrl("other://items/1");
	assert ref.currentPath() === "Main>Profile", "a foreign prefix is ignored";
	assert ref.linkTo("/items/7");
	assert ref.currentPath() === "Main>Home>Detail", ref.currentPath();
}
