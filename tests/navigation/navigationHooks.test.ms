import { flush } from "../../src/core/runtime";
import { createSignal } from "../../src/core/signal";
import { NeonNode } from "../../src/render/node";
import { HostNode, MockNode, mockNode, mockHost, render } from "../../src/render/host";
import { Text } from "../../src/components/primitives";
import {
	NavigationContainer,
	NavigationContainerRef,
	NavigationEventArg,
	NavigationRoute,
	NavigationState,
	ScreenProps,
	createNavigationContainerRef,
	createStackNavigator,
	getFocusedRouteNameFromRoute,
	usePreventRemove,
} from "../../src/navigation/index";
import { settle } from "./navHarness";

interface NavParams {
	Home: null;
	Form: null;
}

const Stack = createStackNavigator<NavParams>();
const [dirty, setDirty] = createSignal<boolean>(true);
let prevented = "";

function Home(props: ScreenProps<NavParams>): NeonNode {
	return <Text>home</Text>;
}

function Form(props: ScreenProps<NavParams>): NeonNode {
	usePreventRemove<NavParams>(dirty, (e: NavigationEventArg): void => { prevented += e.data.action.type + ";"; });
	return <Text>form</Text>;
}

function mount(ref: NavigationContainerRef): void {
	const root: MockNode = mockNode("root");
	render(<NavigationContainer ref={ref}>
		<Stack.Navigator screenOptions={{ animation: "none" }}>
			<Stack.Screen name="Home" component={Home} />
			<Stack.Screen name="Form" component={Form} />
		</Stack.Navigator>
	</NavigationContainer>, mockHost(), root as unknown as HostNode);
}

function stateOf(names: string[], index: int32): NavigationState {
	const routes: NavigationRoute[] = [];
	for (const name of names) { routes.push({ key: name, name, params: null, state: null }); }
	return { index, routeNames: names, routes };
}

test "usePreventRemove blocks leaving while its flag is set and reports the action" {
	const ref = createNavigationContainerRef();
	mount(ref);
	setDirty(true);
	prevented = "";
	ref.navigate("Form");
	flush();
	ref.goBack();
	flush();
	assert ref.currentPath() === "Form", ref.currentPath();
	assert prevented === "GO_BACK;", prevented;
	setDirty(false);
	flush();
	ref.goBack();
	flush();
	settle();
	assert ref.currentPath() === "Home", ref.currentPath();
}

test "getFocusedRouteNameFromRoute names the focused child route of a nested state" {
	const nested = stateOf(["Feed", "Chat", "Profile"], 1);
	const route: NavigationRoute = { key: "tabs", name: "Tabs", params: null, state: nested };
	assert getFocusedRouteNameFromRoute(route) === "Chat";
}

test "getFocusedRouteNameFromRoute falls back to the screen param, then to nothing" {
	const params = new Map<string, string>();
	params.set("screen", "Profile");
	const routed: NavigationRoute = { key: "tabs", name: "Tabs", params, state: null };
	assert getFocusedRouteNameFromRoute(routed) === "Profile";
	const bare: NavigationRoute = { key: "tabs", name: "Tabs", params: null, state: null };
	assert getFocusedRouteNameFromRoute(bare) === null;
}
