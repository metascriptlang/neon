import { flush } from "../../src/core/runtime";
import { NeonNode } from "../../src/render/node";
import { HostNode, MockNode, mockNode, mockHost, render } from "../../src/render/host";
import { Text } from "../../src/components/primitives";
import {
	Navigation,
	NavigationContainer,
	ScreenProps,
	createDrawerNavigator,
	createNavigationContainerRef,
	useRoute,
} from "../../src/navigation/index";
import { visibleText } from "./navHarness";

interface AccountParams {
	id: int32;
	name: string;
}

interface FeedParams {
	topic: string;
}

interface DrawerList {
	Home: null;
	Account: AccountParams;
	Feed: FeedParams | null;
}

const Drawer = createDrawerNavigator<DrawerList>();

let homeNavigation: Navigation<DrawerList> | null = null;

function Home(props: ScreenProps<DrawerList>): NeonNode {
	homeNavigation = props.navigation;
	return <Text>home</Text>;
}

function Account(props: ScreenProps<DrawerList>): NeonNode {
	const route = useRoute<DrawerList, "Account">();
	const label = (): string => {
		const params = route.params();
		return params === null ? "account none" : "account " + params.id.toString() + " " + params.name;
	};
	return <Text>{label()}</Text>;
}

function Feed(props: ScreenProps<DrawerList>): NeonNode {
	const route = useRoute<DrawerList, "Feed">();
	const label = (): string => {
		const params = route.params();
		return params === null ? "feed all" : "feed " + params.topic;
	};
	return <Text>{label()}</Text>;
}

function mount(): MockNode {
	const root: MockNode = mockNode("root");
	const ref = createNavigationContainerRef();
	render(<NavigationContainer ref={ref}>
		<Drawer.Navigator>
			<Drawer.Screen name="Home" component={Home} />
			<Drawer.Screen name="Account" component={Account} />
			<Drawer.Screen name="Feed" component={Feed} />
		</Drawer.Navigator>
	</NavigationContainer>, mockHost(), root as unknown as HostNode);
	return root;
}

test "a drawer screen navigates with the params type its ParamList entry declares" {
	const root = mount();
	const home = homeNavigation as Navigation<DrawerList>;
	home.navigate("Account", { id: 3, name: "Three" });
	flush();
	assert visibleText(root).indexOf("account 3 Three") >= 0, visibleText(root);
	home.navigate("Feed");
	flush();
	assert visibleText(root).indexOf("feed all") >= 0, visibleText(root);
	// Parked on ~/metascript/.inbox/compiler/2026-10-24-an-object-literal-into-an-optional-element-of-a-conditional-rest-tuple-is-refused.md: a literal here is refused, so the params are a variable
	const topic: FeedParams = { topic: "neon" };
	home.navigate("Feed", topic);
	flush();
	assert visibleText(root).indexOf("feed neon") >= 0, visibleText(root);
}

test "jumpTo on a drawer carries the same typed params" {
	const root = mount();
	(homeNavigation as Navigation<DrawerList>).jumpTo("Account", { id: 8, name: "Eight" });
	flush();
	assert visibleText(root).indexOf("account 8 Eight") >= 0, visibleText(root);
}

test "a drawer navigator reset takes routes built by routeOf with each screen's own params" {
	const root = mount();
	const home = homeNavigation as Navigation<DrawerList>;
	home.reset({
		index: 1,
		routes: [home.routeOf("Home"), home.routeOf("Account", { id: 4, name: "Four" })],
	});
	flush();
	assert visibleText(root).indexOf("account 4 Four") >= 0, visibleText(root);
}
