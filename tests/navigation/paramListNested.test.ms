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
	createStackNavigator,
	useRoute,
} from "../../src/navigation/index";
import { visibleText } from "./navHarness";

interface ItemParams {
	id: int32;
	title: string;
}

interface SettingsParams {
	theme: string;
}

interface TabList {
	Browse: null;
	Settings: SettingsParams;
}

interface StackList {
	List: null;
	Detail: ItemParams;
}

const Tab = createBottomTabNavigator<TabList>();
const Stack = createStackNavigator<StackList>();

let detailNavigation: Navigation<StackList> | null = null;

let listNavigation: Navigation<StackList> | null = null;

function List(props: ScreenProps<StackList>): NeonNode {
	listNavigation = props.navigation;
	return <Text>list</Text>;
}

function Detail(props: ScreenProps<StackList>): NeonNode {
	detailNavigation = props.navigation;
	return <Text>detail</Text>;
}

function Browse(props: ScreenProps<TabList>): NeonNode {
	return <Stack.Navigator>
		<Stack.Screen name="List" component={List} />
		<Stack.Screen name="Detail" component={Detail} />
	</Stack.Navigator>;
}

function Settings(props: ScreenProps<TabList>): NeonNode {
	const route = useRoute<TabList, "Settings">();
	const label = (): string => {
		const params = route.params();
		return params === null ? "settings none" : "settings " + params.theme;
	};
	return <Text>{label()}</Text>;
}

function mount(): MockNode {
	const root: MockNode = mockNode("root");
	const ref = createNavigationContainerRef();
	render(<NavigationContainer ref={ref}>
		<Tab.Navigator>
			<Tab.Screen name="Browse" component={Browse} />
			<Tab.Screen name="Settings" component={Settings} />
		</Tab.Navigator>
	</NavigationContainer>, mockHost(), root as unknown as HostNode);
	return root;
}

test "a screen of a stack inside a tab reaches the tab's screens with the tab's params" {
	const root = mount();
	flush();
	(listNavigation as Navigation<StackList>).navigate("Detail", { id: 1, title: "One" });
	flush();
	const parent = (detailNavigation as Navigation<StackList>).getParent<StackList, TabList>();
	parent.navigate("Settings", { theme: "dark" });
	flush();
	assert visibleText(root).indexOf("settings dark") >= 0, visibleText(root);
}

test "going back to the parent's own screen leaves the child stack where it was" {
	const root = mount();
	flush();
	const list = listNavigation as Navigation<StackList>;
	list.navigate("Detail", { id: 2, title: "Two" });
	flush();
	assert visibleText(root).indexOf("detail") >= 0, visibleText(root);
	const parent = list.getParent<StackList, TabList>();
	parent.navigate("Browse");
	flush();
	assert visibleText(root).indexOf("detail") >= 0, visibleText(root);
}
