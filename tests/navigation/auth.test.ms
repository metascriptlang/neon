import { createSignal } from "../../src/core/signal";
import { onCleanup } from "../../src/core/cleanup";
import { NeonNode } from "../../src/render/hostTypes";
import { mockHost, mockNode, mockToString, render } from "../../src/render/host";
import { Text } from "../../src/components/primitives";
import { Show } from "../../src/macros/ui/flow";
import {
	NavigationContainer,
	createNavigationContainerRef,
	createStackNavigator,
	ScreenProps,
} from "../../src/navigation/index";

interface AuthParams { user: string; }

let guestDisposed: int32 = 0;
let homeDisposed: int32 = 0;
let helpCreated: int32 = 0;

function Guest(props: ScreenProps<AuthParams>): NeonNode {
	onCleanup((): void => { guestDisposed += 1; });
	return <Text>Guest body</Text>;
}

function Home(props: ScreenProps<AuthParams>): NeonNode {
	onCleanup((): void => { homeDisposed += 1; });
	return <Text>Private body</Text>;
}

function Help(props: ScreenProps<AuthParams>): NeonNode {
	helpCreated += 1;
	return <Text>Help body</Text>;
}

test "conditional screens replace auth stack without retaining protected frames" {
	guestDisposed = 0;
	homeDisposed = 0;
	const [loggedIn, setLoggedIn] = createSignal(false);
	const Stack = createStackNavigator<AuthParams>();
	const ref = createNavigationContainerRef();
	const root = mockNode("root");
	const dispose = render(<NavigationContainer ref={ref}>
		<Stack.Navigator screenOptions={{ animation: "none" }}>
			<Show when={!loggedIn()}>
				<Stack.Screen name="Guest" component={Guest} />
			</Show>
			<Show when={loggedIn}>
				<Stack.Group screenOptions={{ title: "Private area" }}>
					<Stack.Screen name="Home" component={Home} />
				</Stack.Group>
			</Show>
			<Stack.Screen name="Help" component={Help} />
		</Stack.Navigator>
	</NavigationContainer>, mockHost(), root);
	assert ref.currentPath() === "Guest";
	setLoggedIn(true);
	assert ref.currentPath() === "Home", ref.currentPath();
	assert guestDisposed === 1;
	assert mockToString(root).indexOf("Private area") >= 0, mockToString(root);
	setLoggedIn(false);
	assert ref.currentPath() === "Guest";
	assert homeDisposed === 1;
	assert mockToString(root).indexOf("Private body") < 0, mockToString(root);
	assert !ref.canGoBack();
	dispose();
	assert guestDisposed === 2;
}

test "group and screen navigationKey reset matching screen identities" {
	helpCreated = 0;
	const [groupKey, setGroupKey] = createSignal<string>("guest");
	const [screenKey, setScreenKey] = createSignal<string>("first");
	const Stack = createStackNavigator<AuthParams>();
	const ref = createNavigationContainerRef();
	const root = mockNode("root");
	const dispose = render(<NavigationContainer ref={ref}>
		<Stack.Navigator screenOptions={{ animation: "none" }}>
			<Stack.Group navigationKey={groupKey}>
				<Stack.Screen name="Help" component={Help} navigationKey={screenKey} />
			</Stack.Group>
		</Stack.Navigator>
	</NavigationContainer>, mockHost(), root);
	assert helpCreated === 1;
	setGroupKey("member");
	assert helpCreated === 2 && ref.currentPath() === "Help";
	setScreenKey("second");
	assert helpCreated === 3;
	dispose();
}

test "an always-present screen retains instance while auth declarations change" {
	helpCreated = 0;
	const [loggedIn, setLoggedIn] = createSignal(false);
	const Stack = createStackNavigator<AuthParams>();
	const ref = createNavigationContainerRef();
	const root = mockNode("root");
	const dispose = render(<NavigationContainer ref={ref}>
		<Stack.Navigator screenOptions={{ animation: "none" }}>
			<Show when={!loggedIn()}>
				<Stack.Screen name="Guest" component={Guest} />
			</Show>
			<Show when={loggedIn}>
				<Stack.Screen name="Home" component={Home} />
			</Show>
			<Stack.Screen name="Help" component={Help} />
		</Stack.Navigator>
	</NavigationContainer>, mockHost(), root);
	ref.navigate("Help");
	assert helpCreated === 1;
	setLoggedIn(true);
	assert ref.currentPath() === "Help";
	assert helpCreated === 1;
	setLoggedIn(false);
	assert ref.currentPath() === "Help";
	assert helpCreated === 1;
	dispose();
}
