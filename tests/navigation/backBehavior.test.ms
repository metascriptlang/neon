import { flush } from "../../src/core/runtime";
import { NeonNode } from "../../src/render/node";
import { HostNode, mockNode, mockHost, render } from "../../src/render/host";
import { Text } from "../../src/components/primitives";
import {
	Navigation,
	NavigationContainer,
	NavigationContainerRef,
	RouteProp,
	ScreenProps,
	TabBackBehavior,
	createBottomTabNavigator,
	createNavigationContainerRef,
	useRoute,
} from "../../src/navigation/index";

interface PageParams {
	page: int32;
}

interface NavParams {
	A: null;
	B: PageParams | null;
	C: null;
}

const Tab = createBottomTabNavigator<NavParams>();

let home: Navigation<NavParams> | null = null;
let routeOfB: RouteProp<NavParams, "B"> | null = null;

function Plain(props: ScreenProps<NavParams>): NeonNode {
	if (props.route.name === "A") { home = props.navigation; }
	if (props.route.name === "B") { routeOfB = useRoute<NavParams, "B">(); }
	return <Text>plain</Text>;
}

function pageOfB(): int32 {
	const params = (routeOfB as RouteProp<NavParams, "B">).params();
	return params === null ? -1 : params.page;
}

function mount(ref: NavigationContainerRef, behavior: TabBackBehavior): void {
	const root = mockNode("root");
	render(<NavigationContainer ref={ref}>
		<Tab.Navigator backBehavior={behavior}>
			<Tab.Screen name="A" component={Plain} />
			<Tab.Screen name="B" component={Plain} />
			<Tab.Screen name="C" component={Plain} />
		</Tab.Navigator>
	</NavigationContainer>, mockHost(), root as unknown as HostNode);
}

function backs(ref: NavigationContainerRef): string {
	let out = ref.currentPath();
	while (ref.canGoBack()) {
		ref.goBack();
		out += ">" + ref.currentPath();
	}
	return out;
}

test "backBehavior order goes back to the screen declared before the focused one" {
	const ref = createNavigationContainerRef();
	mount(ref, "order");
	ref.navigate("C");
	assert backs(ref) === "C>B>A", backs(ref);
}

test "backBehavior fullHistory gives a screen back the params it had at that visit" {
	const ref = createNavigationContainerRef();
	mount(ref, "fullHistory");
	const nav = home as Navigation<NavParams>;
	const first: PageParams = { page: 1 };
	nav.navigate("B", first);
	flush();
	nav.navigate("C");
	flush();
	const second: PageParams = { page: 2 };
	nav.navigate("B", second);
	flush();
	assert pageOfB() === 2, pageOfB().toString();
	nav.goBack();
	nav.goBack();
	flush();
	assert ref.currentPath() === "B", ref.currentPath();
	assert pageOfB() === 1, pageOfB().toString();
}

test "backBehavior fullHistory keeps repeated visits where history drops them" {
	const full = createNavigationContainerRef();
	mount(full, "fullHistory");
	full.navigate("B");
	full.navigate("C");
	full.navigate("B");
	assert backs(full) === "B>C>B>A", backs(full);
	const dropped = createNavigationContainerRef();
	mount(dropped, "history");
	dropped.navigate("B");
	dropped.navigate("C");
	dropped.navigate("B");
	assert backs(dropped) === "B>C>A", backs(dropped);
}
