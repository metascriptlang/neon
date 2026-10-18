import { createSignal } from "../../src/core/signal";
import { NeonEvent } from "../../src/render/event";
import { HostNode, MockNode, mockNode, mockHost, render } from "../../src/render/host";
import { View, Text, Pressable } from "../../src/components/primitives";
import { dispatchHardwareBackPress } from "../../src/api/backHandler";
import {
	NavigationContainer,
	ScreenProps,
	createStackNavigator,
	useRoute,
} from "../../src/navigation/index";
import { flush } from "../../src/core/runtime";
import { refreshReset } from "../../src/render/refresh";
import { press, visibleText } from "../navigation/navHarness";
import { thisFile } from "./here";

interface ItemParams {
	id: int32;
}

const Stack = createStackNavigator<ItemParams>();

function Home(props: ScreenProps<ItemParams>): NeonNode {
	const [count, setCount] = createSignal<int32>(0);
	const navigation = props.navigation;
	return <View>
		<Text>{"home " + count().toString()}</Text>
		<Pressable accessibilityLabel="more" onPress={(e: NeonEvent): void => { setCount(count() + 1); }}><Text>+</Text></Pressable>
		<Pressable accessibilityLabel="open" onPress={(e: NeonEvent): void => {
			navigation.navigate("Detail", { id: 7 });
		}}><Text>open</Text></Pressable>
	</View>;
}

function Detail(props: ScreenProps<ItemParams>): NeonNode {
	const route = useRoute<ItemParams>();
	const label = (): string => {
		const params = route.params();
		return params === null ? "detail none" : "detail " + params.id.toString();
	};
	return <View><Text>{label()}</Text></View>;
}

function About(props: ScreenProps<ItemParams>): NeonNode {
	return <View><Text>about</Text></View>;
}

function App(): NeonNode {
	return <NavigationContainer>
		<Stack.Navigator initialRouteName="Home">
			<Stack.Screen name="Home" component={Home} options={{ title: "Items" }} />
			<Stack.Screen name="Detail" component={Detail} />
		</Stack.Navigator>
	</NavigationContainer>;
}

function appWithAbout<E>(__refreshEnv: E): NeonNode {
	return <NavigationContainer>
		<Stack.Navigator initialRouteName="Home">
			<Stack.Screen name="Home" component={Home} options={{ title: "All items" }} />
			<Stack.Screen name="Detail" component={Detail} />
			<Stack.Screen name="About" component={About} />
		</Stack.Navigator>
	</NavigationContainer>;
}

function appWithoutDetail<E>(__refreshEnv: E): NeonNode {
	return <NavigationContainer>
		<Stack.Navigator initialRouteName="Home">
			<Stack.Screen name="Home" component={Home} options={{ title: "Items" }} />
			<Stack.Screen name="About" component={About} />
		</Stack.Navigator>
	</NavigationContainer>;
}

const edited = (): string => "edited";

function mountApp(): [MockNode, () => void] {
	const root: MockNode = mockNode("root");
	const dispose = render(App(), mockHost(), root as unknown as HostNode);
	return [root, dispose];
}

test "refresh navigation: an edit above the navigator keeps the route stack and each screen's signals" {
	refreshReset();
	const [root, dispose] = mountApp();
	press(root, "more");
	flush();
	press(root, "more");
	flush();
	press(root, "open");
	flush();
	assert visibleText(root).indexOf("detail 7") >= 0, "on the detail screen: " + visibleText(root);
	refreshTemplate0(thisFile(), "App#template", appWithAbout, edited, __refreshSetup_App);
	const summary = refreshModule(thisFile());
	assert summary.rebuilt === 1, "the app template is rebuilt: " + summary.rebuilt.toString();
	assert visibleText(root).indexOf("detail 7") >= 0, "still on the detail screen: " + visibleText(root);
	const handled = dispatchHardwareBackPress();
	flush();
	assert handled, "back pops to the screen below";
	assert visibleText(root).indexOf("home 2") >= 0, "home kept its count: " + visibleText(root);
	assert visibleText(root).indexOf("All items") >= 0, "and shows the edited title: " + visibleText(root);
	dispose();
}

test "refresh navigation: a kept stack that names a removed screen starts again" {
	refreshReset();
	const [root, dispose] = mountApp();
	press(root, "open");
	flush();
	refreshTemplate0(thisFile(), "App#template", appWithoutDetail, edited, __refreshSetup_App);
	refreshModule(thisFile());
	assert visibleText(root).indexOf("home 0") >= 0, "back on the initial route: " + visibleText(root);
	dispose();
}
