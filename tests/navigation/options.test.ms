import { createSignal } from "../../src/core/signal";
import { Dispose } from "../../src/core/types";
import { onCleanup } from "../../src/core/cleanup";
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
	createMaterialTopTabNavigator,
	createDrawerNavigator,
	createNavigationContainerRef,
	createStackNavigator,
	useNavigationState,
	useTheme,
	Link,
	LinkingOptions,
	NavigationEventArg,
	DarkTheme,
	DefaultTheme,
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

function Themed(props: ScreenProps<string>): NeonNode {
	const theme = useTheme();
	return <Text>{theme().dark ? "dark screen" : "light screen"}</Text>;
}

function headerOf(root: MockNode): MockNode {
	let node = root;
	while (node.children.length > 0 && node.tag !== "text") {
		const next = node.children[0];
		if (next.style !== null && (next.style as Style).height === 52) { return next; }
		node = next;
	}
	throw new Error("no header bar in " + visibleText(root));
}

test "the container theme colors headers and reaches screens through useTheme" {
	const [dark, setDark] = createSignal(false);
	const root: MockNode = mockNode("root");
	const dispose: Dispose = render(<NavigationContainer theme={dark() ? DarkTheme : DefaultTheme}>
		<Stack.Navigator>
			<Stack.Screen name="Themed" component={Themed} />
		</Stack.Navigator>
	</NavigationContainer>, mockHost(), root as unknown as HostNode);
	assert visibleText(root) === "Themed|light screen", visibleText(root);
	assert (headerOf(root).style as Style).backgroundColor === "#ffffff";
	setDark(true);
	assert visibleText(root) === "Themed|dark screen", visibleText(root);
	assert (headerOf(root).style as Style).backgroundColor === DarkTheme.colors.card;
	dispose();
}

test "a Group hands its screenOptions to its screens, under their own options" {
	const root: MockNode = mockNode("root");
	const ref = createNavigationContainerRef();
	const dispose: Dispose = render(<NavigationContainer ref={ref}>
		<Stack.Navigator>
			<Stack.Screen name="Base" component={Counted} />
			<Stack.Group screenOptions={{ presentation: "transparentModal", title: "Grouped" }}>
				<Stack.Screen name="Overlay" component={Counted} />
				<Stack.Screen name="Titled" component={Counted} options={{ presentation: "card", title: "Own" }} />
			</Stack.Group>
		</Stack.Navigator>
	</NavigationContainer>, mockHost(), root as unknown as HostNode);
	ref.navigate("Overlay");
	assert visibleText(root) === "Base|Base 0|+|Overlay 0|+", "overlay keeps Base visible: " + visibleText(root);
	ref.goBack();
	ref.navigate("Titled");
	assert visibleText(root) === "‹ Base|Own|Titled 0|+", visibleText(root);
	dispose();
}

const TopTabs = createMaterialTopTabNavigator<string>();

test "material top tabs put the bar above the screens, without a header, with a focus indicator" {
	const root: MockNode = mockNode("root");
	const ref = createNavigationContainerRef();
	const dispose: Dispose = render(<NavigationContainer ref={ref}>
		<TopTabs.Navigator>
			<TopTabs.Screen name="Chats" component={Counted} />
			<TopTabs.Screen name="Calls" component={Counted} />
		</TopTabs.Navigator>
	</NavigationContainer>, mockHost(), root as unknown as HostNode);
	assert visibleText(root) === "Chats 0|+|Chats|Calls", "no header: " + visibleText(root);
	const frame = root.children[0];
	assert (frame.style as Style).flexDirection === "column-reverse", "bar on top";
	const chats = findLabel(root, "Chats") as MockNode;
	const calls = findLabel(root, "Calls") as MockNode;
	const under = (tab: MockNode): string => {
		for (const child of tab.children) {
			const style = child.style;
			if (style !== null && (style as Style).height === 2) { return (style as Style).backgroundColor as string; }
		}
		return "none";
	};
	assert under(chats) === DefaultTheme.colors.primary, "focused indicator";
	press(root, "Calls");
	assert under(calls) === DefaultTheme.colors.primary && under(chats) === DefaultTheme.colors.card;
	assert ref.currentPath() === "Calls";
	dispose();
}

let blockTabs = false;

function Landing(props: ScreenProps<string>): NeonNode {
	const stop = props.navigation.addListener("tabPress", (e: NavigationEventArg): void => {
		if (blockTabs) { e.preventDefault(); }
	});
	onCleanup(stop);
	return <View>
		<Text>landing</Text>
		<Link to="/second" accessibilityLabel="go second"><Text>second</Text></Link>
	</View>;
}

test "Link opens a path, tabPress can be prevented and onStateChange reports each change" {
	blockTabs = false;
	const root: MockNode = mockNode("root");
	const ref = createNavigationContainerRef();
	const seen: string[] = [];
	const linking: LinkingOptions = {
		prefixes: ["app://"],
		config: { screens: [{ name: "Landing", path: "" }, { name: "Second", path: "second" }] },
	};
	const dispose: Dispose = render(<NavigationContainer ref={ref} linking={linking}
		onStateChange={(state: NavigationState): void => { seen.push(state.routes[state.index].name); }}>
		<Tab.Navigator>
			<Tab.Screen name="Landing" component={Landing} />
			<Tab.Screen name="Second" component={Counted} />
		</Tab.Navigator>
	</NavigationContainer>, mockHost(), root as unknown as HostNode);
	press(root, "go second");
	assert ref.currentPath() === "Second", ref.currentPath();
	press(root, "Landing");
	blockTabs = true;
	press(root, "Landing");
	assert ref.currentPath() === "Landing";
	ref.navigate("Second");
	press(root, "Landing");
	assert ref.currentPath() === "Second", "a prevented tabPress keeps the tab: " + ref.currentPath();
	assert seen.join(",") === "Second,Landing,Second", seen.join(",");
	dispose();
}
