import { flush } from "../../src/core/runtime";
import { NeonNode } from "../../src/render/node";
import { HostNode, MockNode, mockNode, mockHost, render } from "../../src/render/host";
import { Text } from "../../src/components/primitives";
import {
	Navigation,
	NavigationContainer,
	ScreenProps,
	createBottomTabNavigator,
	createNavigationContainerRef,
	useRoute,
} from "../../src/navigation/index";
import { visibleText } from "./navHarness";

interface ProfileParams {
	id: int32;
	name: string;
}

interface FeedParams {
	topic: string;
}

interface TabList {
	Home: null;
	Profile: ProfileParams;
	Feed: FeedParams | null;
}

const Tab = createBottomTabNavigator<TabList>();

let homeNavigation: Navigation<TabList> | null = null;

function Home(props: ScreenProps<TabList>): NeonNode {
	homeNavigation = props.navigation;
	return <Text>home</Text>;
}

function Profile(props: ScreenProps<TabList>): NeonNode {
	const route = useRoute<TabList, "Profile">();
	const label = (): string => {
		const params = route.params();
		return params === null ? "profile none" : "profile " + params.id.toString() + " " + params.name;
	};
	return <Text>{label()}</Text>;
}

function Feed(props: ScreenProps<TabList>): NeonNode {
	const route = useRoute<TabList, "Feed">();
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
		<Tab.Navigator>
			<Tab.Screen name="Home" component={Home} />
			<Tab.Screen name="Profile" component={Profile} />
			<Tab.Screen name="Feed" component={Feed} />
		</Tab.Navigator>
	</NavigationContainer>, mockHost(), root as unknown as HostNode);
	return root;
}

test "a tab navigates with the params type its ParamList entry declares" {
	const root = mount();
	const home = homeNavigation as Navigation<TabList>;
	home.navigate("Profile", { id: 3, name: "Three" });
	flush();
	assert visibleText(root).indexOf("profile 3 Three") >= 0, visibleText(root);
	home.navigate("Feed");
	flush();
	assert visibleText(root).indexOf("feed all") >= 0, visibleText(root);
	// Parked on ~/metascript/.inbox/compiler/2026-10-24-an-object-literal-into-an-optional-element-of-a-conditional-rest-tuple-is-refused.md: a literal here is refused, so the params are a variable
	const topic: FeedParams = { topic: "neon" };
	home.navigate("Feed", topic);
	flush();
	assert visibleText(root).indexOf("feed neon") >= 0, visibleText(root);
}

test "jumpTo carries the same typed params" {
	const root = mount();
	(homeNavigation as Navigation<TabList>).jumpTo("Profile", { id: 8, name: "Eight" });
	flush();
	assert visibleText(root).indexOf("profile 8 Eight") >= 0, visibleText(root);
}
