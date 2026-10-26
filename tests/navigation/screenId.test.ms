import { NeonNode } from "../../src/render/node";
import { HostNode, mockNode, mockHost, render } from "../../src/render/host";
import { Text } from "../../src/components/primitives";
import {
	Navigation,
	NavigationContainer,
	NavigationContainerRef,
	ScreenProps,
	createNavigationContainerRef,
	createStackNavigator,
} from "../../src/navigation/index";

interface ItemParams {
	id: int32;
}

interface NavParams {
	Home: null;
	Item: ItemParams;
	Plain: ItemParams;
}

const Stack = createStackNavigator<NavParams>();

let home: Navigation<NavParams> | null = null;

function Home(props: ScreenProps<NavParams>): NeonNode {
	home = props.navigation;
	return <Text>home</Text>;
}

function Body(props: ScreenProps<NavParams>): NeonNode {
	return <Text>body</Text>;
}

function mount(ref: NavigationContainerRef): void {
	const root = mockNode("root");
	render(<NavigationContainer ref={ref}>
		<Stack.Navigator screenOptions={{ animation: "none" }}>
			<Stack.Screen name="Home" component={Home} />
			<Stack.Screen name="Item" component={Body}
				params={Stack.params.of("Item", { getId: (params: ItemParams | null): string => params === null ? "" : params.id.toString() })} />
			<Stack.Screen name="Plain" component={Body} />
		</Stack.Navigator>
	</NavigationContainer>, mockHost(), root as unknown as HostNode);
}

function names(ref: NavigationContainerRef): string {
	let out = "";
	for (const route of ref.getRootState().routes) { out += route.name + ";"; }
	return out;
}

test "navigate with a getId pushes a screen whose id differs from the top screen's" {
	const ref = createNavigationContainerRef();
	mount(ref);
	const base = home as Navigation<NavParams>;
	base.navigate("Item", { id: 1 });
	base.navigate("Item", { id: 2 });
	assert names(ref) === "Home;Item;Item;", names(ref);
}

test "navigate to an existing id moves that screen to the top instead of pushing" {
	const ref = createNavigationContainerRef();
	mount(ref);
	const base = home as Navigation<NavParams>;
	base.navigate("Item", { id: 1 });
	const first = ref.getRootState().routes[1].key;
	base.navigate("Item", { id: 2 });
	base.navigate("Item", { id: 1 });
	assert names(ref) === "Home;Item;Item;", names(ref);
	const routes = ref.getRootState().routes;
	assert routes[2].key === first, "the first Item moved to the top";
}

test "push to an existing id moves that screen to the top, and a screen without getId still pushes" {
	const ref = createNavigationContainerRef();
	mount(ref);
	const base = home as Navigation<NavParams>;
	base.push("Item", { id: 1 });
	const first = ref.getRootState().routes[1].key;
	base.push("Item", { id: 2 });
	base.push("Item", { id: 1 });
	assert names(ref) === "Home;Item;Item;", names(ref);
	assert ref.getRootState().routes[2].key === first;
	base.push("Plain", { id: 1 });
	base.push("Plain", { id: 1 });
	assert names(ref) === "Home;Item;Item;Plain;Plain;", names(ref);
}
