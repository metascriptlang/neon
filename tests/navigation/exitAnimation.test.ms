import { flush } from "../../src/core/runtime";
import { onCleanup } from "../../src/core/cleanup";
import { NeonNode } from "../../src/render/hostTypes";
import { HostNode, mockHost, mockNode, render } from "../../src/render/host";
import { Text } from "../../src/components/primitives";
import {
	Navigation,
	NavigationContainer,
	ScreenProps,
	createNavigationContainerRef,
	createStackNavigator,
} from "../../src/navigation/index";
import { settle } from "./navHarness";

interface NavParams {
	Home: null;
	Detail: null;
	Middle: null;
}

const Stack = createStackNavigator<NavParams>();

let bodies: int32 = 0;

let cleanups: int32 = 0;

let counted: Navigation<NavParams> | null = null;

function Plain(props: ScreenProps<NavParams>): NeonNode {
	return <Text>plain</Text>;
}

function Counted(props: ScreenProps<NavParams>): NeonNode {
	bodies += 1;
	counted = props.navigation;
	onCleanup((): void => { cleanups += 1; });
	return <Text>counted</Text>;
}

test "a screen popped with an exit animation is built once and released when the animation ends" {
	bodies = 0;
	cleanups = 0;
	const ref = createNavigationContainerRef();
	const root = mockNode("root");
	const dispose = render(<NavigationContainer ref={ref}>
		<Stack.Navigator>
			<Stack.Screen name="Home" component={Plain} />
			<Stack.Screen name="Detail" component={Counted} />
		</Stack.Navigator>
	</NavigationContainer>, mockHost(), root as unknown as HostNode);
	ref.navigate("Detail");
	flush();
	settle();
	assert bodies === 1 && cleanups === 0, bodies.toString() + "/" + cleanups.toString();
	ref.goBack();
	flush();
	assert ref.currentPath() === "Home", ref.currentPath();
	assert bodies === 1, "the leaving screen is kept, not rebuilt: " + bodies.toString();
	assert cleanups === 0, "the leaving screen is kept until the animation ends: " + cleanups.toString();
	settle();
	assert bodies === 1 && cleanups === 1, bodies.toString() + "/" + cleanups.toString();
	dispose();
}

test "a screen popped without an animation is released at once" {
	bodies = 0;
	cleanups = 0;
	const ref = createNavigationContainerRef();
	const root = mockNode("root");
	const dispose = render(<NavigationContainer ref={ref}>
		<Stack.Navigator screenOptions={{ animation: "none" }}>
			<Stack.Screen name="Home" component={Plain} />
			<Stack.Screen name="Detail" component={Counted} />
		</Stack.Navigator>
	</NavigationContainer>, mockHost(), root as unknown as HostNode);
	ref.navigate("Detail");
	flush();
	ref.goBack();
	flush();
	assert bodies === 1 && cleanups === 1, bodies.toString() + "/" + cleanups.toString();
	dispose();
}

test "a screen popped to the top with an exit animation is built once" {
	bodies = 0;
	cleanups = 0;
	const ref = createNavigationContainerRef();
	const root = mockNode("root");
	const dispose = render(<NavigationContainer ref={ref}>
		<Stack.Navigator>
			<Stack.Screen name="Home" component={Plain} />
			<Stack.Screen name="Middle" component={Plain} />
			<Stack.Screen name="Detail" component={Counted} />
		</Stack.Navigator>
	</NavigationContainer>, mockHost(), root as unknown as HostNode);
	ref.navigate("Middle");
	flush();
	ref.navigate("Detail");
	flush();
	settle();
	(counted as Navigation<NavParams>).popTo("Home");
	flush();
	assert bodies === 1, "the leaving screen is not rebuilt: " + bodies.toString();
	settle();
	assert ref.currentPath() === "Home", ref.currentPath();
	assert bodies === 1 && cleanups === 1, bodies.toString() + "/" + cleanups.toString();
	dispose();
}
