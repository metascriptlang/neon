import { createSignal } from "../../src/core/signal";
import { resetErrorHalt } from "../../src/core/runtime";
import { NeonNode } from "../../src/render/hostTypes";
import { HostNode, mockHost, mockNode, render } from "../../src/render/host";
import { Text } from "../../src/components/primitives";
import { Show } from "../../src/macros/ui/flow";
import {
	NavigationContainer,
	ScreenProps,
	createBottomTabNavigator,
	createDrawerNavigator,
	createNavigationContainerRef,
	createStackNavigator,
} from "../../src/navigation/index";

const EMPTY_AFTER_UPDATE = "a navigator needs at least one Screen after a conditional update";
const EMPTY_AT_MOUNT = "a navigator needs at least one Screen child";

function Page(props: ScreenProps<string>): NeonNode {
	return <Text>page</Text>;
}

function First(props: ScreenProps<string>): NeonNode {
	return <Text>first</Text>;
}

function Second(props: ScreenProps<string>): NeonNode {
	return <Text>second</Text>;
}

function failureOf(run: () => void): string {
	try {
		run();
	} catch (e) {
		return (e as Error).message;
	}
	return "";
}

test "a stack whose only screen goes away throws, naming the case" {
	const [present, setPresent] = createSignal(true);
	const Stack = createStackNavigator<string>();
	const root = mockNode("root");
	const dispose = render(<NavigationContainer>
		<Stack.Navigator>
			<Show when={present}>
				<Stack.Screen name="Only" component={Page} />
			</Show>
		</Stack.Navigator>
	</NavigationContainer>, mockHost(), root as unknown as HostNode);
	assert failureOf((): void => { setPresent(false); }) === EMPTY_AFTER_UPDATE;
	resetErrorHalt();
	dispose();
}

test "a tab navigator whose only screen goes away throws, naming the case" {
	const [present, setPresent] = createSignal(true);
	const Tab = createBottomTabNavigator<string>();
	const root = mockNode("root");
	const dispose = render(<NavigationContainer>
		<Tab.Navigator>
			<Show when={present}>
				<Tab.Screen name="Only" component={Page} />
			</Show>
		</Tab.Navigator>
	</NavigationContainer>, mockHost(), root as unknown as HostNode);
	assert failureOf((): void => { setPresent(false); }) === EMPTY_AFTER_UPDATE;
	resetErrorHalt();
	dispose();
}

test "a drawer navigator whose only screen goes away throws, naming the case" {
	const [present, setPresent] = createSignal(true);
	const Drawer = createDrawerNavigator<string>();
	const root = mockNode("root");
	const dispose = render(<NavigationContainer>
		<Drawer.Navigator>
			<Show when={present}>
				<Drawer.Screen name="Only" component={Page} />
			</Show>
		</Drawer.Navigator>
	</NavigationContainer>, mockHost(), root as unknown as HostNode);
	assert failureOf((): void => { setPresent(false); }) === EMPTY_AFTER_UPDATE;
	resetErrorHalt();
	dispose();
}

test "a navigator mounted with no screen throws, naming the case" {
	const [present, setPresent] = createSignal(false);
	const Stack = createStackNavigator<string>();
	const root = mockNode("root");
	const mount = (): void => {
		render(<NavigationContainer>
			<Stack.Navigator>
				<Show when={present}>
					<Stack.Screen name="Only" component={Page} />
				</Show>
			</Stack.Navigator>
		</NavigationContainer>, mockHost(), root as unknown as HostNode);
	};
	assert failureOf(mount) === EMPTY_AT_MOUNT;
}

test "a stack that swaps its only screen for another focuses the replacement" {
	const [first, setFirst] = createSignal(true);
	const Stack = createStackNavigator<string>();
	const ref = createNavigationContainerRef();
	const root = mockNode("root");
	const dispose = render(<NavigationContainer ref={ref}>
		<Stack.Navigator screenOptions={{ animation: "none" }}>
			<Show when={first}>
				<Stack.Screen name="First" component={First} />
			</Show>
			<Show when={!first()}>
				<Stack.Screen name="Second" component={Second} />
			</Show>
			<Stack.Screen name="Help" component={Page} />
		</Stack.Navigator>
	</NavigationContainer>, mockHost(), root as unknown as HostNode);
	assert ref.currentPath() === "First", ref.currentPath();
	setFirst(false);
	assert ref.currentPath() === "Second", ref.currentPath();
	dispose();
}

test "a tab navigator that swaps its focused screen for another keeps a screen focused" {
	const [first, setFirst] = createSignal(true);
	const Tab = createBottomTabNavigator<string>();
	const ref = createNavigationContainerRef();
	const root = mockNode("root");
	const dispose = render(<NavigationContainer ref={ref}>
		<Tab.Navigator>
			<Show when={first}>
				<Tab.Screen name="First" component={First} />
			</Show>
			<Show when={!first()}>
				<Tab.Screen name="Second" component={Second} />
			</Show>
			<Tab.Screen name="Help" component={Page} />
		</Tab.Navigator>
	</NavigationContainer>, mockHost(), root as unknown as HostNode);
	assert ref.currentPath() === "First", ref.currentPath();
	setFirst(false);
	assert ref.currentPath() === "Second", ref.currentPath();
	dispose();
}

test "a drawer navigator that swaps its focused screen for another keeps a screen focused" {
	const [first, setFirst] = createSignal(true);
	const Drawer = createDrawerNavigator<string>();
	const ref = createNavigationContainerRef();
	const root = mockNode("root");
	const dispose = render(<NavigationContainer ref={ref}>
		<Drawer.Navigator>
			<Show when={first}>
				<Drawer.Screen name="First" component={First} />
			</Show>
			<Show when={!first()}>
				<Drawer.Screen name="Second" component={Second} />
			</Show>
			<Drawer.Screen name="Help" component={Page} />
		</Drawer.Navigator>
	</NavigationContainer>, mockHost(), root as unknown as HostNode);
	assert ref.currentPath() === "First", ref.currentPath();
	setFirst(false);
	assert ref.currentPath() === "Second", ref.currentPath();
	dispose();
}
