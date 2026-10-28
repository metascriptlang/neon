import { flush } from "../../src/core/runtime";
import { NeonNode } from "../../src/render/node";
import { NeonEvent } from "../../src/render/event";
import { HostNode, MockNode, mockNode, mockHost, render } from "../../src/render/host";
import { View, Text, Pressable } from "../../src/components/primitives";
import {
	Navigation,
	NavigationContainer,
	NavigationContainerRef,
	ScreenProps,
	createNavigationContainerRef,
	createStackNavigator,
	useRoute,
} from "../../src/navigation/index";
import { press, visibleText } from "./navHarness";

interface ItemParams {
	id: int32;
	title: string;
}

interface SearchParams {
	query: string;
	page: int32;
}

interface RootList {
	Home: null;
	Item: ItemParams;
	Search: SearchParams | null;
	Inner: null;
	Wrong: ItemParams;
}

interface InnerList {
	Leaf: null;
	Step: ItemParams;
	Item: ItemParams;
}

const Stack = createStackNavigator<RootList>();
const Inner = createStackNavigator<InnerList>();

let homeNavigation: Navigation<RootList> | null = null;
let leafNavigation: Navigation<InnerList> | null = null;
let wrongRead = "";

function Home(props: ScreenProps<RootList>): NeonNode {
	homeNavigation = props.navigation;
	return <Text>home</Text>;
}

function Item(props: ScreenProps<RootList>): NeonNode {
	const route = useRoute<RootList, "Item">();
	const label = (): string => {
		const params = route.params();
		return params === null ? "item none" : "item " + params.id.toString() + " " + params.title;
	};
	return <View>
		<Text>{label()}</Text>
		<Pressable accessibilityLabel="rename" onPress={(e: NeonEvent): void => {
			route.setParams({ id: 7, title: "Renamed" });
		}}><Text>rename</Text></Pressable>
	</View>;
}

function Search(props: ScreenProps<RootList>): NeonNode {
	const route = useRoute<RootList, "Search">();
	const label = (): string => {
		const params = route.params();
		return params === null ? "search all" : "search " + params.query + " " + params.page.toString();
	};
	return <Text>{label()}</Text>;
}

function WrongReader(props: ScreenProps<RootList>): NeonNode {
	const wrong = useRoute<RootList, "Search">();
	try {
		const params = wrong.params();
		wrongRead = params === null ? "null" : params.query;
	} catch (e) {
		wrongRead = "refused";
	}
	return <Text>wrong reader</Text>;
}

function Leaf(props: ScreenProps<InnerList>): NeonNode {
	leafNavigation = props.navigation;
	return <Text>leaf</Text>;
}

function Step(props: ScreenProps<InnerList>): NeonNode {
	const route = useRoute<InnerList, "Step">();
	return <Text>{"step " + (route.params() === null ? "-" : (route.params() as ItemParams).title)}</Text>;
}

function InnerHost(props: ScreenProps<RootList>): NeonNode {
	return <Inner.Navigator>
		<Inner.Screen name="Leaf" component={Leaf} />
		<Inner.Screen name="Step" component={Step} />
	</Inner.Navigator>;
}

function mount(ref: NavigationContainerRef): MockNode {
	const root: MockNode = mockNode("root");
	render(<NavigationContainer ref={ref}>
		<Stack.Navigator initialRouteName="Home">
			<Stack.Screen name="Home" component={Home} />
			<Stack.Screen name="Item" component={Item} />
			<Stack.Screen name="Search" component={Search}
				params={Stack.params.of("Search", { initial: { query: "start", page: 1 } })} />
			<Stack.Screen name="Inner" component={InnerHost} />
			<Stack.Screen name="Wrong" component={WrongReader} />
		</Stack.Navigator>
	</NavigationContainer>, mockHost(), root as unknown as HostNode);
	return root;
}

test "each screen reads the params type its ParamList entry declares" {
	const ref = createNavigationContainerRef();
	const root = mount(ref);
	const home = homeNavigation as Navigation<RootList>;
	home.navigate("Item", { id: 3, title: "Three" });
	flush();
	assert visibleText(root).indexOf("item 3 Three") >= 0, visibleText(root);
	// Parked on ~/metascript/.inbox/compiler/2026-10-24-an-object-literal-into-an-optional-element-of-a-conditional-rest-tuple-is-refused.md: a literal here is refused, so the params are a variable
	const neon: SearchParams = { query: "neon", page: 2 };
	home.navigate("Search", neon);
	flush();
	assert visibleText(root).indexOf("search neon 2") >= 0, visibleText(root);
}

test "a screen with initialParams shows them until navigate carries its own" {
	const ref = createNavigationContainerRef();
	const root = mount(ref);
	const home = homeNavigation as Navigation<RootList>;
	home.navigate("Search");
	flush();
	assert visibleText(root).indexOf("search start 1") >= 0, visibleText(root);
	const next: SearchParams = { query: "next", page: 4 };
	home.navigate("Search", next, { pop: true });
	flush();
	assert visibleText(root).indexOf("search next 4") >= 0, visibleText(root);
}

test "setParams replaces the route's params and the screen follows" {
	const ref = createNavigationContainerRef();
	const root = mount(ref);
	(homeNavigation as Navigation<RootList>).push("Item", { id: 1, title: "One" });
	flush();
	assert visibleText(root).indexOf("item 1 One") >= 0, visibleText(root);
	press(root, "rename");
	assert visibleText(root).indexOf("item 7 Renamed") >= 0, visibleText(root);
}

test "reading a route as another screen's params type stops with a conversion error" {
	const ref = createNavigationContainerRef();
	const root = mount(ref);
	wrongRead = "";
	(homeNavigation as Navigation<RootList>).navigate("Wrong", { id: 2, title: "Two" });
	flush();
	assert wrongRead === "refused", wrongRead;
}

test "params stay inside their navigator and getParent reaches the parent typed" {
	const ref = createNavigationContainerRef();
	const root = mount(ref);
	(homeNavigation as Navigation<RootList>).navigate("Inner");
	flush();
	const leaf = leafNavigation as Navigation<InnerList>;
	leaf.navigate("Step", { id: 5, title: "Five" });
	flush();
	assert visibleText(root).indexOf("step Five") >= 0, visibleText(root);
	let crossed = "no error";
	try {
		leaf.navigate("Item", { id: 4, title: "Four" });
	} catch (e) {
		crossed = (e as Error).message;
	}
	assert crossed.indexOf("cannot reach another navigator") >= 0, crossed;
	const parent = leaf.getParent<InnerList, RootList>();
	parent.navigate("Item", { id: 9, title: "Nine" });
	flush();
	assert ref.currentPath() === "Item", ref.currentPath();
}

test "a stack reset takes routes built by routeOf with each screen's own params" {
	const ref = createNavigationContainerRef();
	const root = mount(ref);
	const home = homeNavigation as Navigation<RootList>;
	home.reset({
		routes: [home.routeOf("Home"), home.routeOf("Item", { id: 6, title: "Six" })],
	});
	flush();
	assert visibleText(root).indexOf("item 6 Six") >= 0, visibleText(root);
	assert ref.getRootState().routes.length === 2, ref.getRootState().routes.length.toString();
}
