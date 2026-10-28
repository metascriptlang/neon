import { flush } from "../../src/core/runtime";
import { NeonNode } from "../../src/render/node";
import { NeonEvent } from "../../src/render/event";
import { HostNode, MockNode, mockNode, mockHost, render } from "../../src/render/host";
import { View, Text, Pressable } from "../../src/components/primitives";
import {
	Navigation,
	NavigationContainer,
	NavigationContainerRef,
	NavigationState,
	ScreenProps,
	createNavigationContainerRef,
	createStackNavigator,
	useRoute,
} from "../../src/navigation/index";
import { press, visibleText } from "./navHarness";

interface DetailParams {
	id: string;
	tab: string;
}

interface RootList {
	Home: null;
	Detail: DetailParams;
	Empty: DetailParams | null;
	Optional: DetailParams | null;
}

const Stack = createStackNavigator<RootList>();

let homeNavigation: Navigation<RootList> | null = null;
let bareOutcome = "";

function Home(props: ScreenProps<RootList>): NeonNode {
	homeNavigation = props.navigation;
	return <Text>home</Text>;
}

function Detail(props: ScreenProps<RootList>): NeonNode {
	const route = useRoute<RootList, "Detail">();
	const label = (): string => {
		const params = route.params();
		return params === null ? "none" : params.id + "/" + params.tab;
	};
	return <View>
		<Text>{"detail " + label()}</Text>
		<Pressable accessibilityLabel="merge" onPress={(e: NeonEvent): void => { route.setParams({ tab: "reviews" }); }}><Text>merge</Text></Pressable>
		<Pressable accessibilityLabel="replace" onPress={(e: NeonEvent): void => { route.replaceParams({ id: "9", tab: "info" }); }}><Text>replace</Text></Pressable>
	</View>;
}

function Optional(props: ScreenProps<RootList>): NeonNode {
	const route = useRoute<RootList, "Optional">();
	return <Pressable accessibilityLabel="optional" onPress={(e: NeonEvent): void => { route.setParams({ tab: "next" }); }}>
		<Text>{"optional " + (route.params() === null ? "none" : (route.params() as DetailParams).id + "/" + (route.params() as DetailParams).tab)}</Text>
	</Pressable>;
}

function Empty(props: ScreenProps<RootList>): NeonNode {
	const route = useRoute<RootList, "Empty">();
	return <Pressable accessibilityLabel="empty" onPress={(e: NeonEvent): void => {
		try {
			route.setParams({ tab: "x" });
			bareOutcome = "merged";
		} catch (e) {
			bareOutcome = "refused";
		}
	}}><Text>bare</Text></Pressable>;
}

function mount(ref: NavigationContainerRef): MockNode {
	const root: MockNode = mockNode("root");
	render(<NavigationContainer ref={ref}>
		<Stack.Navigator initialRouteName="Home">
			<Stack.Screen name="Home" component={Home} />
			<Stack.Screen name="Detail" component={Detail}
				params={Stack.params.of("Detail", {
					stringify: (p: DetailParams): Map<string, string> => {
						const out = new Map<string, string>();
						out.set("id", p.id);
						out.set("tab", p.tab);
						return out;
					},
				})} />
			<Stack.Screen name="Empty" component={Empty} />
			<Stack.Screen name="Optional" component={Optional}
				params={Stack.params.of("Optional", { initial: { id: "b", tab: "t" } })} />
		</Stack.Navigator>
	</NavigationContainer>, mockHost(), root as unknown as HostNode);
	return root;
}

function detailState(ref: NavigationContainerRef): Map<string, string> {
	const state: NavigationState = ref.getRootState();
	const params = state.routes[state.index].params;
	return params === null ? new Map<string, string>() : params as Map<string, string>;
}

test "setParams keeps the fields it is not given" {
	const ref = createNavigationContainerRef();
	const root = mount(ref);
	(homeNavigation as Navigation<RootList>).navigate("Detail", { id: "1", tab: "info" });
	flush();
	assert visibleText(root).indexOf("detail 1/info") >= 0, visibleText(root);
	press(root, "merge");
	assert visibleText(root).indexOf("detail 1/reviews") >= 0, visibleText(root);
}

test "replaceParams drops what it is not given" {
	const ref = createNavigationContainerRef();
	const root = mount(ref);
	(homeNavigation as Navigation<RootList>).navigate("Detail", { id: "1", tab: "info" });
	flush();
	press(root, "merge");
	press(root, "replace");
	assert visibleText(root).indexOf("detail 9/info") >= 0, visibleText(root);
}

test "merged and replaced params reach getState" {
	const ref = createNavigationContainerRef();
	const root = mount(ref);
	(homeNavigation as Navigation<RootList>).navigate("Detail", { id: "1", tab: "info" });
	flush();
	press(root, "merge");
	const merged = detailState(ref);
	assert merged.get("id") === "1" && merged.get("tab") === "reviews", "merged " + (merged.get("id") ?? "?") + " " + (merged.get("tab") ?? "?");
	press(root, "replace");
	const replaced = detailState(ref);
	assert replaced.get("id") === "9" && replaced.get("tab") === "info", "replaced";
}

test "setParams merges into a screen whose list entry is nullable" {
	const ref = createNavigationContainerRef();
	const root = mount(ref);
	(homeNavigation as Navigation<RootList>).navigate("Optional");
	flush();
	assert visibleText(root).indexOf("optional b/t") >= 0, visibleText(root);
	press(root, "optional");
	assert visibleText(root).indexOf("optional b/next") >= 0, visibleText(root);
}

test "setParams on a route that holds no params throws and names replaceParams" {
	const ref = createNavigationContainerRef();
	const root = mount(ref);
	bareOutcome = "";
	(homeNavigation as Navigation<RootList>).navigate("Empty");
	flush();
	press(root, "empty");
	assert bareOutcome === "refused", bareOutcome;
}
