import { createSignal } from "../../src/core/signal";
import { Dispose } from "../../src/core/types";
import { onCleanup } from "../../src/core/cleanup";
import { NeonNode } from "../../src/render/node";
import { NeonEvent } from "../../src/render/event";
import { HostNode, MockNode, mockNode, mockHost, render } from "../../src/render/host";
import { View, Text, Pressable } from "../../src/components/primitives";
import { dispatchHardwareBackPress } from "../../src/api/backHandler";
import {
	NavigationContainer,
	NavigationContainerRef,
	NavigationAction,
	NavigationEventArg,
	ScreenProps,
	createNavigationContainerRef,
	createStackNavigator,
	useNavigation,
	useRoute,
} from "../../src/navigation/index";
import { press, visibleText } from "./navHarness";

interface ItemParams {
	id: int32;
	title: string;
}

const Stack = createStackNavigator<ItemParams>();

let homeBodies = 0;

function Home(props: ScreenProps<ItemParams>): NeonNode {
	homeBodies += 1;
	const [count, setCount] = createSignal<int32>(0);
	const navigation = props.navigation;
	return <View>
		<Text>{"home " + count().toString()}</Text>
		<Pressable accessibilityLabel="more" onPress={(e: NeonEvent): void => { setCount(count() + 1); }}><Text>+</Text></Pressable>
		<Pressable accessibilityLabel="open 7" onPress={(e: NeonEvent): void => {
			navigation.navigate("Detail", { id: 7, title: "Seven" });
		}}><Text>open</Text></Pressable>
	</View>;
}

function Detail(props: ScreenProps<ItemParams>): NeonNode {
	const route = useRoute<ItemParams>();
	const navigation = useNavigation<ItemParams>();
	const label = (): string => {
		const params = route.params();
		return params === null ? "detail none" : "detail " + params.id.toString() + " " + params.title;
	};
	return <View>
		<Text>{label()}</Text>
		<Pressable accessibilityLabel="edit" onPress={(e: NeonEvent): void => {
			const params = route.params();
			navigation.push("Edit", params);
		}}><Text>edit</Text></Pressable>
		<Pressable accessibilityLabel="rename" onPress={(e: NeonEvent): void => {
			navigation.setParams({ id: 7, title: "Renamed" });
			navigation.setOptions({ title: "Item 7" });
		}}><Text>rename</Text></Pressable>
	</View>;
}

function Edit(props: ScreenProps<ItemParams>): NeonNode {
	const navigation = props.navigation;
	return <View>
		<Text>{"edit can back " + (navigation.canGoBack() ? "yes" : "no")}</Text>
		<Pressable accessibilityLabel="done" onPress={(e: NeonEvent): void => { navigation.popToTop(); }}><Text>done</Text></Pressable>
		<Pressable accessibilityLabel="swap" onPress={(e: NeonEvent): void => { navigation.replace("Detail", { id: 9, title: "Nine" }); }}><Text>swap</Text></Pressable>
	</View>;
}

let unmount: Dispose | null = null;

function Sheet(props: ScreenProps<ItemParams>): NeonNode {
	const navigation = props.navigation;
	return <View>
		<Text>sheet</Text>
		<Pressable accessibilityLabel="close sheet" onPress={(e: NeonEvent): void => { navigation.goBack(); }}><Text>x</Text></Pressable>
	</View>;
}

let pending: NavigationAction | null = null;

function Draft(props: ScreenProps<ItemParams>): NeonNode {
	const navigation = props.navigation;
	const [dirty, setDirty] = createSignal(true);
	const stop = navigation.addListener("beforeRemove", (e: NavigationEventArg): void => {
		if (!dirty()) { return; }
		e.preventDefault();
		pending = e.data.action;
	});
	onCleanup(stop);
	return <View>
		<Text>{dirty() ? "draft unsaved" : "draft saved"}</Text>
		<Pressable accessibilityLabel="discard" onPress={(e: NeonEvent): void => {
			const action = pending;
			if (action !== null) { navigation.dispatch(action as NavigationAction); }
		}}><Text>discard</Text></Pressable>
		<Pressable accessibilityLabel="save draft" onPress={(e: NeonEvent): void => { setDirty(false); }}><Text>save</Text></Pressable>
	</View>;
}

function mountStack(ref: NavigationContainerRef): MockNode {
	if (unmount !== null) { (unmount as Dispose)(); }
	const root: MockNode = mockNode("root");
	unmount = render(<NavigationContainer ref={ref}>
		<Stack.Navigator initialRouteName="Home">
			<Stack.Screen name="Home" component={Home} options={{ title: "Items" }} />
			<Stack.Screen name="Detail" component={Detail} />
			<Stack.Screen name="Edit" component={Edit} options={{ title: "Edit item" }} />
			<Stack.Screen name="Sheet" component={Sheet} options={{ presentation: "transparentModal" }} />
			<Stack.Screen name="Draft" component={Draft} />
		</Stack.Navigator>
	</NavigationContainer>, mockHost(), root as unknown as HostNode);
	return root;
}

test "a stack shows its initial route with a header and no back button" {
	const ref = createNavigationContainerRef();
	const root = mountStack(ref);
	assert visibleText(root) === "Items|home 0|+|open", visibleText(root);
	assert ref.currentPath() === "Home", ref.currentPath();
	assert !ref.canGoBack();
}

test "navigate pushes with params, the header backs to the screen below with its state kept" {
	homeBodies = 0;
	const ref = createNavigationContainerRef();
	const root = mountStack(ref);
	press(root, "more");
	press(root, "more");
	press(root, "open 7");
	assert visibleText(root) === "‹ Items|Detail|detail 7 Seven|edit|rename", visibleText(root);
	assert ref.currentPath() === "Detail" && ref.canGoBack();
	press(root, "Back");
	assert visibleText(root) === "Items|home 2|+|open", "state kept: " + visibleText(root);
	assert homeBodies === 1, "home mounted once: " + homeBodies.toString();
}

test "push, setParams, setOptions, replace and popToTop" {
	const ref = createNavigationContainerRef();
	const root = mountStack(ref);
	press(root, "open 7");
	press(root, "rename");
	assert visibleText(root) === "‹ Items|Item 7|detail 7 Renamed|edit|rename", visibleText(root);
	press(root, "edit");
	assert visibleText(root) === "‹ Item 7|Edit item|edit can back yes|done|swap", visibleText(root);
	assert ref.currentPath() === "Edit", ref.currentPath();
	press(root, "swap");
	assert visibleText(root) === "‹ Item 7|Detail|detail 9 Nine|edit|rename", visibleText(root);
	press(root, "edit");
	press(root, "done");
	assert ref.currentPath() === "Home", ref.currentPath();
	assert visibleText(root) === "Items|home 0|+|open", visibleText(root);
}

test "navigate to a route already in the stack goes back to it" {
	const ref = createNavigationContainerRef();
	const root = mountStack(ref);
	press(root, "open 7");
	press(root, "edit");
	ref.navigate("Home");
	assert ref.currentPath() === "Home", ref.currentPath();
	assert !ref.canGoBack();
}

test "hardware back pops the stack, then is left to the system at the root" {
	const ref = createNavigationContainerRef();
	const root = mountStack(ref);
	press(root, "open 7");
	press(root, "edit");
	assert dispatchHardwareBackPress(), "consumed";
	assert ref.currentPath() === "Detail", ref.currentPath();
	assert dispatchHardwareBackPress();
	assert !dispatchHardwareBackPress(), "the root leaves back to the system";
	assert visibleText(root) === "Items|home 0|+|open", visibleText(root);
}

test "navigate to an unknown screen throws, naming it" {
	const ref = createNavigationContainerRef();
	mountStack(ref);
	let message = "";
	try {
		ref.navigate("Nowhere");
	} catch (e) {
		message = (e as Error).message;
	}
	assert message.indexOf("Nowhere") >= 0, message;
}

test "a transparent modal keeps the screen below it visible and has no header" {
	const ref = createNavigationContainerRef();
	const root = mountStack(ref);
	ref.navigate("Sheet");
	assert visibleText(root) === "Items|home 0|+|open|sheet|x", visibleText(root);
	press(root, "close sheet");
	assert visibleText(root) === "Items|home 0|+|open", visibleText(root);
}

test "beforeRemove holds a screen with unsaved changes until its action is dispatched" {
	pending = null;
	const ref = createNavigationContainerRef();
	const root = mountStack(ref);
	ref.navigate("Draft");
	press(root, "Back");
	assert ref.currentPath() === "Draft", "the header back was prevented";
	assert dispatchHardwareBackPress(), "hardware back is consumed while prevented";
	assert ref.currentPath() === "Draft", ref.currentPath();
	assert pending !== null && (pending as NavigationAction).type === "GO_BACK";
	press(root, "discard");
	assert ref.currentPath() === "Home", "the dispatched action leaves: " + ref.currentPath();
	ref.navigate("Draft");
	press(root, "save draft");
	press(root, "Back");
	assert ref.currentPath() === "Home", "a saved draft leaves at once";
}
